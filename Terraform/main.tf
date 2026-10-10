terraform {
  # The bucket is managed in ci.tf. use_lockfile locks state with S3 conditional writes, so no DynamoDB table is needed.
  backend "s3" {
    bucket       = "elliotpryde-terraform-state"
    key          = "personal-infrastructure/terraform.tfstate"
    region       = "eu-west-2"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = local.aws_default_region
}

provider "time" {}

module "elliotpryde-com" {
  source                                         = "./elliotpryde.com"
  nas_public_ip                                  = var.nas_public_ip
  protonmail_elliotpryde_com_verification_string = var.protonmail_elliotpryde_com_verification_string
  enable_aggregate_health_check                  = false
  disable_all_health_checks                      = var.disable_all_health_checks
}
