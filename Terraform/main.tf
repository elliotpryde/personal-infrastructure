terraform {
  backend "remote" {
    organization = "elliotpryde"

    workspaces {
      name = "personal-infrastructure"
    }
  }
}

provider "azurerm" {
  client_id       = var.azure_client_id
  client_secret   = var.azure_client_secret
  subscription_id = var.azure_subscription_id
  tenant_id       = var.azure_tenant_id

  features {}
}

provider "aws" {
  region = "eu-west-2"
}

provider "time" {}

module "elliotpryde-com" {
  source                                         = "./elliotpryde.com"
  nas_public_ip                                  = var.nas_public_ip
  protonmail_elliotpryde_com_verification_string = var.protonmail_elliotpryde_com_verification_string
  enable_aggregate_health_check                  = false
  disable_all_health_checks                      = var.disable_all_health_checks
}
