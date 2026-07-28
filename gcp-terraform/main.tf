# =============================================================================
# Root module — wires the platform modules together for GCP.
# =============================================================================
#
#                ┌──────────────────────────────────────────┐
#                │                vpc                       │
#                │  VPC + subnet (with secondary ranges     │
#                │  for pods/services) + Cloud NAT/Router   │
#                └─────────┬────────────────────────┬───────┘
#                          │                        │
#                          ▼                        ▼
#                  ┌──────────────┐         ┌──────────────┐
#                  │   firewall   │         │      iam     │
#                  │ (rules: IAP, │         │ (node SA +   │
#                  │  internal,   │         │  bastion SA) │
#                  │  health-chk) │         └──────┬───────┘
#                  └──────┬───────┘                │
#                         │                        │
#                         ▼                        ▼
#                  ┌──────────────────────────────────────┐
#                  │              gke                     │
#                  │ Cluster (private) + node pool        │
#                  │ + Workload Identity (built-in)       │
#                  └──────────────────────────────────────┘
#
#                  ┌──────────────┐         ┌──────────────┐
#                  │ artifact-reg │         │   bastion    │
#                  │ (9 repos)    │         │ (e2 VM, IAP) │
#                  └──────────────┘         └──────────────┘
# =============================================================================

locals {
  name_prefix  = "${var.project}-${var.environment}" # e.g. cloudkitchen-dev
  cluster_name = "${var.project}-${var.environment}"

  common_labels = {
    project     = var.project
    environment = var.environment
    managed_by  = "terraform"
  }

  # The 9 service Artifact Registry repos (matches the 9 ECR repos on AWS).
  service_repos = [
    "auth-service",
    "user-service",
    "restaurant-service",
    "menu-service",
    "order-service",
    "payment-service",
    "delivery-service",
    "notification-service",
    "frontend",
  ]
}

# -----------------------------------------------------------------------------
# IAM note (intentionally simple):
# Both the GKE nodes and the bastion use the project's DEFAULT Compute Engine
# Service Account (already has `roles/editor` on the project), with the broad
# `cloud-platform` OAuth scope. That gives them full project access — fine for
# a learning/personal-account setup. No custom Service Accounts to manage.
# Tighten this for production (least-privilege SAs + Workload Identity bindings).
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# VPC — network + GKE subnet (with secondary ranges) + Cloud NAT
# -----------------------------------------------------------------------------
module "vpc" {
  source = "./modules/vpc"

  project_id    = var.project_id
  name_prefix   = local.name_prefix
  region        = var.region
  subnet_cidr   = var.subnet_cidr
  pods_cidr     = var.pods_cidr
  services_cidr = var.services_cidr
}

# -----------------------------------------------------------------------------
# Firewall — internal traffic, IAP SSH, GCP health checks
# -----------------------------------------------------------------------------
module "firewall" {
  source = "./modules/firewall"

  project_id  = var.project_id
  name_prefix = local.name_prefix
  network     = module.vpc.network_name
  subnet_cidr = var.subnet_cidr
}

# -----------------------------------------------------------------------------
# GKE — cluster + node pool (private nodes + Workload Identity)
# -----------------------------------------------------------------------------
module "gke" {
  source = "./modules/gke"

  project_id              = var.project_id
  name_prefix             = local.name_prefix
  cluster_name            = local.cluster_name
  region                  = var.region
  zone                    = var.zone
  network                 = module.vpc.network_self_link
  subnet                  = module.vpc.subnet_self_link
  pods_range_name         = module.vpc.pods_range_name
  services_range_name     = module.vpc.services_range_name
  master_ipv4_cidr        = var.master_ipv4_cidr
  master_authorized_cidrs = var.master_authorized_cidrs

  kubernetes_version = var.kubernetes_version
  release_channel    = var.release_channel
  node_machine_type  = var.node_machine_type
  node_disk_size_gb  = var.node_disk_size_gb
  node_count         = var.node_count
  node_min_count     = var.node_min_count
  node_max_count     = var.node_max_count

  labels = local.common_labels
}

# -----------------------------------------------------------------------------
# Artifact Registry — ONE Docker repository ("cloudkitchen-registry") that
# holds every service image. Image URLs look like:
#   <region>-docker.pkg.dev/<project>/cloudkitchen-registry/<image>:<tag>
# -----------------------------------------------------------------------------
module "artifact_registry" {
  source = "./modules/artifact-registry"

  project_id    = var.project_id
  name_prefix   = local.name_prefix
  region        = var.region
  repository_id = "cloudkitchen-registry"
  images        = local.service_repos # reused as logical image names
  labels        = local.common_labels
}

# -----------------------------------------------------------------------------
# Bastion — Compute Engine VM, reachable only via IAP tunnel
# -----------------------------------------------------------------------------
module "bastion" {
  source = "./modules/bastion"

  project_id        = var.project_id
  name_prefix       = local.name_prefix
  zone              = var.zone
  network           = module.vpc.network_self_link
  subnet            = module.vpc.subnet_self_link
  machine_type      = var.bastion_machine_type
  iap_allowed_users = var.iap_allowed_users
  labels            = local.common_labels
}
