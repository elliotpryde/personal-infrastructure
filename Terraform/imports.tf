# Brings existing resources into the S3 state on the first apply from GitHub Actions. The state that used to live in
# Terraform Cloud was abandoned rather than migrated. Once that first apply has run these blocks do nothing, and can be
# deleted.
locals {
  aws_account_id = "670785527082"
  zone_id        = "Z104083113ZEFTET5POA5"
}

import {
  to = time_static.budget-start
  id = "2021-06-06T13:22:47Z"
}

import {
  to = aws_budgets_budget.total-cost
  id = "${local.aws_account_id}:budget-total"
}

import {
  to = aws_iam_user.nas-traefik
  id = "nas-traefik"
}

import {
  to = aws_iam_access_key.nas-traefik
  id = "AKIAZYLPO3UVJT2N6HNQ"
}

import {
  to = aws_iam_user_policy.nas-traefik-letsencrypt
  id = "nas-traefik:nas-traefik-letsencrypt"
}

# elliotpryde.com

import {
  to = module.elliotpryde-com.aws_route53_zone.elliotpryde-com
  id = local.zone_id
}

import {
  to = module.elliotpryde-com.aws_route53_record.traefik-wildcard
  identity = {
    zone_id = local.zone_id
    name    = "*.elliotpryde.com"
    type    = "A"
  }
}

import {
  to = module.elliotpryde-com.aws_route53_record.protonmail-verify-and-spf
  identity = {
    zone_id = local.zone_id
    name    = "elliotpryde.com"
    type    = "TXT"
  }
}

import {
  to = module.elliotpryde-com.aws_route53_record.protonmail-mx
  identity = {
    zone_id = local.zone_id
    name    = "elliotpryde.com"
    type    = "MX"
  }
}

import {
  to = module.elliotpryde-com.aws_route53_record.protonmail-dkim[0]
  identity = {
    zone_id = local.zone_id
    name    = "protonmail._domainkey.elliotpryde.com"
    type    = "CNAME"
  }
}

import {
  to = module.elliotpryde-com.aws_route53_record.protonmail-dkim[1]
  identity = {
    zone_id = local.zone_id
    name    = "protonmail2._domainkey.elliotpryde.com"
    type    = "CNAME"
  }
}

import {
  to = module.elliotpryde-com.aws_route53_record.protonmail-dkim[2]
  identity = {
    zone_id = local.zone_id
    name    = "protonmail3._domainkey.elliotpryde.com"
    type    = "CNAME"
  }
}

import {
  to = module.elliotpryde-com.aws_route53_record.protonmail-dmarc
  identity = {
    zone_id = local.zone_id
    name    = "_dmarc.elliotpryde.com"
    type    = "TXT"
  }
}

# Created by bootstrap/bootstrap.sh

import {
  to = aws_s3_bucket.terraform-state
  id = "elliotpryde-terraform-state"
}

import {
  to = aws_s3_bucket_versioning.terraform-state
  id = "elliotpryde-terraform-state"
}

import {
  to = aws_s3_bucket_server_side_encryption_configuration.terraform-state
  id = "elliotpryde-terraform-state"
}

import {
  to = aws_s3_bucket_public_access_block.terraform-state
  id = "elliotpryde-terraform-state"
}

import {
  to = aws_iam_openid_connect_provider.github-actions
  id = "arn:aws:iam::${local.aws_account_id}:oidc-provider/token.actions.githubusercontent.com"
}

import {
  to = aws_iam_role.github-terraform-plan
  id = "github-terraform-plan"
}

import {
  to = aws_iam_role_policy_attachment.github-terraform-plan-read-only
  id = "github-terraform-plan/arn:aws:iam::aws:policy/ReadOnlyAccess"
}

import {
  to = aws_iam_role_policy.github-terraform-plan-state-lock
  id = "github-terraform-plan:terraform-state-lock"
}

import {
  to = aws_iam_role.github-terraform-apply
  id = "github-terraform-apply"
}

import {
  to = aws_iam_role_policy_attachment.github-terraform-apply-admin
  id = "github-terraform-apply/arn:aws:iam::aws:policy/AdministratorAccess"
}
