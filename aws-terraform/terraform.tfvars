# =============================================================================
# Variable VALUES — edit this file to change what gets provisioned.
# =============================================================================
# Defaults below are tuned for a small, cost-friendly learning deployment in
# us-east-1: 2x t3.medium nodes, single NAT gateway.
# Roughly $4–$8 per day while the cluster is running.
# =============================================================================

project     = "cloudkitchen"
environment = "dev"
region      = "us-east-1"

# --- networking ---
azs                  = ["us-east-1a", "us-east-1b", "us-east-1c"]
vpc_cidr             = "10.10.0.0/16"
public_subnet_cidrs  = ["10.10.0.0/20", "10.10.16.0/20", "10.10.32.0/20"]
private_subnet_cidrs = ["10.10.48.0/20", "10.10.64.0/20", "10.10.80.0/20"]
single_nat_gateway   = true # one NAT instead of three saves ~$60/month

# --- EKS ---
kubernetes_version  = "1.30"
node_instance_types = ["t3.medium"]
node_desired_size   = 2
node_min_size       = 2
node_max_size       = 3

# --- security: tighten these to your IP/office CIDR for real deployments ---
endpoint_public_access_cidrs = ["0.0.0.0/0"]
bastion_allowed_cidrs        = ["0.0.0.0/0"]

# --- bastion ---
bastion_instance_type = "t3.micro"
# Set to an existing EC2 KeyPair name to enable SSH; leave empty to use SSM only.
bastion_key_name = ""
