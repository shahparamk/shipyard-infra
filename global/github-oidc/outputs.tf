output "plan_role_arn" {
  value = aws_iam_role.plan.arn
}

output "apply_role_arn" {
  value = aws_iam_role.apply.arn
}

output "ecr_push_role_arn" {
  value = aws_iam_role.ecr_push.arn
}