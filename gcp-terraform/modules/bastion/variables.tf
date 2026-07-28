variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "name_prefix" {
  description = "Resource name prefix (e.g. cloudkitchen-dev)."
  type        = string
}

variable "zone" {
  description = "Zone for the bastion VM."
  type        = string
}

variable "network" {
  description = "VPC network self_link."
  type        = string
}

variable "subnet" {
  description = "Subnet self_link."
  type        = string
}

variable "machine_type" {
  description = "Bastion VM machine type."
  type        = string
  default     = "e2-small"
}

variable "iap_allowed_users" {
  description = "Identities allowed to IAP-tunnel SSH (e.g. user:you@gmail.com)."
  type        = list(string)
  default     = []
}

variable "labels" {
  description = "Labels on the VM."
  type        = map(string)
  default     = {}
}
