#!/bin/bash
set -e

# Script to setup SSL certificates using Let's Encrypt
# Usage: setup-ssl.sh <frontend_domain> <backend_domain> <email>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FRONTEND_DOMAIN="${1:-yourdomain.com}"
BACKEND_DOMAIN="${2:-api.yourdomain.com}"
SSL_EMAIL="${3:-admin@yourdomain.com}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if certbot is installed
check_certbot() {
    if ! command -v certbot >/dev/null 2>&1; then
        log_error "Certbot is not installed. Run install-dependencies.sh first"
        exit 1
    fi
}

# Check if domains are accessible
check_domain_accessibility() {
    local domain=$1
    log_info "Checking if $domain points to this server..."
    
    # Get public IP
    PUBLIC_IP=$(curl -s ifconfig.me || curl -s icanhazip.com || echo "")
    
    if [ -z "$PUBLIC_IP" ]; then
        log_warn "Could not determine public IP. Skipping domain verification."
        return 0
    fi
    
    # Get domain IP (simple check)
    DOMAIN_IP=$(dig +short $domain 2>/dev/null | tail -n1 || echo "")
    
    if [ -z "$DOMAIN_IP" ]; then
        log_warn "Could not resolve $domain. Make sure DNS is configured correctly."
        log_warn "SSL certificate generation may fail if domain doesn't point to this server."
    elif [ "$DOMAIN_IP" != "$PUBLIC_IP" ]; then
        log_warn "Domain $domain ($DOMAIN_IP) does not point to this server ($PUBLIC_IP)"
        log_warn "SSL certificate generation may fail."
    else
        log_success "Domain $domain correctly points to this server"
    fi
}

# Check if Nginx is running and stop it temporarily for cert generation
handle_nginx_for_cert() {
    local nginx_was_running=false
    
    # Check if Nginx is running
    if systemctl is-active --quiet nginx 2>/dev/null; then
        log_info "Nginx is running. Temporarily stopping it for certificate generation..."
        nginx_was_running=true
        sudo systemctl stop nginx
        sleep 2  # Give it time to fully stop
        log_success "Nginx stopped temporarily"
    fi
    
    echo "$nginx_was_running"
}

# Restart Nginx if it was running before
restart_nginx_if_needed() {
    local nginx_was_running=$1
    
    if [ "$nginx_was_running" = "true" ]; then
        log_info "Restarting Nginx..."
        sudo systemctl start nginx
        sleep 2
        if systemctl is-active --quiet nginx 2>/dev/null; then
            log_success "Nginx restarted successfully"
        else
            log_warn "Nginx failed to restart. You may need to start it manually."
        fi
    fi
}

# Generate SSL certificate for a domain
generate_certificate() {
    local domain=$1
    local cert_path="/etc/letsencrypt/live/$domain/fullchain.pem"
    
    # Check if certificate already exists
    if [ -f "$cert_path" ]; then
        log_info "SSL certificate for $domain already exists"
        
        # Check if certificate is valid and not expired soon
        if openssl x509 -in "$cert_path" -noout -checkend 2592000 >/dev/null 2>&1; then
            log_success "Certificate for $domain is valid for more than 30 days"
            return 0
        else
            log_warn "Certificate for $domain expires soon, renewing..."
            sudo certbot renew --cert-name $domain --quiet || true
        fi
    else
        log_info "Generating SSL certificate for $domain..."
        
        # Stop Nginx temporarily if it's running
        local nginx_was_running=$(handle_nginx_for_cert)
        
        # Generate certificate using standalone method
        local cert_success=false
        if sudo certbot certonly \
            --standalone \
            --non-interactive \
            --agree-tos \
            --email "$SSL_EMAIL" \
            -d "$domain" \
            --preferred-challenges http; then
            cert_success=true
            log_success "SSL certificate generated for $domain"
        else
            log_error "Failed to generate certificate for $domain"
            log_error "Make sure:"
            log_error "  1. Domain $domain points to this server's IP"
            log_error "  2. Port 80 is accessible from the internet"
            log_error "  3. No firewall is blocking port 80"
            log_error "  4. No other service is using port 80"
        fi
        
        # Restart Nginx if it was running before
        restart_nginx_if_needed "$nginx_was_running"
        
        if [ "$cert_success" = "false" ]; then
            exit 1
        fi
    fi
}

# Setup auto-renewal
setup_auto_renewal() {
    log_info "Setting up SSL certificate auto-renewal..."
    
    # Create renewal script
    sudo tee /usr/local/bin/certbot-renew-hook.sh > /dev/null <<'EOF'
#!/bin/bash
# Reload Nginx after certificate renewal
systemctl reload nginx
EOF
    
    sudo chmod +x /usr/local/bin/certbot-renew-hook.sh
    
    # Setup systemd timer (preferred method)
    if [ -d /etc/systemd/system ]; then
        sudo tee /etc/systemd/system/certbot-renewal.service > /dev/null <<EOF
[Unit]
Description=Certbot Renewal
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/bin/certbot renew --quiet --deploy-hook /usr/local/bin/certbot-renew-hook.sh
EOF

        sudo tee /etc/systemd/system/certbot-renewal.timer > /dev/null <<EOF
[Unit]
Description=Run certbot renewal twice daily
After=network.target

[Timer]
OnCalendar=0/12:00:00
RandomizedDelaySec=3600
Persistent=true

[Install]
WantedBy=timers.target
EOF

        sudo systemctl daemon-reload
        sudo systemctl enable certbot-renewal.timer
        sudo systemctl start certbot-renewal.timer
        
        log_success "Auto-renewal timer enabled (checks twice daily)"
    else
        # Fallback to cron
        (crontab -l 2>/dev/null | grep -v certbot; echo "0 0,12 * * * /usr/bin/certbot renew --quiet --deploy-hook /usr/local/bin/certbot-renew-hook.sh") | crontab -
        log_success "Auto-renewal cron job added (runs twice daily)"
    fi
}

# Main function
main() {
    log_info "=========================================="
    log_info "SSL Certificate Setup"
    log_info "=========================================="
    log_info "Frontend Domain: $FRONTEND_DOMAIN"
    log_info "Backend Domain:  $BACKEND_DOMAIN"
    log_info "Email:           $SSL_EMAIL"
    log_info "=========================================="
    echo ""
    
    # Check if using default domains
    if [[ "$FRONTEND_DOMAIN" == "yourdomain.com" ]] || [[ "$BACKEND_DOMAIN" == "api.yourdomain.com" ]]; then
        log_warn "Using default domain placeholders. SSL setup will be skipped."
        log_warn "To enable SSL, set proper domain names in deploy.sh"
        return 0
    fi
    
    check_certbot
    
    # Check domain accessibility
    check_domain_accessibility "$FRONTEND_DOMAIN"
    check_domain_accessibility "$BACKEND_DOMAIN"
    echo ""
    
    # Generate certificates
    generate_certificate "$FRONTEND_DOMAIN"
    generate_certificate "$BACKEND_DOMAIN"
    
    # Setup auto-renewal
    setup_auto_renewal
    
    echo ""
    log_success "=========================================="
    log_success "SSL setup completed successfully!"
    log_success "=========================================="
    log_info "Certificates are stored in:"
    log_info "  /etc/letsencrypt/live/$FRONTEND_DOMAIN/"
    log_info "  /etc/letsencrypt/live/$BACKEND_DOMAIN/"
}

main "$@"

