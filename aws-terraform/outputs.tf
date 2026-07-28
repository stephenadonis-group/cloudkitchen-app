# =============================================================================
# Outputs — printed after `terraform apply`. Useful for the next steps in the
# deployment (kubeconfig, ECR push, ArgoCD wiring).
# =============================================================================

output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "kubeconfig_command" {
  description = "Run this to point your local kubectl at the cluster."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "ecr_repository_urls" {
  description = "Map of microservice name -> ECR repository URL. Tag and push your images to these."
  value       = module.ecr.repository_urls
}

output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (where worker nodes run)."
  value       = module.vpc.private_subnet_ids
}

output "bastion_public_ip" {
  description = "Public IP of the bastion host. Use SSM Session Manager or SSH (if bastion_key_name was set)."
  value       = module.bastion.bastion_public_ip
}

output "irsa_role_arns" {
  description = "IAM role ARNs for IRSA-enabled cluster add-ons. Pass these into the relevant Helm values."
  value = {
    aws_load_balancer_controller = module.iam.aws_load_balancer_controller_role_arn
    external_dns                 = module.iam.external_dns_role_arn
    cert_manager                 = module.iam.cert_manager_role_arn
    ebs_csi_driver               = module.iam.ebs_csi_driver_role_arn
  }
}
