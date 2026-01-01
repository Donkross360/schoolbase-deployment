#!/bin/bash
set -e

# Script to setup Nginx configuration using Jinja2 templates
# Usage: setup-nginx.sh <frontend_domain> <backend_domain>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYMENT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

FRONTEND_DOMAIN="${1:-yourdomain.com}"
BACKEND_DOMAIN="${2:-api.yourdomain.com}"

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

# Check if Python3 and Jinja2 are available
check_python_jinja2() {
    if ! command -v python3 >/dev/null 2>&1; then
        log_error "Python3 is not installed. Run install-dependencies.sh first"
        exit 1
    fi
    
    if ! python3 -c "import jinja2" 2>/dev/null; then
        log_error "Jinja2 is not installed. Run install-dependencies.sh first"
        exit 1
    fi
}

# Render Jinja2 template
render_template() {
    local template_file=$1
    local output_file=$2
    local frontend_domain=$3
    local backend_domain=$4
    
    python3 << EOF
from jinja2 import Environment, FileSystemLoader
import os

# Get template directory
template_dir = os.path.dirname('$template_file')
template_name = os.path.basename('$template_file')

# Setup Jinja2 environment
env = Environment(loader=FileSystemLoader(template_dir))
template = env.get_template(template_name)

# Determine SSL certificate paths
use_ssl = '$frontend_domain' != 'yourdomain.com' and '$backend_domain' != 'api.yourdomain.com'

frontend_ssl_cert = '/etc/letsencrypt/live/$frontend_domain/fullchain.pem' if use_ssl else None
frontend_ssl_key = '/etc/letsencrypt/live/$frontend_domain/privkey.pem' if use_ssl else None
backend_ssl_cert = '/etc/letsencrypt/live/$backend_domain/fullchain.pem' if use_ssl else None
backend_ssl_key = '/etc/letsencrypt/live/$backend_domain/privkey.pem' if use_ssl else None

# Render template
output = template.render(
    frontend_domain='$frontend_domain',
    backend_domain='$backend_domain',
    use_ssl=use_ssl,
    frontend_ssl_cert=frontend_ssl_cert,
    frontend_ssl_key=frontend_ssl_key,
    backend_ssl_cert=backend_ssl_cert,
    backend_ssl_key=backend_ssl_key,
    backend_port=3008,
    frontend_port=3000
)

# Write output
with open('$output_file', 'w') as f:
    f.write(output)
EOF
}

# Generate frontend Nginx configuration
generate_frontend_config() {
    local template="$DEPLOYMENT_DIR/nginx/templates/frontend.conf.j2"
    local output="/tmp/schoolbase-frontend.conf"
    
    if [ ! -f "$template" ]; then
        log_error "Template not found: $template" >&2
        exit 1
    fi
    
    log_info "Generating frontend Nginx configuration..." >&2
    render_template "$template" "$output" "$FRONTEND_DOMAIN" "$BACKEND_DOMAIN"
    
    # Validate configuration
    if sudo nginx -t -c "$output" 2>/dev/null; then
        log_success "Frontend configuration is valid" >&2
    else
        log_warn "Configuration validation skipped (nginx may not be installed yet)" >&2
    fi
    
    echo "$output"
}

# Generate backend Nginx configuration
generate_backend_config() {
    local template="$DEPLOYMENT_DIR/nginx/templates/backend.conf.j2"
    local output="/tmp/schoolbase-backend.conf"
    
    if [ ! -f "$template" ]; then
        log_error "Template not found: $template" >&2
        exit 1
    fi
    
    log_info "Generating backend Nginx configuration..." >&2
    render_template "$template" "$output" "$FRONTEND_DOMAIN" "$BACKEND_DOMAIN"
    
    # Validate configuration
    if sudo nginx -t -c "$output" 2>/dev/null; then
        log_success "Backend configuration is valid" >&2
    else
        log_warn "Configuration validation skipped (nginx may not be installed yet)" >&2
    fi
    
    echo "$output"
}

# Install Nginx configurations
install_configs() {
    local frontend_config=$1
    local backend_config=$2
    
    log_info "Installing Nginx configurations..."
    
    # Backup existing configs if they exist
    if [ -f /etc/nginx/sites-available/schoolbase-frontend ]; then
        log_info "Backing up existing frontend configuration..."
        sudo cp /etc/nginx/sites-available/schoolbase-frontend \
            /etc/nginx/sites-available/schoolbase-frontend.backup.$(date +%Y%m%d_%H%M%S)
    fi
    
    if [ -f /etc/nginx/sites-available/schoolbase-backend ]; then
        log_info "Backing up existing backend configuration..."
        sudo cp /etc/nginx/sites-available/schoolbase-backend \
            /etc/nginx/sites-available/schoolbase-backend.backup.$(date +%Y%m%d_%H%M%S)
    fi
    
    # Copy configurations
    sudo cp "$frontend_config" /etc/nginx/sites-available/schoolbase-frontend
    sudo cp "$backend_config" /etc/nginx/sites-available/schoolbase-backend
    
    # Enable sites
    sudo ln -sf /etc/nginx/sites-available/schoolbase-frontend /etc/nginx/sites-enabled/schoolbase-frontend
    sudo ln -sf /etc/nginx/sites-available/schoolbase-backend /etc/nginx/sites-enabled/schoolbase-backend
    
    # Remove default site if it exists
    if [ -L /etc/nginx/sites-enabled/default ]; then
        log_info "Removing default Nginx site..."
        sudo rm /etc/nginx/sites-enabled/default
    fi
    
    log_success "Nginx configurations installed"
}

# Test and reload Nginx
test_and_reload() {
    log_info "Testing Nginx configuration..."
    
    if sudo nginx -t; then
        log_success "Nginx configuration test passed"
        
        # Reload Nginx
        if sudo systemctl is-active --quiet nginx; then
            log_info "Reloading Nginx..."
            sudo systemctl reload nginx
            log_success "Nginx reloaded successfully"
        else
            log_info "Starting Nginx..."
            sudo systemctl start nginx
            sudo systemctl enable nginx
            log_success "Nginx started successfully"
        fi
    else
        log_error "Nginx configuration test failed"
        log_error "Please check the configuration files:"
        log_error "  /etc/nginx/sites-available/schoolbase-frontend"
        log_error "  /etc/nginx/sites-available/schoolbase-backend"
        exit 1
    fi
}

# Main function
main() {
    log_info "=========================================="
    log_info "Nginx Configuration Setup"
    log_info "=========================================="
    log_info "Frontend Domain: $FRONTEND_DOMAIN"
    log_info "Backend Domain:  $BACKEND_DOMAIN"
    log_info "=========================================="
    echo ""
    
    check_python_jinja2
    
    # Generate configurations
    FRONTEND_CONFIG=$(generate_frontend_config)
    BACKEND_CONFIG=$(generate_backend_config)
    
    # Install configurations
    install_configs "$FRONTEND_CONFIG" "$BACKEND_CONFIG"
    
    # Test and reload
    test_and_reload
    
    echo ""
    log_success "=========================================="
    log_success "Nginx setup completed successfully!"
    log_success "=========================================="
    
    if [[ "$FRONTEND_DOMAIN" != "yourdomain.com" ]]; then
        log_info "Your application should be accessible at:"
        log_info "  Frontend: https://$FRONTEND_DOMAIN"
        log_info "  Backend:  https://$BACKEND_DOMAIN/api/v1"
    else
        log_info "Using default domains. Update FRONTEND_DOMAIN and BACKEND_DOMAIN for SSL."
    fi
}

main "$@"

