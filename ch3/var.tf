variable "KeyName" {
  description = "Name of an existing EC2 KeyPair to enable SSH access to the instances."
  type        = string
}

variable "MyIamUserAccessKeyID" {
  description = "IAM User - AWS Access Key ID."
  type        = string
  sensitive   = true
}

variable "MyIamUserSecretAccessKey" {
  description = "IAM User - AWS Secret Access Key."
  type        = string
  sensitive   = true
}

variable "SgIngressSshCidr" {
  description = "The IP address range that can be used to SSH to the EC2 instances."
  type        = string
  validation {
    condition     = can(regex("^(\\d{1,3})\\.(\\d{1,3})\\.(\\d{1,3})\\.(\\d{1,3})/(\\d{1,2})$", var.SgIngressSshCidr))
    error_message = "The SgIngressSshCidr value must be a valid IP CIDR range of the form x.x.x.x/x."
  }
}

variable "MyInstanceType" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.medium"
  validation {
    condition     = contains(["t2.micro", "t2.small", "t2.medium", "t3.micro", "t3.small", "t3.medium"], var.MyInstanceType)
    error_message = "Invalid instance type. Valid options are t2.micro, t2.small, t2.medium, t3.micro, t3.small, t3.medium."
  }
}

variable "ClusterBaseName" {
  description = "Base name of the cluster."
  type        = string
  default     = "myeks"
}

variable "KubernetesVersion" {
  description = "Kubernetes version for the EKS cluster."
  type        = string
  default     = "1.30"
}

variable "WorkerNodeInstanceType" {
  description = "EC2 instance type for the worker nodes."
  type        = string
  default     = "t3.xlarge"
}

variable "WorkerNodeCount" {
  description = "Number of worker nodes."
  type        = number
  default     = 3
}

variable "WorkerNodeVolumesize" {
  description = "Volume size for worker nodes (in GiB)."
  type        = number
  default     = 30
}

variable "TargetRegion" {
  description = "AWS region where the resources will be created."
  type        = string
  default     = "ap-northeast-2"
}

variable "availability_zones" {
  description = "List of availability zones."
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2b", "ap-northeast-2c"]
}

variable "VpcBlock" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "192.168.0.0/16"
}

variable "public_subnet_blocks" {
  description = "List of CIDR blocks for the public subnets."
  type        = list(string)
  default     = ["192.168.1.0/24", "192.168.2.0/24", "192.168.3.0/24"]
}

variable "private_subnet_blocks" {
  description = "List of CIDR blocks for the private subnets."
  type        = list(string)
  default     = ["192.168.11.0/24", "192.168.12.0/24", "192.168.13.0/24"]
}
