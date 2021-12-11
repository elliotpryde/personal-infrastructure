locals {
  aws_default_region = "eu-west-2"
  aws_budget_usd     = "5"
  aws_budget_start   = formatdate("YYYY-MM-DD_hh:mm", time_static.budget-start.rfc3339)
  azure_budget_gbp   = 3
  # first day of the month rfc3339
  azure_budget_start     = "${time_static.budget-start.year}-${format("%02v", time_static.budget-start.month)}-01T00:00:00Z"
  azure_default_location = "UK South"
}

variable "azure_client_id" {
  type        = string
  description = "The Azure service principal id"
}

variable "azure_client_secret" {
  type        = string
  description = "The Azure service principal secret"
}

variable "azure_subscription_id" {
  type        = string
  description = "The Azure subscription id"
}

variable "azure_tenant_id" {
  type        = string
  description = "The Azure tenant id"
}

variable "nas_public_ip" {
  type        = string
  description = "The public IP address of my NAS"
}

variable "protonmail_elliotpryde_com_verification_string" {
  type        = string
  description = "The domain verification data provided at https://mail.protonmail.com/domains"
}

variable "my_email_address" {
  type        = string
  description = "The email address that I will receive alerts/notifications on."
}

variable "disable_all_health_checks" {
  type        = bool
  description = "Removes all Route 53 health checks. If they're not being used then there's no need to pay for them."
}

variable "azure_mandatory_resource_group_tags" {
  description = <<EOF
A list of tags which must be present across all resource groups.
Any new resources groups created without these tags will be flagged with a warning event in the activity log.
EOF
  type = set(string)
}
