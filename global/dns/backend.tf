terraform {
  backend "s3" {
    bucket       = "shipyard-tfstate-717279721195"
    key          = "global/dns/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}