resource "time_static" "budget-start" {
}

resource "aws_budgets_budget" "total-cost" {
  name              = "budget-total"
  budget_type       = "COST"
  limit_amount      = format("%.1f", local.aws_budget_usd) # workaround for https://github.com/terraform-providers/terraform-provider-aws/issues/10692
  limit_unit        = "USD"
  time_unit         = "MONTHLY"
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

resource "azurerm_consumption_budget_subscription" "total-cost" {
  name            = "budget-total"
  subscription_id = data.azurerm_subscription.current.subscription_id

  amount     = local.azure_budget_gbp
  time_grain = "Monthly"

  time_period {
    start_date = local.azure_budget_start
  }

  notification {
    enabled        = true
    threshold      = 60.0
    operator       = "GreaterThan"
    contact_emails = [var.my_email_address]
  }

  notification {
    enabled        = true
    threshold      = 100.0
    operator       = "GreaterThan"
    contact_emails = [var.my_email_address]
  }
}
