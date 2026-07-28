# =============================================================================
# security-groups module - variables
# =============================================================================
# Inputs required to build the bastion, worker-node, and control-plane
# security groups and the cross-group rules that wire them together.
# =============================================================================

variable "name_prefix" {
  description = "Prefix applied to all security group names (e.g. cloudkitchen-dev)."
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC the security groups are created in."
  type        = string
}

variable "vpc_cidr" {
  description = "Primary CIDR block of the VPC, used for intra-VPC allow rules."
  type        = string
}

variable "bastion_allowed_cidrs" {
  description = "List of CIDR blocks permitted to reach the bastion over SSH (port 22)."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "tags" {
  description = "Common tags applied to every security group."
  type        = map(string)
  default     = {}
}
