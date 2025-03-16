output "public_ip" {
  value       = aws_instance.eks_bastion.public_ip
  description = "The public IP of the myeks-host EC2 instance."
}
