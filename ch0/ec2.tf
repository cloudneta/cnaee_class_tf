########################
# Provider Definitions #
########################

# AWS 공급자: 지정된 리전에서 AWS 리소스를 설정
provider "aws" {
  region = var.TargetRegion
}



######################
# EC2 Instance Setup #
######################

# 최신 Ubuntu 22.04 AMI ID를 AWS SSM Parameter Store에서 가져옴.
data "aws_ssm_parameter" "ami" {
  name = "/aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id"
}


# EKS 클러스터 관리용 Bastion Host EC2 인스턴스를 생성.
resource "aws_instance" "eks_bastion" {
  ami                         = data.aws_ssm_parameter.ami.value
  instance_type               = var.MyInstanceType
  key_name                    = var.KeyName
  subnet_id                   = module.vpc.public_subnets[0]
  associate_public_ip_address = true
  private_ip                  = "192.168.1.100"
  vpc_security_group_ids      = [aws_security_group.eks_sec_group.id]

  tags = {
    Name = "cnaee-bastion-EC2"
  }

  user_data = <<-EOF
    #!/bin/bash
    wget https://busybox.net/downloads/binaries/1.31.0-defconfig-multiarch-musl/busybox-x86_64
    mv busybox-x86_64 busybox
    chmod +x busybox
    echo "<h1>CNAEE Web Server</h1>" > index.html
    nohup ./busybox httpd -f -p 80 &
    EOF
  
  user_data_replace_on_change = true
  
}