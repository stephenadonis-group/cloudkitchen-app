# =============================================================================
# vpc module - variables
# =============================================================================

variable "name_prefix" {
  description = "Prefix applied to VPC resource names (e.g. cloudkitchen-dev)."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name; used for the kubernetes.io/cluster shared tags."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "List of 3 Availability Zones to spread subnets across."
  type        = list(string)

  validation {
    condition     = length(var.azs) == 3
    error_message = "Exactly 3 availability zones must be provided."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the 3 public subnets (one per AZ)."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) == 3
    error_message = "Exactly 3 public subnet CIDRs must be provided."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the 3 private subnets (one per AZ)."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_cidrs) == 3
    error_message = "Exactly 3 private subnet CIDRs must be provided."
  }
}

variable "single_nat_gateway" {
  description = "If true, provision a single NAT gateway (cost-saving for non-prod). If false, one NAT gateway per AZ for HA."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common tags applied to all VPC resources."
  type        = map(string)
  default     = {}
}
