# =============================================================================
# eks module
# =============================================================================
# Provisions the managed Kubernetes control plane and worker nodes:
#   * aws_eks_cluster          - the control plane, attached to both public and
#                                private subnets; worker nodes themselves run
#                                ONLY in the private subnets
#   * OIDC provider            - enables IRSA (IAM Roles for Service Accounts)
#   * aws_eks_node_group        - managed worker nodes in the private subnets
#   * aws_eks_addon             - vpc-cni, coredns, kube-proxy
#
# IAM roles for the cluster and nodes are passed in from the iam module so all
# role management lives in one place.
# =============================================================================

# -----------------------------------------------------------------------------
# Control-plane log group
# -----------------------------------------------------------------------------
# Created explicitly so we own the retention. If left to EKS, the group is
# auto-created with "never expire" retention (unbounded cost). The name must
# match EKS's convention: /aws/eks/<cluster>/cluster.
resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.cluster_log_retention_days
  tags              = var.tags
}

# -----------------------------------------------------------------------------
# Control plane
# -----------------------------------------------------------------------------
resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = var.cluster_role_arn

  # Ensure our retention-managed log group exists before EKS starts logging.
  depends_on = [aws_cloudwatch_log_group.eks]

  vpc_config {
    # Attach both tiers: control plane ENIs + public LBs live in public subnets,
    # workloads/worker nodes are scheduled in the private subnets.
    subnet_ids              = concat(var.private_subnet_ids, var.public_subnet_ids)
    security_group_ids      = [var.control_plane_sg_id]
    endpoint_private_access = true
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.endpoint_public_access_cidrs
  }

  # Ship all control-plane log types to CloudWatch.
  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler",
  ]

  tags = merge(var.tags, {
    Name = var.cluster_name
  })
}

# -----------------------------------------------------------------------------
# OIDC provider (IRSA)
# -----------------------------------------------------------------------------
data "tls_certificate" "oidc" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "oidc" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-oidc"
  })
}

# -----------------------------------------------------------------------------
# Managed node group (workers in PRIVATE subnets)
# -----------------------------------------------------------------------------
resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-ng"
  node_role_arn   = var.node_role_arn
  # Workers run only in private subnets.
  subnet_ids = var.private_subnet_ids

  instance_types = var.node_instance_types
  capacity_type  = var.node_capacity_type
  disk_size      = var.node_disk_size

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  # Keep cluster running during rolling node replacements.
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-ng"
  })

  depends_on = [aws_eks_cluster.this]
}

# -----------------------------------------------------------------------------
# Core addons
# -----------------------------------------------------------------------------
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "vpc-cni"
  addon_version               = lookup(var.addon_versions, "vpc-cni", null)
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.tags

  # CNI must be healthy on the nodes before it can fully reconcile.
  depends_on = [aws_eks_node_group.this]
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "coredns"
  addon_version               = lookup(var.addon_versions, "coredns", null)
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.tags

  # CoreDNS schedules onto worker nodes, so they must exist first.
  depends_on = [aws_eks_node_group.this]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "kube-proxy"
  addon_version               = lookup(var.addon_versions, "kube-proxy", null)
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.tags

  depends_on = [aws_eks_node_group.this]
}
