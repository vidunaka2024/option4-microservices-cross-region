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
