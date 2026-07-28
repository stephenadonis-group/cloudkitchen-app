# =============================================================================
# Terraform & AWS provider configuration
# =============================================================================
# - Pins the Terraform CLI version (>= 1.5) and provider versions.
# - Configures the AWS provider with the region from var.region.
# - Backend: LOCAL state by default (state lives in this folder as
#   `terraform.tfstate`). This is the simplest setup to learn with — no S3
#   bucket or DynamoDB table to create first. For a real shared/production
#   environment, switch to the S3 backend block below (and create the bucket
#   + lock table out-of-band before running `terraform init`).
# =============================================================================

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # ---------------------------------------------------------------------------
  # Remote state (UNCOMMENT for shared/production use)
  # ---------------------------------------------------------------------------
  # 1. Create an S3 bucket (versioned + encrypted) and a DynamoDB table with a
  #    primary key named "LockID" out-of-band.
  # 2. Replace the CHANGE_ME values below.
  # 3. Run `terraform init -migrate-state` to move the local state into S3.
  #
  # backend "s3" {
  #   bucket         = "CHANGE_ME-cloudkitchen-tf-state"
  #   key            = "cloudkitchen/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "CHANGE_ME-cloudkitchen-tf-locks"
  #   encrypt        = true
  # }
}

# AWS provider. Region comes from var.region (terraform.tfvars).
# default_tags are applied to every resource that supports tagging.
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
