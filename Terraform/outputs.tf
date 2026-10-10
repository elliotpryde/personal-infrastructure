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

output "uptime-status-url" {
  value       = aws_lambda_function_url.uptime-status.function_url
  description = "The function URL serving the uptime chart. Requests need the token from /uptime-monitoring/status-token."
}

output "github-lambda-deploy-role-arn" {
  value       = aws_iam_role.github-lambda-deploy.arn
  description = "Set as the AWS_LAMBDA_DEPLOY_ROLE_ARN Actions variable."
}
