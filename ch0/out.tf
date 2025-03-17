output "public_ip" {
  value       = aws_instance.eks_bastion.public_ip
  description = "The public IP of the EC2 instance."
}
