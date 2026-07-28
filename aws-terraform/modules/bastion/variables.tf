# =============================================================================
# bastion module - variables
# =============================================================================

variable "name_prefix" {
  description = "Prefix applied to bastion resource names (e.g. cloudkitchen-dev)."
  type        = string
}

variable "subnet_id" {
  description = "Public subnet ID where the bastion host is launched."
  type        = string
}

variable "security_group_id" {
  description = "Security group ID for the bastion (from security-groups module)."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for the bastion host."
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "Name of an existing EC2 key pair for SSH access. Leave empty to launch without a key (SSM-only access)."
  type        = string
  default     = ""
}

variable "ami_id" {
  description = "Optional AMI ID. When empty, the latest Amazon Linux 2023 AMI is looked up automatically."
  type        = string
  default     = ""
}

variable "associate_public_ip" {
  description = "Whether to associate a public IP with the bastion."
  type        = bool
  default     = true
}

variable "root_volume_size" {
  description = "Root EBS volume size (GiB)."
  type        = number
  default     = 20
}

variable "tags" {
  description = "Common tags applied to all bastion resources."
  type        = map(string)
  default     = {}
}
