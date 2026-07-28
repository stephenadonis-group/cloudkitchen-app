output "network_name" {
  description = "VPC network name."
  value       = google_compute_network.this.name
}

output "network_self_link" {
  description = "Self link of the VPC network."
  value       = google_compute_network.this.self_link
}

output "subnet_self_link" {
  description = "Self link of the GKE subnet."
  value       = google_compute_subnetwork.gke.self_link
}

output "subnet_name" {
  description = "Name of the GKE subnet."
  value       = google_compute_subnetwork.gke.name
}

output "pods_range_name" {
  description = "Secondary range name to be used for GKE Pods."
  value       = "${var.name_prefix}-pods"
}

output "services_range_name" {
  description = "Secondary range name to be used for GKE Services."
  value       = "${var.name_prefix}-services"
}
