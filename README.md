# Personal infrastructure

## Gotchas

If for some reason `azurerm_consumption_budget_subscription.total-cost` needs to be deleted and recreated, creation will fail because the `start_date` needs to be this month at
the latest. `time_static.budget-start` can't have a trigger to be recreated whenever the budget is recreated because that would create a circular dependency, so the solution is
to taint `time_static.budget-start` manually.
