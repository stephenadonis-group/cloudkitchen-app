variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "name_prefix" {
  description = "Resource name prefix (e.g. cloudkitchen-dev)."
  type        = string
}

variable "region" {
  description = "Region for the subnet, router, and Cloud NAT."
  type        = string
}

variable "subnet_cidr" {
  description = "Primary IPv4 range of the GKE subnet (node IPs)."
  type        = string
}

variable "pods_cidr" {
  description = "Secondary IPv4 range for GKE Pods."
  type        = string
}

variable "services_cidr" {
  description = "Secondary IPv4 range for GKE Services."
  type        = string
}
