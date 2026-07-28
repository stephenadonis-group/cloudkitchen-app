# =============================================================================
# eks module - variables
# =============================================================================

variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes control plane version."
  type        = string
  default     = "1.30"
}

variable "cluster_role_arn" {
  description = "ARN of the IAM role assumed by the EKS control plane (from iam module)."
  type        = string
}

variable "node_role_arn" {
  description = "ARN of the IAM role assumed by the managed worker nodes (from iam module)."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs where the worker nodes are launched."
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Public subnet IDs attached to the cluster for public load balancers."
  type        = list(string)
}

variable "control_plane_sg_id" {
  description = "Security group ID for the EKS control plane (from security-groups module)."
  type        = string
}

variable "endpoint_public_access" {
  description = "Whether the Kubernetes API server endpoint is publicly accessible."
  type        = bool
  default     = true
}

variable "endpoint_public_access_cidrs" {
  description = "CIDR blocks allowed to reach the public API server endpoint."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "node_instance_types" {
  description = "EC2 instance types for the managed node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_disk_size" {
  description = "EBS volume size (GiB) for each worker node."
  type        = number
  default     = 50
}

variable "node_capacity_type" {
  description = "Capacity type for the node group: ON_DEMAND or SPOT."
  type        = string
  default     = "ON_DEMAND"
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

variable "addon_versions" {
  description = "Optional explicit addon versions keyed by addon name (vpc-cni, coredns, kube-proxy). Leave empty to let EKS pick the default for the cluster version."
  type        = map(string)
  default     = {}
}

variable "cluster_log_retention_days" {
  description = "Retention period (days) for the EKS control-plane CloudWatch log group."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Common tags applied to all EKS resources."
  type        = map(string)
  default     = {}
}
