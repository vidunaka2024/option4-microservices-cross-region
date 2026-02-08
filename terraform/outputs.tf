# ==========================================
# EAST US Resource Group Outputs
# ==========================================

output "east_resource_group_name" {
  description = "Name of the East US resource group"
  value       = azurerm_resource_group.east.name
}

output "east_virtual_network_name" {
  description = "Name of the East US virtual network"
  value       = azurerm_virtual_network.east.name
}

# ==========================================
# WEST US 2 Resource Group Outputs  
# ==========================================

output "west_resource_group_name" {
  description = "Name of the West US 2 resource group"
  value       = azurerm_resource_group.west.name
}

output "west_virtual_network_name" {
  description = "Name of the West US 2 virtual network"
  value       = azurerm_virtual_network.west.name
}

# ==========================================
# EAST US VMs - Core Services (Public IPs)
# ==========================================

output "joke_vm_public_ip" {
  description = "Public IP address of the joke VM (East US)"
  value       = azurerm_public_ip.joke_vm.ip_address
}

output "submit_vm_public_ip" {
  description = "Public IP address of the submit VM (East US)"
  value       = azurerm_public_ip.submit_vm.ip_address
}

output "moderate_vm_public_ip" {
  description = "Public IP address of the moderate VM (East US)"
  value       = azurerm_public_ip.moderate_vm.ip_address
}

# ==========================================
# WEST US 2 VMs - Gateway & Message Broker (Public IPs)
# ==========================================

output "rabbitmq_vm_public_ip" {
  description = "Public IP address of the RabbitMQ VM (West US 2)"
  value       = azurerm_public_ip.rabbitmq_vm.ip_address
}

output "kong_vm_public_ip" {
  description = "Public IP address of the Kong VM (West US 2)"
  value       = azurerm_public_ip.kong_vm.ip_address
}

# ==========================================
# EAST US VMs - Private IPs (Cross-region)
# ==========================================

output "joke_vm_private_ip" {
  description = "Private IP address of the joke VM (East US)"
  value       = azurerm_network_interface.joke_vm.private_ip_address
}

output "submit_vm_private_ip" {
  description = "Private IP address of the submit VM (East US)"
  value       = azurerm_network_interface.submit_vm.private_ip_address
}

output "moderate_vm_private_ip" {
  description = "Private IP address of the moderate VM (East US)"
  value       = azurerm_network_interface.moderate_vm.private_ip_address
}

# ==========================================
# WEST US 2 VMs - Private IPs (Cross-region)
# ==========================================

output "rabbitmq_vm_private_ip" {
  description = "Private IP address of the RabbitMQ VM (West US 2)"
  value       = azurerm_network_interface.rabbitmq_vm.private_ip_address
}

output "kong_vm_private_ip" {
  description = "Private IP address of the Kong VM (West US 2)"
  value       = azurerm_network_interface.kong_vm.private_ip_address
}

# ==========================================
# Cross-Region Network Configuration
# ==========================================

output "vnet_peering_status" {
  description = "VNet peering status between East and West"
  value = {
    east_to_west = azurerm_virtual_network_peering.east_to_west.name
    west_to_east = azurerm_virtual_network_peering.west_to_east.name
  }
}

output "cross_region_connectivity" {
  description = "Cross-region private connectivity information"
  value = {
    east_subnet_range = "10.1.1.0/24"
    west_subnet_range = "10.2.1.0/24"
    east_services = {
      joke_vm     = "10.1.1.10"
      submit_vm   = "10.1.1.11" 
      moderate_vm = "10.1.1.12"
    }
    west_services = {
      rabbitmq_vm = "10.2.1.7"
      kong_vm     = "10.2.1.4"
    }
  }
}

# ==========================================
# Service URLs and Endpoints
# ==========================================

output "rabbitmq_management_url" {
  description = "RabbitMQ Management UI URL (West US 2)"
  value       = "http://${azurerm_public_ip.rabbitmq_vm.ip_address}:15672"
}

output "joke_service_url" {
  description = "Joke Service URL (East US)"
  value       = "http://${azurerm_public_ip.joke_vm.ip_address}:4000"
}

output "submit_service_url" {
  description = "Submit Service URL (East US)"
  value       = "http://${azurerm_public_ip.submit_vm.ip_address}:4200"
}

output "moderate_service_url" {
  description = "Moderate Service URL (East US)"
  value       = "http://${azurerm_public_ip.moderate_vm.ip_address}:3100"
}

output "kong_gateway_url" {
  description = "Kong Gateway URL (West US 2)"
  value       = "http://${azurerm_public_ip.kong_vm.ip_address}"
}

output "kong_gateway_ssl_url" {
  description = "Kong Gateway HTTPS URL (West US 2)"
  value       = "https://${azurerm_public_ip.kong_vm.ip_address}"
}

# ==========================================
# Configuration Information
# ==========================================

output "database_type" {
  description = "Currently configured database type"
  value       = var.db_type
}

output "deployment_architecture" {
  description = "Deployment architecture information"
  value = {
    east_region = "East US"
    west_region = "West US 2"
    total_resource_groups = 2
    total_vms = 5
    vnet_peering = "Enabled"
    ssl_enabled = "Yes"
  }
}

# ==========================================
# SSH Connection Commands
# ==========================================

output "ssh_connection_commands" {
  description = "SSH connection commands for all VMs"
  value = {
    # East US VMs
    joke_vm     = "ssh ${var.admin_username}@${azurerm_public_ip.joke_vm.ip_address}     # East US - Core Services"
    submit_vm   = "ssh ${var.admin_username}@${azurerm_public_ip.submit_vm.ip_address}   # East US - Core Services"  
    moderate_vm = "ssh ${var.admin_username}@${azurerm_public_ip.moderate_vm.ip_address} # East US - Core Services"
    
    # West US 2 VMs
    rabbitmq_vm = "ssh ${var.admin_username}@${azurerm_public_ip.rabbitmq_vm.ip_address} # West US 2 - Message Broker"
    kong_vm     = "ssh ${var.admin_username}@${azurerm_public_ip.kong_vm.ip_address}     # West US 2 - API Gateway"
  }
}

# ==========================================
# Quick Access URLs
# ==========================================

output "quick_access_urls" {
  description = "Quick access URLs for testing and management"
  value = {
    kong_gateway        = "http://${azurerm_public_ip.kong_vm.ip_address}"
    kong_gateway_https  = "https://${azurerm_public_ip.kong_vm.ip_address}"
    kong_admin         = "http://${azurerm_public_ip.kong_vm.ip_address}:8001"
    rabbitmq_ui        = "http://${azurerm_public_ip.rabbitmq_vm.ip_address}:15672"
    joke_api           = "http://${azurerm_public_ip.kong_vm.ip_address}/api/jokes"
    moderate_dashboard = "http://${azurerm_public_ip.kong_vm.ip_address}/moderate"
    submit_api         = "http://${azurerm_public_ip.kong_vm.ip_address}/submit"
  }
}