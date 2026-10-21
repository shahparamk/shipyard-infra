variable "aws_account_id" {
  description = "The only AWS account this code may touch"
  type        = string
  default     = "717279721195"
}

variable "github_repo" {
  description = "GitHub repo allowed to assume the CI roles (owner/name)"
  type        = string
  default     = "shahparamk/shipyard-infra"
}

variable "state_bucket" {
  description = "Terraform state bucket name"
  type        = string
  default     = "shipyard-tfstate-717279721195"
}