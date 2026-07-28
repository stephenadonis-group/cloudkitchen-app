# =============================================================================
# bastion module - outputs
# =============================================================================

output "bastion_instance_id" {
  description = "EC2 instance ID of the bastion host."
  value       = aws_instance.bastion.id
}

output "bastion_public_ip" {
  description = "Public IP address of the bastion host."
  value       = aws_instance.bastion.public_ip
}

output "bastion_private_ip" {
  description = "Private IP address of the bastion host."
  value       = aws_instance.bastion.private_ip
}

output "bastion_role_arn" {
  description = "ARN of the bastion IAM role."
  value       = aws_iam_role.bastion.arn
}
