# =============================================================================
# ecr module - variables
# =============================================================================

variable "name_prefix" {
  description = "Prefix applied to each repository name (e.g. cloudkitchen-dev)."
  type        = string
}

variable "services" {
  description = "List of microservice names; one ECR repository is created per service."
  type        = list(string)
  default = [
    "auth",
    "user",
    "restaurant",
    "menu",
    "order",
    "payment",
    "delivery",
    "notification",
    "frontend",
  ]
}

variable "image_tag_mutability" {
  description = "Whether image tags can be overwritten. IMMUTABLE is recommended for prod."
  type        = string
  default     = "IMMUTABLE"
}

variable "keep_last_images" {
  description = "Number of most-recent images to retain in each repository."
  type        = number
  default     = 20
}

variable "force_delete" {
  description = "Allow deletion of repositories that still contain images."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Common tags applied to all repositories."
  type        = map(string)
  default     = {}
}
