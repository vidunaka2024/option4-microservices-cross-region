#!/bin/bash

# SSL Certificate Setup Script
# Creates and configures SSL certificates for Kong Gateway

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CERT_DIR="$PROJECT_ROOT/ssl-certificates"

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

# Create certificate directory
create_cert_directory() {
    mkdir -p "$CERT_DIR"
    print_success "Certificate directory created: $CERT_DIR"
}

# Option 1: Self-signed certificates (for development)
create_self_signed_cert() {
    print_header "Creating Self-Signed SSL Certificate"
    
    local domain="${1:-joke-gateway.local}"
    local cert_file="$CERT_DIR/gateway.crt"
    local key_file="$CERT_DIR/gateway.key"
    
    # Create certificate configuration
    cat > "$CERT_DIR/cert.conf" << EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = US
ST = State
L = City
O = Microservices Demo
OU = IT Department
CN = $domain

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = $domain
DNS.2 = *.joke-service.local
DNS.3 = localhost
IP.1 = 127.0.0.1
EOF

    # Generate private key
    openssl genrsa -out "$key_file" 2048
    print_success "Private key generated: $key_file"
    
    # Generate certificate
    openssl req -new -x509 -key "$key_file" -out "$cert_file" -days 365 \
        -config "$CERT_DIR/cert.conf" -extensions v3_req
    print_success "Certificate generated: $cert_file"
    
    # Display certificate info
    print_info "Certificate details:"
    openssl x509 -in "$cert_file" -text -noout | grep -E "(Subject:|DNS:|IP Address:)"
    
    return 0
}

# Option 2: Let's Encrypt certificates (for production)
create_letsencrypt_cert() {
    print_header "Setting Up Let's Encrypt SSL Certificate"
    
    local domain="$1"
    
    if [[ -z "$domain" ]]; then
        print_error "Domain name required for Let's Encrypt certificate"
        print_info "Usage: $0 --letsencrypt your-domain.com"
        return 1
    fi
    
    # Check if certbot is installed
    if ! command -v certbot &> /dev/null; then
        print_warning "Certbot not installed. Installing..."
        
        if command -v apt &> /dev/null; then
            sudo apt update && sudo apt install -y certbot
        elif command -v yum &> /dev/null; then
            sudo yum install -y certbot
        else
            print_error "Please install certbot manually"
            return 1
        fi
    fi
    
    # Generate certificate
    print_info "Generating Let's Encrypt certificate for $domain"
    sudo certbot certonly --standalone --agree-tos --no-eff-email \
        -d "$domain" \
        --email "admin@$domain" || {
        print_error "Let's Encrypt certificate generation failed"
        print_info "Make sure:"
        print_info "1. Domain $domain points to this server"
        print_info "2. Port 80 is accessible from internet"
        print_info "3. No other web server is running on port 80"
        return 1
    }
    
    # Copy certificates to our directory
    sudo cp "/etc/letsencrypt/live/$domain/fullchain.pem" "$CERT_DIR/gateway.crt"
    sudo cp "/etc/letsencrypt/live/$domain/privkey.pem" "$CERT_DIR/gateway.key"
    sudo chown $(whoami):$(whoami) "$CERT_DIR/gateway.crt" "$CERT_DIR/gateway.key"
    
    print_success "Let's Encrypt certificate configured"
    return 0
}

# Option 3: mkcert for local development
create_mkcert_cert() {
    print_header "Creating mkcert SSL Certificate"
    
    # Check if mkcert is installed
    if ! command -v mkcert &> /dev/null; then
        print_warning "mkcert not installed. Installing..."
        
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            curl -s https://api.github.com/repos/FiloSottile/mkcert/releases/latest \
                | grep browser_download_url \
                | grep linux-amd64 \
                | cut -d '"' -f 4 \
                | wget -qi -
            chmod +x mkcert-v*-linux-amd64
            sudo mv mkcert-v*-linux-amd64 /usr/local/bin/mkcert
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            if command -v brew &> /dev/null; then
                brew install mkcert
            else
                print_error "Please install mkcert manually on macOS"
                return 1
            fi
        fi
    fi
    
    # Install local CA
    mkcert -install
    
    # Generate certificates
    cd "$CERT_DIR"
    mkcert \
        "joke-gateway.local" \
        "*.joke-service.local" \
        "localhost" \
        "127.0.0.1" \
        "::1"
    
    # Rename files to standard names
    mv joke-gateway.local+4.pem gateway.crt 2>/dev/null || true
    mv joke-gateway.local+4-key.pem gateway.key 2>/dev/null || true
    
    print_success "mkcert certificate created with local CA trust"
    return 0
}

# Update Kong configuration with certificates
update_kong_config() {
    print_header "Updating Kong Configuration with SSL Certificates"
    
    local cert_file="$CERT_DIR/gateway.crt"
    local key_file="$CERT_DIR/gateway.key"
    
    if [[ ! -f "$cert_file" || ! -f "$key_file" ]]; then
        print_error "Certificate files not found in $CERT_DIR"
        return 1
    fi
    
    local kong_config="$PROJECT_ROOT/kong-vm/kong-declarative.yml"
    
    # Read certificate content
    local cert_content
    local key_content
    
    cert_content=$(sed 's/^/      /' "$cert_file")
    key_content=$(sed 's/^/      /' "$key_file")
    
    # Create updated Kong configuration
    local temp_config="/tmp/kong-config-temp.yml"
    
    # Replace certificate placeholders
    sed '/# This will be replaced by actual certificate content/,$d' "$kong_config" > "$temp_config"
    
    cat >> "$temp_config" << EOF
$cert_content
    key: |
$key_content
    snis:
      - "*.joke-service.local"
      - "joke-service.local"
      - "localhost"

EOF

    # Add the rest of the configuration (services section)
    sed -n '/^services:/,$p' "$kong_config" >> "$temp_config"
    
    # Replace original configuration
    mv "$temp_config" "$kong_config"
    
    print_success "Kong configuration updated with SSL certificates"
    print_info "Kong config: $kong_config"
    
    return 0
}

# Create Kong SSL environment setup
create_kong_ssl_setup() {
    print_header "Creating Kong SSL Setup Script"
    
    cat > "$PROJECT_ROOT/kong-vm/setup-ssl.sh" << 'EOF'
#!/bin/bash

# Kong SSL Setup Script - runs on Kong VM
set -e

CERT_DIR="/app/ssl-certificates"
mkdir -p "$CERT_DIR"

# Copy certificates from deployment
if [[ -f "/tmp/gateway.crt" && -f "/tmp/gateway.key" ]]; then
    cp /tmp/gateway.crt "$CERT_DIR/"
    cp /tmp/gateway.key "$CERT_DIR/"
    chmod 600 "$CERT_DIR/gateway.key"
    chmod 644 "$CERT_DIR/gateway.crt"
    echo "✅ SSL certificates installed"
else
    echo "⚠️ No certificates found, generating self-signed certificate..."
    
    # Generate self-signed certificate on VM
    openssl genrsa -out "$CERT_DIR/gateway.key" 2048
    openssl req -new -x509 -key "$CERT_DIR/gateway.key" -out "$CERT_DIR/gateway.crt" \
        -days 365 -subj "/C=US/ST=State/L=City/O=Demo/CN=kong-gateway"
    
    echo "✅ Self-signed certificate generated"
fi

# Restart Kong with SSL
docker-compose restart kong

echo "✅ Kong SSL setup completed"
EOF

    chmod +x "$PROJECT_ROOT/kong-vm/setup-ssl.sh"
    print_success "Kong SSL setup script created"
}

# Main function
main() {
    print_header "SSL Certificate Setup for Kong Gateway"
    
    local method="self-signed"
    local domain=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --self-signed)
                method="self-signed"
                domain="${2:-joke-gateway.local}"
                shift 2
                ;;
            --mkcert)
                method="mkcert"
                shift
                ;;
            --letsencrypt)
                method="letsencrypt"
                domain="$2"
                if [[ -z "$domain" ]]; then
                    print_error "Domain required for Let's Encrypt"
                    exit 1
                fi
                shift 2
                ;;
            --help|-h)
                echo "Usage: $0 [--self-signed [domain]] [--mkcert] [--letsencrypt domain]"
                echo ""
                echo "Options:"
                echo "  --self-signed [domain]  Create self-signed certificate (default)"
                echo "  --mkcert               Use mkcert for local development"  
                echo "  --letsencrypt domain   Use Let's Encrypt for production"
                echo ""
                echo "Examples:"
                echo "  $0                                    # Self-signed for joke-gateway.local"
                echo "  $0 --self-signed my-gateway.com      # Self-signed for custom domain"
                echo "  $0 --mkcert                          # mkcert for local development"
                echo "  $0 --letsencrypt my-gateway.com      # Let's Encrypt for production"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    create_cert_directory
    
    case "$method" in
        "self-signed")
            create_self_signed_cert "$domain"
            ;;
        "mkcert")
            create_mkcert_cert
            ;;
        "letsencrypt")
            create_letsencrypt_cert "$domain"
            ;;
    esac
    
    update_kong_config
    create_kong_ssl_setup
    
    print_header "SSL Setup Complete!"
    print_info "Certificate files:"
    ls -la "$CERT_DIR/"
    
    print_info "Next steps:"
    print_info "1. Deploy infrastructure: ./scripts/deploy-infrastructure.sh"
    print_info "2. Certificates will be automatically deployed to Kong VM"
    print_info "3. Access services via HTTPS: https://your-kong-vm-ip/"
    
    print_success "SSL certificate setup completed! 🔐"
}

main "$@"