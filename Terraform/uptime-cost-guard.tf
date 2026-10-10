# A kill switch for uptime monitoring. Two things publish to the uptime-cost-guard topic:
#   - an alarm on uptime-status being invoked far more than Dashy ever would, which catches abuse of the public function
#     URL within minutes
#   - the monthly budget going over its limit, a slower backstop because AWS updates budgets a few times a day
#
# Both uptime-kill-switch and alert-notifier subscribe to it. The kill switch sets the reserved concurrency of health-probe
# and uptime-status to 0, so they're throttled, which isn't billed, and disables the probe schedule and the uptime alarm's
# actions. The notifier tells me it happened.
#
# To resume, run the Terraform workflow. The plan shows the pause as drift (reserved concurrency, the schedule's state
# and the alarm's actions_enabled), and applying it puts everything back.

resource "aws_sns_topic" "uptime-cost-guard" {
  name = "uptime-cost-guard"
}

resource "aws_sns_topic_policy" "uptime-cost-guard" {
  arn = aws_sns_topic.uptime-cost-guard.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowBudgets"
        Effect    = "Allow"
        Principal = { Service = "budgets.amazonaws.com" }
        Action    = "SNS:Publish"
        Resource  = aws_sns_topic.uptime-cost-guard.arn
        Condition = {
          StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
          ArnLike      = { "aws:SourceArn" = "arn:aws:budgets::${data.aws_caller_identity.current.account_id}:*" }
        }
      },
      {
        Sid       = "AllowCloudWatchAlarms"
        Effect    = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
        Action    = "SNS:Publish"
        Resource  = aws_sns_topic.uptime-cost-guard.arn
        Condition = {
          StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        }
      }
    ]
  })
}

resource "aws_sns_topic_subscription" "uptime-cost-guard-kill-switch" {
  topic_arn = aws_sns_topic.uptime-cost-guard.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.uptime["uptime-kill-switch"].arn
}

resource "aws_sns_topic_subscription" "uptime-cost-guard-notifier" {
  topic_arn = aws_sns_topic.uptime-cost-guard.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.uptime["alert-notifier"].arn
}

resource "aws_lambda_permission" "alert-notifier-cost-guard" {
  statement_id  = "AllowUptimeCostGuardTopic"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.uptime["alert-notifier"].function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.uptime-cost-guard.arn
}

resource "aws_lambda_permission" "uptime-kill-switch-sns" {
  statement_id  = "AllowUptimeCostGuardTopic"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.uptime["uptime-kill-switch"].function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.uptime-cost-guard.arn
}

# Dashy loads the chart once per page view and it's cached for 15 minutes, so normal use is a handful of requests an
# hour. 300 in 5 minutes is one a second. Abuse just under that would be about 2.6M requests a month, around $0.30 over
# the free tier, so this bounds the worst case.
resource "aws_cloudwatch_metric_alarm" "uptime-status-invocations" {
  alarm_name        = "uptime-status-invocations"
  alarm_description = "The public uptime-status function URL is being requested far more than Dashy would. Pauses uptime monitoring."

  namespace   = "AWS/Lambda"
  metric_name = "Invocations"
  dimensions  = { FunctionName = aws_lambda_function.uptime["uptime-status"].function_name }
  statistic   = "Sum"
  period      = 300

  comparison_operator = "GreaterThanThreshold"
  threshold           = 300
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.uptime-cost-guard.arn]
}

resource "aws_iam_role_policy" "uptime-kill-switch" {
  name = "pause-uptime-monitoring"
  role = aws_iam_role.uptime-lambda["uptime-kill-switch"].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "lambda:PutFunctionConcurrency"
        Resource = [for name in local.uptime_pausable_functions : aws_lambda_function.uptime[name].arn]
      },
      {
        Effect   = "Allow"
        Action   = ["scheduler:GetSchedule", "scheduler:UpdateSchedule"]
        Resource = aws_scheduler_schedule.health-probe.arn
      },
      {
        # UpdateSchedule passes the schedule's existing role back to EventBridge Scheduler
        Effect    = "Allow"
        Action    = "iam:PassRole"
        Resource  = aws_iam_role.health-probe-scheduler.arn
        Condition = { StringEquals = { "iam:PassedToService" = "scheduler.amazonaws.com" } }
      },
      {
        Effect   = "Allow"
        Action   = "cloudwatch:DisableAlarmActions"
        Resource = aws_cloudwatch_metric_alarm.uptime-services-down.arn
      }
    ]
  })
}

# The notifier says a pause has started, not whether it worked, so this tells me if the kill switch fails
resource "aws_cloudwatch_metric_alarm" "uptime-kill-switch-errors" {
  alarm_name        = "uptime-kill-switch-errors"
  alarm_description = "The uptime kill switch failed, so uptime monitoring may not be paused. Check its logs."

  namespace   = "AWS/Lambda"
  metric_name = "Errors"
  dimensions  = { FunctionName = aws_lambda_function.uptime["uptime-kill-switch"].function_name }
  statistic   = "Sum"
  period      = 60

  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.uptime-alerts.arn]
}
