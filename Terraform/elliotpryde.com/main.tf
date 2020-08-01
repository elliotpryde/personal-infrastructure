module "protonmail-domain" {
  source  = "app.terraform.io/elliotpryde/protonmail-domain/aws"
  version = "1.0.0"

  zone_id = aws_route53_zone.elliotpryde-com.zone_id
  verification_data = var.protonmail_elliotpryde_com_verification_string
  dkim_records = local.dkim_records
  dmarc_policy = "none"
}
