#!/bin/bash

#############################################################################
# daas-mkcert-controller installer
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
#   ./install.sh install   - Install everything
#   ./install.sh uninstall - Remove everything
#   ./install.sh status    - Check status
#   ./install.sh logs      - Show controller logs
#   ./install.sh help      - Show this help message
#############################################################################

set -e

# Script version
VERSION="1.4.0"

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
INSTALL_CA="${INSTALL_CA:-true}"
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
    local ver_right="v${VERSION} "
    local ver_pad=$(( TOTAL_WIDTH - ${#ver_right} ))
    printf "${PURPLE_BG}%${ver_pad}s${ver_right}${RST}\n" ""

    echo ""
}

# Show usage
show_usage() {
    cat << EOF
Usage: $0 [command] [options]

Commands:
    install     Install everything (CA + controller)
    uninstall   Remove everything (CA + controller)
    status      Check installation status
    logs        Show controller logs
    help        Show this help message

Options:
    --install-ca=VALUE      Set CA installation (true/false/yes/no/si/no/1/0/t/f/y/n/s/n)
    --disable-install-ca    Disable automatic CA installation (alias for --install-ca=false)

Environment Variables:
    CONTAINER_NAME      Container name (default: daas-mkcert-controller)
    IMAGE_NAME          Docker image name (default: daas-mkcert-controller)
    IMAGE_TAG           Docker image tag (default: latest)
    INSTALL_CA          Install CA in trust store (default: true)
                        Accepted values: true/false, yes/no, si/no, 1/0, t/f, y/n, s/n
    TRAEFIK_DIR         Traefik config directory
                        Default (root):     /etc/traefik
                        Default (non-root): ~/.traefik
    CERTS_DIR           Certificates directory
                        Default (root):     /var/lib/daas-mkcert/certs
                        Default (non-root): ~/.daas-mkcert/certs
    MKCERT_CA_DIR       mkcert CA directory (default: ~/.local/share/mkcert)

Priority:
    Command-line arguments > Environment variables > Default values

Features:
    ✓ No local mkcert installation required
    ✓ Generates CA using Docker container
    ✓ Installs CA using native OS commands
    ✓ Single unified process
    ✓ Minimal dependencies (Docker only)

Examples:
    # Install everything
    $0 install

    # Install without CA installation
    $0 install --disable-install-ca
    $0 install --install-ca=false
    INSTALL_CA=false $0 install

    # Install with custom directories
    TRAEFIK_DIR=/custom/traefik CERTS_DIR=/custom/certs $0 install

    # Check status
    $0 status

    # Uninstall everything
    $0 uninstall

    # Install via curl (single command)
    curl -fsSL <script-url> | bash

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

# Validate environment variables
validate_environment() {
    log_info "Validating environment variables..."
    
    # Check required paths are not empty
    if [[ -z "$TRAEFIK_DIR" ]]; then
        log_fail "TRAEFIK_DIR cannot be empty"
        exit 1
    fi
    
    if [[ -z "$CERTS_DIR" ]]; then
        log_fail "CERTS_DIR cannot be empty"
        exit 1
    fi
    
    # Validate INSTALL_CA is boolean
    local install_ca_lower=$(echo "$INSTALL_CA" | tr '[:upper:]' '[:lower:]')
    if [[ "$install_ca_lower" =~ ^(1|t(rue)?|s(i)?|y(es)?)$ ]]; then
        INSTALL_CA="true"
    elif [[ "$install_ca_lower" =~ ^(0|f(alse)?|n(o)?)$ ]]; then
        INSTALL_CA="false"
    else
        log_fail "Invalid value for INSTALL_CA: '$INSTALL_CA'. Use true/false, yes/no, si/no, 1/0"
        exit 1
    fi
    
    log_success "Environment variables validated"
    
    log_info "Configuration:"
    log_info "  CONTAINER_NAME: $CONTAINER_NAME"
    log_info "  IMAGE_NAME: $IMAGE_NAME"
    log_info "  INSTALL_CA: $INSTALL_CA"
    log_info "  TRAEFIK_DIR: $TRAEFIK_DIR"
    log_info "  CERTS_DIR: $CERTS_DIR"
    log_info "  MKCERT_CA_DIR: $MKCERT_CA_DIR"
}

# Check if Traefik is running
check_traefik() {
    log_info "Checking if Traefik is running..."
    
    if docker ps --format '{{.Names}}' | grep -q "traefik" || \
       docker ps --format '{{.Image}}' | grep -q "traefik"; then
        log_success "Traefik is running"
        return 0
    else
        log_warn "Traefik is not running"
        log_info "The controller requires Traefik to be running"
        return 1
    fi
}

# Build or reuse the helper Docker image (openssl + nss-tools)
# This image is needed for CA generation AND for NSS trust store operations
ensure_helper_image() {
    # Check if helper image already exists
    if docker image inspect "$HELPER_IMAGE" &>/dev/null; then
        log_info "Helper image already available: $HELPER_IMAGE"
        return 0
    fi
    
    log_info "Building helper Docker image with openssl + nss-tools..."
    
    # Build helper image
    docker build -t "$HELPER_IMAGE" -f - . << 'DOCKERFILE'
FROM alpine:3.19
RUN apk add --no-cache ca-certificates nss-tools openssl
WORKDIR /work
CMD ["/bin/sh"]
DOCKERFILE
    
    if [[ $? -ne 0 ]]; then
        log_fail "Failed to build helper image"
        exit 1
    fi
    
    log_success "Helper image built: $HELPER_IMAGE"
}

# Generate CA files using Docker (openssl-based, no mkcert needed)
generate_ca_in_docker() {
    log_info "Generating CA files using Docker..."
    
    # Check if CA already exists
    if [[ -f "$MKCERT_CA_DIR/rootCA.pem" ]] && [[ -f "$MKCERT_CA_DIR/rootCA-key.pem" ]]; then
        log_warn "CA already exists at $MKCERT_CA_DIR"
        log_info "Keeping existing CA files"
        return 0
    fi
    
    # Build helper image if needed
    ensure_helper_image
    
    # Generate CA certificate with openssl using custom subject
    local ca_subject="/CN=DAAS Development CA/O=DAAS Consulting/OU=daas-mkcert-controller v${VERSION}"
    log_info "Generating CA with openssl (subject: ${ca_subject})..."
    docker run --rm \
        -v "$MKCERT_CA_DIR:/ca" \
        "$HELPER_IMAGE" \
        sh -c "openssl genrsa -out /ca/rootCA-key.pem 4096 2>/dev/null && openssl req -x509 -new -nodes -key /ca/rootCA-key.pem -sha256 -days 3650 -out /ca/rootCA.pem -subj '${ca_subject}' && ls -la /ca/"
    
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
    
    # Compute CA fingerprint for unique identification
    local ca_fingerprint
    ca_fingerprint=$(openssl x509 -in "$MKCERT_CA_DIR/rootCA.pem" -noout -fingerprint -sha256 2>/dev/null | sed 's/.*=//;s/://g' | tr '[:upper:]' '[:lower:]')
    local ca_short_fp="${ca_fingerprint:0:16}"
    local ca_cert_name="daas-mkcert-rootCA-${ca_short_fp}.crt"
    log_info "CA fingerprint (SHA-256): ${ca_fingerprint}"
    log_info "CA trust store filename: ${ca_cert_name}"
    
    # Detect distribution
    if [[ -f /etc/os-release ]]; then
        local _saved_version="$VERSION"
        . /etc/os-release
        local distro="$ID"
        VERSION="$_saved_version"
    else
        log_error "Cannot detect Linux distribution"
        exit 1
    fi
    
    log_info "Detected distribution: $distro"
    
    case "$distro" in
        ubuntu|debian|pop|linuxmint)
            log_info "Installing CA for Debian/Ubuntu-based systems..."
            local ca_dest="/usr/local/share/ca-certificates/${ca_cert_name}"
            
            # Remove old CA files from previous installations
            for old_ca in /usr/local/share/ca-certificates/daas-mkcert-rootCA*.crt /usr/local/share/ca-certificates/mkcert-rootCA.crt; do
                if [[ -f "$old_ca" ]] && [[ "$old_ca" != "$ca_dest" ]]; then
                    log_info "Removing old CA: $old_ca"
                    sudo rm -f "$old_ca" 2>/dev/null || true
                fi
            done
            
            # Check if already installed with current fingerprint
            if [[ -f "$ca_dest" ]]; then
                log_info "CA already installed in system trust store (${ca_cert_name})"
            else
                # Copy CA to system location
                if ! sudo cp "$MKCERT_CA_DIR/rootCA.pem" "$ca_dest" 2>/dev/null; then
                    log_warn "Could not install CA in system (no sudo access or declined)"
                    log_info "CA generation successful but system trust store not updated"
                else
                    # Update CA trust store
                    sudo update-ca-certificates >/dev/null 2>&1
                    log_success "CA installed in system trust store as ${ca_cert_name}"
                fi
            fi
            ;;
            
        fedora|rhel|centos|rocky|almalinux)
            log_info "Installing CA for Fedora/RHEL-based systems..."
            local ca_dest="/etc/pki/ca-trust/source/anchors/${ca_cert_name}"
            
            # Remove old CA files from previous installations
            for old_ca in /etc/pki/ca-trust/source/anchors/daas-mkcert-rootCA*.crt /etc/pki/ca-trust/source/anchors/mkcert-rootCA.crt; do
                if [[ -f "$old_ca" ]] && [[ "$old_ca" != "$ca_dest" ]]; then
                    log_info "Removing old CA: $old_ca"
                    sudo rm -f "$old_ca" 2>/dev/null || true
                fi
            done
            
            # Check if already installed with current fingerprint
            if [[ -f "$ca_dest" ]]; then
                log_info "CA already installed in system trust store (${ca_cert_name})"
            else
                # Copy CA to system location
                if ! sudo cp "$MKCERT_CA_DIR/rootCA.pem" "$ca_dest" 2>/dev/null; then
                    log_warn "Could not install CA in system (no sudo access or declined)"
                    log_info "CA generation successful but system trust store not updated"
                else
                    # Update CA trust store
                    sudo update-ca-trust >/dev/null 2>&1
                    log_success "CA installed in system trust store as ${ca_cert_name}"
                fi
            fi
            ;;
            
        arch|manjaro)
            log_info "Installing CA for Arch-based systems..."
            local ca_dest="/etc/ca-certificates/trust-source/anchors/${ca_cert_name}"
            
            # Remove old CA files from previous installations
            for old_ca in /etc/ca-certificates/trust-source/anchors/daas-mkcert-rootCA*.crt /etc/ca-certificates/trust-source/anchors/mkcert-rootCA.crt; do
                if [[ -f "$old_ca" ]] && [[ "$old_ca" != "$ca_dest" ]]; then
                    log_info "Removing old CA: $old_ca"
                    sudo rm -f "$old_ca" 2>/dev/null || true
                fi
            done
            
            # Check if already installed with current fingerprint
            if [[ -f "$ca_dest" ]]; then
                log_info "CA already installed in system trust store (${ca_cert_name})"
            else
                # Copy CA to system location
                if ! sudo cp "$MKCERT_CA_DIR/rootCA.pem" "$ca_dest" 2>/dev/null; then
                    log_warn "Could not install CA in system (no sudo access or declined)"
                    log_info "CA generation successful but system trust store not updated"
                else
                    # Update CA trust store
                    sudo trust extract-compat >/dev/null 2>&1
                    log_success "CA installed in system trust store as ${ca_cert_name}"
                fi
            fi
            ;;
            
        *)
            log_warn "Unsupported distribution: $distro"
            log_info "CA files generated but system trust store not updated"
            log_info "Manual installation required. Copy $MKCERT_CA_DIR/rootCA.pem to your system's CA directory."
            ;;
    esac
    
    # Build or reuse helper image for NSS operations (certutil)
    ensure_helper_image
    
    # Install in Firefox NSS (if Firefox is installed)
    install_nss_firefox
    
    # Install in Chrome NSS (if Chrome/Chromium is installed)
    install_nss_chrome
    
    log_success "CA installation complete"
    log_info "You may need to restart your browser for changes to take effect"
}

# Install CA in Firefox NSS database
# Supports standard, snap, and flatpak Firefox installations
install_nss_firefox() {
    # Candidate Firefox profile directories
    local firefox_dirs=(
        "$HOME/.mozilla/firefox"
        "$HOME/snap/firefox/common/.mozilla/firefox"
        "$HOME/.var/app/org.mozilla.firefox/.mozilla/firefox"
    )
    
    local found_any=false
    for firefox_dir in "${firefox_dirs[@]}"; do
        if [[ -d "$firefox_dir" ]]; then
            found_any=true
            break
        fi
    done
    
    if [[ "$found_any" == "false" ]]; then
        log_info "No Firefox profile directory found, skipping Firefox NSS"
        return 0
    fi
    
    log_info "Installing CA in Firefox NSS database..."
    
    local installed=false
    for firefox_dir in "${firefox_dirs[@]}"; do
        [[ ! -d "$firefox_dir" ]] && continue
        
        for profile in "$firefox_dir"/*.default* "$firefox_dir"/*.dev-edition-default*; do
            if [[ -d "$profile" ]]; then
                local profile_name=$(basename "$profile")
                log_info "  Updating profile: $profile_name"
                
                if docker run --rm \
                    -v "$MKCERT_CA_DIR:/ca:ro" \
                    -v "$profile:/profile" \
                    "$HELPER_IMAGE" \
                    certutil -A -n "mkcert CA" -t "C,," -i /ca/rootCA.pem -d sql:/profile 2>&1; then
                    installed=true
                else
                    log_warn "  Failed to update Firefox profile: $profile_name"
                fi
            fi
        done
    done
    
    if [[ "$installed" == "true" ]]; then
        log_success "Firefox NSS database updated"
    else
        log_warn "No Firefox profiles updated (no profiles found or all failed)"
    fi
}

# Install CA in Chrome/Chromium NSS database
install_nss_chrome() {
    local nssdb="$HOME/.pki/nssdb"
    
    if [[ ! -d "$nssdb" ]]; then
        log_info "Chrome NSS directory not found ($nssdb), skipping Chrome NSS"
        return 0
    fi
    
    log_info "Installing CA in Chrome/Chromium NSS database..."
    
    if docker run --rm \
        -v "$MKCERT_CA_DIR:/ca:ro" \
        -v "$nssdb:/nssdb" \
        "$HELPER_IMAGE" \
        certutil -A -n "mkcert CA" -t "C,," -i /ca/rootCA.pem -d sql:/nssdb 2>&1; then
        log_success "Chrome/Chromium NSS database updated"
    else
        log_fail "Failed to install CA in Chrome/Chromium NSS database"
        log_warn "You may need to manually import the CA in Chrome:"
        log_warn "  Settings > Privacy and Security > Security > Manage certificates > Authorities > Import"
        log_warn "  File: $MKCERT_CA_DIR/rootCA.pem"
    fi
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

# Validate Traefik static configuration (providers.file)
validate_traefik_config() {
    log_info "Validating Traefik static configuration..."

    local traefik_config_dir="${TRAEFIK_HOST_CONFIG_DIR:-$TRAEFIK_DIR}"
    local config_file=""

    # Find config file
    for name in traefik.yml traefik.yaml traefik.toml; do
        if [[ -f "$traefik_config_dir/$name" ]]; then
            config_file="$traefik_config_dir/$name"
            break
        fi
    done

    if [[ -z "$config_file" ]]; then
        log_warn "No Traefik static configuration file found in $traefik_config_dir"
        log_info "The controller will create the necessary configuration at runtime"
        return 0
    fi

    log_info "Found Traefik config: $config_file"

    # Ensure dynamic directory exists
    local dynamic_dir="$traefik_config_dir/dynamic"
    if [[ ! -d "$dynamic_dir" ]]; then
        log_info "Creating dynamic config directory: $dynamic_dir"
        mkdir -p "$dynamic_dir" 2>/dev/null || true
    fi

    # Check if providers.file.directory is already set correctly
    # Simple grep-based check for YAML files
    if grep -q "directory:.*\/etc\/traefik\/dynamic" "$config_file" 2>/dev/null && \
       grep -q "watch:.*true" "$config_file" 2>/dev/null; then
        log_success "Traefik configuration already has the expected providers.file setup"
        return 0
    fi

    # Config needs updating
    log_warn "Traefik configuration does not match expected providers.file setup"
    log_info "Expected configuration:"
    log_info "  providers:"
    log_info "    file:"
    log_info "      directory: /etc/traefik/dynamic"
    log_info "      watch: true"

    # Create backup
    local timestamp
    timestamp=$(date +"%Y%m%d-%H%M%S")
    local ext="${config_file##*.}"
    local base="${config_file%.*}"
    local backup_file="${base}-${timestamp}.${ext}.bak"

    cp "$config_file" "$backup_file"
    log_success "Backup created: $backup_file"

    # Merge providers.file into existing providers block (preserving other providers)
    local tmp_file
    tmp_file=$(mktemp)
    local has_providers=false
    local in_providers=false
    local in_file_block=false
    local providers_indent=-1
    local file_block_indent=-1
    local file_block_replaced=false
    local file_block_added=false

    # First pass: check if providers: block exists
    if grep -q "^[[:space:]]*providers[[:space:]]*:" "$config_file" 2>/dev/null; then
        has_providers=true
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        local trimmed="${line#"${line%%[![:space:]]*}"}"
        local indent=$(( ${#line} - ${#trimmed} ))

        if [[ "$has_providers" == false ]]; then
            # No providers block exists, just copy everything
            echo "$line" >> "$tmp_file"
            continue
        fi

        if [[ "$in_providers" == false ]]; then
            if [[ "$trimmed" =~ ^providers[[:space:]]*: ]]; then
                in_providers=true
                providers_indent=$indent
                echo "$line" >> "$tmp_file"
                continue
            fi
            echo "$line" >> "$tmp_file"
        else
            # Inside providers block
            if [[ -z "$trimmed" || "$trimmed" =~ ^# ]]; then
                echo "$line" >> "$tmp_file"
                continue
            fi

            if (( indent <= providers_indent )); then
                # We've left the providers block
                # If we never found/replaced file: sub-block, add it now
                if [[ "$file_block_replaced" == false && "$file_block_added" == false ]]; then
                    local p_indent=""
                    for (( i=0; i<providers_indent+2; i++ )); do p_indent+=" "; done
                    echo "${p_indent}# Added by daas-mkcert-controller" >> "$tmp_file"
                    echo "${p_indent}file:" >> "$tmp_file"
                    echo "${p_indent}  directory: /etc/traefik/dynamic" >> "$tmp_file"
                    echo "${p_indent}  watch: true" >> "$tmp_file"
                    file_block_added=true
                fi
                in_providers=false
                in_file_block=false
                echo "$line" >> "$tmp_file"
                continue
            fi

            # Still inside providers block (indent > providers_indent)
            if [[ "$in_file_block" == false ]]; then
                if [[ "$trimmed" =~ ^file[[:space:]]*: ]]; then
                    in_file_block=true
                    file_block_indent=$indent
                    # Replace file: block with correct values
                    local p_indent=""
                    for (( i=0; i<indent; i++ )); do p_indent+=" "; done
                    echo "# Modified by daas-mkcert-controller" >> "$tmp_file"
                    echo "${p_indent}file:" >> "$tmp_file"
                    echo "${p_indent}  directory: /etc/traefik/dynamic" >> "$tmp_file"
                    echo "${p_indent}  watch: true" >> "$tmp_file"
                    file_block_replaced=true
                    continue
                fi
                echo "$line" >> "$tmp_file"
            else
                # Inside file: sub-block, skip old lines
                if (( indent > file_block_indent )); then
                    # Skip old file: sub-block content
                    continue
                else
                    # Left file: sub-block
                    in_file_block=false
                    if [[ "$trimmed" =~ ^file[[:space:]]*: ]]; then
                        # Another file: block? Shouldn't happen, but handle gracefully
                        continue
                    fi
                    echo "$line" >> "$tmp_file"
                fi
            fi
        fi
    done < "$config_file"

    # Handle end-of-file cases
    if [[ "$has_providers" == false ]]; then
        # No providers block existed, append a complete one
        {
            echo ""
            echo "# Added by daas-mkcert-controller"
            echo "providers:"
            echo "  file:"
            echo "    directory: /etc/traefik/dynamic"
            echo "    watch: true"
        } >> "$tmp_file"
    elif [[ "$in_providers" == true && "$file_block_replaced" == false && "$file_block_added" == false ]]; then
        # providers block was the last block and we never added file:
        local p_indent=""
        for (( i=0; i<providers_indent+2; i++ )); do p_indent+=" "; done
        echo "${p_indent}# Added by daas-mkcert-controller" >> "$tmp_file"
        echo "${p_indent}file:" >> "$tmp_file"
        echo "${p_indent}  directory: /etc/traefik/dynamic" >> "$tmp_file"
        echo "${p_indent}  watch: true" >> "$tmp_file"
    fi

    mv "$tmp_file" "$config_file"

    log_success "Traefik configuration updated (providers.file merged)"
    log_info "Existing provider configurations have been preserved"
    log_warn "Traefik needs to be restarted to apply the new configuration"

    # Find Traefik container name for restart command
    local traefik_name
    traefik_name=$(docker ps --format '{{.Names}}' | grep "traefik" | head -n 1)
    if [[ -n "$traefik_name" ]]; then
        log_warn "Run: docker restart $traefik_name"
    else
        log_warn "Run: docker restart <traefik-container-name>"
    fi

    return 0
}

# Revert Traefik configuration changes made by this tool
revert_traefik_config() {
    log_info "Checking for Traefik configuration changes to revert..."

    local traefik_config_dir="${TRAEFIK_HOST_CONFIG_DIR:-$TRAEFIK_DIR}"
    local config_file=""

    # Find config file
    for name in traefik.yml traefik.yaml traefik.toml; do
        if [[ -f "$traefik_config_dir/$name" ]]; then
            config_file="$traefik_config_dir/$name"
            break
        fi
    done

    if [[ -z "$config_file" ]]; then
        log_info "No Traefik config file found, nothing to revert"
        return 0
    fi

    # Check if the config was modified by this tool
    if ! grep -qE "# (Modified|Added) by daas-mkcert-controller" "$config_file" 2>/dev/null; then
        log_info "Traefik config was not modified by this tool, nothing to revert"
        return 0
    fi

    # Find the latest backup
    local ext="${config_file##*.}"
    local base="${config_file%.*}"
    local latest_backup=""

    for f in "${base}"-*."${ext}".bak; do
        if [[ -f "$f" ]]; then
            latest_backup="$f"
        fi
    done

    if [[ -z "$latest_backup" ]]; then
        log_warn "No backup file found to restore"
        return 1
    fi

    log_info "Found backup to restore: $latest_backup"
    cp "$latest_backup" "$config_file"
    log_success "Traefik configuration reverted from backup: $latest_backup"
    log_warn "Traefik needs to be restarted to apply the reverted configuration"

    local traefik_name
    traefik_name=$(docker ps --format '{{.Names}}' | grep "traefik" | head -n 1)
    if [[ -n "$traefik_name" ]]; then
        log_warn "Run: docker restart $traefik_name"
    else
        log_warn "Run: docker restart <traefik-container-name>"
    fi

    return 0
}

# Create project files if running from stdin (curl | bash) or files are missing
create_project_files() {
    local work_dir="$1"
    
    log_info "Creating project files in $work_dir..."
    
    # Create package.json
    cat > "$work_dir/package.json" << 'PACKAGE_JSON_EOF'
{
  "name": "daas-mkcert-controller",
  "version": "1.4.0",
  "description": "Docker service for local development that detects *.localhost domains used by Traefik, generates valid TLS certificates with openssl, and keeps TLS configuration synchronized without restarting Traefik",
  "main": "index.js",
  "scripts": {
    "start": "node index.js",
    "test": "node parseBool.test.js && node validateConfig.test.js && node traefikLabels.test.js && node buildTLSConfig.test.js && node validateCertificates.test.js && node certSubject.test.js && node opensslCert.test.js"
  },
  "keywords": [
    "docker",
    "traefik",
    "openssl",
    "tls",
    "certificates",
    "localhost"
  ],
  "author": "DAAS Consulting",
  "license": "MIT",
  "dependencies": {
    "chokidar": "^3.5.3",
    "dockerode": "^4.0.0"
  }
}
PACKAGE_JSON_EOF

    # Create Dockerfile
    cat > "$work_dir/Dockerfile" << 'DOCKERFILE_EOF'
FROM node:24.13.0-alpine

# Install required tools (openssl replaces mkcert for certificate generation)
RUN apk add --no-cache \
    ca-certificates \
    openssl

# Create app directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm install --production

# Copy application code
COPY index.js banner.js parseBool.js validateConfig.js traefikLabels.js buildTLSConfig.js validateCertificates.js certSubject.js opensslCert.js ./

# Create directories for certificates
RUN mkdir -p /etc/traefik/dynamic/certs

# Run as root to access Docker socket and install CA if needed
USER root

# Start the application
CMD ["node", "index.js"]
DOCKERFILE_EOF

    # Create index.js (embedded)
    cat > "$work_dir/index.js" << 'INDEX_JS_EOF'
#!/usr/bin/env node

const Docker = require('dockerode');
const chokidar = require('chokidar');
const fs = require('fs');
const path = require('path');
const os = require('os');
const { printBanner, isBannerShown } = require('./banner');
const { parseBool } = require('./parseBool');
const { validateNotEmpty, validateDirectory } = require('./validateConfig');
const { parseTraefikLabels, extractDomainsFromLabels } = require('./traefikLabels');
const { buildTLSConfig } = require('./buildTLSConfig');
const { validateExistingCertificates, removeInvalidCertificates, getCAFingerprint } = require('./validateCertificates');
const { extractContainerMetadata, buildLeafSubject } = require('./certSubject');
const { generateLeafCertificate } = require('./opensslCert');
const pkg = require('./package.json');

// Configuration from environment variables
const INSTALL_CA = parseBool(process.env.INSTALL_CA, true, 'INSTALL_CA');
const TRAEFIK_DIR = validateNotEmpty(process.env.TRAEFIK_DIR || '/etc/traefik', 'TRAEFIK_DIR');
const CERTS_DIR = validateNotEmpty(process.env.CERTS_DIR || path.join(TRAEFIK_DIR, 'dynamic', 'certs'), 'CERTS_DIR');
const MKCERT_CA_DIR = validateNotEmpty(process.env.MKCERT_CA_DIR || '/root/.local/share/mkcert', 'MKCERT_CA_DIR');
const THROTTLE_MS = parseInt(process.env.THROTTLE_MS || '300', 10);
const SCHEDULED_INTERVAL_MS = parseInt(process.env.SCHEDULED_INTERVAL_MS || '60000', 10); // 1 minute

const docker = new Docker({ socketPath: '/var/run/docker.sock' });
const processedDomains = new Set();

// Throttle and scheduling state
let reconcileTimer = null;
let isReconciling = false;
let scheduledTimer = null;
let lastReconcileTime = 0;

// ANSI color codes
const RESET = '\x1b[0m';
const GRAY = '\x1b[90m';
const RED = '\x1b[31m';
const RED_BOLD = '\x1b[1;31m';
const BG_RED_WHITE_BOLD = '\x1b[41;37;1m';
const BG_RED_WHITE = '\x1b[41;37m';
const GREEN = '\x1b[32m';
const YELLOW = '\x1b[33m';
const CYAN = '\x1b[36m';

// Syslog RFC 5424 severity mapping
const SYSLOG_SEVERITY = {
  EMERG: 0,
  ALERT: 1,
  CRIT: 2,
  ERROR: 3,
  WARN: 4,
  NOTICE: 5,
  INFO: 6,
  DEBUG: 7,
};

// Syslog facility: local0 (16)
const SYSLOG_FACILITY = 16;

const APP_NAME = 'daas-mkcert-controller';
const HOSTNAME = os.hostname();

// ANSI color sequences for each severity level
const LEVEL_COLORS = {
  EMERG: BG_RED_WHITE_BOLD,
  ALERT: BG_RED_WHITE,
  CRIT: RED_BOLD,
  ERROR: RED,
  WARN: YELLOW,
  NOTICE: CYAN,
  INFO: GREEN,
  DEBUG: GRAY,
};

// Logging utility - Syslog RFC 5424 format with ANSI colors
// Format: <PRI>VERSION TIMESTAMP HOSTNAME APP-NAME PROCID MSGID SD MSG
function log(message, level = 'INFO') {
  const severity = SYSLOG_SEVERITY[level] !== undefined ? SYSLOG_SEVERITY[level] : SYSLOG_SEVERITY.INFO;
  const priority = SYSLOG_FACILITY * 8 + severity;
  const timestamp = new Date().toISOString();
  const procId = process.pid;
  const color = LEVEL_COLORS[level] || LEVEL_COLORS.INFO;

  const header = `<${priority}>1 ${timestamp} ${HOSTNAME} ${APP_NAME} ${procId} - -`;
  const levelTag = `[${level}]`;

  console.log(`${header} ${color}${levelTag}${RESET} ${message}`);
}

// Validate read/write access to a directory
function validateAccess(dir, description) {
  try {
    validateDirectory(dir, description);
    log(`✓ Read/write access validated for ${description}: ${dir}`, 'INFO');
    return true;
  } catch (error) {
    log(`✗ ${error.message}`, 'ERROR');
    return false;
  }
}

// Verify mkcert CA exists (installation should be done on host, not in container)
function installCA() {
  if (!INSTALL_CA) {
    log('CA installation not requested (INSTALL_CA != true)', 'INFO');
    return true;
  }

  log('CA installation requested, validating access...', 'INFO');
  
  // Validate access to CA directory
  if (!validateAccess(MKCERT_CA_DIR, 'mkcert CA directory')) {
    log('Cannot verify CA: insufficient permissions', 'ERROR');
    return false;
  }

  try {
    // Check if CA already exists
    const rootCAKey = path.join(MKCERT_CA_DIR, 'rootCA-key.pem');
    const rootCA = path.join(MKCERT_CA_DIR, 'rootCA.pem');
    
    if (fs.existsSync(rootCAKey) && fs.existsSync(rootCA)) {
      log('✓ mkcert CA found and verified', 'INFO');
      log('Note: CA should be installed on Docker host, not inside container', 'INFO');
      return true;
    }

    log('✗ mkcert CA files not found', 'ERROR');
    log('Expected files:', 'ERROR');
    log(`  - ${rootCA}`, 'ERROR');
    log(`  - ${rootCAKey}`, 'ERROR');
    log('The CA must be installed on the Docker host machine before starting the controller', 'ERROR');
    log('Run the install.sh script with INSTALL_CA=true to install the CA on the host', 'ERROR');
    return false;
  } catch (error) {
    log(`✗ Failed to verify mkcert CA: ${error.message}`, 'ERROR');
    return false;
  }
}

// Get domains that still have valid certificate files in CERTS_DIR
function getRemainingCertDomains(excludeSet) {
  try {
    return fs.readdirSync(CERTS_DIR)
      .filter(f => f.endsWith('.pem') && !f.endsWith('-key.pem'))
      .map(f => f.replace(/\.pem$/, ''))
      .filter(d => !excludeSet || !excludeSet.has(d));
  } catch (error) {
    log(`Error reading certificates directory: ${error.message}`, 'ERROR');
    return [];
  }
}

// Validate existing certificates against current CA and remove invalid ones
function validateAndRemoveInvalidCerts() {
  const caPemPath = path.join(MKCERT_CA_DIR, 'rootCA.pem');

  if (!fs.existsSync(caPemPath)) {
    log('CA certificate not found, skipping certificate validation', 'WARN');
    return;
  }

  try {
    const fingerprint = getCAFingerprint(caPemPath);
    log(`Current CA fingerprint (SHA-256): ${fingerprint}`, 'INFO');
  } catch (error) {
    log(`Could not read CA fingerprint: ${error.message}`, 'WARN');
  }

  const invalidDomains = validateExistingCertificates(CERTS_DIR, caPemPath, log);

  if (invalidDomains.length > 0) {
    log(`Found ${invalidDomains.length} certificate(s) not matching current CA, removing...`, 'WARN');
    const removed = removeInvalidCertificates(invalidDomains, CERTS_DIR, log);
    log(`Removed ${removed} invalid certificate(s). They will be regenerated on next reconciliation.`, 'INFO');

    // Clear processedDomains so certs get regenerated
    for (const domain of invalidDomains) {
      processedDomains.delete(domain);
    }

    // Update tls.yml so Traefik stops referencing removed certificates
    const invalidSet = new Set(invalidDomains);
    const remainingDomains = getRemainingCertDomains(invalidSet);
    writeTLSConfig(remainingDomains);
  } else {
    log('✓ All existing certificates are valid for current CA', 'INFO');
  }
}

// Check if Traefik is running
async function checkTraefikRunning() {
  try {
    const containers = await docker.listContainers();
    const traefikContainer = containers.find(c => 
      c.Names.some(name => name.includes('traefik')) ||
      c.Image.includes('traefik')
    );
    
    if (traefikContainer) {
      log(`✓ Traefik is running (container: ${traefikContainer.Names[0]})`, 'INFO');
      return true;
    } else {
      log('✗ Traefik is not running', 'ERROR');
      return false;
    }
  } catch (error) {
    log(`✗ Error checking Traefik status: ${error.message}`, 'ERROR');
    return false;
  }
}

// Generate certificate for a domain using openssl with custom subject
function generateCertificate(domain, metadata) {
  try {
    const certPath = path.join(CERTS_DIR, `${domain}.pem`);
    const keyPath = path.join(CERTS_DIR, `${domain}-key.pem`);

    if (fs.existsSync(certPath) && fs.existsSync(keyPath)) {
      if (!processedDomains.has(domain)) {
        log(`Certificate files for ${domain} already exist`, 'INFO');
        processedDomains.add(domain);
      }
      return;
    }

    const caCertPath = path.join(MKCERT_CA_DIR, 'rootCA.pem');
    const caKeyPath = path.join(MKCERT_CA_DIR, 'rootCA-key.pem');

    if (!fs.existsSync(caCertPath) || !fs.existsSync(caKeyPath)) {
      log(`✗ CA files not found in ${MKCERT_CA_DIR}, cannot generate certificate`, 'ERROR');
      return;
    }

    const meta = metadata || { project: '', service: '' };
    const subject = buildLeafSubject(domain, meta);

    log(`Generating certificate for: ${domain} (O=${meta.project || 'n/a'}, service=${meta.service || 'n/a'})`, 'INFO');
    generateLeafCertificate({
      domain,
      certPath,
      keyPath,
      caCertPath,
      caKeyPath,
      subject,
    });
    
    log(`✓ Certificate generated for ${domain}`, 'INFO');
    processedDomains.add(domain);
  } catch (error) {
    log(`✗ Failed to generate certificate for ${domain}: ${error.message}`, 'ERROR');
  }
}

// Write TLS configuration file for Traefik
function writeTLSConfig(domains) {
  try {
    const dynamicPath = path.join(TRAEFIK_DIR, 'dynamic');
    if (!fs.existsSync(dynamicPath)) {
      log(`Creating Traefik dynamic directory: ${dynamicPath}`, 'INFO');
      fs.mkdirSync(dynamicPath, { recursive: true, mode: 0o755 });
    }

    const tlsConfigPath = path.join(dynamicPath, 'tls.yml');
    
    if (domains.length === 0) {
      log('No domains to configure for TLS', 'DEBUG');
      if (fs.existsSync(tlsConfigPath)) {
        fs.unlinkSync(tlsConfigPath);
        log('Removed tls.yml (no certificates to configure)', 'INFO');
      }
      return;
    }

    const certificates = domains.map(d => ({
      certFile: path.join(CERTS_DIR, `${d}.pem`),
      keyFile: path.join(CERTS_DIR, `${d}-key.pem`)
    }));

    const yml = buildTLSConfig(certificates);

    fs.writeFileSync(tlsConfigPath, yml);
    log(`✓ TLS configuration updated with ${domains.length} certificate(s)`, 'INFO');
  } catch (error) {
    log(`✗ Failed to write TLS configuration: ${error.message}`, 'ERROR');
  }
}

// Throttled reconcile function
function scheduleReconcile() {
  if (reconcileTimer) {
    return; // Already scheduled
  }
  
  const now = Date.now();
  const timeSinceLastReconcile = now - lastReconcileTime;
  const delay = Math.max(0, THROTTLE_MS - timeSinceLastReconcile);
  
  reconcileTimer = setTimeout(async () => {
    reconcileTimer = null;
    await reconcile();
  }, delay);
  
  if (delay > 0) {
    log(`Reconcile scheduled in ${delay}ms`, 'DEBUG');
  }
}

// Main reconcile function - scans all containers and updates certificates
async function reconcile() {
  if (isReconciling) {
    log('Reconcile already in progress, skipping', 'DEBUG');
    return;
  }

  isReconciling = true;
  lastReconcileTime = Date.now();
  
  try {
    log('Starting reconciliation...', 'DEBUG');
    const containers = await docker.listContainers();
    // Map domain -> metadata (preserves container info for certificate subject)
    const domainMetadata = new Map();
    
    for (const containerInfo of containers) {
      if (containerInfo.Labels) {
        const domains = extractDomainsFromLabels(containerInfo.Labels, log);
        if (domains.length > 0) {
          const containerName = (containerInfo.Names && containerInfo.Names[0]) || '';
          const metadata = extractContainerMetadata(containerInfo.Labels, containerName);
          domains.forEach(d => {
            if (!domainMetadata.has(d)) {
              domainMetadata.set(d, metadata);
            }
          });
        }
      }
    }
    
    const domainList = Array.from(domainMetadata.keys());
    log(`Found ${domainList.length} TLS-enabled localhost domain(s)`, 'INFO');
    
    // Generate certificates for all domains with container metadata
    domainList.forEach(domain => generateCertificate(domain, domainMetadata.get(domain)));
    
    // Update TLS configuration file
    writeTLSConfig(domainList);
    
    log('✓ Reconciliation complete', 'DEBUG');
  } catch (error) {
    log(`✗ Error during reconciliation: ${error.message}`, 'ERROR');
  } finally {
    isReconciling = false;
  }
}

// Setup scheduled reconciliation (every minute)
function setupScheduledReconcile() {
  scheduledTimer = setInterval(async () => {
    if (!isReconciling) {
      log('Running scheduled reconciliation', 'DEBUG');
      await reconcile();
    } else {
      log('Skipping scheduled reconciliation (already running)', 'DEBUG');
    }
  }, SCHEDULED_INTERVAL_MS);
  
  log(`✓ Scheduled reconciliation every ${SCHEDULED_INTERVAL_MS / 1000}s`, 'INFO');
}

// Monitor Docker events
async function monitorDockerEvents() {
  log('Starting Docker events monitoring...', 'INFO');
  
  try {
    const stream = await docker.getEvents();
    
    stream.on('data', async (chunk) => {
      try {
        const event = JSON.parse(chunk.toString());
        
        // Listen for container events
        if (event.Type === 'container' && 
            (event.Action === 'start' || event.Action === 'create' || 
             event.Action === 'die' || event.Action === 'stop')) {
          const attrs = event.Actor.Attributes || {};
          log(`Docker event: ${event.Action} for container ${event.Actor.ID.substring(0, 12)} (name: ${attrs.name || 'unknown'}, image: ${attrs.image || 'unknown'})`, 'DEBUG');
          scheduleReconcile();
        }
      } catch (error) {
        log(`Error processing Docker event: ${error.message}`, 'ERROR');
      }
    });

    stream.on('error', (error) => {
      log(`Docker events stream error: ${error.message}`, 'ERROR');
    });

    log('✓ Docker events monitoring started', 'INFO');
  } catch (error) {
    log(`✗ Failed to start Docker events monitoring: ${error.message}`, 'ERROR');
    throw error;
  }
}

// Scan existing containers on startup
async function scanExistingContainers() {
  log('Scanning existing containers for localhost domains...', 'INFO');
  await reconcile();
}

// Monitor Traefik dynamic configuration files
function monitorTraefikFiles() {
  const dynamicPath = path.join(TRAEFIK_DIR, 'dynamic');
  
  if (!fs.existsSync(dynamicPath)) {
    log(`Traefik dynamic directory not found: ${dynamicPath}`, 'WARN');
    return;
  }

  log(`Starting Traefik files monitoring: ${dynamicPath}`, 'INFO');
  
  const watcher = chokidar.watch(dynamicPath, {
    persistent: true,
    ignoreInitial: true,
    depth: 2,
    ignored: /tls\.yml$/ // Ignore our own tls.yml file
  });

  watcher.on('add', (filePath) => {
    log(`Traefik file added: ${filePath}`, 'DEBUG');
    scheduleReconcile();
  });

  watcher.on('change', (filePath) => {
    log(`Traefik file changed: ${filePath}`, 'DEBUG');
    scheduleReconcile();
  });

  watcher.on('unlink', (filePath) => {
    log(`Traefik file removed: ${filePath}`, 'DEBUG');
    scheduleReconcile();
  });

  watcher.on('error', (error) => {
    log(`Traefik file watcher error: ${error.message}`, 'ERROR');
  });

  log('✓ Traefik files monitoring started', 'INFO');
}

// Main startup function
async function main() {
  if (!isBannerShown()) {
    printBanner();
  }
  log('=== daas-mkcert-controller starting ===', 'INFO');
  log(`Configuration:`, 'INFO');
  log(`  - INSTALL_CA: ${INSTALL_CA}`, 'INFO');
  log(`  - TRAEFIK_DIR: ${TRAEFIK_DIR}`, 'INFO');
  log(`  - CERTS_DIR: ${CERTS_DIR}`, 'INFO');
  log(`  - MKCERT_CA_DIR: ${MKCERT_CA_DIR}`, 'INFO');
  log(`  - THROTTLE_MS: ${THROTTLE_MS}`, 'INFO');
  log(`  - SCHEDULED_INTERVAL_MS: ${SCHEDULED_INTERVAL_MS}`, 'INFO');

  // Validate access to required directories
  if (!validateAccess(CERTS_DIR, 'certificates directory')) {
    log('Cannot start: insufficient permissions for certificates directory', 'ERROR');
    process.exit(1);
  }

  // Install CA if requested
  if (INSTALL_CA) {
    if (!installCA()) {
      log('Cannot start: CA installation failed', 'ERROR');
      process.exit(1);
    }
  }

  // Validate existing certificates against current CA
  validateAndRemoveInvalidCerts();

  // Check if Traefik is running
  const traefikRunning = await checkTraefikRunning();
  if (!traefikRunning) {
    log('Cannot start: Traefik is not running', 'ERROR');
    process.exit(1);
  }

  // Start monitoring
  await scanExistingContainers();
  await monitorDockerEvents();
  monitorTraefikFiles();
  setupScheduledReconcile();

  log('=== daas-mkcert-controller is running ===', 'INFO');
  log('Press Ctrl+C to stop', 'INFO');
}

// Handle shutdown gracefully
process.on('SIGINT', () => {
  log('Shutting down...', 'INFO');
  if (reconcileTimer) clearTimeout(reconcileTimer);
  if (scheduledTimer) clearInterval(scheduledTimer);
  process.exit(0);
});

process.on('SIGTERM', () => {
  log('Shutting down...', 'INFO');
  if (reconcileTimer) clearTimeout(reconcileTimer);
  if (scheduledTimer) clearInterval(scheduledTimer);
  process.exit(0);
});

// Start the application
main().catch((error) => {
  log(`Fatal error: ${error.message}`, 'ERROR');
  console.error(error);
  process.exit(1);
});
INDEX_JS_EOF

    # Create parseBool.js (embedded)
    cat > "$work_dir/parseBool.js" << 'PARSEBOOL_JS_EOF'
'use strict';

/**
 * Parse a boolean value from a string using locale-aware regex patterns.
 *
 * Truthy pattern: ^(1|t(rue)?|s(i)?|y(es)?)  (case-insensitive)
 * Falsy  pattern: ^(0|f(alse)?|n(o)?)         (case-insensitive)
 *
 * @param {string|undefined} value - The string value to parse.
 * @param {boolean|undefined} defaultValue - Default when value is undefined/null/empty.
 *   Pass undefined to make the parameter required (throws on missing value).
 * @param {string} [name] - Parameter name used in error messages.
 * @returns {boolean} The parsed boolean value.
 * @throws {Error} When value cannot be parsed or is missing and no default is provided.
 */
function parseBool(value, defaultValue, name) {
  const label = name ? `'${name}'` : 'boolean parameter';

  if (value === undefined || value === null || value === '') {
    if (defaultValue === undefined) {
      throw new Error(`Required ${label} is not configured`);
    }
    return defaultValue;
  }

  const v = String(value).trim().toLowerCase();

  if (/^(1|t(rue)?|s(i)?|y(es)?)$/.test(v)) {
    return true;
  }

  if (/^(0|f(alse)?|n(o)?)$/.test(v)) {
    return false;
  }

  throw new Error(`Invalid value for ${label}: '${value}'. Use true/false, yes/no, si/no, 1/0`);
}

module.exports = { parseBool };
PARSEBOOL_JS_EOF

    # Create validateConfig.js (embedded)
    cat > "$work_dir/validateConfig.js" << 'VALIDATECONFIG_JS_EOF'
'use strict';

const fs = require('fs');
const path = require('path');

/**
 * Validate that a string parameter is not empty after trimming.
 *
 * @param {string|undefined} value - The value to validate.
 * @param {string} name - Parameter name used in error messages.
 * @returns {string} The trimmed value.
 * @throws {Error} When value is undefined, null, or empty after trimming.
 */
function validateNotEmpty(value, name) {
  if (value === undefined || value === null) {
    throw new Error(
      `Parameter '${name}' is required but was not provided. ` +
      `Set the '${name}' environment variable to a non-empty value.`
    );
  }

  const trimmed = String(value).trim();

  if (trimmed === '') {
    throw new Error(
      `Parameter '${name}' cannot be an empty string. ` +
      `Set the '${name}' environment variable to a non-empty value.`
    );
  }

  return trimmed;
}

/**
 * Validate that a directory path is not empty, exists (or can be created),
 * and is accessible with read/write permissions.
 *
 * @param {string} dir - The directory path to validate.
 * @param {string} name - Parameter name used in error messages.
 * @returns {string} The validated directory path.
 * @throws {Error} When the directory cannot be accessed or created.
 */
function validateDirectory(dir, name) {
  const validated = validateNotEmpty(dir, name);

  if (!fs.existsSync(validated)) {
    try {
      fs.mkdirSync(validated, { recursive: true, mode: 0o755 });
    } catch (error) {
      throw new Error(
        `Directory '${validated}' for parameter '${name}' does not exist and could not be created: ${error.message}. ` +
        `Ensure the parent directory exists and has the correct permissions, or create '${validated}' manually.`
      );
    }
  }

  // Verify it is a directory
  try {
    const stats = fs.statSync(validated);
    if (!stats.isDirectory()) {
      const err = new Error(
        `Path '${validated}' for parameter '${name}' exists but is not a directory. ` +
        `Ensure '${name}' points to a valid directory path.`
      );
      err.code = 'NOT_A_DIRECTORY';
      throw err;
    }
  } catch (error) {
    if (error.code === 'NOT_A_DIRECTORY') {
      throw error;
    }
    throw new Error(
      `Cannot access path '${validated}' for parameter '${name}': ${error.message}. ` +
      `Ensure the path exists and has the correct permissions.`
    );
  }

  // Test read/write access
  const testFile = path.join(validated, `.access_test_${process.pid}`);
  try {
    fs.writeFileSync(testFile, 'test');
  } catch (error) {
    throw new Error(
      `No write permission on directory '${validated}' for parameter '${name}': ${error.message}. ` +
      `Ensure the process has write access to '${validated}'.`
    );
  }

  try {
    fs.readFileSync(testFile);
  } catch (error) {
    throw new Error(
      `No read permission on directory '${validated}' for parameter '${name}': ${error.message}. ` +
      `Ensure the process has read access to '${validated}'.`
    );
  }

  try {
    fs.unlinkSync(testFile);
  } catch (_) {
    // Best effort cleanup
  }

  return validated;
}

module.exports = { validateNotEmpty, validateDirectory };
VALIDATECONFIG_JS_EOF

    # Create banner.js (embedded)
    cat > "$work_dir/banner.js" << 'BANNER_JS_EOF'
'use strict';

// Track whether the banner has been shown
let bannerShown = false;

/**
 * Prints the daas ASCII logo banner with colored output.
 * Uses figlet graffiti font for "daas" with lolcat-style rainbow colors.
 * Uses ANSI escape codes directly for colored output.
 * Tracks if the banner has been shown to avoid duplicates.
 */
function printBanner() {
  const pkg = require('./package.json');
  const version = `v${pkg.version}`;
  const product = 'mkcert-controller';
  const company = 'consulting';
  const brand = 'daas';

  // Figlet "daas" in graffiti font (pre-generated)
  const artLines = [
    '       .___                     ',
    '     __| _/____  _____    ______',
    '    / __ |\\__  \\ \\__  \\  /  ___/',
    '   / /_/ | / __ \\_/ __ \\_\\___ \\ ',
    '   \\____ |(____  (____  /____  >',
    '        \\/     \\/     \\/     \\/ ',
  ];

  // Determine total width based on the longest art line + padding
  const totalWidth = 34;

  // Pad art lines to totalWidth with trailing spaces and add left padding
  const paddedArt = artLines.map((line) => {
    if (line.length < totalWidth) {
      return line + ' '.repeat(totalWidth - line.length);
    }
    return line;
  });

  // Build top bar: " daas" left, "mkcert-controller " right
  const topLeft = ` ${brand}`;
  const topRight = `${product} `;
  const topPad = totalWidth - topLeft.length - topRight.length;
  const topBar = topLeft + ' '.repeat(Math.max(topPad, 1)) + topRight;

  // Build bottom bar: " mkcert-controller" left, "consulting " right
  const botLeft = ` ${product}`;
  const botRight = `${company} `;
  const botPad = totalWidth - botLeft.length - botRight.length;
  const botBar = botLeft + ' '.repeat(Math.max(botPad, 1)) + botRight;

  // Build version bar: version right-aligned with trailing space
  const verRight = `${version} `;
  const verBar = ' '.repeat(totalWidth - verRight.length) + verRight;

  // ANSI color codes
  const RESET = '\x1b[0m';
  const BLUE_BG_WHITE = '\x1b[44;37m'; // Blue background, white text
  const PURPLE_BG_WHITE = '\x1b[45;37m'; // Purple/magenta background, white text

  // Lolcat-style rainbow color palette (256-color)
  const rainbowColors = [118, 154, 148, 184, 178, 214, 208, 209, 203];

  /**
   * Apply lolcat-style rainbow coloring to a line of text.
   * Colors shift across characters, creating a gradient effect.
   */
  function colorizeArtLine(line, lineIndex) {
    let result = '';
    for (let i = 0; i < line.length; i++) {
      const colorIdx = Math.floor(
        ((i + lineIndex * 2) / line.length) * rainbowColors.length
      );
      const color =
        rainbowColors[Math.min(colorIdx, rainbowColors.length - 1)];
      result += `\x1b[38;5;${color}m${line[i]}\x1b[39m`;
    }
    return result;
  }

  // Print the banner
  const output = [];

  // Top bar (blue background, white text)
  output.push(`${BLUE_BG_WHITE}${topBar}${RESET}`);

  // Colored figlet art
  paddedArt.forEach((line, idx) => {
    output.push(colorizeArtLine(line, idx));
  });

  // Bottom bar (blue background, white text)
  output.push(`${BLUE_BG_WHITE}${botBar}${RESET}`);

  // Version bar (purple background, white text)
  output.push(`${PURPLE_BG_WHITE}${verBar}${RESET}`);

  // Empty line after banner
  output.push('');

  console.log(output.join('\n'));
  bannerShown = true;
}

/**
 * Returns whether the banner has been shown.
 * @returns {boolean}
 */
function isBannerShown() {
  return bannerShown;
}

module.exports = { printBanner, isBannerShown };
BANNER_JS_EOF

    # Create traefikLabels.js (embedded)
    cat > "$work_dir/traefikLabels.js" << 'TRAEFIKLABELS_JS_EOF'
'use strict';

// Parse Traefik labels into a structured object
function parseTraefikLabels(labels) {
  const routers = {};
  
  for (const [key, value] of Object.entries(labels)) {
    // Parse label keys like: traefik.http.routers.myrouter.rule
    const routerMatch = key.match(/^traefik\.http\.routers\.([^.]+)\.(.+)$/);
    if (routerMatch) {
      const routerName = routerMatch[1];
      const property = routerMatch[2];
      
      if (!routers[routerName]) {
        routers[routerName] = {};
      }
      routers[routerName][property] = value;
    }
  }
  
  return routers;
}

// Extract localhost domains from Traefik labels (only if TLS is enabled)
function extractDomainsFromLabels(labels, log) {
  const noop = () => {};
  const _log = typeof log === 'function' ? log : noop;
  const domains = new Set();
  const routers = parseTraefikLabels(labels);
  _log(`Processing labels: ${JSON.stringify(labels)}`, 'DEBUG');
  
  for (const [routerName, router] of Object.entries(routers)) {
    // Only process routers with TLS enabled
    if (!router.tls || router.tls !== 'true') {
      continue;
    }
    
    // Extract domains from the rule
    if (router.rule) {
      // Match all backtick-quoted domains inside Host() expressions
      // Supports both single and multiple comma-separated hosts:
      //   Host(`app.localhost`)
      //   Host(`app.localhost`, `api.localhost`)
      const hostMatch = router.rule.match(/Host\(([^)]+)\)/g);
      if (hostMatch) {
        hostMatch.forEach(expr => {
          // Extract all backtick-quoted values from within the Host() expression
          const domainMatches = expr.match(/`([^`]+)`/g);
          if (domainMatches) {
            domainMatches.forEach(quoted => {
              const domain = quoted.slice(1, -1); // Remove backticks
              if (domain.endsWith('.localhost')) {
                _log(`Found TLS-enabled domain: ${domain} (router: ${routerName})`, 'DEBUG');
                domains.add(domain);
              }
            });
          }
        });
      }
    }
  }
  
  return Array.from(domains);
}

module.exports = { parseTraefikLabels, extractDomainsFromLabels };
TRAEFIKLABELS_JS_EOF

    # Create buildTLSConfig.js (embedded)
    cat > "$work_dir/buildTLSConfig.js" << 'BUILDTLSCONFIG_JS_EOF'
'use strict';

/**
 * Build TLS YAML configuration string for Traefik.
 *
 * Includes a `tls.stores.default.defaultCertificate` section so that Traefik
 * file-provider certificates are placed in a TLS store and actually served
 * to clients.  Without the store definition Traefik loads the certificates
 * but falls back to its own default self-signed certificate.
 *
 * @param {Array<{certFile: string, keyFile: string}>} certificates
 * @returns {string} YAML content for tls.yml
 */
function buildTLSConfig(certificates) {
  if (!certificates || certificates.length === 0) {
    return '';
  }

  const defaultCert = certificates[0];

  return `# Auto-generated by daas-mkcert-controller
# Do not edit manually
tls:
  stores:
    default:
      defaultCertificate:
        certFile: ${defaultCert.certFile}
        keyFile: ${defaultCert.keyFile}
  certificates:
${certificates.map(cert => `    - certFile: ${cert.certFile}
      keyFile: ${cert.keyFile}`).join('\n')}
`;
}

module.exports = { buildTLSConfig };
BUILDTLSCONFIG_JS_EOF

    # Create validateCertificates.js (embedded)
    cat > "$work_dir/validateCertificates.js" << 'VALIDATECERTIFICATES_JS_EOF'
'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

/**
 * Get the SHA-256 fingerprint of a CA certificate.
 * This fingerprint uniquely identifies the CA.
 *
 * @param {string} caPemPath - Path to the CA PEM file
 * @returns {string} SHA-256 fingerprint (colon-separated hex)
 */
function getCAFingerprint(caPemPath) {
  const caPem = fs.readFileSync(caPemPath);
  const ca = new crypto.X509Certificate(caPem);
  return ca.fingerprint256;
}

/**
 * Check if a certificate was issued by the given CA.
 *
 * @param {string} certPemPath - Path to the certificate PEM file
 * @param {string} caPemPath - Path to the CA PEM file
 * @returns {boolean} true if the certificate was issued by the CA
 */
function isCertIssuedByCA(certPemPath, caPemPath) {
  const certPem = fs.readFileSync(certPemPath);
  const caPem = fs.readFileSync(caPemPath);
  const cert = new crypto.X509Certificate(certPem);
  const ca = new crypto.X509Certificate(caPem);
  return cert.checkIssued(ca);
}

/**
 * Validate all existing certificates in a directory against the current CA.
 * Returns the list of domains whose certificates are NOT issued by the current CA.
 *
 * @param {string} certsDir - Directory containing certificate files
 * @param {string} caPemPath - Path to the CA PEM file
 * @param {Function} [log] - Optional logging function (message, level)
 * @returns {string[]} List of domain names with invalid certificates
 */
function validateExistingCertificates(certsDir, caPemPath, log) {
  const _log = typeof log === 'function' ? log : () => {};
  const invalidDomains = [];

  if (!fs.existsSync(certsDir)) {
    _log(`Certificates directory does not exist: ${certsDir}`, 'DEBUG');
    return invalidDomains;
  }

  if (!fs.existsSync(caPemPath)) {
    _log(`CA certificate not found: ${caPemPath}`, 'WARN');
    return invalidDomains;
  }

  const fingerprint = getCAFingerprint(caPemPath);
  _log(`Current CA fingerprint (SHA-256): ${fingerprint}`, 'INFO');

  let certFiles;
  try {
    certFiles = fs.readdirSync(certsDir)
      .filter(f => f.endsWith('.pem') && !f.endsWith('-key.pem'));
  } catch (error) {
    _log(`Error reading certificates directory: ${error.message}`, 'ERROR');
    return invalidDomains;
  }

  if (certFiles.length === 0) {
    _log('No existing certificates to validate', 'DEBUG');
    return invalidDomains;
  }

  _log(`Validating ${certFiles.length} existing certificate(s) against current CA...`, 'INFO');

  const caPem = fs.readFileSync(caPemPath);
  const ca = new crypto.X509Certificate(caPem);

  for (const certFile of certFiles) {
    const domain = certFile.replace(/\.pem$/, '');
    const certPath = path.join(certsDir, certFile);

    try {
      const certPem = fs.readFileSync(certPath);
      const cert = new crypto.X509Certificate(certPem);

      if (!cert.checkIssued(ca)) {
        _log(`Certificate for ${domain} was NOT issued by current CA`, 'WARN');
        invalidDomains.push(domain);
      } else {
        _log(`Certificate for ${domain} is valid (issued by current CA)`, 'DEBUG');
      }
    } catch (error) {
      _log(`Error validating certificate for ${domain}: ${error.message}`, 'WARN');
      invalidDomains.push(domain);
    }
  }

  return invalidDomains;
}

/**
 * Remove certificate and key files for the given domains.
 *
 * @param {string[]} domains - List of domain names to remove
 * @param {string} certsDir - Directory containing certificate files
 * @param {Function} [log] - Optional logging function (message, level)
 * @returns {number} Number of certificate pairs removed
 */
function removeInvalidCertificates(domains, certsDir, log) {
  const _log = typeof log === 'function' ? log : () => {};
  let removed = 0;

  for (const domain of domains) {
    const certPath = path.join(certsDir, `${domain}.pem`);
    const keyPath = path.join(certsDir, `${domain}-key.pem`);

    try {
      let didRemove = false;
      if (fs.existsSync(certPath)) {
        fs.unlinkSync(certPath);
        didRemove = true;
      }
      if (fs.existsSync(keyPath)) {
        fs.unlinkSync(keyPath);
        didRemove = true;
      }
      if (didRemove) {
        _log(`Removed invalid certificate for ${domain}`, 'INFO');
        removed++;
      }
    } catch (error) {
      _log(`Error removing certificate for ${domain}: ${error.message}`, 'ERROR');
    }
  }

  return removed;
}

module.exports = {
  getCAFingerprint,
  isCertIssuedByCA,
  validateExistingCertificates,
  removeInvalidCertificates,
};
VALIDATECERTIFICATES_JS_EOF

    # Create certSubject.js (embedded)
    cat > "$work_dir/certSubject.js" << 'CERTSUBJECT_JS_EOF'
'use strict';

/**
 * Default values for certificate subject fields.
 */
const DEFAULTS = {
  caOrganization: 'DAAS Consulting',
  caCN: 'DAAS Development CA',
  toolName: 'daas-mkcert-controller',
};

/**
 * Extract meaningful metadata from Docker container labels.
 *
 * Looks for Docker Compose labels to identify the project and service.
 * Falls back to container name if Compose labels are not present.
 *
 * @param {Object} labels - Docker container labels
 * @param {string} [containerName] - Container name as fallback
 * @returns {{ project: string, service: string }}
 */
function extractContainerMetadata(labels, containerName) {
  const project = labels['com.docker.compose.project'] || '';
  const service = labels['com.docker.compose.service'] || '';

  // Fallback: derive from container name (strip trailing -N replica suffix)
  if (!project && containerName) {
    const cleaned = containerName.replace(/^\//, '').replace(/-\d+$/, '');
    return { project: cleaned, service: '' };
  }

  return { project, service };
}

/**
 * Build the Subject string for a leaf (domain) certificate.
 *
 * Format: /CN=<domain>/O=<project>/OU=<service> | daas-mkcert-controller
 *
 * @param {string} domain - The domain name (e.g. "app.localhost")
 * @param {{ project: string, service: string }} metadata - Container metadata
 * @param {string} [toolName] - Tool name for OU suffix
 * @returns {string} OpenSSL subject string
 */
function buildLeafSubject(domain, metadata, toolName) {
  const tool = toolName || DEFAULTS.toolName;
  const cn = domain;
  const o = metadata.project || tool;
  const ouParts = [];
  if (metadata.service) ouParts.push(metadata.service);
  ouParts.push(tool);
  const ou = ouParts.join(' | ');

  return `/CN=${cn}/O=${o}/OU=${ou}`;
}

/**
 * Build the Subject string for the CA certificate.
 *
 * Format: /CN=DAAS Development CA/O=DAAS Consulting/OU=daas-mkcert-controller vX.Y.Z
 *
 * @param {string} version - Controller version (e.g. "1.4.0")
 * @param {Object} [options] - Optional overrides
 * @param {string} [options.cn] - Custom CN
 * @param {string} [options.organization] - Custom Organization
 * @param {string} [options.toolName] - Custom tool name
 * @returns {string} OpenSSL subject string
 */
function buildCASubject(version, options) {
  const opts = options || {};
  const cn = opts.cn || DEFAULTS.caCN;
  const o = opts.organization || DEFAULTS.caOrganization;
  const tool = opts.toolName || DEFAULTS.toolName;
  const ou = `${tool} v${version}`;

  return `/CN=${cn}/O=${o}/OU=${ou}`;
}

module.exports = {
  DEFAULTS,
  extractContainerMetadata,
  buildLeafSubject,
  buildCASubject,
};
CERTSUBJECT_JS_EOF

    # Create opensslCert.js (embedded)
    cat > "$work_dir/opensslCert.js" << 'OPENSSLCERT_JS_EOF'
'use strict';

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

/**
 * Generate a leaf certificate signed by the given CA using openssl.
 *
 * @param {Object} options
 * @param {string} options.domain - Domain name for the certificate
 * @param {string} options.certPath - Output path for the certificate PEM
 * @param {string} options.keyPath - Output path for the private key PEM
 * @param {string} options.caCertPath - Path to the CA certificate PEM
 * @param {string} options.caKeyPath - Path to the CA private key PEM
 * @param {string} options.subject - OpenSSL subject string (e.g. "/CN=.../O=.../OU=...")
 * @param {number} [options.days=825] - Certificate validity in days
 */
function generateLeafCertificate(options) {
  const {
    domain,
    certPath,
    keyPath,
    caCertPath,
    caKeyPath,
    subject,
    days = 825,
  } = options;

  // Create a temporary directory for CSR and extension config
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'daas-cert-'));
  const csrPath = path.join(tmpDir, 'cert.csr');
  const extPath = path.join(tmpDir, 'cert.ext');

  try {
    // Write extension config with SAN
    const extContent = [
      'authorityKeyIdentifier=keyid,issuer',
      'basicConstraints=CA:FALSE',
      'keyUsage=digitalSignature,keyEncipherment',
      'extendedKeyUsage=serverAuth',
      `subjectAltName=DNS:${domain}`,
    ].join('\n');
    fs.writeFileSync(extPath, extContent);

    // Generate private key
    execSync(`openssl genrsa -out "${keyPath}" 2048 2>/dev/null`);

    // Generate CSR
    execSync(
      `openssl req -new -key "${keyPath}" -out "${csrPath}" -subj "${subject}"`,
      { stdio: 'pipe' }
    );

    // Sign with CA
    execSync(
      `openssl x509 -req -in "${csrPath}" -CA "${caCertPath}" -CAkey "${caKeyPath}"` +
        ` -CAcreateserial -out "${certPath}" -days ${days} -sha256 -extfile "${extPath}"`,
      { stdio: 'pipe' }
    );
  } finally {
    // Clean up temp files
    try {
      fs.rmSync(tmpDir, { recursive: true, force: true });
    } catch (_) {
      // Ignore cleanup errors
    }
  }
}

/**
 * Generate a self-signed CA certificate using openssl.
 *
 * @param {Object} options
 * @param {string} options.certPath - Output path for the CA certificate PEM
 * @param {string} options.keyPath - Output path for the CA private key PEM
 * @param {string} options.subject - OpenSSL subject string for the CA
 * @param {number} [options.days=3650] - CA validity in days (default ~10 years)
 */
function generateCACertificate(options) {
  const { certPath, keyPath, subject, days = 3650 } = options;

  // Generate CA private key
  execSync(`openssl genrsa -out "${keyPath}" 4096 2>/dev/null`);

  // Generate self-signed CA certificate
  execSync(
    `openssl req -x509 -new -nodes -key "${keyPath}" -sha256` +
      ` -days ${days} -out "${certPath}" -subj "${subject}"`,
    { stdio: 'pipe' }
  );
}

module.exports = {
  generateLeafCertificate,
  generateCACertificate,
};
OPENSSLCERT_JS_EOF

    # Create .dockerignore
    cat > "$work_dir/.dockerignore" << 'DOCKERIGNORE_EOF'
node_modules
npm-debug.log
.git
.gitignore
README.md
.dockerignore
Dockerfile
docker-compose.yml
*.sh
*.test.js
DOCKERIGNORE_EOF

    log_success "Project files created"
}

# Build Docker image
build_image() {
    log_info "Building Docker image: ${IMAGE_NAME}:${IMAGE_TAG}..."
    
    # Determine build context
    local build_dir
    
    # If running from stdin (piped), create a temporary directory
    if [[ ! -t 0 ]] && [[ ! -f "package.json" ]]; then
        build_dir=$(mktemp -d)
        log_info "Creating temporary build directory: $build_dir"
        create_project_files "$build_dir"
    else
        # Running from a git repo or local directory with files
        build_dir="."
        
        # Create files if they don't exist
        if [[ ! -f "package.json" ]]; then
            create_project_files "$build_dir"
        fi
    fi
    
    # Build the image with version label
    if docker build \
        --label "version=${VERSION}" \
        -t "${IMAGE_NAME}:${IMAGE_TAG}" \
        -t "${IMAGE_NAME}:${VERSION}" \
        "$build_dir"; then
        log_success "Docker image built successfully"
        log_info "Tagged as: ${IMAGE_NAME}:${IMAGE_TAG}"
        log_info "Tagged as: ${IMAGE_NAME}:${VERSION}"
        
        # Clean up temp directory if created
        if [[ "$build_dir" != "." ]]; then
            log_info "Cleaning up temporary directory"
            rm -rf "$build_dir"
        fi
        
        return 0
    else
        log_fail "Failed to build Docker image"
        
        # Clean up temp directory if created
        if [[ "$build_dir" != "." ]]; then
            rm -rf "$build_dir"
        fi
        
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
    log_info "Installing daas-mkcert-controller..."
    
    # Run all validations
    validate_os
    validate_docker
    validate_permissions
    validate_environment
    validate_directories
    
    # Check if Traefik is running
    if ! check_traefik; then
        log_warn "Traefik is not running. The controller will wait for it to start."
    fi
    
    # Get Traefik volume mounts
    get_traefik_volumes || true
    
    # Validate Traefik static configuration
    validate_traefik_config
    
    if [[ "$INSTALL_CA" == "true" ]]; then
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
    else
        log_info "CA installation disabled (INSTALL_CA=false)"
        log_info ""
        log_info "=== Building and starting controller ==="
    fi
    
    # Build image
    build_image
    
    # Start controller
    start_controller
    
    # Final success message
    echo ""
    log_success "Installation complete!"
    echo ""
    log_info "Summary:"
    if [[ "$INSTALL_CA" == "true" ]]; then
        log_info "  ✓ CA generated using Docker (no local mkcert installed)"
        log_info "  ✓ CA installed in system trust store"
        log_info "  ✓ CA installed in Firefox/Chrome (if available)"
    else
        log_info "  ⊘ CA installation skipped (INSTALL_CA=false)"
    fi
    log_info "  ✓ Controller container running"
    echo ""
    log_info "Next steps:"
    if [[ "$INSTALL_CA" == "true" ]]; then
        log_info "  1. Restart your browser to load the new CA"
    fi
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
    
    # Revert Traefik configuration changes
    get_traefik_volumes || true
    revert_traefik_config
    
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
            local _saved_version="$VERSION"
            . /etc/os-release
            VERSION="$_saved_version"
            case "$ID" in
                ubuntu|debian|pop|linuxmint)
                    # Remove both old and new naming formats
                    for old_ca in /usr/local/share/ca-certificates/daas-mkcert-rootCA*.crt /usr/local/share/ca-certificates/mkcert-rootCA.crt; do
                        if [[ -f "$old_ca" ]]; then
                            sudo rm -f "$old_ca" 2>/dev/null || true
                        fi
                    done
                    sudo update-ca-certificates >/dev/null 2>&1
                    log_success "CA removed from system trust store"
                    ;;
                fedora|rhel|centos|rocky|almalinux)
                    for old_ca in /etc/pki/ca-trust/source/anchors/daas-mkcert-rootCA*.crt /etc/pki/ca-trust/source/anchors/mkcert-rootCA.crt; do
                        if [[ -f "$old_ca" ]]; then
                            sudo rm -f "$old_ca" 2>/dev/null || true
                        fi
                    done
                    sudo update-ca-trust >/dev/null 2>&1
                    log_success "CA removed from system trust store"
                    ;;
                arch|manjaro)
                    for old_ca in /etc/ca-certificates/trust-source/anchors/daas-mkcert-rootCA*.crt /etc/ca-certificates/trust-source/anchors/mkcert-rootCA.crt; do
                        if [[ -f "$old_ca" ]]; then
                            sudo rm -f "$old_ca" 2>/dev/null || true
                        fi
                    done
                    sudo trust extract-compat >/dev/null 2>&1
                    log_success "CA removed from system trust store"
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
        local _saved_version="$VERSION"
        . /etc/os-release
        VERSION="$_saved_version"
        case "$ID" in
            ubuntu|debian|pop|linuxmint)
                if ls /usr/local/share/ca-certificates/daas-mkcert-rootCA*.crt 1>/dev/null 2>&1 || [[ -f /usr/local/share/ca-certificates/mkcert-rootCA.crt ]]; then
                    log_success "CA installed in Debian/Ubuntu trust store"
                else
                    log_warn "CA not found in system trust store"
                fi
                ;;
            fedora|rhel|centos|rocky|almalinux)
                if ls /etc/pki/ca-trust/source/anchors/daas-mkcert-rootCA*.crt 1>/dev/null 2>&1 || [[ -f /etc/pki/ca-trust/source/anchors/mkcert-rootCA.crt ]]; then
                    log_success "CA installed in Fedora/RHEL trust store"
                else
                    log_warn "CA not found in system trust store"
                fi
                ;;
            arch|manjaro)
                if ls /etc/ca-certificates/trust-source/anchors/daas-mkcert-rootCA*.crt 1>/dev/null 2>&1 || [[ -f /etc/ca-certificates/trust-source/anchors/mkcert-rootCA.crt ]]; then
                    log_success "CA installed in Arch trust store"
                else
                    log_warn "CA not found in system trust store"
                fi
                ;;
        esac
    fi
    
    echo ""
    
    # Check browser NSS trust stores
    log_info "Browser NSS Trust Stores:"
    local nss_checked=false
    
    # Chrome/Chromium NSS
    local nssdb="$HOME/.pki/nssdb"
    if [[ -d "$nssdb" ]]; then
        if docker image inspect "$HELPER_IMAGE" &>/dev/null; then
            if docker run --rm -v "$nssdb:/nssdb:ro" "$HELPER_IMAGE" certutil -d sql:/nssdb -L 2>/dev/null | grep -q "mkcert CA"; then
                log_success "CA installed in Chrome/Chromium NSS database"
            else
                log_warn "CA NOT found in Chrome/Chromium NSS database"
                log_warn "  Run: $0 install  (to reinstall CA in browser trust stores)"
            fi
        else
            log_warn "Helper image not available — cannot verify Chrome NSS"
            log_warn "  Run: $0 install  (to rebuild helper image and install CA)"
        fi
        nss_checked=true
    fi
    
    # Firefox NSS (standard, snap, flatpak)
    local firefox_dirs=(
        "$HOME/.mozilla/firefox"
        "$HOME/snap/firefox/common/.mozilla/firefox"
        "$HOME/.var/app/org.mozilla.firefox/.mozilla/firefox"
    )
    for firefox_dir in "${firefox_dirs[@]}"; do
        if [[ -d "$firefox_dir" ]]; then
            local firefox_type="standard"
            [[ "$firefox_dir" == *"/snap/"* ]] && firefox_type="snap"
            [[ "$firefox_dir" == *"/.var/app/"* ]] && firefox_type="flatpak"
            
            for profile in "$firefox_dir"/*.default* "$firefox_dir"/*.dev-edition-default*; do
                if [[ -d "$profile" ]]; then
                    local pname=$(basename "$profile")
                    if docker image inspect "$HELPER_IMAGE" &>/dev/null; then
                        if docker run --rm -v "$profile:/profile:ro" "$HELPER_IMAGE" certutil -d sql:/profile -L 2>/dev/null | grep -q "mkcert CA"; then
                            log_success "CA installed in Firefox ($firefox_type) profile: $pname"
                        else
                            log_warn "CA NOT found in Firefox ($firefox_type) profile: $pname"
                            log_warn "  Run: $0 install  (to reinstall CA in browser trust stores)"
                        fi
                    else
                        log_warn "Helper image not available — cannot verify Firefox NSS"
                    fi
                    nss_checked=true
                fi
            done
        fi
    done
    
    if [[ "$nss_checked" == "false" ]]; then
        log_info "No browser NSS databases found"
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

# Show controller logs
show_logs() {
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        docker logs -f "$CONTAINER_NAME"
    else
        log_error "Container not found: $CONTAINER_NAME"
        exit 1
    fi
}

# Main function
main() {
    # Parse arguments for flags
    local command=""
    local args=()
    
    for arg in "$@"; do
        case "$arg" in
            --disable-install-ca)
                INSTALL_CA=false
                ;;
            --install-ca=*)
                INSTALL_CA="${arg#*=}"
                ;;
            *)
                if [[ -z "$command" ]]; then
                    command="$arg"
                else
                    args+=("$arg")
                fi
                ;;
        esac
    done
    
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
        logs)
            show_logs
            ;;
        help|--help|-h)
            show_banner
            show_usage
            ;;
        *)
            # If no command specified and running from stdin, assume install
            if [[ ! -t 0 ]] && [[ -z "$command" ]]; then
                show_banner
                install_all
            else
                show_banner
                show_usage
                if [[ -n "$command" ]]; then
                    log_error "Unknown command: $command"
                    exit 1
                fi
            fi
            ;;
    esac
}

# Run main function
main "$@"
