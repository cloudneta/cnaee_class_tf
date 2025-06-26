########################
# Provider Definitions #
########################

# AWS 공급자: 지정된 리전에서 AWS 리소스를 설정
provider "aws" {
  region = var.TargetRegion
}

# 요구 프로바이더 버전: helm 2.12.1
terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12.1"
    }
  }
}

# Kubernetes 공급자: EKS 클러스터와 연결 (엔드포인트, 인증 토큰, CA 인증서 사용)
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

# Helm 공급자: EKS 클러스터에서 Helm Chart 배포를 관리
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}



##################
# Data Resources #
##################

# AWS 계정 정보 조회 (예: AWS Account ID)
data "aws_caller_identity" "current" {}

# EKS 클러스터의 OIDC 공급자 ARN을 구성
locals {
  cluster_oidc_issuer_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}"
}

# EKS 클러스터 메타데이터 조회
data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_name
  depends_on = [module.eks]
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_name
  depends_on = [module.eks]
}



########################
# Security Group Setup #
########################

# 보안 그룹: EKS 워커 노드용 보안 그룹 생성
resource "aws_security_group" "node_group_sg" {
  name        = "${var.ClusterBaseName}-node-group-sg"
  description = "Security group for EKS Node Group"
  vpc_id      = module.vpc.vpc_id

  tags = {
    Name = "${var.ClusterBaseName}-node-group-sg"
  }
}

# 보안 그룹 규칙: 특정 IP에서 EKS 워커 노드로 SSH(22번 포트) 접속 허용
resource "aws_security_group_rule" "allow_ssh" {
  type        = "ingress"
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = ["192.168.1.100/32"]

  security_group_id = aws_security_group.node_group_sg.id
}



#######################
# Amazon EKS Cluster  #
#######################

# EKS 모듈: 관리형 노드 그룹 및 기본 애드온이 포함된 EKS 클러스터 생성
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~>20.0"

  cluster_name = var.ClusterBaseName
  cluster_version = var.KubernetesVersion
  cluster_endpoint_private_access = false
  cluster_endpoint_public_access  = true

  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent = true
      service_account_role_arn = module.irsa-ebs-csi.iam_role_arn
    }
  }

  vpc_id = module.vpc.vpc_id
  enable_irsa = true
  subnet_ids = module.vpc.public_subnets
  
  # EKS 관리형 노드 그룹 설정
  eks_managed_node_groups = {
    default = {
      name             = "${var.ClusterBaseName}-node-group"
      use_name_prefix  = false
      instance_types   = ["${var.WorkerNodeInstanceType}"]
      desired_size     = var.WorkerNodeCount
      max_size         = var.WorkerNodeCount + 2
      min_size         = var.WorkerNodeCount - 1
      disk_size        = var.WorkerNodeVolumesize
      subnets          = module.vpc.public_subnets
      key_name         = "kp_node"
      vpc_security_group_ids = [aws_security_group.node_group_sg.id]
      iam_role_name    = "${var.ClusterBaseName}-node-group-eks-node-group"
      iam_role_use_name_prefix = false
      iam_role_additional_policies = {
        "${var.ClusterBaseName}ExternalDNSPolicy" = aws_iam_policy.external_dns_policy.arn
      } 
   }
  }

  depends_on = [aws_instance.eks_bastion]
  
  # EKS 클러스터 액세스 관리
  access_entries = {
    admin = {
      kubernetes_groups = []
      principal_arn     = "${data.aws_caller_identity.current.arn}" 

      policy_associations = {
        myeks = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            namespaces = []
            type       = "cluster"
          }
        }
      }
    }
  }

  tags = {
    Environment = "cnaee-lab"
    Terraform   = "true"
  }
}



################
# IAM Policies #
################

# ExternalDNS가 Route 53 DNS 레코드를 관리할 수 있도록 허용하는 IAM 정책
resource "aws_iam_policy" "external_dns_policy" {
  name        = "${var.ClusterBaseName}ExternalDNSPolicy"
  description = "Policy for allowing ExternalDNS to modify Route 53 records"

  policy = file("external_dns_policy.json")
}

# AWS Load Balancer Controller가 ELB를 관리할 수 있도록 허용하는 IAM 정책
resource "aws_iam_policy" "aws_lb_controller_policy" {
  name        = "${var.ClusterBaseName}AWSLoadBalancerControllerPolicy"
  description = "Policy for allowing AWS LoadBalancerController to modify AWS ELB"

  policy = file("aws_lb_controller_policy.json")
}

# EBS CSI Driver가 Amazon EBS 볼륨을 생성, 삭제 및 관리할 수 있도록 허용하는 AWS 관리형 IAM 정책의 ARN
data "aws_iam_policy" "ebs_csi_policy" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}


####################
# IRSA Roles Setup #
####################

# AWS Load Balancer Controller가 OIDC 인증을 통해 AWS 리소스에 접근할 수 있도록 하는 역할
module "irsa-lb-controller" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version = "5.39.0"

  create_role                   = true
  role_name                     = "AmazonEKSTFLBControllerRole-${module.eks.cluster_name}"
  provider_url                  = module.eks.oidc_provider
  role_policy_arns              = [aws_iam_policy.aws_lb_controller_policy.arn]
  oidc_fully_qualified_subjects = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
  oidc_fully_qualified_audiences = ["sts.amazonaws.com"]
}

# ExternalDNS가 OIDC 인증을 통해 Route 53을 관리할 수 있도록 하는 역할
module "irsa-external-dns" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version = "5.39.0"

  create_role                   = true
  role_name                     = "AmazonEKSTFExternalDnsRole-${module.eks.cluster_name}"
  provider_url                  = module.eks.oidc_provider
  role_policy_arns              = [aws_iam_policy.external_dns_policy.arn]
  oidc_fully_qualified_subjects = ["system:serviceaccount:kube-system:external-dns"]
  oidc_fully_qualified_audiences = ["sts.amazonaws.com"]
}

# EBS CSI Driver가 OIDC 인증을 통해 Amazon EBS 볼륨을 관리할 수 있도록 하는 역할
module "irsa-ebs-csi" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version = "5.39.0"

  create_role                   = true
  role_name                     = "AmazonEKSTFEBSCSIRole-${module.eks.cluster_name}"
  provider_url                  = module.eks.oidc_provider
  role_policy_arns              = [data.aws_iam_policy.ebs_csi_policy.arn]
  oidc_fully_qualified_subjects = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
}


######################
# Helm Chart Install #
######################

# Helm Chart: ExternalDNS를 EKS 클러스터에 배포
module "eks-external-dns" {
  source  = "lablabs/eks-external-dns/aws"
  version = "1.2.0"

  cluster_identity_oidc_issuer     = module.eks.cluster_oidc_issuer_url
  cluster_identity_oidc_issuer_arn = local.cluster_oidc_issuer_arn
  depends_on = [helm_release.aws_load_balancer_controller]
}

# Helm Chart: AWS Load Balancer Controller를 EKS 클러스터에 배포
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  set {
    name  = "clusterName"
    value = var.ClusterBaseName
  }
  set {
    name  = "serviceAccount.create"
    value = "true"
  }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/AmazonEKSTFLBControllerRole-${module.eks.cluster_name}"
  }
  set {
    name  = "region"
    value = "ap-northeast-2"
  }
  depends_on = [module.eks, module.irsa-lb-controller]
}