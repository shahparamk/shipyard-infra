# shipyard-infra

Terraform for **ShipYard**, a production-style EKS platform with GitOps and observability.

## Layout

```
bootstrap/   One-time setup: S3 bucket for Terraform remote state
modules/     Reusable modules (vpc, eks, rds, sqs, iam) - coming next
envs/dev/    Dev environment that composes the modules - coming next
```

## Guardrails

- Every provider pins `allowed_account_ids`, so Terraform refuses to run against the wrong AWS account.
- Local auth uses IAM Identity Center (SSO): `aws sso login --profile shipyard`. No long-lived access keys.
- State lives in a versioned, encrypted, private S3 bucket with native S3 state locking.

## Bootstrap (run once)

```powershell
$env:AWS_PROFILE = "shipyard"
cd bootstrap
terraform init
terraform plan
terraform apply
```
