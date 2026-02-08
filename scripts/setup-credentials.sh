#!/bin/bash

# Credential Setup Script
# This script sets up all required credentials for the Option 4 deployment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️ $1${NC}"
}

# Step 1: Generate SSH Keys
setup_ssh_keys() {
    print_header "Setting Up SSH Keys"
    
    SSH_KEY_PATH="$HOME/.ssh/microservices_key"
    
    if [[ -f "$SSH_KEY_PATH" ]]; then
        print_warning "SSH key already exists at $SSH_KEY_PATH"
        read -p "Regenerate SSH key? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Using existing SSH key"
        else
            rm -f "$SSH_KEY_PATH" "$SSH_KEY_PATH.pub"
        fi
    fi
    
    if [[ ! -f "$SSH_KEY_PATH" ]]; then
        print_info "Generating new SSH key pair..."
        ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N "" -C "microservices-deployment"
        print_success "SSH key generated at $SSH_KEY_PATH"
    fi
    
    # Copy public key to terraform directory
    cp "$SSH_KEY_PATH.pub" "$PROJECT_ROOT/terraform/ssh-key.pub"
    print_success "Public key copied to terraform/ssh-key.pub"
    
    # Display public key for manual copying if needed
    print_info "SSH Public Key (for manual setup if needed):"
    cat "$SSH_KEY_PATH.pub"
    echo
}

# Step 2: Setup Azure Service Principal
setup_azure_credentials() {
    print_header "Setting Up Azure Credentials"
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI not found. Please install it first:"
        print_info "curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash"
        return 1
    fi
    
    # Check if logged in
    if ! az account show &> /dev/null; then
        print_warning "Not logged into Azure. Please run 'az login' first."
        print_info "Running 'az login' now..."
        az login
    fi
    
    local subscription_id
    subscription_id=$(az account show --query id -o tsv)
    
    print_info "Current subscription: $subscription_id"
    
    # Create service principal
    print_info "Creating service principal for automation..."
    local sp_output
    sp_output=$(az ad sp create-for-rbac --name "microservices-sp-$(date +%s)" --role contributor --scopes "/subscriptions/$subscription_id" --output json)
    
    local client_id
    local client_secret
    local tenant_id
    
    client_id=$(echo "$sp_output" | jq -r '.appId')
    client_secret=$(echo "$sp_output" | jq -r '.password')
    tenant_id=$(echo "$sp_output" | jq -r '.tenant')
    
    # Update .env file
    print_info "Updating .env file with Azure credentials..."
    
    sed -i.bak "s/ARM_CLIENT_ID=.*/ARM_CLIENT_ID=$client_id/" "$PROJECT_ROOT/.env"
    sed -i.bak "s/ARM_CLIENT_SECRET=.*/ARM_CLIENT_SECRET=$client_secret/" "$PROJECT_ROOT/.env"
    sed -i.bak "s/ARM_SUBSCRIPTION_ID=.*/ARM_SUBSCRIPTION_ID=$subscription_id/" "$PROJECT_ROOT/.env"
    sed -i.bak "s/ARM_TENANT_ID=.*/ARM_TENANT_ID=$tenant_id/" "$PROJECT_ROOT/.env"
    
    rm -f "$PROJECT_ROOT/.env.bak"
    
    print_success "Azure credentials configured in .env file"
    
    # Display credentials for GitHub Secrets
    print_warning "IMPORTANT: Add these to GitHub Repository Secrets:"
    echo "ARM_CLIENT_ID=$client_id"
    echo "ARM_CLIENT_SECRET=$client_secret"
    echo "ARM_SUBSCRIPTION_ID=$subscription_id"
    echo "ARM_TENANT_ID=$tenant_id"
    echo
}

# Step 3: Display SSH Private Key for GitHub
display_ssh_private_key() {
    print_header "SSH Private Key for GitHub Secrets"
    
    local ssh_private_key_path="$HOME/.ssh/microservices_key"
    
    if [[ -f "$ssh_private_key_path" ]]; then
        print_warning "Add this SSH private key to GitHub Secrets as 'SSH_PRIVATE_KEY':"
        echo "------- Copy everything below (including BEGIN/END lines) -------"
        cat "$ssh_private_key_path"
        echo "------- Copy everything above (including BEGIN/END lines) -------"
        echo
    else
        print_error "SSH private key not found at $ssh_private_key_path"
    fi
}

# Step 4: Auth0 Setup Instructions
auth0_setup_instructions() {
    print_header "Auth0 Setup Instructions"
    
    print_info "1. Create Auth0 Account:"
    print_info "   Go to https://auth0.com/ and create a free account"
    echo
    
    print_info "2. Create Application:"
    print_info "   - Applications → Create Application"
    print_info "   - Name: 'Joke Moderation Service'"
    print_info "   - Type: 'Regular Web Applications'"
    print_info "   - Technology: 'Node.js'"
    echo
    
    print_info "3. Configure Application URLs:"
    print_info "   Allowed Callback URLs:"
    print_info "   http://localhost:3100/callback"
    print_info "   https://your-kong-gateway.com/moderate/callback"
    echo
    print_info "   Allowed Logout URLs:"
    print_info "   http://localhost:3100/"
    print_info "   https://your-kong-gateway.com/moderate/"
    echo
    
    print_info "4. Copy Credentials:"
    print_info "   Update moderate-vm/moderate/.env with:"
    print_info "   - AUTH0_CLIENT_ID (from Basic Information)"
    print_info "   - AUTH0_CLIENT_SECRET (from Basic Information)"
    print_info "   - AUTH0_ISSUER_BASE_URL (https://your-tenant.auth0.com)"
    echo
}

# Step 5: GitHub Secrets Summary
github_secrets_summary() {
    print_header "GitHub Repository Secrets Summary"
    
    print_info "Add these secrets to your GitHub repository:"
    print_info "Repository → Settings → Secrets and variables → Actions → New repository secret"
    echo
    
    print_warning "Required GitHub Secrets:"
    echo "ARM_CLIENT_ID=<from Azure setup above>"
    echo "ARM_CLIENT_SECRET=<from Azure setup above>"
    echo "ARM_SUBSCRIPTION_ID=<from Azure setup above>"
    echo "ARM_TENANT_ID=<from Azure setup above>"
    echo "SSH_PRIVATE_KEY=<from SSH private key above>"
    echo
    
    print_info "Optional GitHub Secrets (for Docker registry):"
    echo "DOCKERHUB_USERNAME=<your Docker Hub username>"
    echo "DOCKERHUB_TOKEN=<your Docker Hub access token>"
    echo
}

# Step 6: Validation
validate_setup() {
    print_header "Validating Setup"
    
    local validation_errors=0
    
    # Check .env file
    if [[ -f "$PROJECT_ROOT/.env" ]]; then
        if grep -q "your_service_principal" "$PROJECT_ROOT/.env"; then
            print_error ".env file still contains placeholder values"
            validation_errors=$((validation_errors + 1))
        else
            print_success ".env file configured"
        fi
    else
        print_error ".env file not found"
        validation_errors=$((validation_errors + 1))
    fi
    
    # Check SSH keys
    if [[ -f "$HOME/.ssh/microservices_key" && -f "$PROJECT_ROOT/terraform/ssh-key.pub" ]]; then
        print_success "SSH keys configured"
    else
        print_error "SSH keys not properly configured"
        validation_errors=$((validation_errors + 1))
    fi
    
    # Check Auth0 config
    if [[ -f "$PROJECT_ROOT/moderate-vm/moderate/.env" ]]; then
        if grep -q "your_auth0_client" "$PROJECT_ROOT/moderate-vm/moderate/.env"; then
            print_warning "Auth0 configuration still contains placeholder values"
            print_info "Remember to update moderate-vm/moderate/.env with real Auth0 credentials"
        else
            print_success "Auth0 configuration file exists"
        fi
    else
        print_warning "Auth0 configuration file not found (moderate-vm/moderate/.env)"
        print_info "This will be needed for the moderate service authentication"
    fi
    
    # Check Azure login
    if az account show &> /dev/null; then
        print_success "Azure CLI authenticated"
    else
        print_error "Azure CLI not authenticated"
        validation_errors=$((validation_errors + 1))
    fi
    
    echo
    if [[ $validation_errors -eq 0 ]]; then
        print_success "🎉 Setup validation passed! Ready for deployment!"
    else
        print_warning "⚠️ Some issues found. Please resolve before deploying."
    fi
    
    return $validation_errors
}

# Main execution
main() {
    print_header "Option 4 Credential Setup - Exceptional 1st Class"
    
    setup_ssh_keys
    setup_azure_credentials
    display_ssh_private_key
    auth0_setup_instructions
    github_secrets_summary
    validate_setup
    
    print_header "Next Steps"
    print_info "1. Complete Auth0 setup using the instructions above"
    print_info "2. Add all secrets to your GitHub repository"
    print_info "3. Update Auth0 URLs after deployment"
    print_info "4. Run deployment: ./scripts/deploy-infrastructure.sh"
    echo
    print_success "Credential setup completed! 🚀"
}

main "$@"