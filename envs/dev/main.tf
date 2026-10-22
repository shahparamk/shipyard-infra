locals {
  name         = "shipyard-dev"
  cluster_name = "shipyard-dev"
}

module "vpc" {
  source = "../../modules/vpc"

  name         = local.name
  cidr_block   = "10.0.0.0/16"
  azs          = ["us-east-1a", "us-east-1b"]
  cluster_name = local.cluster_name

  # Off until EKS is built. Flip to true then (~$33/month while running)
  enable_nat_gateway = false
}