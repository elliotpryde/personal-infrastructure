resource "aws_route53_health_check" "nas-health-checks" {
  count             = length(local.nas_service_endpoints)
  fqdn              = local.nas_service_endpoints[count.index].fqdn
  port              = 443
  type              = "HTTPS"
  resource_path     = local.nas_service_endpoints[count.index].path
  failure_threshold = "5"
  request_interval  = "30"
}

resource "aws_route53_health_check" "nas-health-checks-aggregate" {
  type                   = "CALCULATED"
  child_health_threshold = length(local.nas_service_endpoints)
  child_healthchecks     = aws_route53_health_check.nas-health-checks[*].id
}

resource "aws_cloudwatch_metric_alarm" "nas-http-health-check-alarm" {
  alarm_name          = "nas-http-health-check-alarm"
  namespace           = "AWS/Route53"
  metric_name         = "HealthCheckStatus"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  period              = "60"
  statistic           = "Minimum"
  threshold           = "1"
  unit                = "None"
  alarm_description   = "Alert when all NAS services are unavailable."

  dimensions = {
    HealthCheckId = aws_route53_health_check.nas-health-checks-aggregate.id
  }
}