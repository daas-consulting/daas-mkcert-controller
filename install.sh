#!/bin/bash

#############################################################################
# daas-mkcert-controller installer
# Self-installable script for building, installing, and uninstalling
# the daas-mkcert-controller Docker service
#############################################################################

set -e

# Script version
VERSION="1.0.0"

# Configuration defaults (can be overridden by environment variables)
CONTAINER_NAME="${CONTAINER_NAME:-daas-mkcert-controller}"
IMAGE_NAME="${IMAGE_NAME:-daas-mkcert-controller:latest}"
INSTALL_CA="${INSTALL_CA:-false}"
TRAEFIK_DIR="${TRAEFIK_DIR:-/etc/traefik}"
CERTS_DIR="${CERTS_DIR:-/var/lib/daas-mkcert/certs}"
MKCERT_CA_DIR="${MKCERT_CA_DIR:-$HOME/.local/share/mkcert}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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
    echo -e "${GREEN}[✓]${NC} $1"
}

log_fail() {
    echo -e "${RED}[✗]${NC} $1"
}

# Display banner
show_banner() {
    cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║       daas-mkcert-controller Installation Script         ║
║   Automatic TLS certificate generation for Traefik       ║
╚═══════════════════════════════════════════════════════════╝
EOF
    echo ""
}

# Show usage
show_usage() {
    cat << EOF
Usage: $0 [command] [options]

Commands:
    install     Build and install the daas-mkcert-controller
    uninstall   Stop and remove the daas-mkcert-controller
    status      Check the status of the controller
    logs        Show controller logs
    help        Show this help message

Environment Variables:
    CONTAINER_NAME      Container name (default: daas-mkcert-controller)
    IMAGE_NAME          Docker image name (default: daas-mkcert-controller:latest)
    INSTALL_CA          Install mkcert CA: true/false (default: false)
    TRAEFIK_DIR         Traefik config directory (default: /etc/traefik)
    CERTS_DIR           Certificates directory (default: /var/lib/daas-mkcert/certs)
    MKCERT_CA_DIR       mkcert CA directory (default: ~/.local/share/mkcert)

Examples:
    # Install with CA installation
    INSTALL_CA=true $0 install

    # Install with custom directories
    TRAEFIK_DIR=/custom/traefik CERTS_DIR=/custom/certs $0 install

    # Uninstall
    $0 uninstall

    # Install via curl (single command)
    curl -fsSL <script-url> | INSTALL_CA=true bash

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
    
    local dirs=("$CERTS_DIR")
    
    # Add Traefik directory if it should exist
    if [[ -d "$TRAEFIK_DIR" ]]; then
        dirs+=("$TRAEFIK_DIR")
    else
        log_warn "Traefik directory does not exist: $TRAEFIK_DIR"
        log_warn "Will create it or ensure it's mounted when Traefik runs"
    fi
    
    # Add CA directory if CA installation is requested
    if [[ "$INSTALL_CA" == "true" ]]; then
        dirs+=("$MKCERT_CA_DIR")
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
    if [[ "$INSTALL_CA" != "true" ]] && [[ "$INSTALL_CA" != "false" ]]; then
        log_fail "INSTALL_CA must be 'true' or 'false'"
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
    
    if docker ps --format '{{.Names}}' | grep -q traefik || \
       docker ps --format '{{.Image}}' | grep -q traefik; then
        log_success "Traefik is running"
        return 0
    else
        log_fail "Traefik is not running"
        log_error "daas-mkcert-controller requires Traefik to be running"
        log_error "Please start Traefik before installing the controller"
        return 1
    fi
}

# Create Dockerfile if running from stdin
create_project_files() {
    local work_dir="$1"
    
    log_info "Creating project files in $work_dir..."
    
    # Create package.json
    cat > "$work_dir/package.json" << 'PACKAGE_JSON_EOF'
{
  "name": "daas-mkcert-controller",
  "version": "1.0.0",
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
FROM node:18-alpine

# Install mkcert and required tools
RUN apk add --no-cache \
    curl \
    ca-certificates \
    nss-tools \
    && curl -JLO "https://dl.filippo.io/mkcert/latest?for=linux/amd64" \
    && chmod +x mkcert-v*-linux-amd64 \
    && mv mkcert-v*-linux-amd64 /usr/local/bin/mkcert

# Create app directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm install --production

# Copy application code
COPY index.js ./

# Create directories for certificates
RUN mkdir -p /certs

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
const { execSync, exec } = require('child_process');
const fs = require('fs');
const path = require('path');

// Configuration from environment variables
const INSTALL_CA = process.env.INSTALL_CA === 'true';
const TRAEFIK_DIR = process.env.TRAEFIK_DIR || '/etc/traefik';
const CERTS_DIR = process.env.CERTS_DIR || '/certs';
const MKCERT_CA_DIR = process.env.MKCERT_CA_DIR || '/root/.local/share/mkcert';

const docker = new Docker({ socketPath: '/var/run/docker.sock' });
const processedDomains = new Set();

// Logging utility
function log(message, level = 'INFO') {
  const timestamp = new Date().toISOString();
  console.log(`[${timestamp}] [${level}] ${message}`);
}

// Validate read/write access to a directory
function validateAccess(dir, description) {
  try {
    if (!fs.existsSync(dir)) {
      log(`Creating directory: ${dir}`, 'INFO');
      fs.mkdirSync(dir, { recursive: true, mode: 0o755 });
    }
    
    // Test write access
    const testFile = path.join(dir, '.access_test');
    fs.writeFileSync(testFile, 'test');
    fs.unlinkSync(testFile);
    
    log(`✓ Read/write access validated for ${description}: ${dir}`, 'INFO');
    return true;
  } catch (error) {
    log(`✗ No read/write access to ${description}: ${dir} - ${error.message}`, 'ERROR');
    return false;
  }
}

// Install mkcert CA if requested
function installCA() {
  if (!INSTALL_CA) {
    log('CA installation not requested (INSTALL_CA != true)', 'INFO');
    return true;
  }

  log('CA installation requested, validating access...', 'INFO');
  
  // Validate access to CA directory
  if (!validateAccess(MKCERT_CA_DIR, 'mkcert CA directory')) {
    log('Cannot install CA: insufficient permissions', 'ERROR');
    return false;
  }

  try {
    // Check if CA already exists
    const rootCAKey = path.join(MKCERT_CA_DIR, 'rootCA-key.pem');
    const rootCA = path.join(MKCERT_CA_DIR, 'rootCA.pem');
    
    if (fs.existsSync(rootCAKey) && fs.existsSync(rootCA)) {
      log('mkcert CA already exists', 'INFO');
      return true;
    }

    log('Installing mkcert CA...', 'INFO');
    execSync('mkcert -install', { stdio: 'inherit' });
    log('✓ mkcert CA installed successfully', 'INFO');
    return true;
  } catch (error) {
    log(`✗ Failed to install mkcert CA: ${error.message}`, 'ERROR');
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

// Extract localhost domains from Traefik labels
function extractDomainsFromLabels(labels) {
  const domains = new Set();
  
  for (const [key, value] of Object.entries(labels)) {
    // Look for Traefik router rules
    if (key.includes('traefik.http.routers') && key.endsWith('.rule')) {
      // Extract domains from rules like: Host(`example.localhost`) || Host(`app.localhost`)
      const matches = value.match(/Host\(`([^`]+\.localhost)`\)/g);
      if (matches) {
        matches.forEach(match => {
          const domain = match.match(/Host\(`([^`]+)`\)/)[1];
          if (domain.endsWith('.localhost')) {
            domains.add(domain);
          }
        });
      }
    }
  }
  
  return Array.from(domains);
}

// Generate certificate for a domain
function generateCertificate(domain) {
  if (processedDomains.has(domain)) {
    log(`Certificate for ${domain} already generated`, 'INFO');
    return;
  }

  try {
    const certPath = path.join(CERTS_DIR, `${domain}.pem`);
    const keyPath = path.join(CERTS_DIR, `${domain}-key.pem`);

    if (fs.existsSync(certPath) && fs.existsSync(keyPath)) {
      log(`Certificate files for ${domain} already exist`, 'INFO');
      processedDomains.add(domain);
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

// Monitor Docker events
async function monitorDockerEvents() {
  log('Starting Docker events monitoring...', 'INFO');
  
  try {
    const stream = await docker.getEvents();
    
    stream.on('data', async (chunk) => {
      try {
        const event = JSON.parse(chunk.toString());
        
        // Listen for container start events
        if (event.Type === 'container' && (event.Action === 'start' || event.Action === 'create')) {
          const container = docker.getContainer(event.id);
          const info = await container.inspect();
          
          if (info.Config.Labels) {
            const domains = extractDomainsFromLabels(info.Config.Labels);
            if (domains.length > 0) {
              log(`Detected ${domains.length} localhost domain(s) in container ${info.Name}`, 'INFO');
              domains.forEach(domain => generateCertificate(domain));
            }
          }
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
  
  try {
    const containers = await docker.listContainers();
    let totalDomains = 0;
    
    for (const containerInfo of containers) {
      if (containerInfo.Labels) {
        const domains = extractDomainsFromLabels(containerInfo.Labels);
        if (domains.length > 0) {
          log(`Found ${domains.length} localhost domain(s) in container ${containerInfo.Names[0]}`, 'INFO');
          domains.forEach(domain => generateCertificate(domain));
          totalDomains += domains.length;
        }
      }
    }
    
    log(`✓ Scan complete. Found ${totalDomains} localhost domain(s)`, 'INFO');
  } catch (error) {
    log(`✗ Error scanning existing containers: ${error.message}`, 'ERROR');
  }
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
    ignoreInitial: false,
    depth: 2
  });

  watcher.on('add', (filePath) => {
    log(`Traefik file added: ${filePath}`, 'INFO');
    processTraefikFile(filePath);
  });

  watcher.on('change', (filePath) => {
    log(`Traefik file changed: ${filePath}`, 'INFO');
    processTraefikFile(filePath);
  });

  watcher.on('error', (error) => {
    log(`Traefik file watcher error: ${error.message}`, 'ERROR');
  });

  log('✓ Traefik files monitoring started', 'INFO');
}

// Process Traefik configuration file
function processTraefikFile(filePath) {
  try {
    const content = fs.readFileSync(filePath, 'utf8');
    
    // Try to parse as JSON or YAML
    let config;
    if (filePath.endsWith('.json')) {
      config = JSON.parse(content);
    } else if (filePath.endsWith('.yml') || filePath.endsWith('.yaml')) {
      // Simple YAML parsing for Host() rules
      const matches = content.match(/Host\(`([^`]+\.localhost)`\)/g);
      if (matches) {
        matches.forEach(match => {
          const domain = match.match(/Host\(`([^`]+)`\)/)[1];
          if (domain.endsWith('.localhost')) {
            generateCertificate(domain);
          }
        });
      }
      return;
    }
    
    // Process JSON config
    if (config && config.http && config.http.routers) {
      for (const router of Object.values(config.http.routers)) {
        if (router.rule) {
          const matches = router.rule.match(/Host\(`([^`]+\.localhost)`\)/g);
          if (matches) {
            matches.forEach(match => {
              const domain = match.match(/Host\(`([^`]+)`\)/)[1];
              generateCertificate(domain);
            });
          }
        }
      }
    }
  } catch (error) {
    log(`Error processing Traefik file ${filePath}: ${error.message}`, 'ERROR');
  }
}

// Main startup function
async function main() {
  log('=== daas-mkcert-controller starting ===', 'INFO');
  log(`Configuration:`, 'INFO');
  log(`  - INSTALL_CA: ${INSTALL_CA}`, 'INFO');
  log(`  - TRAEFIK_DIR: ${TRAEFIK_DIR}`, 'INFO');
  log(`  - CERTS_DIR: ${CERTS_DIR}`, 'INFO');
  log(`  - MKCERT_CA_DIR: ${MKCERT_CA_DIR}`, 'INFO');

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

  log('=== daas-mkcert-controller is running ===', 'INFO');
  log('Press Ctrl+C to stop', 'INFO');
}

// Handle shutdown gracefully
process.on('SIGINT', () => {
  log('Shutting down...', 'INFO');
  process.exit(0);
});

process.on('SIGTERM', () => {
  log('Shutting down...', 'INFO');
  process.exit(0);
});

// Start the application
main().catch((error) => {
  log(`Fatal error: ${error.message}`, 'ERROR');
  console.error(error);
  process.exit(1);
});
INDEX_JS_EOF

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
DOCKERIGNORE_EOF

    log_success "Project files created"
}

# Build Docker image
build_image() {
    log_info "Building Docker image: $IMAGE_NAME..."
    
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
    
    # Build the image
    if docker build -t "$IMAGE_NAME" "$build_dir"; then
        log_success "Docker image built successfully"
        
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

# Install and run the controller
install_controller() {
    log_info "Installing daas-mkcert-controller..."
    
    # Run all validations
    validate_os
    validate_docker
    validate_permissions
    validate_environment
    validate_directories
    
    # Check if Traefik is running
    if ! check_traefik; then
        log_error "Please start Traefik and try again"
        exit 1
    fi
    
    # Build image if it doesn't exist
    if ! docker image inspect "$IMAGE_NAME" &>/dev/null; then
        log_info "Image not found, building..."
        build_image
    else
        log_info "Using existing image: $IMAGE_NAME"
        read -p "Do you want to rebuild the image? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            build_image
        fi
    fi
    
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
    )
    
    # Add Traefik directory if it exists
    if [[ -d "$TRAEFIK_DIR" ]]; then
        volume_args+=(-v "$TRAEFIK_DIR:/etc/traefik:ro")
    fi
    
    # Add CA directory if CA installation is requested
    if [[ "$INSTALL_CA" == "true" ]]; then
        volume_args+=(-v "$MKCERT_CA_DIR:/root/.local/share/mkcert")
    fi
    
    # Run the container
    log_info "Starting container..."
    if docker run -d \
        --name "$CONTAINER_NAME" \
        --restart unless-stopped \
        -e "INSTALL_CA=$INSTALL_CA" \
        -e "TRAEFIK_DIR=/etc/traefik" \
        -e "CERTS_DIR=/certs" \
        -e "MKCERT_CA_DIR=/root/.local/share/mkcert" \
        "${volume_args[@]}" \
        "$IMAGE_NAME"; then
        
        log_success "Container started successfully"
        log_info "Container name: $CONTAINER_NAME"
        log_info "View logs with: docker logs -f $CONTAINER_NAME"
        
        # Show initial logs
        sleep 2
        log_info "Initial logs:"
        docker logs "$CONTAINER_NAME" 2>&1 | tail -20
        
        return 0
    else
        log_fail "Failed to start container"
        exit 1
    fi
}

# Uninstall the controller
uninstall_controller() {
    log_info "Uninstalling daas-mkcert-controller..."
    
    # Stop and remove container
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log_info "Stopping container..."
        docker stop "$CONTAINER_NAME" 2>/dev/null || true
        
        log_info "Removing container..."
        docker rm "$CONTAINER_NAME" 2>/dev/null || true
        log_success "Container removed"
    else
        log_warn "Container not found: $CONTAINER_NAME"
    fi
    
    # Remove image
    if docker image inspect "$IMAGE_NAME" &>/dev/null; then
        read -p "Do you want to remove the Docker image? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Removing Docker image..."
            docker rmi "$IMAGE_NAME" 2>/dev/null || true
            log_success "Docker image removed"
        fi
    else
        log_warn "Image not found: $IMAGE_NAME"
    fi
    
    # Ask about certificate cleanup
    if [[ -d "$CERTS_DIR" ]]; then
        read -p "Do you want to remove generated certificates in $CERTS_DIR? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Removing certificates..."
            rm -rf "$CERTS_DIR"
            log_success "Certificates removed"
        fi
    fi
    
    log_success "Uninstallation complete"
}

# Show controller status
show_status() {
    log_info "Checking daas-mkcert-controller status..."
    
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log_success "Container is running"
        echo ""
        docker ps --filter "name=${CONTAINER_NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
        echo ""
        log_info "View logs with: docker logs -f $CONTAINER_NAME"
    elif docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log_warn "Container exists but is not running"
        echo ""
        docker ps -a --filter "name=${CONTAINER_NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
        echo ""
        log_info "Start with: docker start $CONTAINER_NAME"
    else
        log_warn "Container not found: $CONTAINER_NAME"
        log_info "Install with: $0 install"
    fi
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
    local command="${1:-}"
    
    case "$command" in
        install)
            show_banner
            install_controller
            ;;
        uninstall)
            show_banner
            uninstall_controller
            ;;
        status)
            show_status
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
                install_controller
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
