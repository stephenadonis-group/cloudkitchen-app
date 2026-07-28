# =============================================================================
# Variable VALUES — edit this file to change what gets provisioned.
# =============================================================================
# Small, cost-friendly footprint:
#   * 1 zonal GKE cluster + 2x e2-medium nodes
#   * 1 Cloud NAT
#   * 1 bastion e2-small (or e2-micro = free-tier)
# Approx ~$3–$6/day while running (first zonal cluster's control plane is FREE
# under GKE's free tier — $74.40/month credit).
# =============================================================================

# GCP project this deployment lives in.
project_id = "project-d31a3358-346c-40e8-bda"

project     = "cloudkitchen"
environment = "dev"

region = "us-central1"
zone   = "us-central1-a"

# --- networking ---
subnet_cidr      = "10.10.0.0/20"
pods_cidr        = "10.20.0.0/16"
services_cidr    = "10.30.0.0/20"
master_ipv4_cidr = "172.16.0.0/28"

# Tighten this to your IP/office CIDR for real deployments.
master_authorized_cidrs = ["0.0.0.0/0"]

# --- GKE ---
kubernetes_version = "1.30"
release_channel    = "REGULAR"
node_machine_type  = "e2-medium"
node_disk_size_gb  = 50
node_count         = 2
node_min_count     = 2
node_max_count     = 3

# --- bastion ---
bastion_machine_type = "e2-small"
# Add yourself so you can IAP-SSH to the bastion. Example:
#   iap_allowed_users = ["user:you@gmail.com"]
iap_allowed_users = []
