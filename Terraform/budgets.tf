# include an Azure budget once that feature is available
# https://github.com/terraform-providers/terraform-provider-azurerm/issues/2677

resource "time_static" "budget-start" {}

resource "aws_budgets_budget" "total-cost" {
  name = "budget-total"
  budget_type  = "COST"
  limit_amount = local.aws_budget_usd
  limit_unit   = "USD"
  time_unit = "MONTHLY"
  time_period_start = local.aws_budget_start

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.my_email_address]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.my_email_address]
  }
}
