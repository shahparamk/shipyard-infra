terraform {
  # 1.10+ is required for native S3 state locking (use_lockfile), so no DynamoDB table is needed
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # Guardrail: refuse to run against any account except the ShipYard personal account
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = {
      Project   = "shipyard"
      ManagedBy = "terraform"
      Component = "bootstrap"
    }
  }
}
