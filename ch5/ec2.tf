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
    Name = "${var.ClusterBaseName}-bastion-EC2"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    delete_on_termination = true
  }

  user_data = <<-EOF
    #!/bin/bash
    hostnamectl --static set-hostname "${var.ClusterBaseName}-bastion-EC2"

    # Config convenience
    echo 'alias vi=vim' >> /etc/profile
    echo "sudo su -" >> /home/ubuntu/.bashrc
    timedatectl set-timezone Asia/Seoul

    # Install Packages
    apt update
    apt install -y tree jq git htop unzip

    # Install kubectl & helm
    curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.32.0/2024-12-20/bin/linux/amd64/kubectl
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    curl -s https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash

    # Install eksctl
    curl -sL "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz" | tar xz -C /tmp
    mv /tmp/eksctl /usr/local/bin

    # Install aws cli v2
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip >/dev/null 2>&1
    ./aws/install
    complete -C '/usr/local/bin/aws_completer' aws
    echo 'export AWS_PAGER=""' >> /etc/profile
    echo "export AWS_DEFAULT_REGION=${var.TargetRegion}" >> /etc/profile

    # Install YAML Highlighter
    wget https://github.com/andreazorzetto/yh/releases/download/v0.4.0/yh-linux-amd64.zip
    unzip yh-linux-amd64.zip
    mv yh /usr/local/bin/

    # Install kube-ps1
    echo 'source <(kubectl completion bash)' >> /root/.bashrc
    echo 'alias k=kubectl' >> /root/.bashrc
    echo 'complete -F __start_kubectl k' >> /root/.bashrc
            
    git clone https://github.com/jonmosco/kube-ps1.git /root/kube-ps1
    cat <<"EOT" >> /root/.bashrc
    source /root/kube-ps1/kube-ps1.sh
    KUBE_PS1_SYMBOL_ENABLE=false
    function get_cluster_short() {
      echo "$1" | grep -o '${var.ClusterBaseName}[^/]*' | cut -c 1-13 
    }
    KUBE_PS1_CLUSTER_FUNCTION=get_cluster_short
    KUBE_PS1_SUFFIX=') '
    PS1='$(kube_ps1)'$PS1
    EOT

    # kubecolor
    apt install kubecolor
    echo 'alias kubectl=kubecolor' >> /root/.bashrc

    # Install kubectx & kubens
    git clone https://github.com/ahmetb/kubectx /opt/kubectx >/dev/null 2>&1
    ln -s /opt/kubectx/kubens /usr/local/bin/kubens
    ln -s /opt/kubectx/kubectx /usr/local/bin/kubectx

    # Install Docker
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    systemctl enable docker

    # Create SSH Keypair
    ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa

    # IAM User Credentials
    export AWS_ACCESS_KEY_ID="${var.MyIamUserAccessKeyID}"
    export AWS_SECRET_ACCESS_KEY="${var.MyIamUserSecretAccessKey}"
    export ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
    echo "export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID" >> /etc/profile
    echo "export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY" >> /etc/profile
    echo "export ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)" >> /etc/profile

    # CLUSTER_NAME
    export CLUSTER_NAME="${var.ClusterBaseName}"
    echo "export CLUSTER_NAME=$CLUSTER_NAME" >> /etc/profile

    # VPC & Subnet
    export VPCID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$CLUSTER_NAME-VPC" | jq -r .Vpcs[].VpcId)
    echo "export VPCID=$VPCID" >> /etc/profile
    export PublicSubnet1=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=\"$CLUSTER_NAME-PublicSubnet\"" | jq -r '.Subnets[] | select(.CidrBlock | startswith("192.168.1")).SubnetId')
    export PublicSubnet2=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=\"$CLUSTER_NAME-PublicSubnet\"" | jq -r '.Subnets[] | select(.CidrBlock | startswith("192.168.2")).SubnetId')
    export PublicSubnet3=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=\"$CLUSTER_NAME-PublicSubnet\"" | jq -r '.Subnets[] | select(.CidrBlock | startswith("192.168.3")).SubnetId')
    echo "export PublicSubnet1=$PublicSubnet1" >> /etc/profile
    echo "export PublicSubnet2=$PublicSubnet2" >> /etc/profile
    echo "export PublicSubnet3=$PublicSubnet3" >> /etc/profile
    export PrivateSubnet1=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=\"$CLUSTER_NAME-PrivateSubnet\"" | jq -r '.Subnets[] | select(.CidrBlock | startswith("192.168.11")).SubnetId')
    export PrivateSubnet2=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=\"$CLUSTER_NAME-PrivateSubnet\"" | jq -r '.Subnets[] | select(.CidrBlock | startswith("192.168.12")).SubnetId')
    export PrivateSubnet3=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=\"$CLUSTER_NAME-PrivateSubnet\"" | jq -r '.Subnets[] | select(.CidrBlock | startswith("192.168.13")).SubnetId')
    echo "export PrivateSubnet1=$PrivateSubnet1" >> /etc/profile
    echo "export PrivateSubnet2=$PrivateSubnet2" >> /etc/profile
    echo "export PrivateSubnet3=$PrivateSubnet3" >> /etc/profile
    
    # ssh key-pair
    aws ec2 delete-key-pair --key-name kp_node
    aws ec2 create-key-pair --key-name kp_node --query 'KeyMaterial' --output text > ~/.ssh/kp_node.pem
    chmod 400 ~/.ssh/kp_node.pem

  EOF
  
  user_data_replace_on_change = true
  
}
