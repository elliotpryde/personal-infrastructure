resource "azurerm_policy_definition" "mandatory_resource_group_tag" {
  name         = "Audit-ResourceGroup-MandatoryTag"
  display_name = "Audit - Mandatory resource group tags"
  description  = "Audit all resource groups for a mandatory tag"
  policy_type  = "Custom"
  mode         = "All"
  policy_rule  = <<POLICY_RULE
  {
    "if": {
      "allOf": [
        {
          "field": "type",
          "equals": "Microsoft.Resources/subscriptions/resourceGroups"
        },
        {
          "field": "[concat('tags[', parameters('tagName'), ']')]",
          "exists": "false"
        }
      ]
    },
    "then": {
      "effect": "audit"
    }
  }
POLICY_RULE

  parameters = <<PARAMETERS
  {
    "tagName": {
      "type": "String",
      "metadata": {
        "displayName": "Tag Name",
        "description": "Name of the tag, such as 'environment'"
      }
    }
  }
PARAMETERS

}

resource "azurerm_subscription_policy_assignment" "mandatory_resource_group_tag" {
  for_each             = var.azure_mandatory_resource_group_tags
  name                 = "Audit-MandatoryTag-${each.value}"
  display_name         = "Mandatory tag '${each.value}'"
  description          = "Assigning the mandatory tag policy for'${each.value}'"
  policy_definition_id = azurerm_policy_definition.mandatory_resource_group_tag.id
  subscription_id      = data.azurerm_client_config.this.subscription_id
  parameters           = <<PARAMETERS
  {
    "tagName": {
      "value": "${each.value}"
    }
  }
PARAMETERS
}
