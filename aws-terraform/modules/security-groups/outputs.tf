# =============================================================================
# security-groups module - outputs
# =============================================================================

output "bastion_sg_id" {
  description = "Security group ID for the bastion host."
  value       = aws_security_group.bastion.id
}

output "workers_sg_id" {
  description = "Security group ID for the EKS worker nodes."
  value       = aws_security_group.workers.id
}

output "control_plane_sg_id" {
  description = "Security group ID for the EKS control plane."
  value       = aws_security_group.control_plane.id
}
