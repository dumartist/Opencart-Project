#############################################
# VARIABLES - OpenCart AWS Deployment
#############################################
# Sensitive values should be defined in terraform.tfvars
# IMPORTANT: Add terraform.tfvars to .gitignore!
#############################################

#############################################
# Database Variables
#############################################

variable "db_name" {
  description = "Database name for OpenCart"
  type        = string
  default     = "opencartdb"
}

variable "db_username" {
  description = "Database admin username"
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "Database admin password (min 12 chars, mixed case, numbers, symbols. Cannot contain @)"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_password) >= 12
    error_message = "Database password must be at least 12 characters."
  }

  validation {
    condition     = !can(regex("@", var.db_password))
    error_message = "Database password cannot contain @ character (RDS restriction)."
  }
}

#############################################
# OpenCart Admin Variables
#############################################

variable "opencart_admin_username" {
  description = "OpenCart admin panel username"
  type        = string
  sensitive   = true
}

variable "opencart_admin_password" {
  description = "OpenCart admin panel password (min 10 chars)"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.opencart_admin_password) >= 10
    error_message = "OpenCart admin password must be at least 10 characters."
  }
}

variable "opencart_admin_email" {
  description = "OpenCart admin email address"
  type        = string
  default     = "admin@masquerade-shop.com" # This is a placeholder; Change as needed
}

#############################################
# Domain & Networking Variables
#############################################

variable "cloudflare_domain" {
  description = "Your Cloudflare domain (e.g., shop.example.com). Leave empty to use ALB DNS."
  type        = string
  default     = ""
}

#############################################
# Monitoring Variables
#############################################

variable "alert_email" {
  description = "Email address for CloudWatch alarm notifications"
  type        = string
}

#############################################
# SSH Key Variables
#############################################

variable "bastion_public_key" {
  description = "SSH public key for bastion host access (contents of .pub file)"
  type        = string
  sensitive   = true
}
