provider "aws" {
  region = var.TargetRegion
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~>5.7"

  name = "${var.ClusterBaseName}-VPC"
  cidr = var.VpcBlock
  azs  = var.availability_zones

  enable_dns_support   = true
  enable_dns_hostnames = true

  public_subnets  = var.public_subnet_blocks
  private_subnets = var.private_subnet_blocks

  enable_nat_gateway = true
  single_nat_gateway = true
  one_nat_gateway_per_az = false
  
  map_public_ip_on_launch = true
 
  igw_tags = {
    "Name" = "${var.ClusterBaseName}-IGW"
  }
 
  nat_gateway_tags = {
    "Name" = "${var.ClusterBaseName}-NAT"
  }
 
  public_subnet_tags = {
    "Name"                     = "${var.ClusterBaseName}-PublicSubnet"
    "kubernetes.io/role/elb"   = "1"
  }

  private_subnet_tags = {
    "Name"                             = "${var.ClusterBaseName}-PrivateSubnet"
    "kubernetes.io/role/internal-elb" = "1"
  }

  tags = {
    "Environment" = "cnaee-lab"
  }
}

resource "aws_security_group" "eks_sec_group" {
  vpc_id = module.vpc.vpc_id

  name        = "${var.ClusterBaseName}-eks-sec-group"
  description = "Security group for ${var.ClusterBaseName} EKS cluster"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.SgIngressSshCidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.ClusterBaseName}-HOST-SG"
  }
}

