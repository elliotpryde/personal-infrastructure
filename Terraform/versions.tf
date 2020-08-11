terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    azurerm = {
      source = "hashicorp/azurerm"
    }
    time = {
      source = "hashicorp/time"
    }
  }
  required_version = ">= 0.13"
}
