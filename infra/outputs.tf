output "resource_group_name" {
  description = "Name of the provisioned resource group"
  value       = azurerm_resource_group.lakehouse.name
}

output "storage_account_name" {
  description = "ADLS Gen2 storage account name"
  value       = azurerm_storage_account.lakehouse.name
}

output "storage_account_id" {
  description = "ADLS Gen2 storage account resource ID"
  value       = azurerm_storage_account.lakehouse.id
}

output "dbt_runner_client_id" {
  description = "Service principal client ID for the dbt runner"
  value       = azuread_application.dbt_runner.client_id
}

output "dbt_runner_tenant_id" {
  description = "Azure AD tenant ID"
  value       = data.azuread_client_config.current.tenant_id
}

output "key_vault_name" {
  description = "Key Vault name — retrieve secrets with: az keyvault secret show"
  value       = azurerm_key_vault.lakehouse.name
}

output "key_vault_uri" {
  description = "Key Vault URI"
  value       = azurerm_key_vault.lakehouse.vault_uri
}

# ─── Sensitive outputs — never print in CI logs ────────────────────────────────
output "dbt_runner_client_secret" {
  description = "SP client secret — stored in Key Vault; use Key Vault reference in CI"
  value       = azuread_service_principal_password.dbt_runner.value
  sensitive   = true
}

output "storage_primary_connection_string" {
  description = "Storage connection string — stored in Key Vault; use Key Vault reference in CI"
  value       = azurerm_storage_account.lakehouse.primary_connection_string
  sensitive   = true
}

# ─── Shell export block (copy-paste for local dev) ────────────────────────────
output "env_export_block" {
  description = "Environment variable export block for local dbt development"
  sensitive   = true
  value = <<-EOT
    # Add to .env (never commit this file)
    AZURE_CLIENT_ID=${azuread_application.dbt_runner.client_id}
    AZURE_TENANT_ID=${data.azuread_client_config.current.tenant_id}
    AZURE_CLIENT_SECRET=<retrieve from Key Vault: ${azurerm_key_vault.lakehouse.name}>
    AZURE_STORAGE_ACCOUNT=${azurerm_storage_account.lakehouse.name}
  EOT
}
