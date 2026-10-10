locals {
  github_repository     = "elliotpryde/personal-infrastructure"
  terraform_state_key   = "personal-infrastructure/terraform.tfstate"
  github_oidc_subject   = "token.actions.githubusercontent.com:sub"
  github_oidc_audience  = "token.actions.githubusercontent.com:aud"
  github_default_branch = "master"
}

# Remote state for this repository's Terraform, written by GitHub Actions.
resource "aws_s3_bucket" "terraform-state" {
  bucket = "elliotpryde-terraform-state"

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  lifecycle_rule {
    id      = "expire-old-state-versions"
    enabled = true

    noncurrent_version_expiration {
      days = 90
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "terraform-state" {
  bucket                  = aws_s3_bucket.terraform-state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
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
  # AWS no longer checks these for GitHub's OIDC provider, but this provider version requires them
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]
}

# Used for plans on pull requests and for scheduled drift detection
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
            (local.github_oidc_subject) = [
              "repo:${local.github_repository}:pull_request",
              "repo:${local.github_repository}:ref:refs/heads/${local.github_default_branch}"
            ]
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
