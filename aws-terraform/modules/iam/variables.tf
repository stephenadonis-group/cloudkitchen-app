# =============================================================================
# iam module - variables
# =============================================================================

variable "name_prefix" {
  description = "Prefix applied to IAM resource names (e.g. cloudkitchen-dev)."
  type        = string
}

variable "create_irsa_roles" {
  description = "Whether to create the IRSA roles. These depend on the EKS OIDC provider existing, so they are created in a second apply phase or after the cluster is up."
  type        = bool
  default     = true
}

variable "oidc_provider_arn" {
  description = "ARN of the EKS cluster OIDC provider (from the eks module). Required when create_irsa_roles is true."
  type        = string
  default     = ""
}

variable "oidc_provider_url" {
  description = "URL of the EKS cluster OIDC provider WITHOUT the https:// prefix (e.g. oidc.eks.us-east-1.amazonaws.com/id/XXXX)."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Common tags applied to all IAM resources."
  type        = map(string)
  default     = {}
}
