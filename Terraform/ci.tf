# The state bucket, GitHub OIDC provider and the two roles below are first created by bootstrap/bootstrap.sh, because
# GitHub Actions needs them before it can run Terraform at all. imports.tf brings them under Terraform's management.
locals {
  github_repository    = "elliotpryde/personal-infrastructure"
  terraform_state_key  = "personal-infrastructure/terraform.tfstate"
  github_oidc_subject  = "token.actions.githubusercontent.com:sub"
  github_oidc_audience = "token.actions.githubusercontent.com:aud"
}

resource "aws_s3_bucket" "terraform-state" {
  bucket = "elliotpryde-terraform-state"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "terraform-state" {
  bucket = aws_s3_bucket.terraform-state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform-state" {
  bucket = aws_s3_bucket.terraform-state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform-state" {
  bucket                  = aws_s3_bucket.terraform-state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "terraform-state" {
  bucket = aws_s3_bucket.terraform-state.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

resource "aws_s3_bucket_policy" "terraform-state" {
  bucket = aws_s3_bucket.terraform-state.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.terraform-state.arn,
          "${aws_s3_bucket.terraform-state.arn}/*"
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      }
    ]
  })

  # applying a bucket policy and a public access block at the same time can conflict
  depends_on = [aws_s3_bucket_public_access_block.terraform-state]
}

# Lets GitHub Actions workflows assume IAM roles without long-lived access keys
resource "aws_iam_openid_connect_provider" "github-actions" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

# Used for plans on pull requests
resource "aws_iam_role" "github-terraform-plan" {
  name = "github-terraform-plan"
  path = "/github/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Federated = aws_iam_openid_connect_provider.github-actions.arn }
        Action    = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            (local.github_oidc_audience) = "sts.amazonaws.com"
            (local.github_oidc_subject)  = "repo:${local.github_repository}:pull_request"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "github-terraform-plan-read-only" {
  role       = aws_iam_role.github-terraform-plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# Plans take the state lock, so they need to write the lock file and nothing else
resource "aws_iam_role_policy" "github-terraform-plan-state-lock" {
  name = "terraform-state-lock"
  role = aws_iam_role.github-terraform-plan.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.terraform-state.arn}/${local.terraform_state_key}.tflock"
      }
    ]
  })
}

# Used to apply on merge. Only jobs running in the GitHub "production" environment, which is restricted to the
# default branch, can assume it.
resource "aws_iam_role" "github-terraform-apply" {
  name = "github-terraform-apply"
  path = "/github/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Federated = aws_iam_openid_connect_provider.github-actions.arn }
        Action    = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            (local.github_oidc_audience) = "sts.amazonaws.com"
            (local.github_oidc_subject)  = "repo:${local.github_repository}:environment:production"
          }
        }
      }
    ]
  })
}

# TODO: scope this down to the services this repository manages
resource "aws_iam_role_policy_attachment" "github-terraform-apply-admin" {
  role       = aws_iam_role.github-terraform-apply.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
