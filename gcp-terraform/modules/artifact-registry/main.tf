# =============================================================================
# artifact-registry module — ONE Docker repository, many images inside it
# =============================================================================
# Pattern: a single Artifact Registry repository (default: "cloudkitchen-registry")
# holds all the service images. On GCP, image URLs look like:
#
#   <region>-docker.pkg.dev/<project>/<repo>/<image>:<tag>
#
# e.g. us-central1-docker.pkg.dev/my-project/cloudkitchen-registry/auth-service:1.0.0
#
# `var.images` is *informational only* — it doesn't create any resources, but
# the module's `repository_urls` output composes per-image URL prefixes for
# every name in the list, so downstream code (CI / Helm values) doesn't need
# to know there's only one underlying repository.
# =============================================================================

resource "google_artifact_registry_repository" "this" {
  project       = var.project_id
  location      = var.region
  repository_id = var.repository_id
  description   = "${var.name_prefix} — all CloudKitchen container images"
  format        = "DOCKER"
  labels        = var.labels

  # Keep up to the 30 most-recent versions per image.
  cleanup_policies {
    id     = "keep-last-30"
    action = "KEEP"
    most_recent_versions {
      keep_count = 30
    }
  }

  # And delete untagged versions older than 90 days.
  cleanup_policies {
    id     = "delete-old-untagged"
    action = "DELETE"
    condition {
      tag_state  = "UNTAGGED"
      older_than = "7776000s" # 90 days
    }
  }
}
