terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~>3.1"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "random_id" "suffix" {
  byte_length = 4
}

# East US Resource Group for Core Services
resource "azurerm_resource_group" "east" {
  name     = "rg-microservices-east-${random_id.suffix.hex}"
  location = "East US"
  
  tags = {
    Environment = var.environment
    Project     = "MicroservicesDemo"
    Region      = "East"
  }
}

# West US 2 Resource Group for Gateway and Message Broker
resource "azurerm_resource_group" "west" {
  name     = "rg-microservices-west-${random_id.suffix.hex}"
  location = "West US 2"
  
  tags = {
    Environment = var.environment
    Project     = "MicroservicesDemo"
    Region      = "West"
  }
}

# East US Virtual Network for Core Services
resource "azurerm_virtual_network" "east" {
  name                = "vnet-microservices-east"
  address_space       = ["10.1.0.0/16"]
  location            = azurerm_resource_group.east.location
  resource_group_name = azurerm_resource_group.east.name
  
  tags = {
    Environment = var.environment
    Project     = "MicroservicesDemo"
    Region      = "East"
  }
}

# West US 2 Virtual Network for Gateway and Message Broker
resource "azurerm_virtual_network" "west" {
  name                = "vnet-microservices-west"
  address_space       = ["10.2.0.0/16"]
  location            = azurerm_resource_group.west.location
  resource_group_name = azurerm_resource_group.west.name
  
  tags = {
    Environment = var.environment
    Project     = "MicroservicesDemo"
    Region      = "West"
  }
}

# East US Subnet for Core Services
resource "azurerm_subnet" "east" {
  name                 = "subnet-services"
  resource_group_name  = azurerm_resource_group.east.name
  virtual_network_name = azurerm_virtual_network.east.name
  address_prefixes     = ["10.1.1.0/24"]
}

# West US 2 Subnet for Gateway and Message Broker
resource "azurerm_subnet" "west" {
  name                 = "subnet-gateway"
  resource_group_name  = azurerm_resource_group.west.name
  virtual_network_name = azurerm_virtual_network.west.name
  address_prefixes     = ["10.2.1.0/24"]
}

# VNet Peering: East to West
resource "azurerm_virtual_network_peering" "east_to_west" {
  name                = "peer-east-to-west"
  resource_group_name = azurerm_resource_group.east.name
  virtual_network_name = azurerm_virtual_network.east.name
  remote_virtual_network_id = azurerm_virtual_network.west.id
  allow_virtual_network_access = true
  allow_forwarded_traffic = true
  allow_gateway_transit = false
  use_remote_gateways = false
}

# VNet Peering: West to East
resource "azurerm_virtual_network_peering" "west_to_east" {
  name                = "peer-west-to-east"
  resource_group_name = azurerm_resource_group.west.name
  virtual_network_name = azurerm_virtual_network.west.name
  remote_virtual_network_id = azurerm_virtual_network.east.id
  allow_virtual_network_access = true
  allow_forwarded_traffic = true
  allow_gateway_transit = false
  use_remote_gateways = false
}

# East US Network Security Group
resource "azurerm_network_security_group" "east" {
  name                = "nsg-microservices-east"
  location            = azurerm_resource_group.east.location
  resource_group_name = azurerm_resource_group.east.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTP"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTPS"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Services"
    priority                   = 1004
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "4000-5000"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Cross_Region_Communication"
    priority                   = 1005
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "10.2.0.0/16"
    destination_address_prefix = "*"
  }

  tags = {
    Environment = var.environment
    Project     = "MicroservicesDemo"
    Region      = "East"
  }
}

# West US 2 Network Security Group
resource "azurerm_network_security_group" "west" {
  name                = "nsg-microservices-west"
  location            = azurerm_resource_group.west.location
  resource_group_name = azurerm_resource_group.west.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTP"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTPS"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Kong_Admin"
    priority                   = 1004
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8001"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "RabbitMQ"
    priority                   = 1005
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5672"
    source_address_prefix      = "10.1.0.0/16"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "RabbitMQ_Management"
    priority                   = 1006
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "15672"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Cross_Region_Communication"
    priority                   = 1007
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "10.1.0.0/16"
    destination_address_prefix = "*"
  }

  tags = {
    Environment = var.environment
    Project     = "MicroservicesDemo"
    Region      = "West"
  }
}

# Network Security Group Associations
resource "azurerm_subnet_network_security_group_association" "east" {
  subnet_id                 = azurerm_subnet.east.id
  network_security_group_id = azurerm_network_security_group.east.id
}

resource "azurerm_subnet_network_security_group_association" "west" {
  subnet_id                 = azurerm_subnet.west.id
  network_security_group_id = azurerm_network_security_group.west.id
}