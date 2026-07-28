# =============================================================================
# bastion module
# =============================================================================
# A jump host in a PUBLIC subnet used to reach the private worker nodes and the
# (optionally private) Kubernetes API. It is hardened by:
#   * a restrictive SSH security group (managed in the security-groups module)
#   * an IAM instance profile granting SSM Session Manager + read-only EKS
#     describe, so operators can connect without exposing SSH at all
#   * encrypted root volume
# =============================================================================

# -----------------------------------------------------------------------------
# AMI lookup (Amazon Linux 2023) when an explicit AMI is not provided
# -----------------------------------------------------------------------------
data "aws_ami" "al2023" {
  count       = var.ami_id == "" ? 1 : 0
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  ami_id = var.ami_id != "" ? var.ami_id : data.aws_ami.al2023[0].id
}

# -----------------------------------------------------------------------------
# IAM instance profile (SSM + EKS describe)
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "bastion" {
  name               = "${var.name_prefix}-bastion-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = var.tags
}

# Allow connecting via SSM Session Manager (no inbound SSH required).
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Read-only access to describe the EKS cluster so operators can fetch kubeconfig.
resource "aws_iam_policy" "eks_describe" {
  name        = "${var.name_prefix}-bastion-eks-describe"
  description = "Allow the bastion to describe EKS clusters for kubeconfig generation"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters"
        ]
        Resource = "*"
      }
    ]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "eks_describe" {
  role       = aws_iam_role.bastion.name
  policy_arn = aws_iam_policy.eks_describe.arn
}

resource "aws_iam_instance_profile" "bastion" {
  name = "${var.name_prefix}-bastion-profile"
  role = aws_iam_role.bastion.name
  tags = var.tags
}

# -----------------------------------------------------------------------------
# Bastion EC2 instance
# -----------------------------------------------------------------------------
resource "aws_instance" "bastion" {
  ami                         = local.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [var.security_group_id]
  iam_instance_profile        = aws_iam_instance_profile.bastion.name
  associate_public_ip_address = var.associate_public_ip
  key_name                    = var.key_name != "" ? var.key_name : null

  metadata_options {
    # Enforce IMDSv2.
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  user_data = <<-EOF
    #!/bin/bash
    set -euo pipefail
    dnf update -y
    # Install kubectl and the AWS CLI v2 for cluster administration.
    dnf install -y awscli
    curl -sLO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm -f kubectl
  EOF

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-bastion"
  })
}
