locals {
  aws_default_region     = "eu-west-2"
  aws_budget_usd         = "5"
  aws_budget_start       = formatdate("YYYY-MM-DD_hh:mm", time_static.budget-start.rfc3339)
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
