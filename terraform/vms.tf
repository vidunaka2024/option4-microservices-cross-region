# ==========================================
# EAST US VMs - Core Services
# ==========================================

# Public IPs for East US VMs
resource "azurerm_public_ip" "joke_vm" {
  name                = "pip-joke-vm"
  resource_group_name = azurerm_resource_group.east.name
  location            = azurerm_resource_group.east.location
  allocation_method   = "Static"

  tags = {
    Environment = var.environment
    Service     = "joke"
    Region      = "East"
  }
}

resource "azurerm_public_ip" "submit_vm" {
  name                = "pip-submit-vm"
  resource_group_name = azurerm_resource_group.east.name
  location            = azurerm_resource_group.east.location
  allocation_method   = "Static"

  tags = {
    Environment = var.environment
    Service     = "submit"
    Region      = "East"
  }
}

resource "azurerm_public_ip" "moderate_vm" {
  name                = "pip-moderate-vm"
  resource_group_name = azurerm_resource_group.east.name
  location            = azurerm_resource_group.east.location
  allocation_method   = "Static"

  tags = {
    Environment = var.environment
    Service     = "moderate"
    Region      = "East"
  }
}

# Network Interfaces for East US VMs
resource "azurerm_network_interface" "joke_vm" {
  name                = "nic-joke-vm"
  location            = azurerm_resource_group.east.location
  resource_group_name = azurerm_resource_group.east.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.east.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.1.1.10"
    public_ip_address_id          = azurerm_public_ip.joke_vm.id
  }

  tags = {
    Environment = var.environment
    Service     = "joke"
    Region      = "East"
  }
}

resource "azurerm_network_interface" "submit_vm" {
  name                = "nic-submit-vm"
  location            = azurerm_resource_group.east.location
  resource_group_name = azurerm_resource_group.east.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.east.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.1.1.11"
    public_ip_address_id          = azurerm_public_ip.submit_vm.id
  }

  tags = {
    Environment = var.environment
    Service     = "submit"
    Region      = "East"
  }
}

resource "azurerm_network_interface" "moderate_vm" {
  name                = "nic-moderate-vm"
  location            = azurerm_resource_group.east.location
  resource_group_name = azurerm_resource_group.east.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.east.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.1.1.12"
    public_ip_address_id          = azurerm_public_ip.moderate_vm.id
  }

  tags = {
    Environment = var.environment
    Service     = "moderate"
    Region      = "East"
  }
}

# SSH Keys for East US
resource "azurerm_ssh_public_key" "east" {
  name                = "ssh-key-microservices-east"
  resource_group_name = azurerm_resource_group.east.name
  location            = azurerm_resource_group.east.location
  public_key          = file(var.ssh_public_key_path)
}

data "azurerm_ssh_public_key" "east" {
  name                = "ssh-key-microservices-east"
  resource_group_name = azurerm_resource_group.east.name
  depends_on          = [azurerm_ssh_public_key.east]
}

# East US Virtual Machines
resource "azurerm_linux_virtual_machine" "joke_vm" {
  name                = "vm-joke-east"
  resource_group_name = azurerm_resource_group.east.name
  location            = azurerm_resource_group.east.location
  size                = var.vm_size
  admin_username      = var.admin_username

  custom_data = base64encode(templatefile("${path.module}/cloud-init/joke-vm.yml", {
    db_type            = var.db_type
    rabbitmq_host      = "10.2.1.7"  # Cross-region RabbitMQ in West
    mysql_password     = var.mysql_root_password
    mongo_username     = var.mongo_username
    mongo_password     = var.mongo_password
  }))

  disable_password_authentication = true

  network_interface_ids = [
    azurerm_network_interface.joke_vm.id,
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = data.azurerm_ssh_public_key.east.public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts-gen2"
    version   = "latest"
  }

  tags = {
    Environment = var.environment
    Service     = "joke"
    Region      = "East"
  }
}

resource "azurerm_linux_virtual_machine" "submit_vm" {
  name                = "vm-submit-east"
  resource_group_name = azurerm_resource_group.east.name
  location            = azurerm_resource_group.east.location
  size                = var.vm_size
  admin_username      = var.admin_username

  custom_data = base64encode(templatefile("${path.module}/cloud-init/submit-vm.yml", {
    rabbitmq_host = "10.2.1.7"  # Cross-region RabbitMQ in West
  }))

  disable_password_authentication = true

  network_interface_ids = [
    azurerm_network_interface.submit_vm.id,
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = data.azurerm_ssh_public_key.east.public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts-gen2"
    version   = "latest"
  }

  tags = {
    Environment = var.environment
    Service     = "submit"
    Region      = "East"
  }
}

resource "azurerm_linux_virtual_machine" "moderate_vm" {
  name                = "vm-moderate-east"
  resource_group_name = azurerm_resource_group.east.name
  location            = azurerm_resource_group.east.location
  size                = var.vm_size
  admin_username      = var.admin_username

  custom_data = base64encode(templatefile("${path.module}/cloud-init/moderate-vm.yml", {
    rabbitmq_host = "10.2.1.7"  # Cross-region RabbitMQ in West
  }))

  disable_password_authentication = true

  network_interface_ids = [
    azurerm_network_interface.moderate_vm.id,
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = data.azurerm_ssh_public_key.east.public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts-gen2"
    version   = "latest"
  }

  tags = {
    Environment = var.environment
    Service     = "moderate"
    Region      = "East"
  }
}

# ==========================================
# WEST US 2 VMs - Gateway and Message Broker
# ==========================================

# Public IPs for West US 2 VMs
resource "azurerm_public_ip" "rabbitmq_vm" {
  name                = "pip-rabbitmq-vm"
  resource_group_name = azurerm_resource_group.west.name
  location            = azurerm_resource_group.west.location
  allocation_method   = "Static"

  tags = {
    Environment = var.environment
    Service     = "rabbitmq"
    Region      = "West"
  }
}

resource "azurerm_public_ip" "kong_vm" {
  name                = "pip-kong-vm"
  resource_group_name = azurerm_resource_group.west.name
  location            = azurerm_resource_group.west.location
  allocation_method   = "Static"

  tags = {
    Environment = var.environment
    Service     = "kong"
    Region      = "West"
  }
}

# Network Interfaces for West US 2 VMs
resource "azurerm_network_interface" "rabbitmq_vm" {
  name                = "nic-rabbitmq-vm"
  location            = azurerm_resource_group.west.location
  resource_group_name = azurerm_resource_group.west.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.west.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.2.1.7"
    public_ip_address_id          = azurerm_public_ip.rabbitmq_vm.id
  }

  tags = {
    Environment = var.environment
    Service     = "rabbitmq"
    Region      = "West"
  }
}

resource "azurerm_network_interface" "kong_vm" {
  name                = "nic-kong-vm"
  location            = azurerm_resource_group.west.location
  resource_group_name = azurerm_resource_group.west.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.west.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.2.1.4"
    public_ip_address_id          = azurerm_public_ip.kong_vm.id
  }

  tags = {
    Environment = var.environment
    Service     = "kong"
    Region      = "West"
  }
}

# SSH Keys for West US 2
resource "azurerm_ssh_public_key" "west" {
  name                = "ssh-key-microservices-west"
  resource_group_name = azurerm_resource_group.west.name
  location            = azurerm_resource_group.west.location
  public_key          = file(var.ssh_public_key_path)
}

data "azurerm_ssh_public_key" "west" {
  name                = "ssh-key-microservices-west"
  resource_group_name = azurerm_resource_group.west.name
  depends_on          = [azurerm_ssh_public_key.west]
}

# West US 2 Virtual Machines
resource "azurerm_linux_virtual_machine" "rabbitmq_vm" {
  name                = "vm-rabbitmq-west"
  resource_group_name = azurerm_resource_group.west.name
  location            = azurerm_resource_group.west.location
  size                = var.vm_size
  admin_username      = var.admin_username

  custom_data = base64encode(file("${path.module}/cloud-init/rabbitmq-vm.yml"))

  disable_password_authentication = true

  network_interface_ids = [
    azurerm_network_interface.rabbitmq_vm.id,
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = data.azurerm_ssh_public_key.west.public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts-gen2"
    version   = "latest"
  }

  tags = {
    Environment = var.environment
    Service     = "rabbitmq"
    Region      = "West"
  }
}

resource "azurerm_linux_virtual_machine" "kong_vm" {
  name                = "vm-kong-west"
  resource_group_name = azurerm_resource_group.west.name
  location            = azurerm_resource_group.west.location
  size                = var.vm_size
  admin_username      = var.admin_username

  custom_data = base64encode(templatefile("${path.module}/cloud-init/kong-vm.yml", {
    joke_service_url    = "http://10.1.1.10:4000"      # Cross-region Joke service
    submit_service_url  = "http://10.1.1.11:4200"     # Cross-region Submit service  
    moderate_service_url = "http://10.1.1.12:3100"    # Cross-region Moderate service
    etl_service_url     = "http://10.1.1.10:4001"     # Cross-region ETL service
  }))

  disable_password_authentication = true

  network_interface_ids = [
    azurerm_network_interface.kong_vm.id,
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = data.azurerm_ssh_public_key.west.public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts-gen2"
    version   = "latest"
  }

  tags = {
    Environment = var.environment
    Service     = "kong"
    Region      = "West"
  }
}