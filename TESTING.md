# Testing Guide for daas-mkcert-controller

This guide provides instructions for testing the daas-mkcert-controller installation and functionality.

## Prerequisites for Testing

1. **Linux system** (Ubuntu, Debian, Fedora, etc.)
2. **Docker installed and running**
3. **User with Docker permissions** (member of docker group or sudo access)
4. **Traefik running** (for full integration tests)

## Basic Tests (No Traefik Required)

### Test 1: Script Execution

```bash
# Test help command
./install.sh help

# Expected: Shows usage information
```

### Test 2: Status Command

```bash
# Test status command
./install.sh status

# Expected: Shows "Container not found" if not installed
```

### Test 3: Environment Variables

```bash
# Test with custom environment variables
INSTALL_CA=true CERTS_DIR=/custom/certs ./install.sh help

# Expected: Help displays correctly
```

### Test 4: Validation Functions

```bash
# Test OS validation (should pass on Linux)
bash -c 'source ./install.sh; validate_os'

# Test Docker validation
bash -c 'source ./install.sh; validate_docker'
```

## Integration Tests (Requires Traefik)

### Setup Test Environment

1. **Start Traefik**:

```bash
# Create Traefik config directory
mkdir -p ./traefik/dynamic

# Start Traefik using the example docker-compose
docker run -d \
  --name traefik \
  -p 80:80 \
  -p 443:443 \
  -p 8080:8080 \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -v $(pwd)/traefik:/etc/traefik \
  traefik:v2.10 \
  --api.insecure=true \
  --providers.docker=true \
  --providers.docker.exposedbydefault=false \
  --providers.file.directory=/etc/traefik/dynamic \
  --providers.file.watch=true \
  --entrypoints.web.address=:80 \
  --entrypoints.websecure.address=:443
```

2. **Verify Traefik is running**:

```bash
docker ps | grep traefik
curl -s http://localhost:8080/api/version | grep Version
```

### Test 5: Installation

```bash
# Install daas-mkcert-controller
INSTALL_CA=true ./install.sh install

# Expected output:
# - ✓ Operating system validated: Linux
# - ✓ Docker daemon is accessible
# - ✓ Docker socket is accessible
# - ✓ Directory validated: /var/lib/daas-mkcert/certs
# - ✓ Environment variables validated
# - ✓ Traefik is running
# - Container started successfully
```

### Test 6: Container Status

```bash
# Check container status
./install.sh status

# Expected: Container is running

# Check logs
./install.sh logs

# Expected: Shows controller startup logs
```

### Test 7: Certificate Generation

1. **Start a test container with Traefik labels**:

```bash
docker run -d \
  --name test-app \
  --label "traefik.enable=true" \
  --label "traefik.http.routers.test.rule=Host(\`test.localhost\`)" \
  --label "traefik.http.routers.test.entrypoints=websecure" \
  --label "traefik.http.routers.test.tls=true" \
  nginx:alpine
```

2. **Check controller logs**:

```bash
docker logs -f daas-mkcert-controller

# Expected to see:
# - "Detected 1 localhost domain(s) in container /test-app"
# - "Generating certificate for: test.localhost"
# - "✓ Certificate generated for test.localhost"
```

3. **Verify certificates were created**:

```bash
ls -la /var/lib/daas-mkcert/certs/

# Expected files:
# - test.localhost.pem
# - test.localhost-key.pem
```

### Test 8: Dynamic File Monitoring

1. **Create a Traefik dynamic configuration**:

```bash
cat > ./traefik/dynamic/test-config.yml << EOF
http:
  routers:
    dynamic-test:
      rule: "Host(\`dynamic.localhost\`)"
      service: dynamic-test
      tls: true
  services:
    dynamic-test:
      loadBalancer:
        servers:
          - url: "http://localhost:8080"
EOF
```

2. **Check controller logs**:

```bash
docker logs -f daas-mkcert-controller

# Expected to see:
# - "Traefik file added: /etc/traefik/dynamic/test-config.yml"
# - "Generating certificate for: dynamic.localhost"
```

3. **Verify new certificates**:

```bash
ls -la /var/lib/daas-mkcert/certs/ | grep dynamic

# Expected files:
# - dynamic.localhost.pem
# - dynamic.localhost-key.pem
```

### Test 9: Uninstallation

```bash
# Uninstall the controller
./install.sh uninstall

# When prompted:
# - Choose 'y' to remove Docker image
# - Choose 'n' to keep certificates (for testing verification)

# Expected:
# - ✓ Container removed
# - ✓ Docker image removed (if selected)
```

### Test 10: Cleanup

```bash
# Stop test containers
docker stop test-app traefik
docker rm test-app traefik

# Clean up directories
sudo rm -rf /var/lib/daas-mkcert/certs
rm -rf ./traefik
```

## Automated Test Script

Save this as `test-suite.sh`:

```bash
#!/bin/bash

set -e

echo "=== daas-mkcert-controller Test Suite ==="
echo ""

# Test 1: Basic commands
echo "Test 1: Basic commands"
./install.sh help > /dev/null
./install.sh status > /dev/null
echo "✓ Basic commands work"

# Test 2: Syntax validation
echo "Test 2: Syntax validation"
node --check index.js
bash -n install.sh
echo "✓ Syntax is valid"

# Test 3: File structure
echo "Test 3: File structure"
[ -f package.json ] && echo "  ✓ package.json"
[ -f index.js ] && echo "  ✓ index.js"
[ -f Dockerfile ] && echo "  ✓ Dockerfile"
[ -f install.sh ] && echo "  ✓ install.sh"
[ -x install.sh ] && echo "  ✓ install.sh is executable"
[ -f README.md ] && echo "  ✓ README.md"
[ -f LICENSE ] && echo "  ✓ LICENSE"

# Test 4: Docker availability
echo "Test 4: Docker availability"
if command -v docker &> /dev/null; then
    echo "  ✓ Docker is installed"
    if docker info &> /dev/null; then
        echo "  ✓ Docker daemon is accessible"
    else
        echo "  ✗ Docker daemon is not accessible"
    fi
else
    echo "  ✗ Docker is not installed"
fi

echo ""
echo "=== Basic tests complete ==="
echo ""
echo "For integration tests:"
echo "1. Start Traefik"
echo "2. Run: INSTALL_CA=true ./install.sh install"
echo "3. Check logs: ./install.sh logs"
echo "4. Test with a labeled container"
echo "5. Run: ./install.sh uninstall"
```

Run it with:

```bash
chmod +x test-suite.sh
./test-suite.sh
```

## Expected Results

### Successful Installation

- All validations pass (✓)
- Docker image builds successfully
- Container starts and runs
- Controller connects to Docker events
- Controller scans existing containers
- Logs show "daas-mkcert-controller is running"

### Successful Certificate Generation

- Controller detects new containers
- Certificates are generated in CERTS_DIR
- Certificate files have correct permissions (readable)
- Logs show successful generation messages

### Successful Uninstallation

- Container stops cleanly
- Container is removed
- Image is removed (if selected)
- No errors in the process

## Troubleshooting Tests

### Test Fails: "Docker is not running"

```bash
# Check Docker status
sudo systemctl status docker

# Start Docker if needed
sudo systemctl start docker
```

### Test Fails: "Traefik is not running"

```bash
# Check if Traefik is actually running
docker ps | grep traefik

# Start Traefik first
docker run -d --name traefik ...
```

### Test Fails: "Permission denied"

```bash
# Add user to docker group
sudo usermod -aG docker $USER

# Re-login or run
newgrp docker
```

### Test Fails: Certificate not generated

```bash
# Check controller logs for errors
docker logs daas-mkcert-controller

# Verify domain ends with .localhost
# Verify Traefik labels are correct
# Check if mkcert is installed in container
docker exec daas-mkcert-controller mkcert -version
```

## Performance Tests

### Test Certificate Generation Speed

```bash
# Time certificate generation for 10 domains
time for i in {1..10}; do
  docker run -d \
    --name "test-$i" \
    --label "traefik.enable=true" \
    --label "traefik.http.routers.test$i.rule=Host(\`test$i.localhost\`)" \
    nginx:alpine
done

# Check how long it takes to generate all certificates
docker logs daas-mkcert-controller | grep "Certificate generated"

# Cleanup
for i in {1..10}; do
  docker stop "test-$i"
  docker rm "test-$i"
done
```

## Security Tests

### Test Permission Validation

```bash
# Test with no write permissions
mkdir -p /tmp/readonly-certs
chmod 444 /tmp/readonly-certs
CERTS_DIR=/tmp/readonly-certs ./install.sh install

# Expected: Should fail with permission error

# Cleanup
chmod 755 /tmp/readonly-certs
rmdir /tmp/readonly-certs
```

### Test CA Installation Validation

```bash
# Test CA installation when INSTALL_CA=false
INSTALL_CA=false ./install.sh install
docker logs daas-mkcert-controller | grep "CA installation not requested"

# Test CA installation when INSTALL_CA=true
./install.sh uninstall
INSTALL_CA=true ./install.sh install
docker logs daas-mkcert-controller | grep "CA installation requested"
```

## Continuous Integration Tests

For CI/CD pipelines:

```yaml
# .github/workflows/test.yml example
name: Test daas-mkcert-controller

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Validate syntax
        run: |
          node --check index.js
          bash -n install.sh
      
      - name: Test help command
        run: ./install.sh help
      
      - name: Test status command
        run: ./install.sh status
      
      - name: Start Traefik
        run: |
          docker run -d --name traefik \
            -v /var/run/docker.sock:/var/run/docker.sock:ro \
            traefik:v2.10 \
            --providers.docker=true
      
      - name: Install controller
        run: INSTALL_CA=true ./install.sh install
      
      - name: Check logs
        run: docker logs daas-mkcert-controller
      
      - name: Uninstall
        run: ./install.sh uninstall
```

---

## Summary

This testing guide covers:

- ✅ Basic functionality tests
- ✅ Integration tests with Traefik
- ✅ Certificate generation validation
- ✅ Permission and security tests
- ✅ Performance tests
- ✅ CI/CD integration

For questions or issues, please check the logs and documentation in README.md.
