locals {
  dns_ttl = 120
  dkim_records = [
    {
      hostname = "protonmail._domainkey",
      data     = "protonmail.domainkey.d4zotdvax2nt4447zdfl5bkm6uc3lozcidvlw5jdxq3hhurmq3u5q.domains.proton.ch."
    },
    {
      hostname = "protonmail2._domainkey",
      data     = "protonmail2.domainkey.d4zotdvax2nt4447zdfl5bkm6uc3lozcidvlw5jdxq3hhurmq3u5q.domains.proton.ch."
    },
    {
      hostname = "protonmail3._domainkey",
      data     = "protonmail3.domainkey.d4zotdvax2nt4447zdfl5bkm6uc3lozcidvlw5jdxq3hhurmq3u5q.domains.proton.ch."
    }
  ]

  nas_service_health_endpoints = disable_all_health_checks ? [] : [
    # { fqdn : "plex.elliotpryde.com", path : "/identity" },
    # { fqdn : "homeassistant.elliotpryde.com", path : "/" },
    { fqdn : "wallabag.elliotpryde.com", path : "/" },
    # { fqdn : "miniflux.elliotpryde.com", path : "/healthcheck" },
    # { fqdn : "grafana.elliotpryde.com", path : "/api/health" },
    # { fqdn : "heimdall.elliotpryde.com", path : "/" }
  ]
  aggregate_health_check_is_active = var.enable_aggregate_health_check && (length(local.nas_service_health_endpoints) > 1)
  // use the aggregate health check for the alarm if it's enabled, otherwise use the first NAS service endpoint health check
  health_check_to_use_for_cloudwatch_alarm = (
    local.aggregate_health_check_is_active ?
    aws_route53_health_check.nas-health-checks-aggregate[0].id :
    aws_route53_health_check.nas-health-checks[0]
  )
}

variable "nas_public_ip" {
  type        = string
  description = "The public IP address of my NAS"
}

variable "protonmail_elliotpryde_com_verification_string" {
  type        = string
  description = "The domain verification data provided at https://mail.protonmail.com/domains"
}

variable "enable_aggregate_health_check" {
  type        = bool
  description = <<EOF
Enable a Route 53 health check which only passes if all other health checks pass.

The health check will be disabled regardless of this setting if you only have 1 NAS service endpoint health check in total.
EOF
}

variable "disable_all_health_checks" {
  type        = bool
  description = "Removes all Route 53 health checks. If they're not being used then there's no need to pay for them."
}
