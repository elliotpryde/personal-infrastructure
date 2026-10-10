locals {
  aws_default_region = "eu-west-2"
  aws_budget_usd     = "5"
  # the budget's existing start date; changing it would replace the budget
  aws_budget_start = "2021-06-06_13:22"
}

variable "protonmail_elliotpryde_com_verification_string" {
  type        = string
  description = "The domain verification data provided at https://mail.protonmail.com/domains"
}

variable "my_email_address" {
  type        = string
  description = "The email address that I will receive alerts/notifications on."
  # plans are posted as public pull request comments
  sensitive = true
}

variable "disable_all_health_checks" {
  type        = bool
  description = "Removes all Route 53 health checks. If they're not being used then there's no need to pay for them."
}
