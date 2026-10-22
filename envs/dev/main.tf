locals {
  name         = "shipyard-dev"
  cluster_name = "shipyard-dev"

  # ONE switch for the expensive parts (EKS + NAT gateway).
  # true = environment up (~$0.25-0.30/hr), false = torn down (~$0)
  cluster_enabled = false
}

# Your IAM Identity Center admin role, so your SSO login works with kubectl
data "aws_iam_roles" "sso_admin" {
  name_regex  = "AWSReservedSSO_AdministratorAccess_.*"
  path_prefix = "/aws-reserved/sso.amazonaws.com/"
}

module "vpc" {
  source = "../../modules/vpc"

  name         = local.name
  cidr_block   = "10.0.0.0/16"
  azs          = ["us-east-1a", "us-east-1b"]
  cluster_name = local.cluster_name

  # Private nodes need NAT to pull images; follows the cluster switch
  enable_nat_gateway = local.cluster_enabled
}

module "eks" {
  source = "../../modules/eks"
  count  = local.cluster_enabled ? 1 : 0

  cluster_name       = local.cluster_name
  kubernetes_version = "1.37" # <-- replace with the default version from Step 0
  subnet_ids         = module.vpc.private_subnet_ids
  admin_role_arns    = tolist(data.aws_iam_roles.sso_admin.arns)
}