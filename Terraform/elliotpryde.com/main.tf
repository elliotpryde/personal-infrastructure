module "protonmail-domain" {
  source = "git::https://github.com/elliotpryde/terraform-aws-protonmail-domain.git?ref=1.1.0"

  zone_id           = aws_route53_zone.elliotpryde-com.zone_id
  verification_data = var.protonmail_elliotpryde_com_verification_string
  dkim_records      = local.dkim_records
  dmarc_policy      = "none"
}
