#!/bin/bash

# Health Check Script
# This script performs comprehensive health checks on all deployed services

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

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

Perform health checks on all deployed services

OPTIONS:
    -v, --verbose          Show detailed output
    -q, --quiet           Show only summary
    -t, --timeout SECONDS Set timeout for health checks (default: 10)
    -f, --functional      Run functional tests in addition to health checks
    -h, --help            Show this help message

EXAMPLES:
    # Basic health check
    $0

    # Verbose health check with functional tests
    $0 --verbose --functional

    # Quick health check with custom timeout
    $0 --timeout 5

EOF
}

# Default options
VERBOSE="false"
QUIET="false"
TIMEOUT=10
FUNCTIONAL_TESTS="false"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            VERBOSE="true"
            shift
            ;;
        -q|--quiet)
            QUIET="true"
            shift
            ;;
        -t|--timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        -f|--functional)
            FUNCTIONAL_TESTS="true"
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
    DB_TYPE=$(jq -r '.database_type // "mongo"' "$PROJECT_ROOT/deployment-info.json")
else
    print_error "jq is required for parsing deployment info. Please install jq."
    exit 1
fi

# Validate IPs
for ip in "$JOKE_VM_IP" "$SUBMIT_VM_IP" "$MODERATE_VM_IP" "$RABBITMQ_VM_IP" "$KONG_VM_IP"; do
    if [[ -z "$ip" || "$ip" == "null" ]]; then
        print_error "Could not retrieve VM IP addresses from deployment info."
        exit 1
    fi
done

if [[ "$QUIET" != "true" ]]; then
    print_status "Starting health checks for all services..."
    print_status "Database type: $DB_TYPE"
    echo
fi

# Health check counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

# Function to perform HTTP health check
http_health_check() {
    local url=$1
    local service_name=$2
    local expected_code=${3:-200}
    
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    if [[ "$VERBOSE" == "true" ]]; then
        print_status "Testing $service_name at $url"
    fi
    
    local response_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time $TIMEOUT "$url" 2>/dev/null || echo "000")
    
    if [[ "$response_code" == "$expected_code" ]]; then
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        if [[ "$QUIET" != "true" ]]; then
            print_success "$service_name: OK (HTTP $response_code)"
        fi
        return 0
    else
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        if [[ "$QUIET" != "true" ]]; then
            print_error "$service_name: FAILED (HTTP $response_code)"
        fi
        return 1
    fi
}

# Function to perform TCP connectivity check
tcp_connectivity_check() {
    local host=$1
    local port=$2
    local service_name=$3
    
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    if [[ "$VERBOSE" == "true" ]]; then
        print_status "Testing TCP connectivity to $service_name at $host:$port"
    fi
    
    if timeout $TIMEOUT bash -c "</dev/tcp/$host/$port" 2>/dev/null; then
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        if [[ "$QUIET" != "true" ]]; then
            print_success "$service_name TCP: OK"
        fi
        return 0
    else
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        if [[ "$QUIET" != "true" ]]; then
            print_error "$service_name TCP: FAILED"
        fi
        return 1
    fi
}

# Function to perform SSH connectivity check
ssh_connectivity_check() {
    local host=$1
    local service_name=$2
    
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    if [[ "$VERBOSE" == "true" ]]; then
        print_status "Testing SSH connectivity to $service_name at $host"
    fi
    
    if timeout $TIMEOUT ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no azureuser@$host "echo 'SSH OK'" >/dev/null 2>&1; then
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        if [[ "$QUIET" != "true" ]]; then
            print_success "$service_name SSH: OK"
        fi
        return 0
    else
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        if [[ "$QUIET" != "true" ]]; then
            print_error "$service_name SSH: FAILED"
        fi
        return 1
    fi
}

# Perform health checks
if [[ "$QUIET" != "true" ]]; then
    echo "=== HTTP HEALTH CHECKS ==="
fi

# Joke Service health checks
http_health_check "http://$JOKE_VM_IP:4000/health" "Joke Service Health"
http_health_check "http://$JOKE_VM_IP:4001/health" "ETL Service Health"

# Submit Service health check
http_health_check "http://$SUBMIT_VM_IP:4200/health" "Submit Service Health"

# Moderate Service health check
http_health_check "http://$MODERATE_VM_IP:4100/health" "Moderate Service Health"

# RabbitMQ Management health check
http_health_check "http://$RABBITMQ_VM_IP:15672" "RabbitMQ Management"

# Kong health checks
http_health_check "http://$KONG_VM_IP:8001" "Kong Admin API"

if [[ "$QUIET" != "true" ]]; then
    echo
    echo "=== TCP CONNECTIVITY CHECKS ==="
fi

# TCP connectivity checks
tcp_connectivity_check "$JOKE_VM_IP" "4000" "Joke Service"
tcp_connectivity_check "$JOKE_VM_IP" "4001" "ETL Service"
tcp_connectivity_check "$SUBMIT_VM_IP" "4200" "Submit Service"
tcp_connectivity_check "$MODERATE_VM_IP" "4100" "Moderate Service"
tcp_connectivity_check "$RABBITMQ_VM_IP" "5672" "RabbitMQ AMQP"
tcp_connectivity_check "$RABBITMQ_VM_IP" "15672" "RabbitMQ Management"
tcp_connectivity_check "$KONG_VM_IP" "8000" "Kong Gateway"
tcp_connectivity_check "$KONG_VM_IP" "8001" "Kong Admin"

if [[ "$QUIET" != "true" ]]; then
    echo
    echo "=== SSH CONNECTIVITY CHECKS ==="
fi

# SSH connectivity checks
ssh_connectivity_check "$JOKE_VM_IP" "Joke VM"
ssh_connectivity_check "$SUBMIT_VM_IP" "Submit VM"
ssh_connectivity_check "$MODERATE_VM_IP" "Moderate VM"
ssh_connectivity_check "$RABBITMQ_VM_IP" "RabbitMQ VM"
ssh_connectivity_check "$KONG_VM_IP" "Kong VM"

# Functional tests
if [[ "$FUNCTIONAL_TESTS" == "true" ]]; then
    if [[ "$QUIET" != "true" ]]; then
        echo
        echo "=== FUNCTIONAL TESTS ==="
    fi
    
    # Test joke API functionality
    if [[ "$VERBOSE" == "true" ]]; then
        print_status "Testing joke API functionality"
    fi
    
    JOKE_RESPONSE=$(curl -s --max-time $TIMEOUT "http://$JOKE_VM_IP:4000/api/jokes/random" 2>/dev/null || echo "")
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    if [[ -n "$JOKE_RESPONSE" && "$JOKE_RESPONSE" != "null" && "$JOKE_RESPONSE" != "FAILED" ]]; then
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        if [[ "$QUIET" != "true" ]]; then
            print_success "Joke API: Functional (serving jokes from $DB_TYPE)"
        fi
        if [[ "$VERBOSE" == "true" ]]; then
            echo "Sample joke response: $JOKE_RESPONSE"
        fi
    else
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        if [[ "$QUIET" != "true" ]]; then
            print_warning "Joke API: Not serving jokes (database may be empty)"
        fi
    fi
    
    # Test API documentation
    if [[ "$VERBOSE" == "true" ]]; then
        print_status "Testing API documentation"
    fi
    
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    if curl -s --max-time $TIMEOUT "http://$JOKE_VM_IP:4000/api-docs" >/dev/null 2>&1; then
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        if [[ "$QUIET" != "true" ]]; then
            print_success "API Documentation: Available"
        fi
    else
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        if [[ "$QUIET" != "true" ]]; then
            print_error "API Documentation: Not available"
        fi
    fi
fi

# Summary
echo
if [[ "$QUIET" == "true" ]]; then
    echo "=== HEALTH CHECK SUMMARY ==="
else
    print_status "=== HEALTH CHECK SUMMARY ==="
fi

echo -e "${BLUE}Total Checks:${NC} $TOTAL_CHECKS"
echo -e "${GREEN}Passed:${NC} $PASSED_CHECKS"
echo -e "${RED}Failed:${NC} $FAILED_CHECKS"

if [[ $FAILED_CHECKS -eq 0 ]]; then
    print_success "All health checks passed! 🎉"
    echo
    echo "=== SERVICE ENDPOINTS ==="
    echo -e "${BLUE}Joke Service:${NC} http://$JOKE_VM_IP:4000"
    echo -e "${BLUE}ETL Service:${NC} http://$JOKE_VM_IP:4001"
    echo -e "${BLUE}Submit Service:${NC} http://$SUBMIT_VM_IP:4200"
    echo -e "${BLUE}Moderate Service:${NC} http://$MODERATE_VM_IP:4100"
    echo -e "${BLUE}RabbitMQ Management:${NC} http://$RABBITMQ_VM_IP:15672"
    echo -e "${BLUE}Kong Gateway:${NC} http://$KONG_VM_IP:8000"
    echo -e "${BLUE}Kong Admin:${NC} http://$KONG_VM_IP:8001"
    echo -e "${BLUE}Current Database:${NC} $DB_TYPE"
    
    exit 0
elif [[ $FAILED_CHECKS -lt 3 ]]; then
    print_warning "Some health checks failed. Services may still be starting."
    echo
    print_status "Troubleshooting tips:"
    echo "  1. Wait a few minutes for services to fully initialize"
    echo "  2. Check individual service logs on VMs"
    echo "  3. Verify network connectivity and security group rules"
    echo "  4. Restart failed services if necessary"
    
    exit 1
else
    print_error "Multiple health checks failed. Please investigate."
    echo
    print_status "Recommended actions:"
    echo "  1. Check VM status in Azure portal"
    echo "  2. Verify cloud-init completion on VMs"
    echo "  3. Check Docker service status on each VM"
    echo "  4. Review application logs for errors"
    echo "  5. Consider redeploying infrastructure"
    
    exit 2
fi