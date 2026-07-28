# =============================================================================
# iam module - outputs
# =============================================================================

output "cluster_role_arn" {
  description = "ARN of the EKS cluster IAM role."
  value       = aws_iam_role.cluster.arn
}

output "node_role_arn" {
  description = "ARN of the EKS worker node IAM role."
  value       = aws_iam_role.node.arn
}

output "aws_load_balancer_controller_role_arn" {
  description = "ARN of the IRSA role for the AWS Load Balancer Controller (empty when IRSA roles disabled)."
  value       = var.create_irsa_roles ? aws_iam_role.aws_load_balancer_controller[0].arn : ""
}

output "external_dns_role_arn" {
  description = "ARN of the IRSA role for external-dns (empty when IRSA roles disabled)."
  value       = var.create_irsa_roles ? aws_iam_role.external_dns[0].arn : ""
}

output "cert_manager_role_arn" {
  description = "ARN of the IRSA role for cert-manager (empty when IRSA roles disabled)."
  value       = var.create_irsa_roles ? aws_iam_role.cert_manager[0].arn : ""
}

output "ebs_csi_driver_role_arn" {
  description = "ARN of the IRSA role for the Amazon EBS CSI driver (empty when IRSA roles disabled)."
  value       = var.create_irsa_roles ? aws_iam_role.ebs_csi_driver[0].arn : ""
}
