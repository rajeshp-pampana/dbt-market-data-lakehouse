terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.50"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Uncomment to use Azure Blob backend (recommended for team use)
  # backend "azurerm" {
  #   resource_group_name  = "tfstate-rg"
  #   storage_account_name = "tfstate<suffix>"
  #   container_name       = "tfstate"
  #   key                  = "dbt-lakehouse.terraform.tfstate"
  # }
}

provider "azurerm" {
  features {}
}

provider "azuread" {}

# ─── RANDOM SUFFIX ─────────────────────────────────────────────────────────────
# Makes storage account names globally unique without manual effort.
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

# ─── RESOURCE GROUP ────────────────────────────────────────────────────────────
resource "azurerm_resource_group" "lakehouse" {
  name     = "${var.project}-${var.environment}-rg"
  location = var.location

  tags = local.common_tags
}

# ─── ADLS GEN2 STORAGE ─────────────────────────────────────────────────────────
resource "azurerm_storage_account" "lakehouse" {
  name                     = "${var.project}${var.environment}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.lakehouse.name
  location                 = azurerm_resource_group.lakehouse.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  # Enable hierarchical namespace → ADLS Gen2
  is_hns_enabled = true

  # Security hardening
  min_tls_version          = "TLS1_2"
  enable_https_traffic_only = true
  shared_access_key_enabled = true  # required for dbt-duckdb ADLS connector

  blob_properties {
    delete_retention_policy {
      days = 7
    }
    versioning_enabled = true
  }

  tags = local.common_tags
}

# ─── ADLS CONTAINERS (MEDALLION LAYERS) ────────────────────────────────────────
resource "azurerm_storage_container" "bronze" {
  name                  = "bronze"
  storage_account_name  = azurerm_storage_account.lakehouse.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "silver" {
  name                  = "silver"
  storage_account_name  = azurerm_storage_account.lakehouse.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "gold" {
  name                  = "gold"
  storage_account_name  = azurerm_storage_account.lakehouse.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "dbt_artifacts" {
  name                  = "dbt-artifacts"
  storage_account_name  = azurerm_storage_account.lakehouse.name
  container_access_type = "private"
}

# ─── SERVICE PRINCIPAL (CI / dbt runner) ───────────────────────────────────────
data "azuread_client_config" "current" {}

resource "azuread_application" "dbt_runner" {
  display_name = "${var.project}-${var.environment}-dbt-runner"
  owners       = [data.azuread_client_config.current.object_id]
}

resource "azuread_service_principal" "dbt_runner" {
  client_id = azuread_application.dbt_runner.client_id
  owners    = [data.azuread_client_config.current.object_id]
}

resource "azuread_service_principal_password" "dbt_runner" {
  service_principal_id = azuread_service_principal.dbt_runner.id
  end_date_relative    = "8760h" # 1 year

  rotate_when_changed = {
    rotation = var.sp_secret_rotation_key
  }
}

# ─── RBAC: SP scoped to Storage Blob Data Contributor on lakehouse account ─────
# Follows least-privilege: read/write blobs only, no management-plane access.
resource "azurerm_role_assignment" "dbt_runner_storage" {
  scope                = azurerm_storage_account.lakehouse.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.dbt_runner.object_id
}

# ─── KEY VAULT (secrets management) ────────────────────────────────────────────
resource "azurerm_key_vault" "lakehouse" {
  name                = "${var.project}-${var.environment}-kv-${random_string.suffix.result}"
  location            = azurerm_resource_group.lakehouse.location
  resource_group_name = azurerm_resource_group.lakehouse.name
  tenant_id           = data.azuread_client_config.current.tenant_id
  sku_name            = "standard"

  # Soft-delete and purge protection
  soft_delete_retention_days = 7
  purge_protection_enabled   = false  # set true for production

  # Deploying identity gets full access
  access_policy {
    tenant_id = data.azuread_client_config.current.tenant_id
    object_id = data.azuread_client_config.current.object_id

    secret_permissions = ["Get", "List", "Set", "Delete", "Recover", "Backup", "Restore", "Purge"]
  }

  # dbt runner SP gets read-only access to secrets
  access_policy {
    tenant_id = data.azuread_client_config.current.tenant_id
    object_id = azuread_service_principal.dbt_runner.object_id

    secret_permissions = ["Get", "List"]
  }

  tags = local.common_tags
}

# ─── STORE SP SECRET IN KEY VAULT ──────────────────────────────────────────────
resource "azurerm_key_vault_secret" "dbt_runner_secret" {
  name         = "dbt-runner-client-secret"
  value        = azuread_service_principal_password.dbt_runner.value
  key_vault_id = azurerm_key_vault.lakehouse.id

  # Never log the secret value
  lifecycle {
    ignore_changes = [value]
  }
}

resource "azurerm_key_vault_secret" "storage_account_key" {
  name         = "storage-account-key"
  value        = azurerm_storage_account.lakehouse.primary_access_key
  key_vault_id = azurerm_key_vault.lakehouse.id

  lifecycle {
    ignore_changes = [value]
  }
}

# ─── LOCALS ────────────────────────────────────────────────────────────────────
locals {
  common_tags = {
    project     = var.project
    environment = var.environment
    managed_by  = "terraform"
    owner       = var.owner_email
  }
}
