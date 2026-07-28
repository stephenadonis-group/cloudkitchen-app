variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "name_prefix" {
  description = "Resource name prefix (e.g. cloudkitchen-dev)."
  type        = string
}

variable "cluster_name" {
  description = "Name of the GKE cluster."
  type        = string
}

variable "region" {
  description = "Region (used for regional clusters / regional resources)."
  type        = string
}

variable "zone" {
  description = "Zone (this module creates a zonal cluster)."
  type        = string
}

variable "network" {
  description = "VPC network self_link (from the vpc module)."
  type        = string
}

variable "subnet" {
  description = "Subnet self_link (from the vpc module)."
  type        = string
}

variable "pods_range_name" {
  description = "Secondary range name for GKE Pods (from the vpc module)."
  type        = string
}

variable "services_range_name" {
  description = "Secondary range name for GKE Services (from the vpc module)."
  type        = string
}

variable "master_ipv4_cidr" {
  description = "Private /28 used for the control-plane peering range."
  type        = string
}

variable "master_authorized_cidrs" {
  description = "Public CIDRs allowed to call the GKE control plane."
  type        = list(string)
}

variable "kubernetes_version" {
  description = "Kubernetes minor version (release channel may override patch)."
  type        = string
}

variable "release_channel" {
  description = "GKE release channel: RAPID | REGULAR | STABLE."
  type        = string
}

variable "node_machine_type" {
  description = "Worker node machine type."
  type        = string
}

variable "node_disk_size_gb" {
  description = "Worker node disk size in GB."
  type        = number
}

variable "node_count" {
  description = "Initial node count per zone."
  type        = number
}

variable "node_min_count" {
  description = "Cluster autoscaler minimum nodes."
  type        = number
}

variable "node_max_count" {
  description = "Cluster autoscaler maximum nodes."
  type        = number
}

variable "labels" {
  description = "Labels applied to the cluster + node pool."
  type        = map(string)
  default     = {}
}
