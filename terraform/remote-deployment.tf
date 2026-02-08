# Remote Executioners for Automated Application Deployment
# This file handles deploying applications to VMs using Terraform remote-exec

# Deploy to Joke VM (East US)
resource "null_resource" "deploy_joke_vm" {
  triggers = {
    vm_id = azurerm_linux_virtual_machine.joke_vm.id
    docker_images_hash = null_resource.export_docker_images.id
  }

  connection {
    type        = "ssh"
    host        = azurerm_public_ip.joke_vm.ip_address
    user        = var.admin_username
    private_key = file(replace(var.ssh_public_key_path, ".pub", ""))
    timeout     = "10m"
  }

  # Wait for VM to be ready
  provisioner "remote-exec" {
    inline = [
      "echo 'Waiting for VM to be ready...'",
      "sudo cloud-init status --wait",
      "echo 'VM is ready for deployment'"
    ]
  }

  # Copy application files
  provisioner "file" {
    source      = "${path.root}/../joke-vm/"
    destination = "/tmp/joke-vm"
  }

  # Copy Docker images
  provisioner "file" {
    source      = "${path.root}/docker-exports/joke-service.tar.gz"
    destination = "/tmp/joke-service.tar.gz"
  }

  provisioner "file" {
    source      = "${path.root}/docker-exports/etl-service.tar.gz"
    destination = "/tmp/etl-service.tar.gz"
  }

  # Deploy and start services
  provisioner "remote-exec" {
    inline = [
      "echo '🚀 Starting Joke VM deployment...'",
      
      # Load Docker images
      "echo '📦 Loading Docker images...'",
      "sudo docker load < /tmp/joke-service.tar.gz",
      "sudo docker load < /tmp/etl-service.tar.gz",
      
      # Setup application directory
      "sudo mkdir -p /app/microservices",
      "sudo cp -r /tmp/joke-vm/* /app/microservices/",
      "cd /app/microservices",
      
      # Create environment-specific docker-compose
      "cat > docker-compose.yml << 'EOF'",
      "version: '3.8'",
      "services:",
      "  joke:",
      "    image: microservices/joke-service:latest",
      "    ports:",
      "      - \"4000:4000\"",
      "    environment:",
      "      - NODE_ENV=production",
      "      - DB_TYPE=${var.db_type}",
      "      - RABBITMQ_URL=amqp://10.2.1.7:5672",
      "      - MYSQL_HOST=joke-mysql",
      "      - MYSQL_PASSWORD=${var.mysql_root_password}",
      "      - MONGO_HOST=joke-mongo",
      "      - MONGO_USERNAME=${var.mongo_username}",
      "      - MONGO_PASSWORD=${var.mongo_password}",
      "    depends_on:",
      "      - joke-mysql",
      "      - joke-mongo",
      "    restart: unless-stopped",
      "",
      "  etl:",
      "    image: microservices/etl-service:latest", 
      "    ports:",
      "      - \"4001:4001\"",
      "    environment:",
      "      - NODE_ENV=production",
      "      - DB_TYPE=${var.db_type}",
      "      - RABBITMQ_URL=amqp://10.2.1.7:5672",
      "      - MYSQL_HOST=joke-mysql",
      "      - MYSQL_PASSWORD=${var.mysql_root_password}",
      "      - MONGO_HOST=joke-mongo",
      "      - MONGO_USERNAME=${var.mongo_username}",
      "      - MONGO_PASSWORD=${var.mongo_password}",
      "    restart: unless-stopped",
      "",
      "  joke-mysql:",
      "    image: mysql:8.0",
      "    environment:",
      "      - MYSQL_ROOT_PASSWORD=${var.mysql_root_password}",
      "      - MYSQL_DATABASE=jokes_db",
      "    volumes:",
      "      - mysql_data:/var/lib/mysql",
      "    restart: unless-stopped",
      "",
      "  joke-mongo:",
      "    image: mongo:6.0",
      "    environment:",
      "      - MONGO_INITDB_ROOT_USERNAME=${var.mongo_username}",
      "      - MONGO_INITDB_ROOT_PASSWORD=${var.mongo_password}",
      "      - MONGO_INITDB_DATABASE=jokes_db",
      "    volumes:",
      "      - mongo_data:/data/db",
      "    restart: unless-stopped",
      "",
      "volumes:",
      "  mysql_data:",
      "  mongo_data:",
      "EOF",
      
      # Start services
      "echo '▶️ Starting services...'",
      "sudo docker-compose up -d",
      
      # Wait and verify
      "sleep 30",
      "sudo docker-compose ps",
      
      # Health check
      "echo '🔍 Running health checks...'",
      "curl -f http://localhost:4000/health || echo 'Joke service starting...'",
      "curl -f http://localhost:4001/health || echo 'ETL service starting...'",
      
      "echo '✅ Joke VM deployment completed!'"
    ]
  }

  depends_on = [
    azurerm_linux_virtual_machine.joke_vm,
    null_resource.export_docker_images,
    null_resource.deploy_rabbitmq_vm
  ]
}

# Deploy to Submit VM (East US) 
resource "null_resource" "deploy_submit_vm" {
  triggers = {
    vm_id = azurerm_linux_virtual_machine.submit_vm.id
    docker_images_hash = null_resource.export_docker_images.id
  }

  connection {
    type        = "ssh"
    host        = azurerm_public_ip.submit_vm.ip_address
    user        = var.admin_username
    private_key = file(replace(var.ssh_public_key_path, ".pub", ""))
    timeout     = "10m"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo cloud-init status --wait",
      "echo 'Submit VM ready for deployment'"
    ]
  }

  provisioner "file" {
    source      = "${path.root}/../submit-vm/"
    destination = "/tmp/submit-vm"
  }

  provisioner "file" {
    source      = "${path.root}/docker-exports/submit-service.tar.gz"
    destination = "/tmp/submit-service.tar.gz"
  }

  provisioner "remote-exec" {
    inline = [
      "echo '🚀 Starting Submit VM deployment...'",
      
      # Load Docker image
      "sudo docker load < /tmp/submit-service.tar.gz",
      
      # Setup application
      "sudo mkdir -p /app/microservices",
      "sudo cp -r /tmp/submit-vm/* /app/microservices/",
      "cd /app/microservices",
      
      # Create docker-compose for submit service
      "cat > docker-compose.yml << 'EOF'",
      "version: '3.8'",
      "services:",
      "  submit:",
      "    image: microservices/submit-service:latest",
      "    ports:",
      "      - \"4200:4200\"",
      "    environment:",
      "      - RABBITMQ_URL=amqp://10.2.1.7:5672",
      "      - NODE_ENV=production",
      "    restart: unless-stopped",
      "EOF",
      
      # Start service
      "sudo docker-compose up -d",
      "sleep 20",
      
      # Health check
      "curl -f http://localhost:4200/health || echo 'Submit service starting...'",
      
      "echo '✅ Submit VM deployment completed!'"
    ]
  }

  depends_on = [
    azurerm_linux_virtual_machine.submit_vm,
    null_resource.export_docker_images,
    null_resource.deploy_rabbitmq_vm
  ]
}

# Deploy to Moderate VM (East US)
resource "null_resource" "deploy_moderate_vm" {
  triggers = {
    vm_id = azurerm_linux_virtual_machine.moderate_vm.id
    docker_images_hash = null_resource.export_docker_images.id
  }

  connection {
    type        = "ssh"
    host        = azurerm_public_ip.moderate_vm.ip_address
    user        = var.admin_username
    private_key = file(replace(var.ssh_public_key_path, ".pub", ""))
    timeout     = "10m"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo cloud-init status --wait",
      "echo 'Moderate VM ready for deployment'"
    ]
  }

  provisioner "file" {
    source      = "${path.root}/../moderate-vm/"
    destination = "/tmp/moderate-vm"
  }

  provisioner "file" {
    source      = "${path.root}/docker-exports/moderate-service.tar.gz"
    destination = "/tmp/moderate-service.tar.gz"
  }

  provisioner "remote-exec" {
    inline = [
      "echo '🚀 Starting Moderate VM deployment...'",
      
      # Load Docker image
      "sudo docker load < /tmp/moderate-service.tar.gz",
      
      # Setup application
      "sudo mkdir -p /app/microservices",
      "sudo cp -r /tmp/moderate-vm/* /app/microservices/",
      "cd /app/microservices",
      
      # Create docker-compose for moderate service
      "cat > docker-compose.yml << 'EOF'",
      "version: '3.8'",
      "services:",
      "  moderate:",
      "    image: microservices/moderate-service:latest",
      "    ports:",
      "      - \"3100:3100\"",
      "    environment:",
      "      - NODE_ENV=production",
      "      - RABBITMQ_URL=amqp://10.2.1.7:5672",
      "      - AUTH0_CLIENT_ID=your_auth0_client_id_here",
      "      - AUTH0_CLIENT_SECRET=your_auth0_client_secret_here",
      "      - AUTH0_ISSUER_BASE_URL=https://your-tenant.auth0.com",
      "      - AUTH0_BASE_URL=http://10.1.1.12:3100",
      "      - AUTH0_SECRET=a_long_random_string_for_session_encryption",
      "    restart: unless-stopped",
      "EOF",
      
      # Start service
      "sudo docker-compose up -d",
      "sleep 20",
      
      # Health check
      "curl -f http://localhost:3100/health || echo 'Moderate service starting...'",
      
      "echo '✅ Moderate VM deployment completed!'"
    ]
  }

  depends_on = [
    azurerm_linux_virtual_machine.moderate_vm,
    null_resource.export_docker_images,
    null_resource.deploy_rabbitmq_vm
  ]
}

# Deploy to RabbitMQ VM (West US 2)
resource "null_resource" "deploy_rabbitmq_vm" {
  triggers = {
    vm_id = azurerm_linux_virtual_machine.rabbitmq_vm.id
  }

  connection {
    type        = "ssh"
    host        = azurerm_public_ip.rabbitmq_vm.ip_address
    user        = var.admin_username
    private_key = file(replace(var.ssh_public_key_path, ".pub", ""))
    timeout     = "10m"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo cloud-init status --wait",
      "echo 'RabbitMQ VM ready for deployment'"
    ]
  }

  provisioner "file" {
    source      = "${path.root}/../rabbitmq-vm/"
    destination = "/tmp/rabbitmq-vm"
  }

  provisioner "remote-exec" {
    inline = [
      "echo '🚀 Starting RabbitMQ VM deployment...'",
      
      # Setup RabbitMQ
      "sudo mkdir -p /app/microservices",
      "sudo cp -r /tmp/rabbitmq-vm/* /app/microservices/",
      "cd /app/microservices",
      
      # Start RabbitMQ
      "sudo docker-compose up -d",
      "sleep 30",
      
      # Wait for RabbitMQ to be ready
      "echo 'Waiting for RabbitMQ to start...'",
      "timeout=60",
      "while [ $timeout -gt 0 ]; do",
      "  if curl -f http://localhost:15672 >/dev/null 2>&1; then",
      "    echo 'RabbitMQ is ready'",
      "    break",
      "  fi",
      "  sleep 5",
      "  timeout=$((timeout-5))",
      "done",
      
      "echo '✅ RabbitMQ VM deployment completed!'"
    ]
  }

  depends_on = [
    azurerm_linux_virtual_machine.rabbitmq_vm
  ]
}

# Deploy to Kong VM (West US 2) with SSL
resource "null_resource" "deploy_kong_vm" {
  triggers = {
    vm_id = azurerm_linux_virtual_machine.kong_vm.id
  }

  connection {
    type        = "ssh"
    host        = azurerm_public_ip.kong_vm.ip_address
    user        = var.admin_username
    private_key = file(replace(var.ssh_public_key_path, ".pub", ""))
    timeout     = "10m"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo cloud-init status --wait",
      "echo 'Kong VM ready for deployment'"
    ]
  }

  # Copy SSL certificates
  provisioner "file" {
    source      = "${path.root}/../ssl-certificates/"
    destination = "/tmp/ssl-certificates"
  }

  # Copy Kong configuration
  provisioner "file" {
    source      = "${path.root}/../kong-vm/"
    destination = "/tmp/kong-vm"
  }

  provisioner "remote-exec" {
    inline = [
      "echo '🚀 Starting Kong VM deployment...'",
      
      # Setup SSL certificates
      "sudo mkdir -p /app/ssl-certificates",
      "sudo cp -r /tmp/ssl-certificates/* /app/ssl-certificates/",
      "sudo chmod 644 /app/ssl-certificates/gateway.crt",
      "sudo chmod 600 /app/ssl-certificates/gateway.key",
      
      # Setup Kong
      "sudo mkdir -p /app/microservices",
      "sudo cp -r /tmp/kong-vm/* /app/microservices/",
      "cd /app/microservices",
      
      # Update Kong configuration with actual service IPs
      "sed -i 's|http://10.1.1.10:4000|http://10.1.1.10:4000|g' kong-declarative.yml",
      "sed -i 's|http://10.1.1.11:4200|http://10.1.1.11:4200|g' kong-declarative.yml",
      "sed -i 's|http://10.1.1.12:3100|http://10.1.1.12:3100|g' kong-declarative.yml",
      
      # Start Kong with SSL
      "sudo docker-compose up -d",
      "sleep 30",
      
      # Verify Kong is running
      "curl -f http://localhost:8001 || echo 'Kong starting...'",
      "curl -f https://localhost:8443 -k || echo 'Kong HTTPS starting...'",
      
      "echo '✅ Kong VM deployment completed!'"
    ]
  }

  depends_on = [
    azurerm_linux_virtual_machine.kong_vm,
    null_resource.deploy_joke_vm,
    null_resource.deploy_submit_vm, 
    null_resource.deploy_moderate_vm
  ]
}