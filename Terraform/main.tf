terraform {
  backend "remote" {
    organization = "elliotpryde"

    workspaces {
      name = "personal-infrastructure"
    }
  }
}

provider "cloudflare" {
  version = "~> 2.8"
  email = "var.cloudflare_email"
  api_key = "var.cloudflare_api_key"
}

provider "azurerm" {
  client_id = var.azure_client_id
  client_secret = var.azure_client_secret
  subscription_id = var.azure_subscription_id
  tenant_id = var.azure_tenant_id

  features {}
}
