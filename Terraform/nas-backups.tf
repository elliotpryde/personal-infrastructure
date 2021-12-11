resource "azurerm_resource_group" "nas" {
  name     = "nas"
  location = local.azure_default_location
  tags     = merge(local.common_tags, {
    description = "Any resources related to my home NAS server."
  })
}

resource "azurerm_storage_account" "nas-backups" {
  name                     = "nasbkups"
  resource_group_name      = azurerm_resource_group.nas.name
  location                 = azurerm_resource_group.nas.location
  account_tier             = "Standard"
  account_replication_type = "RAGRS"
  account_kind             = "StorageV2"
  access_tier              = "Cool"
}

resource "azurerm_storage_container" "nas-docker-backups" {
  name                  = "nas-docker-backup"
  storage_account_name  = azurerm_storage_account.nas-backups.name
  container_access_type = "private"
}
