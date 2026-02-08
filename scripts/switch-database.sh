#!/bin/bash

# Database Switching Script
# This script switches between MySQL and MongoDB for the joke service

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"

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
Usage: $0 <mysql|mongo> [OPTIONS]

Switch database type for the joke service

ARGUMENTS:
    DATABASE_TYPE    Database type to switch to (mysql or mongo)

OPTIONS:
    -f, --force      Force switch even if target database is already active
    -s, --skip-test  Skip functional testing after switch
    -h, --help       Show this help message

EXAMPLES:
    # Switch to MySQL
    $0 mysql

    # Switch to MongoDB
    $0 mongo

    # Force switch to MySQL without testing
    $0 mysql --force --skip-test

PREREQUISITES:
    - Infrastructure must be deployed
    - SSH access to joke VM

EOF
}

# Check arguments
if [[ $# -eq 0 ]]; then
    print_error "Database type argument is required"
    usage
    exit 1
fi

DB_TYPE="$1"
shift

# Default options
FORCE_SWITCH="false"
SKIP_TEST="false"

# Parse remaining arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--force)
            FORCE_SWITCH="true"
            shift
            ;;
        -s|--skip-test)
            SKIP_TEST="true"
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
    usage
    exit 1
fi

print_status "Switching to $DB_TYPE database..."

# Check if infrastructure is deployed
if [[ ! -f "$PROJECT_ROOT/deployment-info.json" ]]; then
    print_error "No deployment info found. Run deploy-infrastructure.sh first."
    exit 1
fi

# Get joke VM IP
if command -v jq &> /dev/null; then
    JOKE_VM_IP=$(jq -r '.services.joke_vm.public_ip' "$PROJECT_ROOT/deployment-info.json")
    CURRENT_DB_TYPE=$(jq -r '.database_type // "mongo"' "$PROJECT_ROOT/deployment-info.json")
else
    # Fallback: read from Terraform
    cd "$TERRAFORM_DIR"
    JOKE_VM_IP=$(terraform output -raw joke_vm_public_ip 2>/dev/null || echo "")
    CURRENT_DB_TYPE=$(terraform output -raw database_type 2>/dev/null || echo "mongo")
    cd "$PROJECT_ROOT"
fi

if [[ -z "$JOKE_VM_IP" || "$JOKE_VM_IP" == "null" ]]; then
    print_error "Could not retrieve joke VM IP address. Check deployment status."
    exit 1
fi

print_status "Joke VM IP: $JOKE_VM_IP"
print_status "Current database type: $CURRENT_DB_TYPE"
print_status "Target database type: $DB_TYPE"

# Check if already using target database
if [[ "$CURRENT_DB_TYPE" == "$DB_TYPE" && "$FORCE_SWITCH" != "true" ]]; then
    print_warning "Database is already set to $DB_TYPE"
    print_status "Use --force flag to restart services anyway"
    exit 0
fi

# Check SSH connectivity
print_status "Checking SSH connectivity to joke VM..."
if ! timeout 10 ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no azureuser@$JOKE_VM_IP "echo 'SSH OK'" >/dev/null 2>&1; then
    print_error "Cannot connect to joke VM via SSH"
    exit 1
fi
print_success "SSH connectivity confirmed"

# Get current service status before switch
print_status "Checking current service status..."
ssh -o StrictHostKeyChecking=no azureuser@$JOKE_VM_IP << 'EOF'
echo "=== Current Docker containers ==="
sudo docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo
EOF

# Perform database switch
print_status "Performing database switch on joke VM..."
ssh -o StrictHostKeyChecking=no azureuser@$JOKE_VM_IP << EOF
set -e

echo "🔄 Switching database to $DB_TYPE..."

# Check if switch script exists
if [[ ! -f "/app/switch-database.sh" ]]; then
    echo "❌ Database switch script not found on VM"
    echo "This might be a deployment issue. Please redeploy the infrastructure."
    exit 1
fi

# Update environment file
echo "📝 Updating environment configuration..."
if [[ -f "/app/.env" ]]; then
    sudo sed -i "s/DB_TYPE=.*/DB_TYPE=$DB_TYPE/" /app/.env
    echo "Environment file updated"
else
    echo "⚠️  Environment file not found, creating new one..."
    sudo bash -c 'echo "DB_TYPE=$DB_TYPE" > /app/.env'
    sudo bash -c 'echo "RMQ_HOST=10.0.2.7" >> /app/.env'
    sudo chown deploy:deploy /app/.env
fi

# Change to application directory
cd /app/microservices/joke-vm || {
    echo "❌ Application directory not found. Please deploy applications first."
    exit 1
}

# Stop current services
echo "⏸️  Stopping current services..."
sudo docker-compose down --remove-orphans || echo "No containers to stop"

# Remove unused containers and networks
sudo docker system prune -f --volumes || true

# Start with new database type
echo "🚀 Starting services with $DB_TYPE database..."
sudo docker-compose --profile $DB_TYPE up -d

# Wait for services to start
echo "⏳ Waiting for services to initialize..."
sleep 45

# Check container status
echo "📊 Container status after switch:"
sudo docker-compose ps

# Basic health check
echo "🏥 Performing basic health checks..."
if curl -sf http://localhost:4000/health >/dev/null 2>&1; then
    echo "✅ Joke service health check passed"
else
    echo "⚠️  Joke service health check failed - service may still be starting"
fi

if curl -sf http://localhost:4001/health >/dev/null 2>&1; then
    echo "✅ ETL service health check passed"
else
    echo "⚠️  ETL service health check failed - service may still be starting"
fi

echo "✅ Database switch to $DB_TYPE completed!"
EOF

if [[ $? -eq 0 ]]; then
    print_success "Database switch completed successfully"
else
    print_error "Database switch failed"
    exit 1
fi

# Wait a bit more for services to stabilize
print_status "Waiting for services to stabilize..."
sleep 30

# Update deployment info file
if [[ -f "$PROJECT_ROOT/deployment-info.json" ]] && command -v jq &> /dev/null; then
    print_status "Updating deployment info..."
    jq --arg db_type "$DB_TYPE" '.database_type = $db_type' "$PROJECT_ROOT/deployment-info.json" > /tmp/deployment-info.json.tmp
    mv /tmp/deployment-info.json.tmp "$PROJECT_ROOT/deployment-info.json"
    print_success "Deployment info updated"
fi

# Functional testing
if [[ "$SKIP_TEST" != "true" ]]; then
    print_status "Performing functional tests..."
    
    # Test joke service API
    print_status "Testing joke service API..."
    if curl -sf "http://$JOKE_VM_IP:4000/api/jokes/random" >/dev/null 2>&1; then
        print_success "Joke API functional test passed"
        
        # Get a sample joke to verify database connectivity
        JOKE_RESPONSE=$(curl -s "http://$JOKE_VM_IP:4000/api/jokes/random" 2>/dev/null || echo "")
        if [[ -n "$JOKE_RESPONSE" && "$JOKE_RESPONSE" != "null" ]]; then
            print_success "Database connectivity confirmed - jokes are being served"
        else
            print_warning "Database may be empty or still initializing"
        fi
    else
        print_warning "Joke API functional test failed"
        print_status "Service may still be initializing. Try again in a few minutes."
    fi
    
    # Test health endpoints
    print_status "Testing health endpoints..."
    if curl -sf "http://$JOKE_VM_IP:4000/health" >/dev/null 2>&1; then
        print_success "Joke service health endpoint OK"
    else
        print_warning "Joke service health endpoint failed"
    fi
    
    if curl -sf "http://$JOKE_VM_IP:4001/health" >/dev/null 2>&1; then
        print_success "ETL service health endpoint OK"
    else
        print_warning "ETL service health endpoint failed"
    fi
else
    print_warning "Skipping functional tests"
fi

# Display service information
echo
print_success "=== DATABASE SWITCH SUMMARY ==="
echo -e "${BLUE}Previous Database:${NC} $CURRENT_DB_TYPE"
echo -e "${BLUE}New Database:${NC} $DB_TYPE"
echo -e "${BLUE}Joke Service URL:${NC} http://$JOKE_VM_IP:4000"
echo -e "${BLUE}ETL Service URL:${NC} http://$JOKE_VM_IP:4001"
echo -e "${BLUE}Health Check URL:${NC} http://$JOKE_VM_IP:4000/health"
echo -e "${BLUE}API Documentation:${NC} http://$JOKE_VM_IP:4000/api-docs"
echo

print_success "Database switch completed successfully!"
echo
print_status "Next steps:"
echo "  1. Test the application thoroughly with the new database"
echo "  2. Monitor service logs for any issues"
echo "  3. Verify data integrity if migrating between databases"
echo "  4. Update any dependent services if necessary"
echo
print_status "To check service status: ssh azureuser@$JOKE_VM_IP 'sudo docker-compose -f /app/microservices/joke-vm/docker-compose.yml ps'"