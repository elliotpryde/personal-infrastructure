resource "cloudflare_record" "traefik-wildcard" {
  zone_id = cloudflare_zone.elliotpryde.id
  name    = "*"
  value   = var.nas_public_ip
  type    = "A"
  ttl     = local.cloudflare_ttl
}
