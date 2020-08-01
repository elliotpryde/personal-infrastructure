terraform {
  backend "remote" {
    organization = "elliotpryde"

    workspaces {
      name = "personal-infrastructure"
    }
  }
}

provider "azurerm" {
  version         = "~> 2.20"
  client_id       = var.azure_client_id
  client_secret   = var.azure_client_secret
  subscription_id = var.azure_subscription_id
  tenant_id       = var.azure_tenant_id

  features {}
}

provider "aws" {
  version = "~> 2.70"
  region = "eu-west-2"
}

provider "time" {
  version = "~> 0.5"
}

module "elliotpryde-com" {
  source        = "./elliotpryde.com"
  nas_public_ip = var.nas_public_ip
  protonmail_elliotpryde_com_verification_string = var.protonmail_elliotpryde_com_verification_string
}
