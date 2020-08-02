# TODO: This could eventually be replaced with DDNS
resource "aws_route53_record" "traefik-wildcard" {
  zone_id = aws_route53_zone.elliotpryde-com.zone_id
  name    = "*"
  type    = "A"
  ttl     = local.dns_ttl

  records = [
    var.nas_public_ip
  ]
}
