output "bastion_1_ip" {
  value       = aws_instance.eks_bastion.public_ip
  description = "The public IP of the myeks-host EC2 instance."
}

output "bastion_2_ip" {
  value       = length(aws_instance.eks_bastion_2) > 0 ? aws_instance.eks_bastion_2[0].public_ip : null
  description = "The public IP of the myeks-host-2 EC2 instance."
}