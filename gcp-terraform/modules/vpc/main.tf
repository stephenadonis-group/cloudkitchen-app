# =============================================================================
# vpc module — Custom VPC + GKE subnet + Cloud NAT
# =============================================================================
# Provides:
#   * google_compute_network     — custom-mode VPC (no auto-created subnets)
#   * google_compute_subnetwork  — one regional subnet with TWO secondary ranges
#                                  (one for GKE Pods, one for GKE Services).
#                                  This pattern is required for VPC-native GKE.
#   * google_compute_router      — Cloud Router (control-plane for Cloud NAT)
#   * google_compute_router_nat  — Cloud NAT so private nodes can egress to
#                                  the internet without public IPs.
# =============================================================================

resource "google_compute_network" "this" {
  name                    = "${var.name_prefix}-vpc"
  project                 = var.project_id
  auto_create_subnetworks = false # we manage subnets explicitly
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "gke" {
  name          = "${var.name_prefix}-gke-subnet"
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.this.id
  ip_cidr_range = var.subnet_cidr

  # Secondary ranges — GKE assigns Pod and Service IPs from these.
  secondary_ip_range {
    range_name    = "${var.name_prefix}-pods"
    ip_cidr_range = var.pods_cidr
  }
  secondary_ip_range {
    range_name    = "${var.name_prefix}-services"
    ip_cidr_range = var.services_cidr
  }

  # Enable VPC flow logs (optional — small extra cost; great for debugging).
  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }

  # Required so nodes can reach Google APIs (Artifact Registry, logging, …)
  # without going through the public internet.
  private_ip_google_access = true
}

# -----------------------------------------------------------------------------
# Cloud Router + Cloud NAT — egress for private nodes / pods
# -----------------------------------------------------------------------------
resource "google_compute_router" "this" {
  name    = "${var.name_prefix}-router"
  project = var.project_id
  region  = var.region
  network = google_compute_network.this.id
}

resource "google_compute_router_nat" "this" {
  name                               = "${var.name_prefix}-nat"
  project                            = var.project_id
  router                             = google_compute_router.this.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
