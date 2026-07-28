# =============================================================================
# eks module - provider requirements
# =============================================================================
# The tls provider is used to fetch the OIDC issuer certificate thumbprint
# required to register the IAM OIDC provider for IRSA.
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
}
