locals {
  aws_default_region = "eu-west-2"
  aws_budget_usd     = "5"
  aws_budget_start   = formatdate("YYYY-MM-DD_hh:mm", time_static.budget-start.rfc3339)
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
