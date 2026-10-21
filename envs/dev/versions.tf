terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"

  # Guardrail: refuse to run against any account except ShipYard's
  allowed_account_ids = ["717279721195"]

  default_tags {
    tags = {
      Project     = "shipyard"
      Environment = "dev"
      ManagedBy   = "terraform"
    }
  }
}