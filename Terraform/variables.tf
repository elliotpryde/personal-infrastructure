variable "azure_client_id" {
  type = string
  description = "The Azure service principal id"
}

variable "azure_client_secret" {
  type = string
  description = "The Azure service principal secret"
}

variable "azure_subscription_id" {
  type = string
  description = "The Azure subscription id"
}

variable "azure_tenant_id" {
  type = string
  description = "The Azure tenant id"
}

variable "cloudflare_email" {
  type = string
  description = "The Cloudflare account email address."
}

variable "cloudflare_api_key" {
  type = string
  description = "The Cloudflare account API key."
}
