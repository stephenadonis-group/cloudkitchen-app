# =============================================================================
# Root module — wires the platform modules together.
# =============================================================================
#
#                          ┌──────────────┐
#                          │     iam      │  (cluster + node roles,
#                          └──────┬───────┘   IRSA roles via OIDC)
#                                 │
#                  ┌──────────────┴───────────────┐
#                  ▼                              ▼
#         ┌──────────────┐               ┌──────────────┐
#         │     vpc      │ ─────────────▶│     eks      │ ─── creates OIDC ──┐
#         └──────┬───────┘               └──────┬───────┘                    │
#                │                              │                            │
#                ▼                              ▼                            │
#       ┌─────────────────┐             ┌──────────────┐                     │
#       │ security-groups │             │   ecr       │                     │
#       └─────────────────┘             │   bastion   │                     │
#                                       └──────────────┘                     │
#                                                                            ▼
#                                           ┌──────────────────────────────────────┐
#                                           │  aws_eks_addon "aws-ebs-csi-driver"  │
#                                           │  (consumes IAM IRSA role + OIDC)     │
#                                           └──────────────────────────────────────┘
#
# The iam module has no OIDC dependency for cluster/node roles, so it can run
# first; its IRSA roles consume eks.oidc_* outputs. Terraform resolves this at
# the resource level, so there is no cycle.
# =============================================================================

locals {
  name_prefix  = "${var.project}-${var.environment}"
  cluster_name = "${var.project}-${var.environment}"

  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# -----------------------------------------------------------------------------
# IAM — cluster role, node role, and IRSA roles
# -----------------------------------------------------------------------------
module "iam" {
  source = "./modules/iam"

  name_prefix       = local.name_prefix
  create_irsa_roles = true
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  tags              = local.common_tags
}

# -----------------------------------------------------------------------------
# VPC — network foundation (public + private subnets, NAT, IGW, route tables)
# -----------------------------------------------------------------------------
module "vpc" {
  source = "./modules/vpc"

  name_prefix          = local.name_prefix
  cluster_name         = local.cluster_name
  vpc_cidr             = var.vpc_cidr
  azs                  = var.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  single_nat_gateway   = var.single_nat_gateway
  tags                 = local.common_tags
}

# -----------------------------------------------------------------------------
# Security groups — bastion, worker nodes, control plane
# -----------------------------------------------------------------------------
module "security_groups" {
  source = "./modules/security-groups"

  name_prefix           = local.name_prefix
  vpc_id                = module.vpc.vpc_id
  vpc_cidr              = module.vpc.vpc_cidr
  bastion_allowed_cidrs = var.bastion_allowed_cidrs
  tags                  = local.common_tags
}

# -----------------------------------------------------------------------------
# EKS — control plane + managed worker nodes (workers run in private subnets)
# -----------------------------------------------------------------------------
module "eks" {
  source = "./modules/eks"

  cluster_name       = local.cluster_name
  kubernetes_version = var.kubernetes_version

  cluster_role_arn = module.iam.cluster_role_arn
  node_role_arn    = module.iam.node_role_arn

  private_subnet_ids  = module.vpc.private_subnet_ids
  public_subnet_ids   = module.vpc.public_subnet_ids
  control_plane_sg_id = module.security_groups.control_plane_sg_id

  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.endpoint_public_access_cidrs

  node_instance_types = var.node_instance_types
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# ECR — one private repository per microservice
# -----------------------------------------------------------------------------
module "ecr" {
  source = "./modules/ecr"

  name_prefix = local.name_prefix
  # Mutable tags = easy iteration in dev; flip to IMMUTABLE for prod.
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  keep_last_images     = 20
  tags                 = local.common_tags
}

# -----------------------------------------------------------------------------
# Bastion — small EC2 jump host in a public subnet
# -----------------------------------------------------------------------------
module "bastion" {
  source = "./modules/bastion"

  name_prefix       = local.name_prefix
  subnet_id         = module.vpc.public_subnet_ids[0]
  security_group_id = module.security_groups.bastion_sg_id
  instance_type     = var.bastion_instance_type
  key_name          = var.bastion_key_name
  tags              = local.common_tags
}

# -----------------------------------------------------------------------------
# EBS CSI driver addon — dynamic EBS volume provisioning for PVCs
# -----------------------------------------------------------------------------
# Required by the PostgreSQL and RabbitMQ StatefulSets; without it their PVCs
# stay Pending. Declared here (not in the eks module) so it can consume the IRSA
# role from the iam module without forming an eks<->iam module dependency cycle.
resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "aws-ebs-csi-driver"
  service_account_role_arn    = module.iam.ebs_csi_driver_role_arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = local.common_tags

  # Needs worker nodes (to schedule the controller) and the IRSA role to exist.
  depends_on = [module.eks, module.iam]
}
