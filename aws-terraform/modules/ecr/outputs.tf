# =============================================================================
# ecr module - outputs
# =============================================================================

output "repository_urls" {
  description = "Map of service name -> ECR repository URL."
  value       = { for svc, repo in aws_ecr_repository.this : svc => repo.repository_url }
}

output "repository_arns" {
  description = "Map of service name -> ECR repository ARN."
  value       = { for svc, repo in aws_ecr_repository.this : svc => repo.arn }
}

output "repository_names" {
  description = "Map of service name -> ECR repository name."
  value       = { for svc, repo in aws_ecr_repository.this : svc => repo.name }
}
