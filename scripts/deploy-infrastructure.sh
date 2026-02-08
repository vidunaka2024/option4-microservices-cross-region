#!/bin/bash

# Infrastructure Deployment Script
# This script automates the deployment of the entire microservices infrastructure

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"

# Default values
DB_TYPE="mongo"
ENVIRONMENT="dev"
LOCATION="East US"
SKIP_PLAN="false"
AUTO_APPROVE="false"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
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

# Function to show usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy microservices infrastructure to Azure using Terraform

OPTIONS:
    -d, --db-type DB_TYPE       Database type (mysql or mongo) [default: mongo]
    -e, --environment ENV       Environment (dev, staging, prod) [default: dev]
    -l, --location LOCATION     Azure location [default: "East US"]
    -s, --skip-plan            Skip terraform plan step
    -y, --auto-approve         Auto approve terraform apply
    -h, --help                 Show this help message

EXAMPLES:
    # Deploy with MongoDB (default)
    $0

    # Deploy with MySQL database
    $0 --db-type mysql

    # Deploy to staging environment with auto-approve
    $0 --environment staging --auto-approve

    # Deploy with custom location
    $0 --location "West US 2" --db-type mysql

PREREQUISITES:
    - Azure CLI logged in (az login)
    - Terraform installed (>= 1.0)
    - SSH key pair generated (~/.ssh/id_rsa and ~/.ssh/id_rsa.pub)
    - Required environment variables set or Azure CLI configured

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--db-type)
            DB_TYPE="$2"
            shift 2
            ;;
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -l|--location)
            LOCATION="$2"
            shift 2
            ;;
        -s|--skip-plan)
            SKIP_PLAN="true"
            shift
            ;;
        -y|--auto-approve)
            AUTO_APPROVE="true"
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

# Validate database type
if [[ "$DB_TYPE" != "mysql" && "$DB_TYPE" != "mongo" ]]; then
    print_error "Database type must be 'mysql' or 'mongo'"
    exit 1
fi

# Validate environment
if [[ "$ENVIRONMENT" != "dev" && "$ENVIRONMENT" != "staging" && "$ENVIRONMENT" != "prod" ]]; then
    print_error "Environment must be 'dev', 'staging', or 'prod'"
    exit 1
fi

print_status "Starting infrastructure deployment..."
print_status "Database Type: $DB_TYPE"
print_status "Environment: $ENVIRONMENT"
print_status "Location: $LOCATION"
echo

# Check prerequisites
print_status "Checking prerequisites..."

# Check if Azure CLI is installed and logged in
if ! command -v az &> /dev/null; then
    print_error "Azure CLI is not installed. Please install it first."
    exit 1
fi

if ! az account show &> /dev/null; then
    print_error "Not logged into Azure. Please run 'az login' first."
    exit 1
fi

# Check if Terraform is installed
if ! command -v terraform &> /dev/null; then
    print_error "Terraform is not installed. Please install it first."
    exit 1
fi

# Check if SSH key exists
if [[ ! -f ~/.ssh/id_rsa.pub ]]; then
    print_warning "SSH public key not found at ~/.ssh/id_rsa.pub"
    read -p "Generate SSH key pair? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
        print_success "SSH key pair generated"
    else
        print_error "SSH key is required for VM access"
        exit 1
    fi
fi

print_success "Prerequisites check passed"
echo

# Change to Terraform directory
cd "$TERRAFORM_DIR"

# Initialize Terraform
print_status "Initializing Terraform..."
if ! terraform init; then
    print_error "Terraform initialization failed"
    exit 1
fi
print_success "Terraform initialized"

# Validate Terraform configuration
print_status "Validating Terraform configuration..."
if ! terraform validate; then
    print_error "Terraform validation failed"
    exit 1
fi
print_success "Terraform configuration is valid"

# Run Terraform plan
if [[ "$SKIP_PLAN" != "true" ]]; then
    print_status "Creating Terraform plan..."
    if ! terraform plan \
        -var="db_type=$DB_TYPE" \
        -var="environment=$ENVIRONMENT" \
        -var="location=$LOCATION" \
        -out=tfplan; then
        print_error "Terraform plan failed"
        exit 1
    fi
    print_success "Terraform plan created"
    
    if [[ "$AUTO_APPROVE" != "true" ]]; then
        echo
        read -p "Do you want to apply this plan? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_warning "Deployment cancelled"
            exit 0
        fi
    fi
else
    print_warning "Skipping Terraform plan"
fi

# Apply Terraform configuration
print_status "Applying Terraform configuration..."
if [[ "$SKIP_PLAN" == "true" ]]; then
    terraform_apply_cmd="terraform apply"
    if [[ "$AUTO_APPROVE" == "true" ]]; then
        terraform_apply_cmd="$terraform_apply_cmd -auto-approve"
    fi
    terraform_apply_cmd="$terraform_apply_cmd -var=\"db_type=$DB_TYPE\" -var=\"environment=$ENVIRONMENT\" -var=\"location=$LOCATION\""
else
    terraform_apply_cmd="terraform apply"
    if [[ "$AUTO_APPROVE" == "true" ]]; then
        terraform_apply_cmd="$terraform_apply_cmd -auto-approve"
    fi
    terraform_apply_cmd="$terraform_apply_cmd tfplan"
fi

if ! eval $terraform_apply_cmd; then
    print_error "Terraform apply failed"
    exit 1
fi

print_success "Infrastructure deployed successfully!"
echo

# Get outputs
print_status "Retrieving infrastructure information..."

JOKE_VM_IP=$(terraform output -raw joke_vm_public_ip 2>/dev/null || echo "")
SUBMIT_VM_IP=$(terraform output -raw submit_vm_public_ip 2>/dev/null || echo "")
MODERATE_VM_IP=$(terraform output -raw moderate_vm_public_ip 2>/dev/null || echo "")
RABBITMQ_VM_IP=$(terraform output -raw rabbitmq_vm_public_ip 2>/dev/null || echo "")
KONG_VM_IP=$(terraform output -raw kong_vm_public_ip 2>/dev/null || echo "")
RESOURCE_GROUP=$(terraform output -raw resource_group_name 2>/dev/null || echo "")

# Display deployment summary
echo
print_success "=== DEPLOYMENT SUMMARY ==="
echo -e "${BLUE}Resource Group:${NC} $RESOURCE_GROUP"
echo -e "${BLUE}Environment:${NC} $ENVIRONMENT"
echo -e "${BLUE}Database Type:${NC} $DB_TYPE"
echo -e "${BLUE}Location:${NC} $LOCATION"
echo
echo -e "${GREEN}=== SERVICE ENDPOINTS ===${NC}"
echo -e "${BLUE}Joke Service:${NC} http://$JOKE_VM_IP:4000"
echo -e "${BLUE}Submit Service:${NC} http://$SUBMIT_VM_IP:4200"
echo -e "${BLUE}Moderate Service:${NC} http://$MODERATE_VM_IP:4100"
echo -e "${BLUE}RabbitMQ Management:${NC} http://$RABBITMQ_VM_IP:15672"
echo -e "${BLUE}Kong Gateway:${NC} http://$KONG_VM_IP:8000"
echo
echo -e "${GREEN}=== SSH ACCESS ===${NC}"
echo -e "${BLUE}Joke VM:${NC} ssh azureuser@$JOKE_VM_IP"
echo -e "${BLUE}Submit VM:${NC} ssh azureuser@$SUBMIT_VM_IP"
echo -e "${BLUE}Moderate VM:${NC} ssh azureuser@$MODERATE_VM_IP"
echo -e "${BLUE}RabbitMQ VM:${NC} ssh azureuser@$RABBITMQ_VM_IP"
echo -e "${BLUE}Kong VM:${NC} ssh azureuser@$KONG_VM_IP"
echo

# Save deployment info to file
DEPLOYMENT_INFO="$PROJECT_ROOT/deployment-info.json"
cat > "$DEPLOYMENT_INFO" << EOF
{
  "deployment_time": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "environment": "$ENVIRONMENT",
  "database_type": "$DB_TYPE",
  "location": "$LOCATION",
  "resource_group": "$RESOURCE_GROUP",
  "services": {
    "joke_vm": {
      "public_ip": "$JOKE_VM_IP",
      "url": "http://$JOKE_VM_IP:4000",
      "ssh": "ssh azureuser@$JOKE_VM_IP"
    },
    "submit_vm": {
      "public_ip": "$SUBMIT_VM_IP",
      "url": "http://$SUBMIT_VM_IP:4200",
      "ssh": "ssh azureuser@$SUBMIT_VM_IP"
    },
    "moderate_vm": {
      "public_ip": "$MODERATE_VM_IP",
      "url": "http://$MODERATE_VM_IP:4100",
      "ssh": "ssh azureuser@$MODERATE_VM_IP"
    },
    "rabbitmq_vm": {
      "public_ip": "$RABBITMQ_VM_IP",
      "management_url": "http://$RABBITMQ_VM_IP:15672",
      "ssh": "ssh azureuser@$RABBITMQ_VM_IP"
    },
    "kong_vm": {
      "public_ip": "$KONG_VM_IP",
      "url": "http://$KONG_VM_IP:8000",
      "ssh": "ssh azureuser@$KONG_VM_IP"
    }
  }
}
EOF

print_success "Deployment information saved to $DEPLOYMENT_INFO"
echo

# Wait for VMs to be ready
print_status "Waiting for VMs to complete initialization (this may take several minutes)..."
sleep 120

# Basic health check
print_status "Performing basic connectivity test..."
for ip in "$JOKE_VM_IP" "$SUBMIT_VM_IP" "$MODERATE_VM_IP" "$RABBITMQ_VM_IP" "$KONG_VM_IP"; do
    if timeout 10 bash -c "</dev/tcp/$ip/22"; then
        print_success "SSH port accessible on $ip"
    else
        print_warning "SSH port not yet accessible on $ip"
    fi
done

echo
print_success "Infrastructure deployment completed!"
print_status "Next steps:"
echo "  1. Wait for cloud-init to complete on all VMs (5-10 minutes)"
echo "  2. Use the provided SSH commands to access VMs"
echo "  3. Deploy application code using CI/CD pipeline or manual deployment"
echo "  4. Use scripts/switch-database.sh to change database type if needed"
echo
print_status "For application deployment, see: scripts/deploy-apps.sh"