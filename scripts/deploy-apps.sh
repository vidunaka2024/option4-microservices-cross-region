#!/bin/bash

# Application Deployment Script
# This script deploys application code to the infrastructure VMs

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"

# Default values
FORCE_DEPLOY="false"
BUILD_IMAGES="true"
HEALTH_CHECK="true"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy applications to the infrastructure VMs

OPTIONS:
    -f, --force                Force deployment even if services are running
    -n, --no-build             Skip Docker image building
    -s, --skip-health-check    Skip health checks after deployment
    -h, --help                 Show this help message

EXAMPLES:
    # Standard deployment
    $0

    # Force deployment without building images
    $0 --force --no-build

    # Deploy and skip health check
    $0 --skip-health-check

PREREQUISITES:
    - Infrastructure must be deployed (run deploy-infrastructure.sh first)
    - Docker installed locally
    - SSH access to VMs

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--force)
            FORCE_DEPLOY="true"
            shift
            ;;
        -n|--no-build)
            BUILD_IMAGES="false"
            shift
            ;;
        -s|--skip-health-check)
            HEALTH_CHECK="false"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            print_error "Unknown option $1"
            usage
            exit 1
            ;;
    esac
done

print_status "Starting application deployment..."

# Check if infrastructure is deployed
if [[ ! -f "$PROJECT_ROOT/deployment-info.json" ]]; then
    print_error "No deployment info found. Run deploy-infrastructure.sh first."
    exit 1
fi

# Read deployment info
if command -v jq &> /dev/null; then
    JOKE_VM_IP=$(jq -r '.services.joke_vm.public_ip' "$PROJECT_ROOT/deployment-info.json")
    SUBMIT_VM_IP=$(jq -r '.services.submit_vm.public_ip' "$PROJECT_ROOT/deployment-info.json")
    MODERATE_VM_IP=$(jq -r '.services.moderate_vm.public_ip' "$PROJECT_ROOT/deployment-info.json")
    RABBITMQ_VM_IP=$(jq -r '.services.rabbitmq_vm.public_ip' "$PROJECT_ROOT/deployment-info.json")
    KONG_VM_IP=$(jq -r '.services.kong_vm.public_ip' "$PROJECT_ROOT/deployment-info.json")
else
    # Fallback: read from Terraform output
    cd "$TERRAFORM_DIR"
    JOKE_VM_IP=$(terraform output -raw joke_vm_public_ip 2>/dev/null || echo "")
    SUBMIT_VM_IP=$(terraform output -raw submit_vm_public_ip 2>/dev/null || echo "")
    MODERATE_VM_IP=$(terraform output -raw moderate_vm_public_ip 2>/dev/null || echo "")
    RABBITMQ_VM_IP=$(terraform output -raw rabbitmq_vm_public_ip 2>/dev/null || echo "")
    KONG_VM_IP=$(terraform output -raw kong_vm_public_ip 2>/dev/null || echo "")
    cd "$PROJECT_ROOT"
fi

# Validate IPs
for ip in "$JOKE_VM_IP" "$SUBMIT_VM_IP" "$MODERATE_VM_IP" "$RABBITMQ_VM_IP" "$KONG_VM_IP"; do
    if [[ -z "$ip" || "$ip" == "null" ]]; then
        print_error "Could not retrieve VM IP addresses. Check deployment status."
        exit 1
    fi
done

print_success "VM IP addresses retrieved successfully"

# Function to check SSH connectivity
check_ssh() {
    local ip=$1
    local service=$2
    print_status "Checking SSH connectivity to $service VM ($ip)..."
    if timeout 10 ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no azureuser@$ip "echo 'SSH OK'" >/dev/null 2>&1; then
        print_success "SSH connectivity to $service VM confirmed"
        return 0
    else
        print_error "Cannot connect to $service VM via SSH"
        return 1
    fi
}

# Check SSH connectivity to all VMs
print_status "Verifying SSH connectivity to all VMs..."
check_ssh "$JOKE_VM_IP" "joke" || exit 1
check_ssh "$SUBMIT_VM_IP" "submit" || exit 1
check_ssh "$MODERATE_VM_IP" "moderate" || exit 1
check_ssh "$RABBITMQ_VM_IP" "rabbitmq" || exit 1
check_ssh "$KONG_VM_IP" "kong" || exit 1

# Build Docker images if requested
if [[ "$BUILD_IMAGES" == "true" ]]; then
    print_status "Building Docker images..."
    
    # Build joke service images
    print_status "Building joke service..."
    docker build -t joke-service:latest "$PROJECT_ROOT/joke-vm/joke"
    docker build -t etl-service:latest "$PROJECT_ROOT/joke-vm/etl"
    
    # Build submit service image
    print_status "Building submit service..."
    docker build -t submit-service:latest "$PROJECT_ROOT/submit-vm/submit"
    
    # Build moderate service image
    print_status "Building moderate service..."
    docker build -t moderate-service:latest "$PROJECT_ROOT/moderate-vm/moderate"
    
    print_success "All Docker images built successfully"
else
    print_warning "Skipping Docker image building"
fi

# Function to deploy to a VM
deploy_to_vm() {
    local vm_ip=$1
    local service_name=$2
    local vm_dir=$3
    local systemd_service=$4
    
    print_status "Deploying to $service_name VM ($vm_ip)..."
    
    # Copy application files
    print_status "Copying application files to $service_name VM..."
    ssh -o StrictHostKeyChecking=no azureuser@$vm_ip "sudo rm -rf /tmp/${vm_dir} && mkdir -p /tmp"
    scp -r -o StrictHostKeyChecking=no "$PROJECT_ROOT/$vm_dir" azureuser@$vm_ip:/tmp/
    
    # Deploy on remote VM
    ssh -o StrictHostKeyChecking=no azureuser@$vm_ip << EOF
        set -e
        echo "Setting up application directory..."
        sudo rm -rf /app/microservices
        sudo mkdir -p /app/microservices
        sudo cp -r /tmp/$vm_dir /app/microservices/
        sudo chown -R deploy:deploy /app/microservices
        
        echo "Restarting $systemd_service service..."
        if [[ "$FORCE_DEPLOY" == "true" ]]; then
            sudo systemctl stop $systemd_service || true
        fi
        sudo systemctl restart $systemd_service || true
        
        echo "Waiting for service to start..."
        sleep 15
        
        echo "Checking service status..."
        sudo systemctl status $systemd_service --no-pager || echo "Service may still be starting..."
EOF
    
    print_success "$service_name deployment completed"
}

# Deploy to each VM
print_status "Starting deployment to all VMs..."

# Deploy joke VM (includes both joke and ETL services)
deploy_to_vm "$JOKE_VM_IP" "joke" "joke-vm" "joke-service"

# Deploy submit VM
deploy_to_vm "$SUBMIT_VM_IP" "submit" "submit-vm" "submit-service"

# Deploy moderate VM
deploy_to_vm "$MODERATE_VM_IP" "moderate" "moderate-vm" "moderate-service"

# Deploy rabbitmq VM
deploy_to_vm "$RABBITMQ_VM_IP" "rabbitmq" "rabbitmq-vm" "rabbitmq-service"

# Deploy kong VM
deploy_to_vm "$KONG_VM_IP" "kong" "kong-vm" "kong-service"

print_success "All applications deployed successfully!"

# Health checks
if [[ "$HEALTH_CHECK" == "true" ]]; then
    print_status "Performing health checks..."
    sleep 30  # Give services time to fully start
    
    # Function to perform health check
    health_check() {
        local url=$1
        local service=$2
        local timeout=30
        
        print_status "Health checking $service at $url..."
        if timeout $timeout curl -sf "$url" >/dev/null 2>&1; then
            print_success "$service health check passed"
            return 0
        else
            print_warning "$service health check failed or service not ready yet"
            return 1
        fi
    }
    
    # Health check all services
    health_check "http://$JOKE_VM_IP:4000" "Joke Service"
    health_check "http://$SUBMIT_VM_IP:4200" "Submit Service"
    health_check "http://$MODERATE_VM_IP:4100" "Moderate Service"
    health_check "http://$RABBITMQ_VM_IP:15672" "RabbitMQ Management"
    health_check "http://$KONG_VM_IP:8001" "Kong Admin API"
    
    # Try a functional test on joke service
    print_status "Testing joke service functionality..."
    if curl -sf "http://$JOKE_VM_IP:4000/api/jokes/random" >/dev/null 2>&1; then
        print_success "Joke service functional test passed"
    else
        print_warning "Joke service functional test failed - service may still be initializing"
    fi
else
    print_warning "Skipping health checks"
fi

echo
print_success "=== APPLICATION DEPLOYMENT SUMMARY ==="
echo -e "${BLUE}Joke Service:${NC} http://$JOKE_VM_IP:4000"
echo -e "${BLUE}  - Joke API:${NC} http://$JOKE_VM_IP:4000/api/jokes"
echo -e "${BLUE}  - ETL Service:${NC} http://$JOKE_VM_IP:4001"
echo -e "${BLUE}Submit Service:${NC} http://$SUBMIT_VM_IP:4200"
echo -e "${BLUE}Moderate Service:${NC} http://$MODERATE_VM_IP:4100"
echo -e "${BLUE}RabbitMQ Management:${NC} http://$RABBITMQ_VM_IP:15672"
echo -e "${BLUE}Kong Gateway:${NC} http://$KONG_VM_IP:8000"
echo -e "${BLUE}Kong Admin:${NC} http://$KONG_VM_IP:8001"
echo

print_success "Application deployment completed successfully!"
print_status "You can now:"
echo "  1. Test the APIs using the provided URLs"
echo "  2. Access RabbitMQ Management UI for message monitoring"
echo "  3. Use Kong Gateway for API management"
echo "  4. Switch database types using scripts/switch-database.sh"
echo
print_status "To monitor services: scripts/health-check.sh"