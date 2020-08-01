module "protonmail-domain" {
  source  = "app.terraform.io/elliotpryde/protonmail-domain/aws"
  version = "1.0.0"

  zone_id           = aws_route53_zone.elliotpryde-com.zone_id
  verification_data = var.protonmail_elliotpryde_com_verification_string
  dkim_records      = local.dkim_records
  dmarc_policy      = "none"
}

resource "aws_route53_health_check" "nas-health-checks" {
  count             = length(local.nas_service_endpoints)
  fqdn              = local.nas_service_endpoints[count.index].fqdn
  port              = 443
  type              = "HTTPS"
  resource_path     = local.nas_service_endpoints[count.index].path
  failure_threshold = "5"
  request_interval  = "30"
}
