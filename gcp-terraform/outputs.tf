# =============================================================================
# Outputs — printed after `terraform apply`. Used by the next steps.
# =============================================================================

output "project_id" {
  description = "GCP project we deployed into."
  value       = var.project_id
}

output "region" {
  description = "GCP region."
  value       = var.region
}

output "cluster_name" {
  description = "GKE cluster name."
  value       = module.gke.cluster_name
}

output "cluster_endpoint" {
  description = "GKE control-plane endpoint (private)."
  value       = module.gke.cluster_endpoint
  sensitive   = true
}

output "kubeconfig_command" {
  description = "Run this to point your local kubectl at the new cluster."
  value       = "gcloud container clusters get-credentials ${module.gke.cluster_name} --zone ${var.zone} --project ${var.project_id}"
}

output "artifact_registry_urls" {
  description = "Map of service -> Artifact Registry Docker image URL prefix."
  value       = module.artifact_registry.repository_urls
}

output "bastion_name" {
  description = "Compute Engine bastion VM name. Connect with `gcloud compute ssh --tunnel-through-iap`."
  value       = module.bastion.instance_name
}

output "bastion_ssh_command" {
  description = "Ready-to-run command to IAP-tunnel SSH to the bastion."
  value       = "gcloud compute ssh ${module.bastion.instance_name} --zone ${var.zone} --tunnel-through-iap --project ${var.project_id}"
}

output "vpc_name" {
  description = "VPC network name."
  value       = module.vpc.network_name
}
