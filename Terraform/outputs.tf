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
