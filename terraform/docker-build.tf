# Docker Build and Push Automation
# This file handles building and pushing Docker images as part of infrastructure deployment

# Build Joke Service Docker Image
resource "null_resource" "build_joke_service" {
  triggers = {
    # Rebuild if source code changes
    joke_source_hash = filemd5("${path.root}/../joke-vm/joke/index.js")
    joke_package_hash = filemd5("${path.root}/../joke-vm/joke/package.json")
    joke_dockerfile_hash = filemd5("${path.root}/../joke-vm/joke/Dockerfile")
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "🐳 Building Joke Service Docker Image..."
      cd ${path.root}/../joke-vm/joke
      docker build -t microservices/joke-service:${var.environment} .
      docker tag microservices/joke-service:${var.environment} microservices/joke-service:latest
      echo "✅ Joke Service image built"
    EOT
  }

  depends_on = [
    azurerm_resource_group.east,
    azurerm_resource_group.west
  ]
}

# Build ETL Service Docker Image  
resource "null_resource" "build_etl_service" {
  triggers = {
    etl_source_hash = filemd5("${path.root}/../joke-vm/etl/index.js")
    etl_package_hash = filemd5("${path.root}/../joke-vm/etl/package.json")
    etl_dockerfile_hash = filemd5("${path.root}/../joke-vm/etl/Dockerfile")
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "🐳 Building ETL Service Docker Image..."
      cd ${path.root}/../joke-vm/etl
      docker build -t microservices/etl-service:${var.environment} .
      docker tag microservices/etl-service:${var.environment} microservices/etl-service:latest
      echo "✅ ETL Service image built"
    EOT
  }
}

# Build Submit Service Docker Image
resource "null_resource" "build_submit_service" {
  triggers = {
    submit_source_hash = filemd5("${path.root}/../submit-vm/submit/index.js")
    submit_package_hash = filemd5("${path.root}/../submit-vm/submit/package.json")
    submit_dockerfile_hash = filemd5("${path.root}/../submit-vm/submit/Dockerfile")
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "🐳 Building Submit Service Docker Image..."
      cd ${path.root}/../submit-vm/submit
      docker build -t microservices/submit-service:${var.environment} .
      docker tag microservices/submit-service:${var.environment} microservices/submit-service:latest
      echo "✅ Submit Service image built"
    EOT
  }
}

# Build Moderate Service Docker Image
resource "null_resource" "build_moderate_service" {
  triggers = {
    moderate_source_hash = filemd5("${path.root}/../moderate-vm/moderate/index.js")
    moderate_package_hash = filemd5("${path.root}/../moderate-vm/moderate/package.json")
    moderate_dockerfile_hash = filemd5("${path.root}/../moderate-vm/moderate/Dockerfile")
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "🐳 Building Moderate Service Docker Image..."
      cd ${path.root}/../moderate-vm/moderate
      docker build -t microservices/moderate-service:${var.environment} .
      docker tag microservices/moderate-service:${var.environment} microservices/moderate-service:latest
      echo "✅ Moderate Service image built"
    EOT
  }
}

# Export Docker Images for Transfer
resource "null_resource" "export_docker_images" {
  triggers = {
    build_timestamp = timestamp()
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "📦 Exporting Docker images for deployment..."
      mkdir -p ${path.root}/docker-exports
      
      docker save microservices/joke-service:latest | gzip > ${path.root}/docker-exports/joke-service.tar.gz
      docker save microservices/etl-service:latest | gzip > ${path.root}/docker-exports/etl-service.tar.gz
      docker save microservices/submit-service:latest | gzip > ${path.root}/docker-exports/submit-service.tar.gz
      docker save microservices/moderate-service:latest | gzip > ${path.root}/docker-exports/moderate-service.tar.gz
      
      echo "✅ Docker images exported for deployment"
    EOT
  }

  depends_on = [
    null_resource.build_joke_service,
    null_resource.build_etl_service,
    null_resource.build_submit_service,
    null_resource.build_moderate_service
  ]
}