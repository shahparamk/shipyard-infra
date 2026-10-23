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
  region              = "us-east-1"
  allowed_account_ids = ["717279721195"]

  default_tags {
    tags = {
      Project   = "shipyard"
      Component = "dns"
      ManagedBy = "terraform"
    }
  }
}