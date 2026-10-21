terraform {
  backend "s3" {
    bucket       = "shipyard-tfstate-717279721195"
    key          = "global/github-oidc/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}