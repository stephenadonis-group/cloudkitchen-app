# =============================================================================
# iam module
# =============================================================================
# Provides all IAM roles for the platform:
#   * EKS cluster role  - assumed by the EKS control plane service
#   * EKS node role     - assumed by the managed worker nodes (EC2)
#   * IRSA roles        - IAM Roles for Service Accounts, federated through the
#                         cluster OIDC provider, for:
#                           - AWS Load Balancer Controller
#                           - external-dns
#                           - cert-manager (Route53 DNS-01 solver)
#
# The cluster/node roles are always created. The IRSA roles depend on the EKS
# OIDC provider, so they are gated behind create_irsa_roles and are typically
# wired up once the cluster (and its OIDC provider) exists.
# =============================================================================

# -----------------------------------------------------------------------------
# EKS cluster role
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "eks_cluster_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.name_prefix}-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster_eks_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "cluster_vpc_resource_controller" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}

# -----------------------------------------------------------------------------
# EKS node (worker) role
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "eks_node_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.name_prefix}-eks-node-role"
  assume_role_policy = data.aws_iam_policy_document.eks_node_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr_readonly" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "node_ssm" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# -----------------------------------------------------------------------------
# IRSA - reusable assume-role policy generator
# -----------------------------------------------------------------------------
# Builds a trust policy that federates a specific Kubernetes ServiceAccount
# (namespace:name) to assume the role via the cluster OIDC provider.
locals {
  # Strip any scheme just in case the caller passed a full URL.
  oidc_url_clean = replace(var.oidc_provider_url, "https://", "")

  irsa_service_accounts = {
    aws_load_balancer_controller = "system:serviceaccount:kube-system:aws-load-balancer-controller"
    external_dns                 = "system:serviceaccount:kube-system:external-dns"
    cert_manager                 = "system:serviceaccount:cert-manager:cert-manager"
    ebs_csi_driver               = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
  }
}

data "aws_iam_policy_document" "irsa_assume" {
  for_each = var.create_irsa_roles ? local.irsa_service_accounts : {}

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url_clean}:sub"
      values   = [each.value]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url_clean}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

# -----------------------------------------------------------------------------
# IRSA role: AWS Load Balancer Controller
# -----------------------------------------------------------------------------
resource "aws_iam_role" "aws_load_balancer_controller" {
  count              = var.create_irsa_roles ? 1 : 0
  name               = "${var.name_prefix}-alb-controller-irsa"
  assume_role_policy = data.aws_iam_policy_document.irsa_assume["aws_load_balancer_controller"].json
  tags               = var.tags
}

# Scoped-down policy covering the ELB/EC2/ACM/WAF actions the controller needs.
resource "aws_iam_policy" "aws_load_balancer_controller" {
  count       = var.create_irsa_roles ? 1 : 0
  name        = "${var.name_prefix}-alb-controller-policy"
  description = "Permissions for the AWS Load Balancer Controller"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:CreateServiceLinkedRole"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "iam:AWSServiceName" = "elasticloadbalancing.amazonaws.com"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeAccountAttributes",
          "ec2:DescribeAddresses",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeInternetGateways",
          "ec2:DescribeVpcs",
          "ec2:DescribeVpcPeeringConnections",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeInstances",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeTags",
          "ec2:GetCoipPoolUsage",
          "ec2:DescribeCoipPools",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeListenerCertificates",
          "elasticloadbalancing:DescribeSSLPolicies",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetGroupAttributes",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:DescribeTags"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cognito-idp:DescribeUserPoolClient",
          "acm:ListCertificates",
          "acm:DescribeCertificate",
          "iam:ListServerCertificates",
          "iam:GetServerCertificate",
          "waf-regional:GetWebACL",
          "waf-regional:GetWebACLForResource",
          "waf-regional:AssociateWebACL",
          "waf-regional:DisassociateWebACL",
          "wafv2:GetWebACL",
          "wafv2:GetWebACLForResource",
          "wafv2:AssociateWebACL",
          "wafv2:DisassociateWebACL",
          "shield:GetSubscriptionState",
          "shield:DescribeProtection",
          "shield:CreateProtection",
          "shield:DeleteProtection"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:CreateSecurityGroup",
          "ec2:CreateTags",
          "ec2:DeleteTags",
          "ec2:DeleteSecurityGroup",
          "elasticloadbalancing:CreateLoadBalancer",
          "elasticloadbalancing:CreateTargetGroup",
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:CreateRule",
          "elasticloadbalancing:DeleteRule",
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:RemoveTags",
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:SetIpAddressType",
          "elasticloadbalancing:SetSecurityGroups",
          "elasticloadbalancing:SetSubnets",
          "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:ModifyTargetGroupAttributes",
          "elasticloadbalancing:DeleteTargetGroup",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:DeregisterTargets",
          "elasticloadbalancing:SetWebAcl",
          "elasticloadbalancing:AddListenerCertificates",
          "elasticloadbalancing:RemoveListenerCertificates"
        ]
        Resource = "*"
      }
    ]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "aws_load_balancer_controller" {
  count      = var.create_irsa_roles ? 1 : 0
  role       = aws_iam_role.aws_load_balancer_controller[0].name
  policy_arn = aws_iam_policy.aws_load_balancer_controller[0].arn
}

# -----------------------------------------------------------------------------
# IRSA role: external-dns (Route53 record management)
# -----------------------------------------------------------------------------
resource "aws_iam_role" "external_dns" {
  count              = var.create_irsa_roles ? 1 : 0
  name               = "${var.name_prefix}-external-dns-irsa"
  assume_role_policy = data.aws_iam_policy_document.irsa_assume["external_dns"].json
  tags               = var.tags
}

resource "aws_iam_policy" "external_dns" {
  count       = var.create_irsa_roles ? 1 : 0
  name        = "${var.name_prefix}-external-dns-policy"
  description = "Permissions for external-dns to manage Route53 records"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["route53:ChangeResourceRecordSets"]
        Resource = ["arn:aws:route53:::hostedzone/*"]
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones",
          "route53:ListResourceRecordSets",
          "route53:ListTagsForResource"
        ]
        Resource = ["*"]
      }
    ]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "external_dns" {
  count      = var.create_irsa_roles ? 1 : 0
  role       = aws_iam_role.external_dns[0].name
  policy_arn = aws_iam_policy.external_dns[0].arn
}

# -----------------------------------------------------------------------------
# IRSA role: cert-manager (Route53 DNS-01 challenge solver)
# -----------------------------------------------------------------------------
resource "aws_iam_role" "cert_manager" {
  count              = var.create_irsa_roles ? 1 : 0
  name               = "${var.name_prefix}-cert-manager-irsa"
  assume_role_policy = data.aws_iam_policy_document.irsa_assume["cert_manager"].json
  tags               = var.tags
}

resource "aws_iam_policy" "cert_manager" {
  count       = var.create_irsa_roles ? 1 : 0
  name        = "${var.name_prefix}-cert-manager-policy"
  description = "Permissions for cert-manager DNS-01 solving via Route53"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["route53:GetChange"]
        Resource = ["arn:aws:route53:::change/*"]
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets",
          "route53:ListResourceRecordSets"
        ]
        Resource = ["arn:aws:route53:::hostedzone/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["route53:ListHostedZonesByName"]
        Resource = ["*"]
      }
    ]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "cert_manager" {
  count      = var.create_irsa_roles ? 1 : 0
  role       = aws_iam_role.cert_manager[0].name
  policy_arn = aws_iam_policy.cert_manager[0].arn
}

# -----------------------------------------------------------------------------
# IRSA role: Amazon EBS CSI driver
# -----------------------------------------------------------------------------
# Required for dynamic EBS volume provisioning. Without this, the PersistentVolume
# Claims for the PostgreSQL and RabbitMQ StatefulSets stay Pending and the pods
# never start. Uses the AWS-managed AmazonEBSCSIDriverPolicy.
resource "aws_iam_role" "ebs_csi_driver" {
  count              = var.create_irsa_roles ? 1 : 0
  name               = "${var.name_prefix}-ebs-csi-irsa"
  assume_role_policy = data.aws_iam_policy_document.irsa_assume["ebs_csi_driver"].json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi_driver" {
  count      = var.create_irsa_roles ? 1 : 0
  role       = aws_iam_role.ebs_csi_driver[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}
