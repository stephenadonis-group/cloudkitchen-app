variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "name_prefix" {
  description = "Resource name prefix."
  type        = string
}

variable "network" {
  description = "VPC network name (output from the vpc module)."
  type        = string
}

variable "subnet_cidr" {
  description = "Primary subnet CIDR — used by the allow-internal rule."
  type        = string
}
