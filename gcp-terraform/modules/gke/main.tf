# =============================================================================
# gke module — GKE cluster + managed node pool
# =============================================================================
# Creates:
#   * google_container_cluster   — a zonal, private VPC-native GKE cluster with
#                                  Workload Identity, Network Policy, and
#                                  release-channel-managed Kubernetes version.
#   * google_container_node_pool — a managed node pool (e2-medium by default)
#                                  attached to that cluster, with autoscaling.
#
# Notes:
#   * Workload Identity is GCP's IRSA equivalent. Enabling it on the cluster
#     lets a Kubernetes ServiceAccount impersonate a Google Service Account.
#   * The cluster is `enable_private_nodes = true` → nodes have NO public IPs,
#     egress via the Cloud NAT created by the vpc module.
#   * Container-Optimized OS (`COS_CONTAINERD`) is the default and what we use.
# =============================================================================

# -----------------------------------------------------------------------------
# Cluster (control plane)
# -----------------------------------------------------------------------------
resource "google_container_cluster" "this" {
  provider = google-beta
  project  = var.project_id
  name     = var.cluster_name
  location = var.zone # zonal cluster — cheaper. Use var.region for HA.

  # We create our own node pool below, so remove the default one immediately.
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = var.network
  subnetwork = var.subnet

  # VPC-native (alias IPs) using secondary ranges from the vpc module.
  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  # Private cluster: nodes have no public IPs; control plane is reachable from
  # outside only at `master_authorized_networks` (we still allow public access
  # to the control plane endpoint for kubectl; tighten in prod).
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false # public endpoint open to authorized CIDRs
    master_ipv4_cidr_block  = var.master_ipv4_cidr
  }

  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.master_authorized_cidrs
      content {
        cidr_block   = cidr_blocks.value
        display_name = "authorized-${cidr_blocks.key}"
      }
    }
  }

  # Workload Identity — KSA <-> GSA federation (the GCP IRSA).
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Native Calico network policy.
  network_policy {
    enabled  = true
    provider = "CALICO"
  }

  # Release channel manages Kubernetes upgrades for us.
  release_channel {
    channel = var.release_channel
  }

  # Recommended addon toggles.
  addons_config {
    http_load_balancing {
      disabled = false # keep the GCP HTTP(S) LB controller available
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
    network_policy_config {
      disabled = false
    }
    gce_persistent_disk_csi_driver_config {
      enabled = true # GCE PD CSI for dynamic PVC provisioning
    }
  }

  # Logging + Monitoring with system + workload metrics.
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }
  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus {
      enabled = false # we install our own kube-prometheus-stack in Phase 6
    }
  }

  # Resource labels (NOT same as tags).
  resource_labels = var.labels

  # Deletion protection — turn ON for prod.
  deletion_protection = false

  lifecycle {
    ignore_changes = [
      # GKE auto-upgrades min/master version; don't recreate on drift.
      min_master_version,
    ]
  }
}

# -----------------------------------------------------------------------------
# Node pool (managed workers in the subnet)
# -----------------------------------------------------------------------------
resource "google_container_node_pool" "primary" {
  provider   = google-beta
  project    = var.project_id
  name       = "${var.name_prefix}-pool"
  location   = var.zone
  cluster    = google_container_cluster.this.name
  node_count = var.node_count

  autoscaling {
    min_node_count = var.node_min_count
    max_node_count = var.node_max_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }

  node_config {
    machine_type = var.node_machine_type
    disk_size_gb = var.node_disk_size_gb
    disk_type    = "pd-balanced"
    image_type   = "COS_CONTAINERD"

    # No `service_account` set — nodes use the project's DEFAULT Compute Engine
    # SA (which has roles/editor) with the broad cloud-platform scope.
    # Simpler for learning; tighten with a custom least-privilege SA in prod.
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    # Workload Identity at the pool level (required when WI is on the cluster).
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    labels = var.labels
    tags   = ["${var.name_prefix}-node"]

    metadata = {
      disable-legacy-endpoints = "true"
    }
  }

  lifecycle {
    ignore_changes = [node_count] # autoscaler manages this at runtime
  }
}
