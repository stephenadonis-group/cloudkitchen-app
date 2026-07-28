# =============================================================================
# firewall module — VPC firewall rules
# =============================================================================
# GCP's networking model uses firewall rules attached to the VPC (unlike AWS
# security groups which are per-resource). We add three rules:
#
#   1. allow-internal     — pod/node/service-to-anything inside the VPC
#   2. allow-iap-ssh      — Google IAP's TCP forwarder (35.235.240.0/20) can
#                            SSH to instances tagged "iap-ssh" (our bastion)
#   3. allow-health-check — GCP LB health-check sources (35.191.0.0/16,
#                            130.211.0.0/22) can reach load-balanced workloads
#
# Note: GKE itself adds extra firewall rules automatically for the cluster's
# control-plane <-> nodes traffic. We do NOT need to manage those here.
# =============================================================================

# Allow all traffic inside the VPC's primary subnet (nodes, pods, services).
resource "google_compute_firewall" "internal" {
  name    = "${var.name_prefix}-allow-internal"
  project = var.project_id
  network = var.network

  direction = "INGRESS"
  priority  = 1000

  source_ranges = [var.subnet_cidr]

  allow { protocol = "tcp" }
  allow { protocol = "udp" }
  allow { protocol = "icmp" }
}

# Allow Google IAP to forward SSH (port 22) to anything tagged `iap-ssh`.
# This is how we reach the bastion without exposing port 22 to the internet.
resource "google_compute_firewall" "iap_ssh" {
  name    = "${var.name_prefix}-allow-iap-ssh"
  project = var.project_id
  network = var.network

  direction = "INGRESS"
  priority  = 1000

  source_ranges = ["35.235.240.0/20"] # Google IAP's published source range
  target_tags   = ["iap-ssh"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

# Allow GCP LB health-check probers (their published IP ranges) to reach pods.
resource "google_compute_firewall" "health_checks" {
  name    = "${var.name_prefix}-allow-health-checks"
  project = var.project_id
  network = var.network

  direction = "INGRESS"
  priority  = 1000

  source_ranges = [
    "35.191.0.0/16",
    "130.211.0.0/22",
  ]

  allow {
    protocol = "tcp"
  }
}
