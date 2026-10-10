# Uptime monitoring for the services on the NAS, replacing the Route 53 health checks.
#
# health-probe runs every minute, requests each service from outside the network and writes an Up metric per service plus
# a ServicesDown count. One alarm on ServicesDown notifies the uptime-alerts topic, which emails me and triggers
# alert-notifier to push a notification through ntfy.sh. uptime-status serves a 7-day uptime chart for Dashy.
#
# The Lambda code lives in tools/<function name> and is deployed by .github/workflows/lambdas.yml, not by Terraform.
# Terraform creates each function with a placeholder and then ignores code changes.
locals {
  uptime_metric_namespace = "UptimeMonitoring"

  # name => URL. A 2xx or 3xx response counts as up; redirects aren't followed. Each service is one CloudWatch custom
  # metric, and the always-free tier covers 10 of them in total, so keep this list short.
  uptime_services = {
    wallabag = "https://wallabag.elliotpryde.com/"
    # plex          = "https://plex.elliotpryde.com/identity"
    # homeassistant = "https://homeassistant.elliotpryde.com/"
    # miniflux      = "https://miniflux.elliotpryde.com/healthcheck"
    # grafana       = "https://grafana.elliotpryde.com/api/health"
    # heimdall      = "https://heimdall.elliotpryde.com/"
  }

  uptime_lambdas = {
    health-probe = {
      description          = "Requests each NAS service and records whether it's up"
      timeout              = 30
      reserved_concurrency = -1
      environment = {
        METRIC_NAMESPACE = local.uptime_metric_namespace
        SERVICES         = jsonencode(local.uptime_services)
      }
    }
    alert-notifier = {
      description          = "Forwards uptime alarm notifications to ntfy.sh"
      timeout              = 30
      reserved_concurrency = -1
      environment = {
        METRIC_NAMESPACE     = local.uptime_metric_namespace
        SERVICES             = jsonencode(local.uptime_services)
        NTFY_URL             = "https://ntfy.sh"
        NTFY_TOPIC_PARAMETER = aws_ssm_parameter.uptime-ntfy-topic.name
      }
    }
    uptime-status = {
      description = "Serves a 7-day uptime chart of the NAS services for Dashy"
      timeout     = 15
      # The function URL is public, so this caps what anyone requesting it can cost. Results are cached for 15 minutes
      # per instance, so one instance makes at most 96 GetMetricData calls a day.
      reserved_concurrency = 1
      environment = {
        METRIC_NAMESPACE       = local.uptime_metric_namespace
        SERVICES               = jsonencode(local.uptime_services)
        ACCESS_TOKEN_PARAMETER = aws_ssm_parameter.uptime-status-token.name
      }
    }
  }
}

data "aws_caller_identity" "current" {}

# A stand-in for the real code, which is deployed separately. It fails on purpose, so a function that has never had its
# code deployed is obvious.
data "archive_file" "lambda-placeholder" {
  type        = "zip"
  output_path = "${path.module}/.terraform/tmp/lambda-placeholder.zip"

  source {
    filename = "bootstrap"
    content  = "#!/bin/sh\necho 'No code deployed yet, run the Lambdas workflow' >&2\nexit 1\n"
  }
}

resource "aws_iam_role" "uptime-lambda" {
  for_each = local.uptime_lambdas
  name     = each.key
  path     = "/lambda/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "uptime-lambda" {
  for_each          = local.uptime_lambdas
  name              = "/aws/lambda/${each.key}"
  retention_in_days = 14
}

resource "aws_iam_role_policy" "uptime-lambda-logs" {
  for_each = local.uptime_lambdas
  name     = "logs"
  role     = aws_iam_role.uptime-lambda[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.uptime-lambda[each.key].arn}:*"
      }
    ]
  })
}

resource "aws_lambda_function" "uptime" {
  for_each      = local.uptime_lambdas
  function_name = each.key
  description   = each.value.description
  role          = aws_iam_role.uptime-lambda[each.key].arn

  runtime       = "provided.al2023"
  handler       = "bootstrap"
  architectures = ["arm64"]
  memory_size   = 128
  timeout       = each.value.timeout

  reserved_concurrent_executions = each.value.reserved_concurrency

  filename = data.archive_file.lambda-placeholder.output_path

  environment {
    variables = each.value.environment
  }

  logging_config {
    log_format = "JSON"
    log_group  = aws_cloudwatch_log_group.uptime-lambda[each.key].name
    # drops the START, END and REPORT lines Lambda writes on every invocation
    system_log_level      = "WARN"
    application_log_level = "INFO"
  }

  lifecycle {
    # code is deployed by the Lambdas workflow
    ignore_changes = [filename, source_code_hash]
  }

  depends_on = [aws_iam_role_policy.uptime-lambda-logs]
}

# health-probe

resource "aws_iam_role_policy" "health-probe-metrics" {
  name = "put-metrics"
  role = aws_iam_role.uptime-lambda["health-probe"].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Action    = "cloudwatch:PutMetricData"
        Resource  = "*"
        Condition = { StringEquals = { "cloudwatch:namespace" = local.uptime_metric_namespace } }
      }
    ]
  })
}

# A stale probe is no use, so neither Lambda nor the scheduler retries a failed run
resource "aws_lambda_function_event_invoke_config" "health-probe" {
  function_name                = aws_lambda_function.uptime["health-probe"].function_name
  maximum_retry_attempts       = 0
  maximum_event_age_in_seconds = 60
}

resource "aws_iam_role" "health-probe-scheduler" {
  name = "health-probe-scheduler"
  path = "/scheduler/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "scheduler.amazonaws.com" }
        Action    = "sts:AssumeRole"
        Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id } }
      }
    ]
  })
}

resource "aws_iam_role_policy" "health-probe-scheduler" {
  name = "invoke-health-probe"
  role = aws_iam_role.health-probe-scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = aws_lambda_function.uptime["health-probe"].arn
      }
    ]
  })
}

resource "aws_scheduler_schedule" "health-probe" {
  name                = "health-probe"
  schedule_expression = "rate(1 minute)"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.uptime["health-probe"].arn
    role_arn = aws_iam_role.health-probe-scheduler.arn

    retry_policy {
      maximum_retry_attempts       = 0
      maximum_event_age_in_seconds = 60
    }
  }
}

# Alerting

resource "aws_cloudwatch_metric_alarm" "uptime-services-down" {
  alarm_name        = "uptime-services-down"
  alarm_description = "A NAS service failed its health probe, or the probe itself stopped reporting."

  namespace   = local.uptime_metric_namespace
  metric_name = "ServicesDown"
  statistic   = "Maximum"
  period      = 60

  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  # about three minutes of failures, so a single dropped request doesn't alert
  evaluation_periods  = 5
  datapoints_to_alarm = 3
  # no data means the probe isn't running, which should alert too
  treat_missing_data = "breaching"

  alarm_actions = [aws_sns_topic.uptime-alerts.arn]
  ok_actions    = [aws_sns_topic.uptime-alerts.arn]
}

resource "aws_sns_topic" "uptime-alerts" {
  name = "uptime-alerts"
}

# A backup channel that doesn't depend on ntfy.sh. AWS emails a confirmation link that has to be clicked once.
resource "aws_sns_topic_subscription" "uptime-alerts-email" {
  topic_arn = aws_sns_topic.uptime-alerts.arn
  protocol  = "email"
  endpoint  = var.my_email_address
}

resource "aws_sns_topic_subscription" "uptime-alerts-notifier" {
  topic_arn = aws_sns_topic.uptime-alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.uptime["alert-notifier"].arn
}

resource "aws_lambda_permission" "alert-notifier-sns" {
  statement_id  = "AllowUptimeAlertsTopic"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.uptime["alert-notifier"].function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.uptime-alerts.arn
}

# Topics on ntfy.sh are public, so the topic name is the password. Read it with
#   aws ssm get-parameter --name /uptime-monitoring/ntfy-topic --with-decryption --query Parameter.Value --output text
# and subscribe to it on https://ntfy.sh in the ntfy app.
resource "random_password" "uptime-ntfy-topic" {
  length  = 32
  special = false
}

resource "aws_ssm_parameter" "uptime-ntfy-topic" {
  name  = "/uptime-monitoring/ntfy-topic"
  type  = "SecureString"
  value = "uptime-${random_password.uptime-ntfy-topic.result}"
}

resource "aws_iam_role_policy" "alert-notifier" {
  name = "notify"
  role = aws_iam_role.uptime-lambda["alert-notifier"].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ssm:GetParameter"
        Resource = aws_ssm_parameter.uptime-ntfy-topic.arn
      },
      {
        # to say which services are down. GetMetricData doesn't support resource-level permissions.
        Effect   = "Allow"
        Action   = "cloudwatch:GetMetricData"
        Resource = "*"
      }
    ]
  })
}

# Dashboard

# The function URL has to be public for Dashy to load it as an image, so requests need this token in the path. Read it with
#   aws ssm get-parameter --name /uptime-monitoring/status-token --with-decryption --query Parameter.Value --output text
resource "random_password" "uptime-status-token" {
  length  = 40
  special = false
}

resource "aws_ssm_parameter" "uptime-status-token" {
  name  = "/uptime-monitoring/status-token"
  type  = "SecureString"
  value = random_password.uptime-status-token.result
}

resource "aws_iam_role_policy" "uptime-status" {
  name = "read-uptime"
  role = aws_iam_role.uptime-lambda["uptime-status"].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ssm:GetParameter"
        Resource = aws_ssm_parameter.uptime-status-token.arn
      },
      {
        Effect   = "Allow"
        Action   = "cloudwatch:GetMetricData"
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function_url" "uptime-status" {
  function_name      = aws_lambda_function.uptime["uptime-status"].function_name
  authorization_type = "NONE"
}

# Public function URLs need both of these permissions
resource "aws_lambda_permission" "uptime-status-url" {
  statement_id           = "AllowPublicFunctionUrl"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.uptime["uptime-status"].function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

resource "aws_lambda_permission" "uptime-status-invoke" {
  statement_id             = "AllowPublicInvokeViaFunctionUrl"
  action                   = "lambda:InvokeFunction"
  function_name            = aws_lambda_function.uptime["uptime-status"].function_name
  principal                = "*"
  invoked_via_function_url = true
}
