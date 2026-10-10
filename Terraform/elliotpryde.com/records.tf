# The *.elliotpryde.com wildcard record pointing at the NAS is owned by the ddns_updater container on the NAS, which
# keeps its IP up to date. Terraform used to manage it with a static IP; this hands it over without deleting it.
removed {
  from = aws_route53_record.traefik-wildcard

  lifecycle {
    destroy = false
  }
}
