# =============================================================================
# bastion module — small Compute Engine VM, reachable only via IAP tunneling
# =============================================================================
# Why a bastion?
#   * Persistent workstation inside the VPC for kubectl/helm work.
#   * No public IP — connect via `gcloud compute ssh --tunnel-through-iap`,
#     so port 22 is never exposed to the internet.
#   * Network tag "iap-ssh" matches the firewall rule from the firewall module.
#
# A startup script pre-installs kubectl, helm, and the GKE auth plugin so the
# bastion is ready to go on first boot.
# =============================================================================

locals {
  startup_script = <<-EOT
    #!/bin/bash
    set -euxo pipefail

    # Install kubectl
    curl -sLO "https://dl.k8s.io/release/v1.30.5/bin/linux/amd64/kubectl"
    chmod +x kubectl && mv kubectl /usr/local/bin/

    # Install Helm v3
    curl -sSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

    # GKE auth plugin (so kubectl can talk to GKE)
    apt-get update -y
    apt-get install -y google-cloud-cli-gke-gcloud-auth-plugin

    echo "Bastion is ready. Run: gcloud container clusters get-credentials ..."
  EOT
}

resource "google_compute_instance" "bastion" {
  project      = var.project_id
  name         = "${var.name_prefix}-bastion"
  machine_type = var.machine_type
  zone         = var.zone

  # No public IP — IAP-only.
  network_interface {
    network    = var.network
    subnetwork = var.subnet
    # NO access_config block ⇒ no external IP
  }

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 20
      type  = "pd-balanced"
    }
  }

  # No `email` set — uses the project's DEFAULT Compute Engine SA
  # (already has roles/editor on the project). cloud-platform scope = full
  # access from this VM. Simple by design; tighten in prod.
  service_account {
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  # Firewall rule "allow-iap-ssh" targets this tag.
  tags = ["iap-ssh"]

  metadata = {
    enable-oslogin = "TRUE" # IAM-based SSH access
    startup-script = local.startup_script
  }

  labels = var.labels

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  allow_stopping_for_update = true
}

# -----------------------------------------------------------------------------
# Grant the listed users permission to IAP-tunnel SSH into the bastion.
# -----------------------------------------------------------------------------
resource "google_iap_tunnel_instance_iam_member" "iap_users" {
  for_each = toset(var.iap_allowed_users)

  project  = var.project_id
  zone     = google_compute_instance.bastion.zone
  instance = google_compute_instance.bastion.name
  role     = "roles/iap.tunnelResourceAccessor"
  member   = each.value
}

# OS Login grants — let the same users actually log in once the IAP tunnel
# is established.
resource "google_project_iam_member" "os_login_user" {
  for_each = toset(var.iap_allowed_users)

  project = var.project_id
  role    = "roles/compute.osLogin"
  member  = each.value
}
