resource "azurerm_policy_definition" "mandatory_resource_group_tag" {
  name         = "Audit-ResourceGroup-MandatoryTag"
  display_name = "Audit - A mandatory resource group tag"
  description  = "Audit all resource groups for a mandatory tag"
  policy_type  = "Custom"
  mode         = "All"
  parameters   = local.mandatory_rsg_tag_policy_definition_params

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

resource "azurerm_policy_set_definition" "resource_tagging_standards" {
  name         = "Audit-Standards-ResourceTagging"
  display_name = "Audit - Resource tagging standards"
  description  = "Audit resource tags to ensure they match our standards."
  policy_type  = "Custom"

  dynamic policy_definition_reference {
    for_each = var.azure_mandatory_resource_group_tags
    content {
      policy_definition_id = azurerm_policy_definition.mandatory_resource_group_tag.id
      parameter_values = jsonencode({
        "tagName" : {
          "value" : policy_definition_reference.value
        }
      })
    }
  }
}

resource "azurerm_subscription_policy_assignment" "resource_tagging_standards" {
  name                 = "Audit-Standards-ResourceTagging"
  display_name         = "Audit - Resource tagging standards"
  description          = "Audit resource tags to ensure they match our standards."
  policy_definition_id = azurerm_policy_set_definition.resource_tagging_standards.id
  subscription_id      = "/subscriptions/${data.azurerm_client_config.this.subscription_id}"
}
