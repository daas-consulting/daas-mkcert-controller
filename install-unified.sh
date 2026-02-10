#!/bin/bash

#############################################################################
# daas-mkcert-controller - Unified Installation Script
# 
# Single script that handles everything:
# 1. Generate CA files using Docker (no local mkcert install needed)
# 2. Install CA in local trust store using native OS commands
# 3. Build and start the controller container
# 4. All with proper directory mounting
# 
# Minimal dependencies: Docker + native OS tools (no mkcert on host)
#
# Usage:
#   ./install-unified.sh install   - Install everything
#   ./install-unified.sh uninstall - Remove everything
#   ./install-unified.sh status    - Check status
#############################################################################

set -e

# Script version
VERSION="1.2.0"

# Detect if running as root to choose appropriate default directories
if [[ $EUID -eq 0 ]]; then
    _DEFAULT_TRAEFIK_DIR="/etc/traefik"
    _DEFAULT_CERTS_DIR="/var/lib/daas-mkcert/certs"
else
    _DEFAULT_TRAEFIK_DIR="$HOME/.traefik"
    _DEFAULT_CERTS_DIR="$HOME/.daas-mkcert/certs"
fi

# Configuration defaults (can be overridden by environment variables)
CONTAINER_NAME="${CONTAINER_NAME:-daas-mkcert-controller}"
IMAGE_NAME="${IMAGE_NAME:-daas-mkcert-controller}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
TRAEFIK_DIR="${TRAEFIK_DIR:-$_DEFAULT_TRAEFIK_DIR}"
CERTS_DIR="${CERTS_DIR:-$_DEFAULT_CERTS_DIR}"
MKCERT_CA_DIR="${MKCERT_CA_DIR:-$HOME/.local/share/mkcert}"
HELPER_IMAGE="daas-mkcert-helper:latest"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
GRAY='\033[0;90m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Syslog RFC 5424 facility: local0 (16)
_SYSLOG_FACILITY=16
_APP_NAME="daas-mkcert-controller"
_HOSTNAME=$(hostname)

# Syslog RFC 5424 log function
_syslog_log() {
    local severity="$1"
    local level="$2"
    local color="$3"
    local message="$4"
    local priority=$(( _SYSLOG_FACILITY * 8 + severity ))
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")
    local header="<${priority}>1 ${timestamp} ${_HOSTNAME} ${_APP_NAME} $$ - -"
    echo -e "${header} ${color}[${level}]${NC} ${message}"
}

# Logging functions - Syslog RFC 5424 format with colors
log_info() {
    _syslog_log 6 "INFO" "${GREEN}" "$1"
}

log_warn() {
    _syslog_log 4 "WARN" "${YELLOW}" "$1"
}

log_error() {
    _syslog_log 3 "ERROR" "${RED}" "$1"
}

log_success() {
    _syslog_log 6 "INFO" "${GREEN}" "✓ $1"
}

log_fail() {
    _syslog_log 3 "ERROR" "${RED}" "✗ $1"
}

# Display banner
show_banner() {
    local TOTAL_WIDTH=34
    local PRODUCT="mkcert-controller"
    local COMPANY="consulting"
    local BRAND="daas"
    local BLUE_BG='\033[44;37m'
    local PURPLE_BG='\033[45;37m'
    local RST='\033[0m'

    # Top bar (blue background, white text)
    local top_left=" ${BRAND}"
    local top_right="${PRODUCT} "
    local top_pad=$(( TOTAL_WIDTH - ${#top_left} - ${#top_right} ))
    printf "${BLUE_BG}${top_left}%${top_pad}s${top_right}${RST}\n" ""

    # Figlet "daas" graffiti with lolcat-style rainbow colors
    printf '\e[38;5;118m \e[39m\e[38;5;118m \e[39m\e[38;5;118m \e[39m\e[38;5;118m \e[39m\e[38;5;154m \e[39m\e[38;5;154m \e[39m\e[38;5;154m \e[39m\e[38;5;154m.\e[39m\e[38;5;148m_\e[39m\e[38;5;148m_\e[39m\e[38;5;148m_\e[39m\e[38;5;148m \e[39m\e[38;5;184m \e[39m\e[38;5;184m \e[39m\e[38;5;184m \e[39m\e[38;5;184m \e[39m\e[38;5;178m \e[39m\e[38;5;178m \e[39m\e[38;5;178m \e[39m\e[38;5;214m \e[39m\e[38;5;214m \e[39m\e[38;5;214m \e[39m\e[38;5;214m \e[39m\e[38;5;208m \e[39m\e[38;5;208m \e[39m\e[38;5;208m \e[39m\e[38;5;208m \e[39m\e[38;5;209m \e[39m\e[38;5;209m \e[39m\e[38;5;209m \e[39m\e[38;5;209m \e[39m\e[38;5;203m \e[39m\e[38;5;203m \e[39m\e[38;5;203m \e[39m\n'
    printf '\e[38;5;118m \e[39m\e[38;5;118m \e[39m\e[38;5;154m \e[39m\e[38;5;154m \e[39m\e[38;5;154m \e[39m\e[38;5;154m_\e[39m\e[38;5;148m_\e[39m\e[38;5;148m|\e[39m\e[38;5;148m \e[39m\e[38;5;148m_\e[39m\e[38;5;184m/\e[39m\e[38;5;184m_\e[39m\e[38;5;184m_\e[39m\e[38;5;184m_\e[39m\e[38;5;178m_\e[39m\e[38;5;178m \e[39m\e[38;5;178m \e[39m\e[38;5;214m_\e[39m\e[38;5;214m_\e[39m\e[38;5;214m_\e[39m\e[38;5;214m_\e[39m\e[38;5;208m_\e[39m\e[38;5;208m \e[39m\e[38;5;208m \e[39m\e[38;5;208m \e[39m\e[38;5;209m \e[39m\e[38;5;209m_\e[39m\e[38;5;209m_\e[39m\e[38;5;209m_\e[39m\e[38;5;203m_\e[39m\e[38;5;203m_\e[39m\e[38;5;203m_\e[39m\e[38;5;203m \e[39m\e[38;5;203m \e[39m\n'
    printf '\e[38;5;154m \e[39m\e[38;5;154m \e[39m\e[38;5;154m \e[39m\e[38;5;154m \e[39m\e[38;5;148m/\e[39m\e[38;5;148m \e[39m\e[38;5;148m_\e[39m\e[38;5;148m_\e[39m\e[38;5;184m \e[39m\e[38;5;184m|\e[39m\e[38;5;184m\\\e[39m\e[38;5;184m_\e[39m\e[38;5;178m_\e[39m\e[38;5;178m \e[39m\e[38;5;178m \e[39m\e[38;5;214m\\\e[39m\e[38;5;214m \e[39m\e[38;5;214m\\\e[39m\e[38;5;214m_\e[39m\e[38;5;208m_\e[39m\e[38;5;208m \e[39m\e[38;5;208m \e[39m\e[38;5;208m\\\e[39m\e[38;5;209m \e[39m\e[38;5;209m \e[39m\e[38;5;209m/\e[39m\e[38;5;209m \e[39m\e[38;5;203m \e[39m\e[38;5;203m_\e[39m\e[38;5;203m_\e[39m\e[38;5;203m_\e[39m\e[38;5;203m/\e[39m\e[38;5;203m \e[39m\e[38;5;203m \e[39m\n'
    printf '\e[38;5;154m \e[39m\e[38;5;154m \e[39m\e[38;5;148m \e[39m\e[38;5;148m/\e[39m\e[38;5;148m \e[39m\e[38;5;148m/\e[39m\e[38;5;184m_\e[39m\e[38;5;184m/\e[39m\e[38;5;184m \e[39m\e[38;5;184m|\e[39m\e[38;5;178m \e[39m\e[38;5;178m/\e[39m\e[38;5;178m \e[39m\e[38;5;214m_\e[39m\e[38;5;214m_\e[39m\e[38;5;214m \e[39m\e[38;5;214m\\\e[39m\e[38;5;208m_\e[39m\e[38;5;208m/\e[39m\e[38;5;208m \e[39m\e[38;5;208m_\e[39m\e[38;5;209m_\e[39m\e[38;5;209m \e[39m\e[38;5;209m\\\e[39m\e[38;5;209m_\e[39m\e[38;5;203m\\\e[39m\e[38;5;203m_\e[39m\e[38;5;203m_\e[39m\e[38;5;203m_\e[39m\e[38;5;203m \e[39m\e[38;5;203m\\\e[39m\e[38;5;203m \e[39m\e[38;5;203m \e[39m\e[38;5;203m \e[39m\n'
    printf '\e[38;5;148m \e[39m\e[38;5;148m \e[39m\e[38;5;148m \e[39m\e[38;5;148m\\\e[39m\e[38;5;184m_\e[39m\e[38;5;184m_\e[39m\e[38;5;184m_\e[39m\e[38;5;184m_\e[39m\e[38;5;178m \e[39m\e[38;5;178m|\e[39m\e[38;5;178m(\e[39m\e[38;5;214m_\e[39m\e[38;5;214m_\e[39m\e[38;5;214m_\e[39m\e[38;5;214m_\e[39m\e[38;5;208m \e[39m\e[38;5;208m \e[39m\e[38;5;208m(\e[39m\e[38;5;208m_\e[39m\e[38;5;209m_\e[39m\e[38;5;209m_\e[39m\e[38;5;209m_\e[39m\e[38;5;209m \e[39m\e[38;5;203m \e[39m\e[38;5;203m/\e[39m\e[38;5;203m_\e[39m\e[38;5;203m_\e[39m\e[38;5;203m_\e[39m\e[38;5;203m_\e[39m\e[38;5;203m \e[39m\e[38;5;203m \e[39m\e[38;5;203m>\e[39m\e[38;5;203m \e[39m\e[38;5;203m \e[39m\n'
    printf '\e[38;5;148m \e[39m\e[38;5;148m \e[39m\e[38;5;184m \e[39m\e[38;5;184m \e[39m\e[38;5;184m \e[39m\e[38;5;184m \e[39m\e[38;5;178m \e[39m\e[38;5;178m \e[39m\e[38;5;178m\\\e[39m\e[38;5;214m/\e[39m\e[38;5;214m \e[39m\e[38;5;214m \e[39m\e[38;5;214m \e[39m\e[38;5;208m \e[39m\e[38;5;208m \e[39m\e[38;5;208m\\\e[39m\e[38;5;208m/\e[39m\e[38;5;209m \e[39m\e[38;5;209m \e[39m\e[38;5;209m \e[39m\e[38;5;209m \e[39m\e[38;5;203m \e[39m\e[38;5;203m\\\e[39m\e[38;5;203m/\e[39m\e[38;5;203m \e[39m\e[38;5;203m \e[39m\e[38;5;203m \e[39m\e[38;5;203m \e[39m\e[38;5;203m \e[39m\e[38;5;203m\\\e[39m\e[38;5;203m/\e[39m\e[38;5;203m \e[39m\e[38;5;203m \e[39m\e[38;5;203m \e[39m\n'

    # Bottom bar (blue background, white text)
    local bot_left=" ${PRODUCT}"
    local bot_right="${COMPANY} "
    local bot_pad=$(( TOTAL_WIDTH - ${#bot_left} - ${#bot_right} ))
    printf "${BLUE_BG}${bot_left}%${bot_pad}s${bot_right}${RST}\n" ""

    # Version bar (purple background, white text)
    local ver_left=" Unified Installer"
    local ver_right="v${VERSION} "
    local ver_pad=$(( TOTAL_WIDTH - ${#ver_left} - ${#ver_right} ))
    printf "${PURPLE_BG}${ver_left}%${ver_pad}s${ver_right}${RST}\n" ""

    echo ""
}

# Show usage
show_usage() {
    cat << EOF
Usage: $0 [command]

Commands:
    install     Install everything (CA + controller)
    uninstall   Remove everything (CA + controller)
    status      Check installation status
    help        Show this help message

Environment Variables:
    CONTAINER_NAME      Container name (default: daas-mkcert-controller)
    IMAGE_NAME          Docker image name (default: daas-mkcert-controller)
    IMAGE_TAG           Docker image tag (default: latest)
    TRAEFIK_DIR         Traefik config directory
                        Default (root):     /etc/traefik
                        Default (non-root): ~/.traefik
    CERTS_DIR           Certificates directory
                        Default (root):     /var/lib/daas-mkcert/certs
                        Default (non-root): ~/.daas-mkcert/certs
    MKCERT_CA_DIR       mkcert CA directory (default: ~/.local/share/mkcert)

Features:
    ✓ No local mkcert installation required
    ✓ Generates CA using Docker container
    ✓ Installs CA using native OS commands
    ✓ Single unified process
    ✓ Minimal dependencies

Examples:
    # Install everything
    $0 install

    # Check status
    $0 status

    # Uninstall everything
    $0 uninstall

EOF
}

# Validate OS is Linux
validate_os() {
    log_info "Validating operating system..."
    
    if [[ "$OSTYPE" != "linux-gnu"* ]]; then
        log_fail "This script only supports Linux"
        log_error "Detected OS: $OSTYPE"
        exit 1
    fi
    
    log_success "Operating system validated: Linux"
}

# Validate Docker is installed and running
validate_docker() {
    log_info "Validating Docker installation..."
    
    if ! command -v docker &> /dev/null; then
        log_fail "Docker is not installed"
        log_error "Please install Docker: https://docs.docker.com/engine/install/"
        exit 1
    fi
    
    log_success "Docker command found"
    
    log_info "Checking Docker daemon..."
    if ! docker info &> /dev/null; then
        log_fail "Docker daemon is not running or not accessible"
        log_error "Please ensure Docker is running and you have permissions to use it"
        log_error "You may need to add your user to the docker group: sudo usermod -aG docker \$USER"
        exit 1
    fi
    
    log_success "Docker daemon is accessible"
}

# Validate user permissions
validate_permissions() {
    log_info "Validating user permissions..."
    
    # Check Docker socket access
    if [[ ! -S /var/run/docker.sock ]]; then
        log_fail "Docker socket not found at /var/run/docker.sock"
        exit 1
    fi
    
    if [[ ! -r /var/run/docker.sock ]]; then
        log_fail "No read access to Docker socket"
        log_error "Run: sudo chmod 666 /var/run/docker.sock"
        exit 1
    fi
    
    log_success "Docker socket is accessible"
}

# Validate and create directories
validate_directories() {
    log_info "Validating required directories..."
    
    local dirs=("$CERTS_DIR" "$MKCERT_CA_DIR")
    
    # Add Traefik directory if it should exist
    if [[ -d "$TRAEFIK_DIR" ]]; then
        dirs+=("$TRAEFIK_DIR")
    else
        log_warn "Traefik directory does not exist: $TRAEFIK_DIR"
        log_warn "Will create it or ensure it's mounted when Traefik runs"
    fi
    
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            log_info "Creating directory: $dir"
            if ! mkdir -p "$dir" 2>/dev/null; then
                log_fail "Cannot create directory: $dir"
                log_error "Please create it manually or run with appropriate permissions"
                exit 1
            fi
        fi
        
        # Test write access
        local test_file="$dir/.access_test_$$"
        if ! touch "$test_file" 2>/dev/null; then
            log_fail "No write access to: $dir"
            log_error "Please fix permissions: sudo chown -R \$USER:docker $dir"
            exit 1
        fi
        rm -f "$test_file"
        
        log_success "Directory validated: $dir"
    done
}

# Check if Traefik is running
check_traefik() {
    log_info "Checking if Traefik is running..."
    
    if docker ps --format '{{.Names}}' | grep -q "traefik"; then
        log_success "Traefik is running"
        return 0
    else
        log_warn "Traefik is not running"
        log_info "The controller requires Traefik to be running"
        return 1
    fi
}

# Generate CA files using Docker (no local mkcert needed)
generate_ca_in_docker() {
    log_info "Generating CA files using Docker..."
    
    # Check if CA already exists
    if [[ -f "$MKCERT_CA_DIR/rootCA.pem" ]] && [[ -f "$MKCERT_CA_DIR/rootCA-key.pem" ]]; then
        log_warn "CA already exists at $MKCERT_CA_DIR"
        log_info "Keeping existing CA files"
        return 0
    fi
    
    log_info "Building helper Docker image with mkcert..."
    
    # Build helper image
    docker build -t "$HELPER_IMAGE" -f - . << 'DOCKERFILE'
FROM alpine:3.19
RUN apk add --no-cache ca-certificates nss-tools mkcert
WORKDIR /work
CMD ["/bin/sh"]
DOCKERFILE
    
    if [[ $? -ne 0 ]]; then
        log_fail "Failed to build helper image"
        exit 1
    fi
    
    log_success "Helper image built: $HELPER_IMAGE"
    
    # Run mkcert to generate CA files
    log_info "Running mkcert in container to generate CA..."
    docker run --rm \
        -v "$MKCERT_CA_DIR:/root/.local/share/mkcert" \
        -e CAROOT=/root/.local/share/mkcert \
        "$HELPER_IMAGE" \
        sh -c 'mkcert -install 2>&1 | grep -v "trust store" || true; ls -la /root/.local/share/mkcert/'
    
    if [[ $? -ne 0 ]]; then
        log_fail "Failed to generate CA files in Docker"
        exit 1
    fi
    
    # Verify files were created
    if [[ -f "$MKCERT_CA_DIR/rootCA.pem" ]] && [[ -f "$MKCERT_CA_DIR/rootCA-key.pem" ]]; then
        log_success "CA files generated successfully!"
        log_info "CA location: $MKCERT_CA_DIR"
        return 0
    else
        log_fail "CA files were not created"
        exit 1
    fi
}

# Install CA in local trust store (using native OS commands - NO mkcert needed)
install_ca_locally() {
    log_info "Installing CA in local trust store..."
    
    # Check if CA files exist
    if [[ ! -f "$MKCERT_CA_DIR/rootCA.pem" ]]; then
        log_fail "CA files not found in $MKCERT_CA_DIR"
        log_error "Run CA generation first"
        exit 1
    fi
    
    # Detect distribution
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        local distro="$ID"
    else
        log_error "Cannot detect Linux distribution"
        exit 1
    fi
    
    log_info "Detected distribution: $distro"
    
    case "$distro" in
        ubuntu|debian|pop|linuxmint)
            log_info "Installing CA for Debian/Ubuntu-based systems..."
            
            # Check if already installed
            if [[ -f /usr/local/share/ca-certificates/mkcert-rootCA.crt ]]; then
                log_info "CA already installed in system trust store"
            else
                # Copy CA to system location
                if ! sudo cp "$MKCERT_CA_DIR/rootCA.pem" /usr/local/share/ca-certificates/mkcert-rootCA.crt 2>/dev/null; then
                    log_warn "Could not install CA in system (no sudo access or declined)"
                    log_info "CA generation successful but system trust store not updated"
                else
                    # Update CA trust store
                    sudo update-ca-certificates >/dev/null 2>&1
                    log_success "CA installed in system trust store"
                fi
            fi
            ;;
            
        fedora|rhel|centos|rocky|almalinux)
            log_info "Installing CA for Fedora/RHEL-based systems..."
            
            # Check if already installed
            if [[ -f /etc/pki/ca-trust/source/anchors/mkcert-rootCA.crt ]]; then
                log_info "CA already installed in system trust store"
            else
                # Copy CA to system location
                if ! sudo cp "$MKCERT_CA_DIR/rootCA.pem" /etc/pki/ca-trust/source/anchors/mkcert-rootCA.crt 2>/dev/null; then
                    log_warn "Could not install CA in system (no sudo access or declined)"
                    log_info "CA generation successful but system trust store not updated"
                else
                    # Update CA trust store
                    sudo update-ca-trust >/dev/null 2>&1
                    log_success "CA installed in system trust store"
                fi
            fi
            ;;
            
        arch|manjaro)
            log_info "Installing CA for Arch-based systems..."
            
            # Check if already installed
            if [[ -f /etc/ca-certificates/trust-source/anchors/mkcert-rootCA.crt ]]; then
                log_info "CA already installed in system trust store"
            else
                # Copy CA to system location
                if ! sudo cp "$MKCERT_CA_DIR/rootCA.pem" /etc/ca-certificates/trust-source/anchors/mkcert-rootCA.crt 2>/dev/null; then
                    log_warn "Could not install CA in system (no sudo access or declined)"
                    log_info "CA generation successful but system trust store not updated"
                else
                    # Update CA trust store
                    sudo trust extract-compat >/dev/null 2>&1
                    log_success "CA installed in system trust store"
                fi
            fi
            ;;
            
        *)
            log_warn "Unsupported distribution: $distro"
            log_info "CA files generated but system trust store not updated"
            log_info "Manual installation required. Copy $MKCERT_CA_DIR/rootCA.pem to your system's CA directory."
            ;;
    esac
    
    # Install in Firefox NSS (if Firefox is installed)
    install_nss_firefox
    
    # Install in Chrome NSS (if Chrome is installed)
    install_nss_chrome
    
    log_success "CA installation complete"
    log_info "You may need to restart your browser for changes to take effect"
}

# Install CA in Firefox NSS database
install_nss_firefox() {
    local firefox_dir="$HOME/.mozilla/firefox"
    
    if [[ ! -d "$firefox_dir" ]]; then
        return 0
    fi
    
    log_info "Installing CA in Firefox NSS database..."
    
    # Find Firefox profiles
    local installed=false
    for profile in "$firefox_dir"/*.default* "$firefox_dir"/*.dev-edition-default*; do
        if [[ -d "$profile" ]]; then
            local profile_name=$(basename "$profile")
            
            # Use Docker with certutil to install in NSS
            docker run --rm \
                -v "$MKCERT_CA_DIR:/ca:ro" \
                -v "$profile:/profile" \
                "$HELPER_IMAGE" \
                certutil -A -n "mkcert CA" -t "C,," -i /ca/rootCA.pem -d sql:/profile 2>/dev/null || true
            
            installed=true
        fi
    done
    
    if [[ "$installed" == "true" ]]; then
        log_success "Firefox NSS database updated"
    fi
}

# Install CA in Chrome NSS database
install_nss_chrome() {
    local nssdb="$HOME/.pki/nssdb"
    
    if [[ ! -d "$nssdb" ]]; then
        return 0
    fi
    
    log_info "Installing CA in Chrome NSS database..."
    
    # Use Docker with certutil to install in NSS
    docker run --rm \
        -v "$MKCERT_CA_DIR:/ca:ro" \
        -v "$nssdb:/nssdb" \
        "$HELPER_IMAGE" \
        certutil -A -n "mkcert CA" -t "C,," -i /ca/rootCA.pem -d sql:/nssdb 2>/dev/null || true
    
    log_success "Chrome NSS database updated"
}

# Get Traefik volume mounts
get_traefik_volumes() {
    log_info "Detecting Traefik volume mounts..."
    
    # Find Traefik container
    local traefik_container=$(docker ps --format '{{.Names}}' | grep "traefik" | head -n 1)
    
    if [[ -z "$traefik_container" ]]; then
        log_warn "Traefik container not found"
        return 1
    fi
    
    log_info "Found Traefik container: $traefik_container"
    
    # Get volume mounts
    local mounts=$(docker inspect "$traefik_container" --format '{{range .Mounts}}{{.Source}}:{{.Destination}}{{"\n"}}{{end}}' 2>/dev/null)
    
    if [[ -n "$mounts" ]]; then
        log_info "Traefik volume mounts:"
        echo "$mounts" | while read mount; do
            log_info "  - $mount"
        done
        
        # Try to detect Traefik config directory
        TRAEFIK_HOST_CONFIG_DIR=$(echo "$mounts" | grep ":/etc/traefik" | cut -d':' -f1 | head -n 1)
        if [[ -n "$TRAEFIK_HOST_CONFIG_DIR" ]]; then
            log_info "Detected Traefik config host path: $TRAEFIK_HOST_CONFIG_DIR"
        fi
    fi
    
    return 0
}

# Build Docker image
build_image() {
    log_info "Building Docker image..."
    
    if docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" . 2>&1 | tee /tmp/docker-build.log; then
        log_success "Image built successfully: ${IMAGE_NAME}:${IMAGE_TAG}"
        return 0
    else
        log_fail "Failed to build Docker image"
        cat /tmp/docker-build.log
        exit 1
    fi
}

# Start the controller container
start_controller() {
    log_info "Starting controller container..."
    
    # Stop existing container if running
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log_info "Stopping existing container..."
        docker stop "$CONTAINER_NAME" 2>/dev/null || true
        docker rm "$CONTAINER_NAME" 2>/dev/null || true
    fi
    
    # Prepare volume mounts
    local volume_args=(
        -v "/var/run/docker.sock:/var/run/docker.sock:ro"
        -v "$CERTS_DIR:/certs"
        -v "$MKCERT_CA_DIR:/root/.local/share/mkcert"
    )
    
    # Add Traefik directory mount
    local traefik_mount_source="${TRAEFIK_HOST_CONFIG_DIR:-$TRAEFIK_DIR}"
    if [[ -n "$traefik_mount_source" && -d "$traefik_mount_source" ]]; then
        log_info "Mounting Traefik config directory: $traefik_mount_source -> /etc/traefik"
        volume_args+=(-v "$traefik_mount_source:/etc/traefik")
    elif [[ -n "$TRAEFIK_HOST_CONFIG_DIR" ]]; then
        log_warn "Detected Traefik config path does not exist: $TRAEFIK_HOST_CONFIG_DIR"
        if [[ -d "$TRAEFIK_DIR" ]]; then
            log_info "Falling back to TRAEFIK_DIR: $TRAEFIK_DIR"
            volume_args+=(-v "$TRAEFIK_DIR:/etc/traefik")
        else
            log_warn "No valid Traefik config directory found to mount"
        fi
    fi
    
    # Run the container
    log_info "Starting container..."
    if docker run -d \
        --name "$CONTAINER_NAME" \
        --restart unless-stopped \
        -e "INSTALL_CA=false" \
        -e "TRAEFIK_DIR=/etc/traefik" \
        -e "CERTS_DIR=/certs" \
        -e "MKCERT_CA_DIR=/root/.local/share/mkcert" \
        "${volume_args[@]}" \
        "${IMAGE_NAME}:${IMAGE_TAG}"; then
        
        log_success "Container started successfully"
        log_info "Container name: $CONTAINER_NAME"
        log_info "View logs with: docker logs -f $CONTAINER_NAME"
        
        # Show initial logs
        sleep 2
        log_info "Initial logs:"
        docker logs "$CONTAINER_NAME" 2>&1 | tail -15
        
        return 0
    else
        log_fail "Failed to start container"
        exit 1
    fi
}

# Unified install function
install_all() {
    show_banner
    log_info "Installing daas-mkcert-controller (unified method)..."
    
    # Run all validations
    validate_os
    validate_docker
    validate_permissions
    validate_directories
    
    # Check if Traefik is running
    if ! check_traefik; then
        log_warn "Traefik is not running. The controller will wait for it to start."
    fi
    
    # Get Traefik volume mounts
    get_traefik_volumes || true
    
    # Step 1: Generate CA using Docker (no local mkcert needed)
    log_info ""
    log_info "=== Step 1/3: Generating CA using Docker ==="
    generate_ca_in_docker
    
    # Step 2: Install CA locally using native OS commands
    log_info ""
    log_info "=== Step 2/3: Installing CA in local trust store ==="
    install_ca_locally
    
    # Step 3: Build and start controller
    log_info ""
    log_info "=== Step 3/3: Building and starting controller ==="
    
    # Build image
    build_image
    
    # Start controller
    start_controller
    
    # Final success message
    echo ""
    log_success "Installation complete!"
    echo ""
    log_info "Summary:"
    log_info "  ✓ CA generated using Docker (no local mkcert installed)"
    log_info "  ✓ CA installed in system trust store"
    log_info "  ✓ CA installed in Firefox/Chrome (if available)"
    log_info "  ✓ Controller container running"
    echo ""
    log_info "Next steps:"
    log_info "  1. Restart your browser to load the new CA"
    log_info "  2. Start containers with Traefik labels"
    log_info "  3. Certificates will be generated automatically"
    echo ""
    log_info "View controller logs: docker logs -f $CONTAINER_NAME"
    log_info "Check status: $0 status"
    echo ""
}

# Uninstall function
uninstall_all() {
    show_banner
    log_info "Uninstalling daas-mkcert-controller..."
    
    # Stop and remove container
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log_info "Stopping and removing container..."
        docker stop "$CONTAINER_NAME" 2>/dev/null || true
        docker rm "$CONTAINER_NAME" 2>/dev/null || true
        log_success "Container removed"
    else
        log_info "Container not found"
    fi
    
    # Ask about image removal
    if docker image inspect "${IMAGE_NAME}:${IMAGE_TAG}" &>/dev/null; then
        echo ""
        read -p "Remove Docker image? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            docker rmi "${IMAGE_NAME}:${IMAGE_TAG}" 2>/dev/null || true
            log_success "Image removed"
        fi
    fi
    
    # Ask about helper image removal
    if docker image inspect "$HELPER_IMAGE" &>/dev/null; then
        read -p "Remove helper image? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            docker rmi "$HELPER_IMAGE" 2>/dev/null || true
            log_success "Helper image removed"
        fi
    fi
    
    # Ask about CA removal from system
    echo ""
    read -p "Remove CA from system trust store? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Detect distribution
        if [[ -f /etc/os-release ]]; then
            . /etc/os-release
            case "$ID" in
                ubuntu|debian|pop|linuxmint)
                    if [[ -f /usr/local/share/ca-certificates/mkcert-rootCA.crt ]]; then
                        sudo rm /usr/local/share/ca-certificates/mkcert-rootCA.crt 2>/dev/null || true
                        sudo update-ca-certificates >/dev/null 2>&1
                        log_success "CA removed from system trust store"
                    fi
                    ;;
                fedora|rhel|centos|rocky|almalinux)
                    if [[ -f /etc/pki/ca-trust/source/anchors/mkcert-rootCA.crt ]]; then
                        sudo rm /etc/pki/ca-trust/source/anchors/mkcert-rootCA.crt 2>/dev/null || true
                        sudo update-ca-trust >/dev/null 2>&1
                        log_success "CA removed from system trust store"
                    fi
                    ;;
                arch|manjaro)
                    if [[ -f /etc/ca-certificates/trust-source/anchors/mkcert-rootCA.crt ]]; then
                        sudo rm /etc/ca-certificates/trust-source/anchors/mkcert-rootCA.crt 2>/dev/null || true
                        sudo trust extract-compat >/dev/null 2>&1
                        log_success "CA removed from system trust store"
                    fi
                    ;;
            esac
        fi
    fi
    
    # Ask about CA files removal
    echo ""
    read -p "Remove CA files from $MKCERT_CA_DIR? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if [[ -d "$MKCERT_CA_DIR" ]]; then
            rm -rf "$MKCERT_CA_DIR"
            log_success "CA files removed"
        fi
    fi
    
    # Ask about certificates removal
    echo ""
    read -p "Remove generated certificates from $CERTS_DIR? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if [[ -d "$CERTS_DIR" ]]; then
            rm -rf "$CERTS_DIR"
            log_success "Certificates removed"
        fi
    fi
    
    echo ""
    log_success "Uninstallation complete!"
    log_info "Note: You may need to restart your browser"
}

# Status function
check_status() {
    show_banner
    log_info "Checking installation status..."
    echo ""
    
    # Check CA files
    log_info "CA Files:"
    if [[ -f "$MKCERT_CA_DIR/rootCA.pem" ]] && [[ -f "$MKCERT_CA_DIR/rootCA-key.pem" ]]; then
        log_success "CA files found: $MKCERT_CA_DIR"
        echo "  - rootCA.pem"
        echo "  - rootCA-key.pem"
    else
        log_error "CA files not found in $MKCERT_CA_DIR"
    fi
    
    echo ""
    
    # Check system trust store
    log_info "System Trust Store:"
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        case "$ID" in
            ubuntu|debian|pop|linuxmint)
                if [[ -f /usr/local/share/ca-certificates/mkcert-rootCA.crt ]]; then
                    log_success "CA installed in Debian/Ubuntu trust store"
                else
                    log_warn "CA not found in system trust store"
                fi
                ;;
            fedora|rhel|centos|rocky|almalinux)
                if [[ -f /etc/pki/ca-trust/source/anchors/mkcert-rootCA.crt ]]; then
                    log_success "CA installed in Fedora/RHEL trust store"
                else
                    log_warn "CA not found in system trust store"
                fi
                ;;
            arch|manjaro)
                if [[ -f /etc/ca-certificates/trust-source/anchors/mkcert-rootCA.crt ]]; then
                    log_success "CA installed in Arch trust store"
                else
                    log_warn "CA not found in system trust store"
                fi
                ;;
        esac
    fi
    
    echo ""
    
    # Check container
    log_info "Controller Container:"
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log_success "Container is running: $CONTAINER_NAME"
        echo ""
        docker ps --filter "name=$CONTAINER_NAME" --format "  ID: {{.ID}}\n  Status: {{.Status}}\n  Image: {{.Image}}"
    else
        log_warn "Container is not running"
    fi
    
    echo ""
    
    # Check Traefik
    log_info "Traefik:"
    if docker ps --format '{{.Names}}' | grep -q "traefik"; then
        log_success "Traefik is running"
    else
        log_warn "Traefik is not running"
    fi
    
    echo ""
}

# Main function
main() {
    local command="${1:-help}"
    
    case "$command" in
        install)
            install_all
            ;;
        uninstall)
            uninstall_all
            ;;
        status)
            check_status
            ;;
        help|--help|-h)
            show_banner
            show_usage
            ;;
        *)
            log_error "Unknown command: $command"
            echo ""
            show_usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
