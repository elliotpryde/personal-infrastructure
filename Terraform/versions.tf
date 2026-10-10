terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.68"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.14"
    }
  }
  # 1.12 for identity-based import blocks, 1.10 for S3 state locking
  required_version = ">= 1.12"
}
