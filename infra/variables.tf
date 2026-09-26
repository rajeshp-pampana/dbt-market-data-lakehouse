variable "project" {
  type        = string
  description = "Short project identifier used in all resource names"
  default     = "dbtlakehouse"

  validation {
    condition     = can(regex("^[a-z0-9]{3,12}$", var.project))
    error_message = "project must be 3-12 lowercase alphanumeric characters (used in storage account names)."
  }
}

variable "environment" {
  type        = string
  description = "Deployment environment: dev | staging | prod"
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "location" {
  type        = string
  description = "Azure region for all resources"
  default     = "westeurope"
}

variable "owner_email" {
  type        = string
  description = "Owner email tag applied to all resources"
  default     = "rajesh.pampana777@gmail.com"
}

variable "sp_secret_rotation_key" {
  type        = string
  description = "Change this value to trigger SP secret rotation without destroying the SP"
  default     = "v1"
}
