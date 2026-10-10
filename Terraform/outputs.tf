output "nas-traefik-user-access-key-id" {
  value       = aws_iam_access_key.nas-traefik.id
  description = "The ID of the AWS user access key used by Traefik to complete DNS challenges."
}

output "nas-traefik-user-access-key-secret" {
  value       = aws_iam_access_key.nas-traefik.secret
  description = "The secret for the AWS user access key used by Traefik to complete DNS challenges."
  sensitive   = true
}

output "elliotpryde-com-zone-id" {
  value       = module.elliotpryde-com.elliotpryde-com-zone-id
  description = "The AWS hosted zone ID for elliotpryde.com."
}

output "terraform-state-bucket" {
  value       = aws_s3_bucket.terraform-state.bucket
  description = "The S3 bucket holding this repository's Terraform state."
}

output "github-terraform-plan-role-arn" {
  value       = aws_iam_role.github-terraform-plan.arn
  description = "The IAM role GitHub Actions assumes to run plans. Set as the AWS_PLAN_ROLE_ARN repository variable."
}

output "github-terraform-apply-role-arn" {
  value       = aws_iam_role.github-terraform-apply.arn
  description = "The IAM role GitHub Actions assumes to apply changes. Set as the AWS_APPLY_ROLE_ARN repository variable."
}
