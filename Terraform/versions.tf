terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.69.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 2.89.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.7.2"
    }
  }
  required_version = ">= 1.0"
}
