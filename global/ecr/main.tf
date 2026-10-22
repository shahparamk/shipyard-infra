variable "aws_account_id" {
  description = "The only AWS account this code may touch"
  type        = string
  default     = "717279721195"
}

locals {
  repositories = toset(["api", "worker"])
}

resource "aws_ecr_repository" "this" {
  for_each = local.repositories
  #checkov:skip=CKV_AWS_136:Images are encrypted at rest with AES256 by default; a customer-managed KMS key adds cost and key-policy work without benefit for a single-operator registry

  name                 = "shipyard/${each.key}"
  image_tag_mutability = "IMMUTABLE" # a pushed tag can never be overwritten

  image_scanning_configuration {
    scan_on_push = true # ECR's free basic scan, in addition to Trivy in CI
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each = aws_ecr_repository.this

  repository = each.value.name
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the 20 most recent images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 20
        }
        action = { type = "expire" }
      },
    ]
  })
}