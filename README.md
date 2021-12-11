# Personal infrastructure

## Getting started

### Creating the Azure Service Principal with the necessary permissions for Terraform Cloud

```sh
az login
subscription_id=$(az account show --subscription "personal-infrastructure" --query "id" --output tsv)
# create a new service principal with the 'Contributor' role
az ad sp create-for-rbac --name "terraform-cloud" --role="Contributor" --scopes="/subscriptions/${subscription_id}"
# get the object id of the newly created service principal
sp_object_id=$(az ad sp list --all --filter "displayName eq 'terraform-cloud'" --query "[0].objectId" --output tsv)

# create a role to manage policy definitions and assignment
az role definition create --role-definition '{
  "Name": "Policy Admin",
  "Description": "Perform any actions with policy definitions, policy assignments, and policy set definitions.",
  "Actions": [
    "Microsoft.Authorization/policyAssignments/read",
    "Microsoft.Authorization/policyAssignments/write",
    "Microsoft.Authorization/policyAssignments/exempt/action",
    "Microsoft.Authorization/policyAssignments/delete",
    "Microsoft.Authorization/policyDefinitions/read",
    "Microsoft.Authorization/policyDefinitions/delete",
    "Microsoft.Authorization/policyDefinitions/write",
    "Microsoft.Authorization/policySetDefinitions/read",
    "Microsoft.Authorization/policySetDefinitions/write",
    "Microsoft.Authorization/policySetDefinitions/delete"
  ],
  "AssignableScopes": ["/subscriptions/'${subscription_id}'"]
}'

# assign that role to the service principal
az role assignment create --assignee "$sp_object_id" --role "Policy Admin" --scope "/subscriptions/${subscription_id}"
```

## Gotchas

If for some reason `azurerm_consumption_budget_subscription.total-cost` needs to be deleted and recreated, creation will fail because the `start_date` needs to be this month at
the latest. `time_static.budget-start` can't have a trigger to be recreated whenever the budget is recreated because that would create a circular dependency, so the solution is
to taint `time_static.budget-start` manually.
