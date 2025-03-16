####################################
# VPC and Networking Configuration #
####################################

# VPC 모듈: 퍼블릭 및 프라이빗 서브넷을 포함하는 VPC를 생성
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~>5.7"

  name = "cnaee-VPC"
  cidr = var.VpcBlock
  azs  = var.availability_zones

  enable_dns_support   = true
  enable_dns_hostnames = true

  public_subnets  = var.public_subnet_blocks
  private_subnets = var.private_subnet_blocks

  enable_nat_gateway = false

  map_public_ip_on_launch = true

  igw_tags = {
    "Name" = "cnaee-IGW"
  }

  nat_gateway_tags = {
    "Name" = "cnaee-NAT"
  }

  public_subnet_tags = {
    "Name"                     = "cnaee-PublicSubnet"
    "kubernetes.io/role/elb"   = "1"
  }

  private_subnet_tags = {
    "Name"                             = "cnaee-PrivateSubnet"
    "kubernetes.io/role/internal-elb" = "1"
  }

  tags = {
    "Environment" = "cnaee-lab"
  }
}



################################
# Security Group Configuration #
################################

# 보안 그룹: Bastion Host를 위한 보안 그룹을 생성
resource "aws_security_group" "eks_sec_group" {
  vpc_id = module.vpc.vpc_id

  name        = "cnaee-eks-sec-group"
  description = "Security group for cnaee Host"
  
  # 인바운드 TCP 22 포트 허용(SSH)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.SgIngressSshCidr]
  }

  # 인바운드 TCP 80 포트 허용
  ingress {
    from_port   = 80
    to_port     = 80
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
    Name = "cnaee-HOST-SG"
  }
}
