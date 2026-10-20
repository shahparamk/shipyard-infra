variable "aws_region" {
  description = "AWS region for the state bucket"
  type        = string
  default     = "us-east-1"
}

variable "aws_account_id" {
  description = "The only AWS account this code is allowed to touch"
  type        = string
  default     = "717279721195"
}
