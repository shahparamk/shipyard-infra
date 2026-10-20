output "state_bucket_name" {
  description = "Use this bucket name in every backend \"s3\" block"
  value       = aws_s3_bucket.tfstate.bucket
}

output "state_bucket_arn" {
  value = aws_s3_bucket.tfstate.arn
}
