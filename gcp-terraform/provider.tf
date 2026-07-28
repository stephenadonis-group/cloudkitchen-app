# =============================================================================
# Terraform & Google Cloud provider configuration
# =============================================================================
# - Pins the Terraform CLI version (>= 1.5) and provider versions.
# - Configures the google provider with the project + region from variables.
# - Backend: LOCAL state by default (state lives in this folder as
#   `terraform.tfstate`). Simplest setup for learning — no GCS bucket to create
#   first. For real/team work, uncomment the GCS backend below.
# =============================================================================

terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
  }

  # ---------------------------------------------------------------------------
  # Remote state: GCS backend
  # ---------------------------------------------------------------------------
  # Bucket: cloudkitchen-tfstate-585510587062
  #   - location: us-central1
  #   - versioning enabled (keeps history of state changes)
  #   - uniform bucket-level access enforced
  #   - public access blocked
  #   - lifecycle: keeps last 10 noncurrent versions for 30 days, then deletes
  # State path inside the bucket: cloudkitchen/default.tfstate
  # ---------------------------------------------------------------------------
  backend "gcs" {
    bucket = "cloudkitchen-tfstate-585510587062"
    prefix = "cloudkitchen"
  }
}

# Google Cloud provider. Project + region come from terraform.tfvars.
# Credentials resolve in this order:
#   1. GOOGLE_APPLICATION_CREDENTIALS env var (a service-account JSON file path)
#   2. `gcloud auth application-default login` cached credentials
#   3. Workload Identity if running inside GCP
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}
