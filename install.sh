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
RUN apk add --no-cache ca-certificates nss-tools \
    && ARCH=$(uname -m) \
    && case "$ARCH" in \
        x86_64) MKCERT_ARCH="amd64"; MKCERT_SHA256="6d31c65b03972c6dc4a14ab429f2928300518b26503f58723e532d1b0a3bbb52" ;; \
        aarch64) MKCERT_ARCH="arm64"; MKCERT_SHA256="b98f2cc69fd9147fe4d405d859c57504571adec0d3611c3eefd04107c7ac00d0" ;; \
        armv7l) MKCERT_ARCH="arm"; MKCERT_SHA256="2f22ff62dfc13357e147e027117724e7ce1ff810e30d2b061b05b668ecb4f1d7" ;; \
        *) echo "Unsupported architecture: $ARCH" && exit 1 ;; \
    esac \
    && wget -qO /usr/local/bin/mkcert "https://github.com/FiloSottile/mkcert/releases/download/v1.4.4/mkcert-v1.4.4-linux-${MKCERT_ARCH}" \
    && echo "${MKCERT_SHA256}  /usr/local/bin/mkcert" | sha256sum -c - \
    && chmod +x /usr/local/bin/mkcert
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

    # Comment out existing providers block and append expected one
    # Use sed to comment out providers block
    local tmp_file
    tmp_file=$(mktemp)
    local in_providers=false
    local providers_indent=-1

    while IFS= read -r line || [[ -n "$line" ]]; do
        local trimmed="${line#"${line%%[![:space:]]*}"}"
        local indent=$(( ${#line} - ${#trimmed} ))

        if [[ "$in_providers" == false ]]; then
            if [[ "$trimmed" =~ ^providers[[:space:]]*: ]]; then
                in_providers=true
                providers_indent=$indent
                echo "# $line" >> "$tmp_file"
                continue
            fi
            echo "$line" >> "$tmp_file"
        else
            if [[ -z "$trimmed" || "$trimmed" =~ ^# ]]; then
                echo "$line" >> "$tmp_file"
                continue
            fi
            if (( indent > providers_indent )); then
                echo "# $line" >> "$tmp_file"
            else
                in_providers=false
                echo "$line" >> "$tmp_file"
            fi
        fi
    done < "$config_file"

    # Append new providers block
    {
        echo ""
        echo "# Modified by daas-mkcert-controller"
        echo "providers:"
        echo "  file:"
        echo "    directory: /etc/traefik/dynamic"
        echo "    watch: true"
    } >> "$tmp_file"

    mv "$tmp_file" "$config_file"

    log_success "Traefik configuration updated"
    log_info "Previous providers configuration has been commented out"
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
    if ! grep -q "# Modified by daas-mkcert-controller" "$config_file" 2>/dev/null; then
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
  "version": "1.2.0",
  "description": "Docker service for local development that detects *.localhost domains used by Traefik, generates valid TLS certificates with mkcert, and keeps TLS configuration synchronized without restarting Traefik",
  "main": "index.js",
  "scripts": {
    "start": "node index.js"
  },
  "keywords": [
    "docker",
    "traefik",
    "mkcert",
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

# Install required tools and mkcert binary
RUN apk add --no-cache \
    ca-certificates \
    nss-tools \
    && ARCH=$(uname -m) \
    && case "$ARCH" in \
        x86_64) MKCERT_ARCH="amd64"; MKCERT_SHA256="6d31c65b03972c6dc4a14ab429f2928300518b26503f58723e532d1b0a3bbb52" ;; \
        aarch64) MKCERT_ARCH="arm64"; MKCERT_SHA256="b98f2cc69fd9147fe4d405d859c57504571adec0d3611c3eefd04107c7ac00d0" ;; \
        armv7l) MKCERT_ARCH="arm"; MKCERT_SHA256="2f22ff62dfc13357e147e027117724e7ce1ff810e30d2b061b05b668ecb4f1d7" ;; \
        *) echo "Unsupported architecture: $ARCH" && exit 1 ;; \
    esac \
    && wget -qO /usr/local/bin/mkcert "https://github.com/FiloSottile/mkcert/releases/download/v1.4.4/mkcert-v1.4.4-linux-${MKCERT_ARCH}" \
    && echo "${MKCERT_SHA256}  /usr/local/bin/mkcert" | sha256sum -c - \
    && chmod +x /usr/local/bin/mkcert

# Create app directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm install --production

# Copy application code
COPY index.js banner.js parseBool.js validateConfig.js ./

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
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');
const { printBanner, isBannerShown } = require('./banner');
const { parseBool } = require('./parseBool');
const { validateNotEmpty, validateDirectory } = require('./validateConfig');

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
function extractDomainsFromLabels(labels) {
  const domains = new Set();
  const routers = parseTraefikLabels(labels);
  log(`Processing labels: ${JSON.stringify(labels)}`, 'DEBUG');
  
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
                log(`Found TLS-enabled domain: ${domain} (router: ${routerName})`, 'DEBUG');
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

// Generate certificate for a domain
function generateCertificate(domain) {
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

    log(`Generating certificate for: ${domain}`, 'INFO');
    execSync(`mkcert -cert-file "${certPath}" -key-file "${keyPath}" "${domain}"`, {
      cwd: CERTS_DIR,
      stdio: 'inherit'
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
      return;
    }

    const certsRelPath = path.relative(dynamicPath, CERTS_DIR);
    const certificates = domains.map(d => ({
      certFile: `${certsRelPath}/${d}.pem`,
      keyFile: `${certsRelPath}/${d}-key.pem`
    }));

    const yml = `# Auto-generated by daas-mkcert-controller
# Do not edit manually
tls:
  certificates:
${certificates.map(cert => `    - certFile: ${cert.certFile}
      keyFile: ${cert.keyFile}`).join('\n')}
`;

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
    const allDomains = new Set();
    
    for (const containerInfo of containers) {
      if (containerInfo.Labels) {
        const domains = extractDomainsFromLabels(containerInfo.Labels);
        domains.forEach(d => allDomains.add(d));
      }
    }
    
    const domainList = Array.from(allDomains);
    log(`Found ${domainList.length} TLS-enabled localhost domain(s)`, 'INFO');
    
    // Generate certificates for all domains
    domainList.forEach(domain => generateCertificate(domain));
    
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
        local _saved_version="$VERSION"
        . /etc/os-release
        VERSION="$_saved_version"
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
