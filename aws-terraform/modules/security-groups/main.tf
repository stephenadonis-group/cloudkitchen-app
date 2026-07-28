# =============================================================================
# security-groups module
# =============================================================================
# Centralises the network access controls for the platform:
#   * bastion SG       - SSH access from a restricted CIDR list
#   * worker-node SG    - traffic between EKS worker nodes and to/from the
#                         control plane, plus SSH from the bastion
#   * control-plane SG  - the EKS managed cluster security group rules that
#                         allow the API server <-> worker node communication
#
# The cross-group rules are declared as standalone
# aws_security_group_rule resources to avoid circular dependencies between
# the worker and control-plane groups.
# =============================================================================

# -----------------------------------------------------------------------------
# Bastion security group
# -----------------------------------------------------------------------------
resource "aws_security_group" "bastion" {
  name        = "${var.name_prefix}-bastion-sg"
  description = "Allow SSH to the bastion host from approved CIDRs"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-bastion-sg"
  })
}

resource "aws_security_group_rule" "bastion_ssh_in" {
  type              = "ingress"
  description       = "SSH from approved CIDR blocks"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = var.bastion_allowed_cidrs
  security_group_id = aws_security_group.bastion.id
}

resource "aws_security_group_rule" "bastion_egress_all" {
  type              = "egress"
  description       = "Allow all outbound from bastion"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.bastion.id
}

# -----------------------------------------------------------------------------
# Worker node security group
# -----------------------------------------------------------------------------
resource "aws_security_group" "workers" {
  name        = "${var.name_prefix}-workers-sg"
  description = "Security group for EKS managed worker nodes"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-workers-sg"
    # Required so the AWS VPC CNI / cluster can discover the SG.
    "kubernetes.io/cluster/${var.name_prefix}" = "owned"
  })
}

resource "aws_security_group_rule" "workers_self" {
  type              = "ingress"
  description       = "Allow node-to-node communication"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  self              = true
  security_group_id = aws_security_group.workers.id
}

resource "aws_security_group_rule" "workers_ssh_from_bastion" {
  type                     = "ingress"
  description              = "SSH from the bastion host"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.bastion.id
  security_group_id        = aws_security_group.workers.id
}

resource "aws_security_group_rule" "workers_egress_all" {
  type              = "egress"
  description       = "Allow all outbound from worker nodes"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.workers.id
}

# -----------------------------------------------------------------------------
# Control-plane (cluster) security group
# -----------------------------------------------------------------------------
resource "aws_security_group" "control_plane" {
  name        = "${var.name_prefix}-control-plane-sg"
  description = "EKS control plane security group"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-control-plane-sg"
  })
}

resource "aws_security_group_rule" "control_plane_egress_all" {
  type              = "egress"
  description       = "Allow all outbound from control plane"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.control_plane.id
}

# -----------------------------------------------------------------------------
# Cross-group rules: control plane <-> workers
# -----------------------------------------------------------------------------

# Control plane receives the kubelet/extension-apiserver traffic from workers.
resource "aws_security_group_rule" "cp_ingress_from_workers" {
  type                     = "ingress"
  description              = "Allow workers to reach the API server (443)"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.workers.id
  security_group_id        = aws_security_group.control_plane.id
}

# Workers receive the kubelet + extension API traffic from the control plane.
resource "aws_security_group_rule" "workers_ingress_from_cp_kubelet" {
  type                     = "ingress"
  description              = "Control plane to worker kubelet/https (10250)"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.control_plane.id
  security_group_id        = aws_security_group.workers.id
}

resource "aws_security_group_rule" "workers_ingress_from_cp_ext" {
  type                     = "ingress"
  description              = "Control plane to worker extension API server ports"
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.control_plane.id
  security_group_id        = aws_security_group.workers.id
}
