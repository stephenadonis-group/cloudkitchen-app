output "cluster_name" {
  description = "Name of the GKE cluster."
  value       = google_container_cluster.this.name
}

output "cluster_endpoint" {
  description = "GKE control-plane endpoint (HTTPS)."
  value       = google_container_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded CA cert of the cluster control plane."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "cluster_location" {
  description = "Location (zone or region) of the cluster."
  value       = google_container_cluster.this.location
}

output "node_pool_name" {
  description = "Name of the managed node pool."
  value       = google_container_node_pool.primary.name
}

output "workload_identity_pool" {
  description = "Workload Identity pool used to federate KSAs <-> GCP SAs."
  value       = "${var.project_id}.svc.id.goog"
}
