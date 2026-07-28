output "repository_id" {
  description = "The single Artifact Registry repository name."
  value       = google_artifact_registry_repository.this.repository_id
}

output "registry_host" {
  description = "Common Artifact Registry hostname for `docker login`."
  value       = "${var.region}-docker.pkg.dev"
}

output "repository_base_url" {
  description = "The repository URL prefix shared by every image (no image name)."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.this.repository_id}"
}

output "repository_urls" {
  description = "Map of logical image name -> full Artifact Registry image URL prefix (push images here)."
  value = {
    for image in var.images :
    image => "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.this.repository_id}/${image}"
  }
}
