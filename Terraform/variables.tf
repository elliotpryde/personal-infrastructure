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
