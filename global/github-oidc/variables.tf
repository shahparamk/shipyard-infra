variable "aws_account_id" {
  description = "The only AWS account this code may touch"
  type        = string
  default     = "717279721195"
}

variable "github_oidc_sub_prefix" {
  description = "Immutable OIDC subject prefix for the repo (owner@id/repo@id). From: gh api repos/<owner>/<repo>/actions/oidc/customization/sub"
  type        = string
  default     = "repo:shahparamk@181007379/shipyard-infra@1426498385"
}

variable "state_bucket" {
  description = "Terraform state bucket name"
  type        = string
  default     = "shipyard-tfstate-717279721195"
}