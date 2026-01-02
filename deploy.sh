#!/bin/bash
set -e

# =============================================================================
# DEPLOYMENT CONFIGURATION - EDIT THESE VARIABLES AS NEEDED
# =============================================================================

# Repository URLs
FRONTEND_REPO="${FRONTEND_REPO:-https://github.com/schoolbaseafrica/SchoolBase-FE.git}"
BACKEND_REPO="${BACKEND_REPO:-https://github.com/Donkross360/SchoolBase-BE.git}"

# Branch/Tag to deploy (update these to deploy specific versions)
FRONTEND_BRANCH="${FRONTEND_BRANCH:-main}"
BACKEND_BRANCH="${BACKEND_BRANCH:-dev}"

# Action: "clone" (fresh clone) or "pull" (update existing)
# Set to "clone" to force fresh clone, "pull" to update existing repos
REPO_ACTION="${REPO_ACTION:-pull}"

# =============================================================================
# SCRIPT CONFIGURATION - DO NOT EDIT UNLESS NECESSARY
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
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

# =============================================================================
# MAIN DEPLOYMENT FLOW
# =============================================================================

main() {
    log_info "=========================================="
    log_info "SchoolBase Deployment Script"
    log_info "=========================================="
    log_info "Frontend: $FRONTEND_REPO (branch: $FRONTEND_BRANCH)"
    log_info "Backend:  $BACKEND_REPO (branch: $BACKEND_BRANCH)"
    log_info "Action:   $REPO_ACTION"
    log_info "=========================================="
    log_info "Note: Domain and email configuration will be loaded from .env file"
    echo ""

    # Step 1: Check and install system dependencies
    log_info "Step 1: Checking system dependencies..."
    "$SCRIPT_DIR/scripts/install-dependencies.sh"

    # Step 2: Clone or pull repositories
    log_info "Step 2: Managing repositories..."
    manage_repositories

    # Step 3: Setup environment configuration (loads .env file)
    log_info "Step 3: Setting up environment configuration..."
    setup_environment

    # Step 4: Setup SSL certificates (if domains are configured)
    if [[ "$FRONTEND_DOMAIN" != "yourdomain.com" ]] && [[ "$BACKEND_DOMAIN" != "api.yourdomain.com" ]]; then
        log_info "Step 4: Setting up SSL certificates..."
        "$SCRIPT_DIR/scripts/setup-ssl.sh" "$FRONTEND_DOMAIN" "$BACKEND_DOMAIN" "$SSL_EMAIL"
    else
        log_warn "Step 4: Skipping SSL setup (using default domain placeholders)"
        log_warn "         To enable SSL, set FRONTEND_DOMAIN and BACKEND_DOMAIN in .env file"
    fi

    # Step 5: Setup Nginx configuration
    log_info "Step 5: Configuring Nginx..."
    "$SCRIPT_DIR/scripts/setup-nginx.sh" "$FRONTEND_DOMAIN" "$BACKEND_DOMAIN"

    # Step 6: Setup Docker Compose command
    log_info "Step 6: Setting up Docker Compose..."
    setup_docker_compose

    # Step 7: Build and start Docker Compose services
    log_info "Step 7: Building and starting services..."
    build_and_start_services

    # Step 8: Health checks
    log_info "Step 8: Running health checks..."
    run_health_checks

    log_success "=========================================="
    log_success "Deployment completed successfully!"
    log_success "=========================================="
    echo ""
    log_info "Access your application:"
    if [[ "$FRONTEND_DOMAIN" != "yourdomain.com" ]]; then
        log_info "  Frontend: https://$FRONTEND_DOMAIN"
        log_info "  Backend:  https://$BACKEND_DOMAIN/api/v1"
    else
        log_info "  Frontend: http://localhost:3000"
        log_info "  Backend:  http://localhost:3008/api/v1"
    fi
    echo ""
    log_info "Useful commands:"
    log_info "  View logs:    $COMPOSE_CMD logs -f"
    log_info "  Stop services: $COMPOSE_CMD down"
    log_info "  Restart:      $COMPOSE_CMD restart"
}

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Detect which docker compose command is available
detect_docker_compose() {
    # Try docker compose (V2 plugin) first
    if docker compose version >/dev/null 2>&1; then
        echo "docker compose"
        return 0
    fi
    # Try docker-compose (standalone)
    if command -v docker-compose >/dev/null 2>&1; then
        echo "docker-compose"
        return 0
    fi
    # Neither found
    return 1
}

# Check docker permissions and set compose command
setup_docker_compose() {
    # Detect compose command
    if ! DOCKER_COMPOSE_CMD=$(detect_docker_compose); then
        log_error "Docker Compose not found. Please install Docker Compose first."
        exit 1
    fi
    
    # Check if docker can be run without sudo
    if docker ps >/dev/null 2>&1; then
        DOCKER_CMD="docker"
        COMPOSE_CMD="$DOCKER_COMPOSE_CMD"
    elif sudo docker ps >/dev/null 2>&1; then
        DOCKER_CMD="sudo docker"
        # For docker compose (V2), we need sudo before docker
        if [[ "$DOCKER_COMPOSE_CMD" == "docker compose" ]]; then
            COMPOSE_CMD="sudo docker compose"
        else
            COMPOSE_CMD="sudo docker-compose"
        fi
        log_warn "Using sudo for Docker commands. Consider logging out and back in after being added to docker group."
    else
        log_error "Cannot access Docker. Please ensure Docker is installed and running."
        log_error "If you were just added to the docker group, you may need to logout and login again."
        exit 1
    fi
    
    log_info "Using Docker Compose command: $COMPOSE_CMD"
}

manage_repositories() {
    # Frontend repository
    if [ -d "SchoolBase-FE" ]; then
        if [[ "$REPO_ACTION" == "clone" ]]; then
            log_warn "Frontend directory exists. Removing for fresh clone..."
            rm -rf SchoolBase-FE
        fi
    fi

    if [ ! -d "SchoolBase-FE" ]; then
        log_info "Cloning frontend repository..."
        git clone -b "$FRONTEND_BRANCH" "$FRONTEND_REPO" SchoolBase-FE
        log_success "Frontend repository cloned"
    else
        if [[ "$REPO_ACTION" == "pull" ]]; then
            log_info "Updating frontend repository..."
            cd SchoolBase-FE
            git fetch origin
            git checkout "$FRONTEND_BRANCH" || git checkout -b "$FRONTEND_BRANCH" origin/"$FRONTEND_BRANCH"
            git pull origin "$FRONTEND_BRANCH" || log_warn "Could not pull latest changes (may be on different branch)"
            cd "$SCRIPT_DIR"
            log_success "Frontend repository updated"
        fi
    fi

    # Backend repository
    if [ -d "SchoolBase-BE" ]; then
        if [[ "$REPO_ACTION" == "clone" ]]; then
            log_warn "Backend directory exists. Removing for fresh clone..."
            rm -rf SchoolBase-BE
        fi
    fi

    if [ ! -d "SchoolBase-BE" ]; then
        log_info "Cloning backend repository..."
        git clone -b "$BACKEND_BRANCH" "$BACKEND_REPO" SchoolBase-BE
        log_success "Backend repository cloned"
    else
        if [[ "$REPO_ACTION" == "pull" ]]; then
            log_info "Updating backend repository..."
            cd SchoolBase-BE
            git fetch origin
            git checkout "$BACKEND_BRANCH" || git checkout -b "$BACKEND_BRANCH" origin/"$BACKEND_BRANCH"
            git pull origin "$BACKEND_BRANCH" || log_warn "Could not pull latest changes (may be on different branch)"
            cd "$SCRIPT_DIR"
            log_success "Backend repository updated"
        fi
    fi

    # Verify both repos exist
    if [ ! -d "SchoolBase-FE" ] || [ ! -d "SchoolBase-BE" ]; then
        log_error "Failed to clone/update repositories"
        exit 1
    fi
}

setup_environment() {
    if [ ! -f ".env" ]; then
        if [ -f "config/env.example" ]; then
            log_info "Creating .env file from example..."
            cp config/env.example .env
            log_warn "Please edit .env file and set your configuration values!"
            log_warn "Especially important:"
            log_warn "  - FRONTEND_DOMAIN and BACKEND_DOMAIN (for SSL)"
            log_warn "  - SSL_EMAIL (for Let's Encrypt)"
            log_warn "  - JWT_SECRET and JWT_REFRESH_SECRET (security)"
            log_warn "  - Database passwords (DB_PASS)"
            log_warn "  - MinIO passwords (MINIO_ROOT_PASSWORD, MINIO_SECRET_KEY)"
            echo ""
            read -p "Press Enter to continue after reviewing .env, or Ctrl+C to cancel..."
        else
            log_error "env.example not found in config/ directory"
            exit 1
        fi
    else
        log_info ".env file already exists, loading configuration..."
    fi
    
    # Load environment variables from .env file
    if [ -f ".env" ]; then
        log_info "Loading configuration from .env file..."
        set -a  # Automatically export all variables
        source .env
        set +a  # Stop automatically exporting
        
        # Set defaults if not provided
        FRONTEND_DOMAIN="${FRONTEND_DOMAIN:-yourdomain.com}"
        BACKEND_DOMAIN="${BACKEND_DOMAIN:-api.yourdomain.com}"
        SSL_EMAIL="${SSL_EMAIL:-admin@yourdomain.com}"
        
        # Set NEXT_PUBLIC_API_BASE_URL based on BACKEND_DOMAIN if not explicitly set
        if [[ -z "$NEXT_PUBLIC_API_BASE_URL" ]]; then
            if [[ "$BACKEND_DOMAIN" != "api.yourdomain.com" ]]; then
                # Use HTTPS for production domains
                export NEXT_PUBLIC_API_BASE_URL="https://${BACKEND_DOMAIN}/api/v1"
            else
                # Use localhost for development
                export NEXT_PUBLIC_API_BASE_URL="${NEXT_PUBLIC_API_URL:-http://localhost:3008/api/v1}"
            fi
        fi
    else
        log_error ".env file not found"
        exit 1
    fi
}

build_and_start_services() {
    # Check if we should rebuild (if FORCE_REBUILD env var is set, or if images don't exist)
    local should_rebuild=false
    
    if [ "${FORCE_REBUILD:-false}" = "true" ]; then
        should_rebuild=true
        log_info "FORCE_REBUILD is set - will rebuild images"
    elif ! $COMPOSE_CMD images | grep -q "schoolbase"; then
        should_rebuild=true
        log_info "Docker images not found - will build"
    else
        log_info "Docker images exist - skipping build (set FORCE_REBUILD=true to rebuild)"
    fi
    
    if [ "$should_rebuild" = "true" ]; then
        log_info "Building Docker images (this may take a while)..."
        $COMPOSE_CMD build
    fi

    log_info "Starting/updating services..."
    $COMPOSE_CMD up -d

    log_info "Waiting for services to be healthy..."
    sleep 10

    # Check if services are running
    if $COMPOSE_CMD ps | grep -q "Up"; then
        log_success "Services started successfully"
    else
        log_error "Some services failed to start. Check logs with: $COMPOSE_CMD logs"
        exit 1
    fi
}

run_health_checks() {
    log_info "Checking service health..."
    
    # Check if containers are running
    if ! $COMPOSE_CMD ps | grep -q "Up"; then
        log_error "Services are not running"
        return 1
    fi

    # Check backend health
    if curl -f -s http://localhost:3008/health > /dev/null 2>&1; then
        log_success "Backend health check passed"
    else
        log_warn "Backend health check failed (may still be starting up)"
    fi

    # Check frontend
    if curl -f -s http://localhost:3000 > /dev/null 2>&1; then
        log_success "Frontend health check passed"
    else
        log_warn "Frontend health check failed (may still be starting up)"
    fi
}

# =============================================================================
# RUN MAIN FUNCTION
# =============================================================================

main "$@"

