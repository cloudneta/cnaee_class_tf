locals {
  cluster_oidc_issuer_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}"
}

data "aws_caller_identity" "current" {}

resource "aws_iam_policy" "external_dns_policy" {
  name        = "${var.ClusterBaseName}ExternalDNSPolicy"
  description = "Policy for allowing ExternalDNS to modify Route 53 records"

  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "route53:ChangeResourceRecordSets"
        ],
        "Resource": [
          "arn:aws:route53:::hostedzone/*"
        ]
      },
      {
        "Effect": "Allow",
        "Action": [
          "route53:ListHostedZones",
          "route53:ListResourceRecordSets"
        ],
        "Resource": [
          "*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "external_dns_policy_attach" {
  role       = "${var.ClusterBaseName}-node-group-eks-node-group"
  policy_arn = aws_iam_policy.external_dns_policy.arn

  depends_on = [module.eks]
}

resource "aws_security_group" "node_group_sg" {
  name        = "${var.ClusterBaseName}-node-group-sg"
  description = "Security group for EKS Node Group"
  vpc_id      = module.vpc.vpc_id

  tags = {
    Name = "${var.ClusterBaseName}-node-group-sg"
  }
}

resource "aws_security_group_rule" "allow_ssh" {
  type        = "ingress"
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = ["192.168.1.100/32"]

  security_group_id = aws_security_group.node_group_sg.id
}

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
      service_account_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/AmazonEKS_EBS_CSI_DriverRole"
    }
  }

  vpc_id = module.vpc.vpc_id
  enable_irsa = true
  subnet_ids = module.vpc.public_subnets

  eks_managed_node_groups = {
    default = {
      name             = "${var.ClusterBaseName}-node-group"
      use_name_prefix  = false
      instance_type    = var.WorkerNodeInstanceType
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

data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_name
  depends_on = [module.eks]
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_name
}

data "aws_iam_policy" "ebs_csi_policy" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  depends_on = [module.eks]
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  token                  = data.aws_eks_cluster_auth.cluster.token
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", var.ClusterBaseName]
      command     = "aws"
    }
  }
}

module "eks-external-dns" {
  source  = "lablabs/eks-external-dns/aws"
  version = "1.2.0"

  cluster_identity_oidc_issuer     = module.eks.cluster_oidc_issuer_url
  cluster_identity_oidc_issuer_arn = local.cluster_oidc_issuer_arn

}

module "eks_aws-load-balancer-controller" {
  source  = "akw-devsecops/eks/aws//modules/aws-load-balancer-controller"
  version = "2.6.11"

  cluster_name      = var.ClusterBaseName
  oidc_provider_arn = local.cluster_oidc_issuer_arn

}
