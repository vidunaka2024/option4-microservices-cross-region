variable "location" {
  description = "The Azure Region where resources should be created"
  default     = "East US"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  default     = "dev"
  type        = string
}

variable "admin_username" {
  description = "Admin username for VMs"
  default     = "azureuser"
  type        = string
}

variable "vm_size" {
  description = "Size of the Virtual Machine"
  default     = "Standard_B2s"
  type        = string
}

variable "db_type" {
  description = "Database type to deploy (mysql or mongo)"
  default     = "mongo"
  type        = string
  
  validation {
    condition     = contains(["mysql", "mongo"], var.db_type)
    error_message = "Database type must be either 'mysql' or 'mongo'."
  }
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key file"
  default     = "~/.ssh/id_rsa.pub"
  type        = string
}

variable "mysql_root_password" {
  description = "Root password for MySQL"
  default     = "SecurePassword123!"
  type        = string
  sensitive   = true
}

variable "mongo_username" {
  description = "Username for MongoDB"
  default     = "admin"
  type        = string
}

variable "mongo_password" {
  description = "Password for MongoDB"
  default     = "SecurePassword123!"
  type        = string
  sensitive   = true
}