# =============================================================================
# Variable declarations
# =============================================================================
# Edit the *values* in terraform.tfvars, not the defaults here.
# =============================================================================

# -----------------------------------------------------------------------------
# Project / environment naming
# -----------------------------------------------------------------------------
variable "project" {
  description = "Project / name prefix applied to every resource."
  type        = string
  default     = "cloudkitchen"
}

variable "environment" {
  description = "Environment name (dev / staging / prod). Becomes part of names + tags."
  type        = string
  default     = "dev"
}

variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

# -----------------------------------------------------------------------------
# Networking (VPC)
# -----------------------------------------------------------------------------
variable "azs" {
  description = "Availability Zones to spread subnets across. Must be 3."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.10.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Three CIDRs for the public subnets (LB + bastion)."
  type        = list(string)
  default     = ["10.10.0.0/20", "10.10.16.0/20", "10.10.32.0/20"]
}

variable "private_subnet_cidrs" {
  description = "Three CIDRs for the private subnets (worker nodes)."
  type        = list(string)
  default     = ["10.10.48.0/20", "10.10.64.0/20", "10.10.80.0/20"]
}

variable "single_nat_gateway" {
  description = "If true, use ONE NAT gateway for all AZs (much cheaper; not HA). Set to false in prod."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# EKS cluster + worker nodes
# -----------------------------------------------------------------------------
variable "kubernetes_version" {
  description = "EKS Kubernetes version."
  type        = string
  default     = "1.30"
}

variable "node_instance_types" {
  description = "Worker node instance types (managed node group)."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Desired number of worker nodes."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of worker nodes."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of worker nodes."
  type        = number
  default     = 3
}

variable "endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the public EKS API endpoint. Tighten this for production."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# -----------------------------------------------------------------------------
# Bastion EC2 (jump host in a public subnet)
# -----------------------------------------------------------------------------
variable "bastion_allowed_cidrs" {
  description = "CIDRs allowed to SSH to the bastion. Restrict to your IP for production."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "bastion_instance_type" {
  description = "EC2 instance type for the bastion."
  type        = string
  default     = "t3.micro"
}

variable "bastion_key_name" {
  description = "Existing EC2 KeyPair name to attach to the bastion (leave empty to rely on AWS Systems Manager Session Manager instead of SSH)."
  type        = string
  default     = ""
}
