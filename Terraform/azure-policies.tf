resource "azurerm_policy_set_definition" "mandatory_resource_group_tags" {
  name         = "Audit-ResourceGroup-MandatoryTags"
  display_name = "Audit - Mandatory resource group tags"
  description  = "Audit all resource groups for a set of mandatory tags"
  policy_type  = "Custom"
  parameters = local.mandatory_rsg_tag_policy_definition_params

  policy_definition_reference {
    policy_definition_id = azurerm_policy_definition.mandatory_resource_group_tag.id
    parameter_values = jsonencode({
      "tagName": {
        "value": "[parameters('tagName')]"
      }
    })
  }
}

resource "azurerm_policy_definition" "mandatory_resource_group_tag" {
  name         = "Audit-ResourceGroup-MandatoryTag"
  display_name = "Audit - A mandatory resource group tag"
  description  = "Audit all resource groups for a mandatory tag"
  policy_type  = "Custom"
  mode         = "All"
  parameters = local.mandatory_rsg_tag_policy_definition_params

  policy_rule = jsonencode({
    "if" : {
      "allOf" : [
        {
          "field" : "type",
          "equals" : "Microsoft.Resources/subscriptions/resourceGroups"
        },
        {
          "field" : "[concat('tags[', parameters('tagName'), ']')]",
          "exists" : "false"
        }
      ]
    },
    "then" : {
      "effect" : "audit"
    }
  })
}

resource "azurerm_subscription_policy_assignment" "mandatory_resource_group_tag" {
  for_each             = var.azure_mandatory_resource_group_tags
  name                 = "Audit-MandatoryTag-${each.value}"
  display_name         = "Mandatory tag '${each.value}'"
  description          = "Assigning the mandatory tag policy for'${each.value}'"
  policy_definition_id = azurerm_policy_definition.mandatory_resource_group_tag.id
  subscription_id      = "/subscriptions/${data.azurerm_client_config.this.subscription_id}"
  parameters = jsonencode({
    "tagName" : {
      "value" : each.value
    }
  })
}
