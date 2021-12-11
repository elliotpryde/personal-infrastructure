terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.47.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 2.89.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.7.1"
    }
  }
  required_version = ">= 0.13"
}
