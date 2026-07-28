# =============================================================================
# Variable declarations
# =============================================================================
# Edit the *values* in terraform.tfvars, not the defaults here.
# =============================================================================

# -----------------------------------------------------------------------------
# Project / environment / location
# -----------------------------------------------------------------------------
variable "project_id" {
  description = "GCP project ID to deploy into. REQUIRED — set in terraform.tfvars."
  type        = string
}

variable "project" {
  description = "Project / name prefix applied to every resource (NOT the GCP project ID)."
  type        = string
  default     = "cloudkitchen"
}

variable "environment" {
  description = "Environment name (dev / staging / prod)."
  type        = string
  default     = "dev"
}

variable "region" {
  description = "GCP region (regional resources: subnet, Cloud NAT, Artifact Registry)."
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone (zonal resources: GKE control plane when not regional, bastion VM)."
  type        = string
  default     = "us-central1-a"
}

# -----------------------------------------------------------------------------
# Networking (VPC + subnet + secondary ranges for GKE)
# -----------------------------------------------------------------------------
variable "subnet_cidr" {
  description = "Primary IPv4 range of the GKE subnet (node IPs)."
  type        = string
  default     = "10.10.0.0/20"
}

variable "pods_cidr" {
  description = "Secondary IPv4 range for GKE Pods (one IP per pod). Must be larger than nodes."
  type        = string
  default     = "10.20.0.0/16"
}

variable "services_cidr" {
  description = "Secondary IPv4 range for GKE Services (ClusterIPs)."
  type        = string
  default     = "10.30.0.0/20"
}

variable "master_ipv4_cidr" {
  description = "Private /28 used for the GKE control-plane peering range."
  type        = string
  default     = "172.16.0.0/28"
}

variable "master_authorized_cidrs" {
  description = "CIDRs allowed to call the GKE control plane (kubectl). Tighten for prod."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# -----------------------------------------------------------------------------
# GKE cluster + node pool
# -----------------------------------------------------------------------------
variable "kubernetes_version" {
  description = "GKE Kubernetes version (use 'latest' to follow the release channel)."
  type        = string
  default     = "1.30"
}

variable "release_channel" {
  description = "GKE release channel: RAPID | REGULAR | STABLE."
  type        = string
  default     = "REGULAR"
}

variable "node_machine_type" {
  description = "Machine type for the worker nodes."
  type        = string
  default     = "e2-medium"
}

variable "node_disk_size_gb" {
  description = "Boot disk size per node (GB)."
  type        = number
  default     = 50
}

variable "node_count" {
  description = "Desired number of nodes per zone (multiplied across the node pool's locations)."
  type        = number
  default     = 2
}

variable "node_min_count" {
  description = "Minimum node count (cluster autoscaler)."
  type        = number
  default     = 2
}

variable "node_max_count" {
  description = "Maximum node count (cluster autoscaler)."
  type        = number
  default     = 3
}

# -----------------------------------------------------------------------------
# Bastion (Compute Engine VM, reached via IAP)
# -----------------------------------------------------------------------------
variable "bastion_machine_type" {
  description = "Bastion VM size. e2-micro is part of GCP's always-free tier."
  type        = string
  default     = "e2-small"
}

variable "iap_allowed_users" {
  description = "GCP identities (user:, group:, serviceAccount:) allowed to IAP-tunnel SSH to the bastion. Add yours, e.g. user:you@gmail.com."
  type        = list(string)
  default     = []
}
