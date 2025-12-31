#!/bin/bash
set -e

# Script to install all required dependencies for SchoolBase deployment
# Supports: Ubuntu/Debian, CentOS/RHEL, Alpine

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# Detect OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    elif type lsb_release >/dev/null 2>&1; then
        OS=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
    elif [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        OS=$DISTRIB_ID
    elif [ -f /etc/debian_version ]; then
        OS=debian
    elif [ -f /etc/redhat-release ]; then
        OS=rhel
    else
        OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    fi
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Install Docker
install_docker() {
    if command_exists docker; then
        log_info "Docker is already installed: $(docker --version)"
        return 0
    fi

    log_info "Installing Docker..."
    
    case $OS in
        ubuntu|debian)
            # Remove old versions
            sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
            
            # Install dependencies
            sudo apt-get update
            sudo apt-get install -y \
                ca-certificates \
                curl \
                gnupg \
                lsb-release
            
            # Add Docker's official GPG key
            sudo mkdir -p /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/$OS/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            
            # Set up repository
            echo \
              "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS \
              $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            
            # Install Docker
            sudo apt-get update
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            
            # Start Docker
            sudo systemctl start docker
            sudo systemctl enable docker
            ;;
        centos|rhel|fedora)
            sudo yum install -y yum-utils
            sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            sudo yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            sudo systemctl start docker
            sudo systemctl enable docker
            ;;
        alpine)
            apk add --no-cache docker docker-compose
            rc-update add docker boot
            service docker start
            ;;
        *)
            log_error "Unsupported OS: $OS"
            exit 1
            ;;
    esac

    # Add current user to docker group (optional, for non-sudo usage)
    if [ "$EUID" -ne 0 ]; then
        log_info "Adding current user to docker group (logout/login required for non-sudo usage)"
        sudo usermod -aG docker $USER || true
    fi

    log_success "Docker installed: $(docker --version)"
}

# Install Docker Compose (standalone, if not using plugin)
install_docker_compose() {
    if command_exists docker-compose || docker compose version >/dev/null 2>&1; then
        log_info "Docker Compose is already installed"
        return 0
    fi

    log_info "Installing Docker Compose..."
    
    # Try to use plugin first (newer method)
    if docker compose version >/dev/null 2>&1; then
        log_success "Docker Compose plugin is available"
        return 0
    fi

    # Install standalone docker-compose
    COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)
    sudo curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    
    log_success "Docker Compose installed: $(docker-compose --version)"
}

# Install Nginx
install_nginx() {
    if command_exists nginx; then
        log_info "Nginx is already installed: $(nginx -v 2>&1)"
        return 0
    fi

    log_info "Installing Nginx..."
    
    case $OS in
        ubuntu|debian)
            sudo apt-get update
            sudo apt-get install -y nginx
            ;;
        centos|rhel|fedora)
            sudo yum install -y nginx
            ;;
        alpine)
            apk add --no-cache nginx
            ;;
        *)
            log_error "Unsupported OS: $OS"
            exit 1
            ;;
    esac

    # Enable Nginx
    sudo systemctl enable nginx || true
    sudo systemctl start nginx || true
    
    log_success "Nginx installed: $(nginx -v 2>&1)"
}

# Install Certbot for Let's Encrypt
install_certbot() {
    if command_exists certbot; then
        log_info "Certbot is already installed: $(certbot --version 2>&1 | head -n1)"
        return 0
    fi

    log_info "Installing Certbot..."
    
    case $OS in
        ubuntu|debian)
            sudo apt-get update
            sudo apt-get install -y certbot python3-certbot-nginx
            ;;
        centos|rhel|fedora)
            sudo yum install -y certbot python3-certbot-nginx
            ;;
        alpine)
            apk add --no-cache certbot certbot-nginx
            ;;
        *)
            log_error "Unsupported OS: $OS"
            exit 1
            ;;
    esac
    
    log_success "Certbot installed: $(certbot --version 2>&1 | head -n1)"
}

# Install Python3 and Jinja2 (for Nginx template rendering)
install_python_jinja2() {
    if ! command_exists python3; then
        log_info "Installing Python3..."
        case $OS in
            ubuntu|debian)
                sudo apt-get update
                sudo apt-get install -y python3 python3-pip
                ;;
            centos|rhel|fedora)
                sudo yum install -y python3 python3-pip
                ;;
            alpine)
                apk add --no-cache python3 py3-pip
                ;;
        esac
    fi

    # Install Jinja2
    if ! python3 -c "import jinja2" 2>/dev/null; then
        log_info "Installing Jinja2 for template rendering..."
        pip3 install --user jinja2 || sudo pip3 install jinja2
    fi

    log_success "Python3 and Jinja2 are available"
}

# Install Git (if not present)
install_git() {
    if command_exists git; then
        log_info "Git is already installed: $(git --version)"
        return 0
    fi

    log_info "Installing Git..."
    
    case $OS in
        ubuntu|debian)
            sudo apt-get update
            sudo apt-get install -y git
            ;;
        centos|rhel|fedora)
            sudo yum install -y git
            ;;
        alpine)
            apk add --no-cache git
            ;;
    esac
    
    log_success "Git installed: $(git --version)"
}

# Main installation function
main() {
    log_info "Detecting operating system..."
    detect_os
    log_info "Detected OS: $OS $OS_VERSION"
    echo ""

    # Check if running as root (some operations require sudo)
    if [ "$EUID" -eq 0 ]; then
        SUDO=""
    else
        SUDO="sudo"
        log_info "Some installations require sudo privileges"
    fi

    # Install dependencies
    install_git
    install_docker
    install_docker_compose
    install_nginx
    install_certbot
    install_python_jinja2

    echo ""
    log_success "=========================================="
    log_success "All dependencies installed successfully!"
    log_success "=========================================="
    
    # Note about Docker group
    if [ "$EUID" -ne 0 ] && ! groups | grep -q docker; then
        echo ""
        log_warn "Note: You've been added to the docker group."
        log_warn "You may need to logout and login again to use docker without sudo"
    fi
}

# Run main function
main "$@"

