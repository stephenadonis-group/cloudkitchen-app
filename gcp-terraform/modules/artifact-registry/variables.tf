variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "name_prefix" {
  description = "Resource name prefix (e.g. cloudkitchen-dev)."
  type        = string
}

variable "region" {
  description = "Region for the Artifact Registry repository."
  type        = string
}

variable "repository_id" {
  description = "Single Artifact Registry repository to create. All service images live inside it as <region>-docker.pkg.dev/<project>/<repository_id>/<image>:<tag>."
  type        = string
  default     = "cloudkitchen-registry"
}

variable "images" {
  description = "Logical image names that will be pushed into the repository. Used only to construct per-image URL prefixes in the module's outputs — no resources are created per image."
  type        = list(string)
}

variable "labels" {
  description = "Labels applied to the repository."
  type        = map(string)
  default     = {}
}
