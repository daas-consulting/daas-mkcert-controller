# Quick Reference - daas-mkcert-controller

## Installation

```bash
# Quick install (recommended)
curl -fsSL https://raw.githubusercontent.com/daas-consulting/daas-mkcert-controller/main/install.sh | bash

# Install with CA
curl -fsSL https://raw.githubusercontent.com/daas-consulting/daas-mkcert-controller/main/install.sh | INSTALL_CA=true bash

# Download and install
wget https://raw.githubusercontent.com/daas-consulting/daas-mkcert-controller/main/install.sh
chmod +x install.sh
./install.sh install
```

## Commands

| Command | Description |
|---------|-------------|
| `./install.sh install` | Build image and start controller |
| `./install.sh uninstall` | Stop and remove controller |
| `./install.sh status` | Check controller status |
| `./install.sh logs` | View controller logs |
| `./install.sh help` | Show help information |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CONTAINER_NAME` | `daas-mkcert-controller` | Container name |
| `IMAGE_NAME` | `daas-mkcert-controller:latest` | Docker image name |
| `INSTALL_CA` | `false` | Install mkcert CA |
| `TRAEFIK_DIR` | `/etc/traefik` (root) · `~/.traefik` (non-root) | Traefik config directory |
| `CERTS_DIR` | `/var/lib/daas-mkcert/certs` (root) · `~/.daas-mkcert/certs` (non-root) | Certificates directory |
| `MKCERT_CA_DIR` | `~/.local/share/mkcert` | mkcert CA directory |

## Examples

### Basic Setup with Traefik

1. Start Traefik:
```bash
docker run -d --name traefik \
  -p 80:80 -p 443:443 -p 8080:8080 \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -v ./traefik:/etc/traefik \
  traefik:v2.10 \
  --providers.docker=true \
  --entrypoints.web.address=:80 \
  --entrypoints.websecure.address=:443
```

2. Install controller:
```bash
INSTALL_CA=true ./install.sh install
```

3. Start an app with Traefik labels:
```bash
docker run -d --name myapp \
  --label "traefik.enable=true" \
  --label "traefik.http.routers.myapp.rule=Host(\`myapp.localhost\`)" \
  --label "traefik.http.routers.myapp.tls=true" \
  nginx:alpine
```

4. Check logs:
```bash
./install.sh logs
# Should show: "Certificate generated for myapp.localhost"
```

### Custom Configuration

```bash
INSTALL_CA=true \
TRAEFIK_DIR=/custom/traefik \
CERTS_DIR=/custom/certs \
./install.sh install
```

## Traefik Label Format

For the controller to detect domains, use this format:

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.NAME.rule=Host(`domain.localhost`)"
  - "traefik.http.routers.NAME.tls=true"
```

Multiple domains:
```yaml
labels:
  - "traefik.http.routers.NAME.rule=Host(`app1.localhost`) || Host(`app2.localhost`)"
```

## Troubleshooting

### Container won't start
```bash
# Check if Traefik is running
docker ps | grep traefik

# Check permissions
./install.sh status

# View detailed logs
docker logs daas-mkcert-controller
```

### Certificates not generated
```bash
# Verify domain format (must end with .localhost)
docker inspect myapp | grep traefik.http.routers

# Check controller logs for errors
./install.sh logs
```

### Permission errors
```bash
# Add user to docker group
sudo usermod -aG docker $USER
newgrp docker

# Fix directory permissions
sudo chown -R $USER:docker /var/lib/daas-mkcert
```

## File Locations

| What | Where |
|------|-------|
| Certificates | `/var/lib/daas-mkcert/certs/` |
| CA files | `~/.local/share/mkcert/` |
| Traefik config | `/etc/traefik/` |
| Container logs | `docker logs daas-mkcert-controller` |

## Certificate Format

Generated certificates follow this naming:

```
/var/lib/daas-mkcert/certs/
├── domain.localhost.pem       # Certificate
└── domain.localhost-key.pem   # Private key
```

## Requirements

- ✅ Linux (Ubuntu, Debian, Fedora, etc.)
- ✅ Docker installed and running
- ✅ Traefik container running
- ✅ User with Docker permissions

## Support

- 📖 [Full Documentation](README.md)
- 🧪 [Testing Guide](TESTING.md)
- 📝 [Implementation Details](IMPLEMENTATION.md)
- 💻 [Example Configuration](docker-compose.example.yml)

## Quick Health Check

```bash
# 1. Check controller status
./install.sh status

# 2. View recent logs
docker logs --tail 50 daas-mkcert-controller

# 3. List generated certificates
ls -lh /var/lib/daas-mkcert/certs/

# 4. Check Traefik is running
docker ps | grep traefik
```

## Uninstall

```bash
# Remove everything
./install.sh uninstall
# Answer 'y' to remove image
# Answer 'y' to remove certificates (if desired)
```

---

**Version:** 1.0.0  
**License:** MIT  
**Author:** DAAS Consulting
