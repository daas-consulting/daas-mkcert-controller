#!/bin/bash

#############################################################################
# daas-mkcert-controller CA installer (Docker-based alternative)
# 
# This script provides an alternative to installing mkcert on the host.
# It uses a Docker container to generate the CA files and provides
# instructions for manual trust store installation.
#
# Use this if you prefer not to install mkcert on your host machine.
#############################################################################

set -e

VERSION="1.1.0"

# Configuration
MKCERT_CA_DIR="${MKCERT_CA_DIR:-$HOME/.local/share/mkcert}"
HELPER_IMAGE="daas-mkcert-helper:latest"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

# Display banner
show_banner() {
    echo -e "${CYAN}"
    echo "╔════════════════════════════════════════╗"
    echo "║  daas-mkcert-controller CA Installer  ║"
    echo "║         (Docker-based method)         ║"
    echo "╚════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Show usage
show_usage() {
    cat << EOF
Usage: $0 [command]

Commands:
    generate    Generate CA files using Docker (no host installation)
    install     Install CA in system trust store (requires sudo)
    status      Check CA installation status
    help        Show this help message

Environment Variables:
    MKCERT_CA_DIR    CA directory (default: ~/.local/share/mkcert)

Examples:
    # Generate CA files using Docker
    $0 generate

    # Install CA in system trust store
    $0 install

    # Check status
    $0 status

Note: This is an alternative to installing mkcert on the host.
The standard install.sh script is recommended for most users.

EOF
}

# Generate CA using Docker container
generate_ca() {
    log_info "Generating CA using Docker container..."
    
    # Create CA directory if it doesn't exist
    mkdir -p "$MKCERT_CA_DIR"
    
    # Check if CA already exists
    if [[ -f "$MKCERT_CA_DIR/rootCA.pem" ]] && [[ -f "$MKCERT_CA_DIR/rootCA-key.pem" ]]; then
        log_warn "CA already exists at $MKCERT_CA_DIR"
        read -p "Do you want to regenerate it? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Keeping existing CA"
            return 0
        fi
    fi
    
    # Build helper image if needed
    log_info "Building helper Docker image..."
    docker build -t "$HELPER_IMAGE" -f - . << 'DOCKERFILE'
FROM alpine:3.19
RUN apk add --no-cache ca-certificates nss-tools mkcert
WORKDIR /work
CMD ["/bin/sh"]
DOCKERFILE
    
    log_success "Helper image built: $HELPER_IMAGE"
    
    # Run mkcert to generate CA files
    log_info "Generating CA files..."
    docker run --rm \
        -v "$MKCERT_CA_DIR:/root/.local/share/mkcert" \
        -e CAROOT=/root/.local/share/mkcert \
        "$HELPER_IMAGE" \
        sh -c 'mkcert -install 2>&1 | grep -v "trust store" || true; ls -la /root/.local/share/mkcert/'
    
    # Verify files were created
    if [[ -f "$MKCERT_CA_DIR/rootCA.pem" ]] && [[ -f "$MKCERT_CA_DIR/rootCA-key.pem" ]]; then
        log_success "CA files generated successfully!"
        log_info "CA files location: $MKCERT_CA_DIR"
        echo ""
        log_warn "IMPORTANT: The CA files have been created, but they are NOT yet installed in your system's trust store."
        log_info "To complete the installation, run: $0 install"
        echo ""
        return 0
    else
        log_error "Failed to generate CA files"
        return 1
    fi
}

# Install CA in system trust store
install_ca() {
    log_info "Installing CA in system trust store..."
    
    # Check if CA files exist
    if [[ ! -f "$MKCERT_CA_DIR/rootCA.pem" ]]; then
        log_error "CA files not found in $MKCERT_CA_DIR"
        log_info "Run '$0 generate' first to create the CA files"
        return 1
    fi
    
    # Detect distribution
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        local distro="$ID"
    else
        log_error "Cannot detect Linux distribution"
        return 1
    fi
    
    log_info "Detected distribution: $distro"
    
    case "$distro" in
        ubuntu|debian|pop|linuxmint)
            log_info "Installing CA for Debian/Ubuntu-based systems..."
            
            # Copy CA to system location
            sudo cp "$MKCERT_CA_DIR/rootCA.pem" /usr/local/share/ca-certificates/mkcert-rootCA.crt
            
            # Update CA trust store
            sudo update-ca-certificates
            
            log_success "CA installed in system trust store"
            ;;
            
        fedora|rhel|centos|rocky|almalinux)
            log_info "Installing CA for Fedora/RHEL-based systems..."
            
            # Copy CA to system location
            sudo cp "$MKCERT_CA_DIR/rootCA.pem" /etc/pki/ca-trust/source/anchors/mkcert-rootCA.crt
            
            # Update CA trust store
            sudo update-ca-trust
            
            log_success "CA installed in system trust store"
            ;;
            
        arch|manjaro)
            log_info "Installing CA for Arch-based systems..."
            
            # Copy CA to system location
            sudo cp "$MKCERT_CA_DIR/rootCA.pem" /etc/ca-certificates/trust-source/anchors/mkcert-rootCA.crt
            
            # Update CA trust store
            sudo trust extract-compat
            
            log_success "CA installed in system trust store"
            ;;
            
        *)
            log_error "Unsupported distribution: $distro"
            log_info "Manual installation required. Copy $MKCERT_CA_DIR/rootCA.pem to your system's CA directory."
            return 1
            ;;
    esac
    
    # Install in Firefox NSS (if Firefox is installed)
    install_nss_firefox
    
    # Install in Chrome NSS (if Chrome is installed)
    install_nss_chrome
    
    echo ""
    log_success "CA installation complete!"
    log_info "You may need to restart your browser for changes to take effect"
}

# Install CA in Firefox NSS database
install_nss_firefox() {
    local firefox_dir="$HOME/.mozilla/firefox"
    
    if [[ ! -d "$firefox_dir" ]]; then
        log_info "Firefox not found, skipping NSS installation"
        return 0
    fi
    
    log_info "Installing CA in Firefox NSS database..."
    
    # Find Firefox profiles
    for profile in "$firefox_dir"/*.default* "$firefox_dir"/*.dev-edition-default*; do
        if [[ -d "$profile" ]]; then
            local profile_name=$(basename "$profile")
            log_info "  Installing in Firefox profile: $profile_name"
            
            # Use certutil to add CA to NSS database
            if command -v certutil &> /dev/null; then
                certutil -A -n "mkcert CA" -t "C,," -i "$MKCERT_CA_DIR/rootCA.pem" -d sql:"$profile" 2>/dev/null || true
            else
                log_warn "  certutil not found, using Docker to install in Firefox NSS..."
                docker run --rm \
                    -v "$MKCERT_CA_DIR:/ca:ro" \
                    -v "$profile:/profile" \
                    "$HELPER_IMAGE" \
                    certutil -A -n "mkcert CA" -t "C,," -i /ca/rootCA.pem -d sql:/profile 2>/dev/null || true
            fi
        fi
    done
    
    log_success "Firefox NSS database updated"
}

# Install CA in Chrome NSS database
install_nss_chrome() {
    local nssdb="$HOME/.pki/nssdb"
    
    if [[ ! -d "$nssdb" ]]; then
        log_info "Chrome NSS database not found, skipping"
        return 0
    fi
    
    log_info "Installing CA in Chrome NSS database..."
    
    # Use certutil to add CA to NSS database
    if command -v certutil &> /dev/null; then
        certutil -A -n "mkcert CA" -t "C,," -i "$MKCERT_CA_DIR/rootCA.pem" -d sql:"$nssdb" 2>/dev/null || true
    else
        log_warn "certutil not found, using Docker to install in Chrome NSS..."
        docker run --rm \
            -v "$MKCERT_CA_DIR:/ca:ro" \
            -v "$nssdb:/nssdb" \
            "$HELPER_IMAGE" \
            certutil -A -n "mkcert CA" -t "C,," -i /ca/rootCA.pem -d sql:/nssdb 2>/dev/null || true
    fi
    
    log_success "Chrome NSS database updated"
}

# Check CA installation status
check_status() {
    log_info "Checking CA installation status..."
    echo ""
    
    # Check if CA files exist
    if [[ -f "$MKCERT_CA_DIR/rootCA.pem" ]] && [[ -f "$MKCERT_CA_DIR/rootCA-key.pem" ]]; then
        log_success "CA files found: $MKCERT_CA_DIR"
        echo "  - rootCA.pem"
        echo "  - rootCA-key.pem"
    else
        log_error "CA files not found in $MKCERT_CA_DIR"
        log_info "Run '$0 generate' to create them"
        return 1
    fi
    
    echo ""
    
    # Check system trust store
    log_info "Checking system trust store..."
    
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        case "$ID" in
            ubuntu|debian|pop|linuxmint)
                if [[ -f /usr/local/share/ca-certificates/mkcert-rootCA.crt ]]; then
                    log_success "CA installed in Debian/Ubuntu trust store"
                else
                    log_warn "CA not found in system trust store"
                    log_info "Run '$0 install' to install it"
                fi
                ;;
            fedora|rhel|centos|rocky|almalinux)
                if [[ -f /etc/pki/ca-trust/source/anchors/mkcert-rootCA.crt ]]; then
                    log_success "CA installed in Fedora/RHEL trust store"
                else
                    log_warn "CA not found in system trust store"
                    log_info "Run '$0 install' to install it"
                fi
                ;;
            arch|manjaro)
                if [[ -f /etc/ca-certificates/trust-source/anchors/mkcert-rootCA.crt ]]; then
                    log_success "CA installed in Arch trust store"
                else
                    log_warn "CA not found in system trust store"
                    log_info "Run '$0 install' to install it"
                fi
                ;;
        esac
    fi
    
    echo ""
}

# Main function
main() {
    show_banner
    
    local command="${1:-help}"
    
    case "$command" in
        generate)
            generate_ca
            ;;
        install)
            install_ca
            ;;
        status)
            check_status
            ;;
        help|--help|-h)
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
