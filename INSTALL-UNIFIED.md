# Instalador Unificado - daas-mkcert-controller

## 🎯 Descripción

Script unificado que combina **lo mejor de ambos métodos** sin requerir instalar mkcert en el host.

### ✨ Características

- ✅ **Sin instalar mkcert en el host** - Usa Docker para generar la CA
- ✅ **Mínimas dependencias locales** - Solo Docker + herramientas nativas del OS
- ✅ **Proceso unificado** - Todo en un solo script
- ✅ **Instalación automática de CA** - Usa comandos nativos del sistema (update-ca-certificates, etc.)
- ✅ **Configuración de navegadores** - Firefox y Chrome automáticamente
- ✅ **Install y uninstall** - Gestión completa del ciclo de vida

## 🚀 Uso Rápido

### Instalación

```bash
# Un solo comando instala TODO
./install-unified.sh install
```

Este comando ejecuta **automáticamente**:
1. ✅ Genera archivos de CA usando Docker (sin instalar mkcert)
2. ✅ Instala CA en el trust store del sistema (usando comandos nativos)
3. ✅ Configura Firefox y Chrome (si están instalados)
4. ✅ Construye la imagen Docker del controlador
5. ✅ Inicia el contenedor con todos los directorios montados

### Verificar Estado

```bash
./install-unified.sh status
```

### Desinstalar

```bash
./install-unified.sh uninstall
```

Pregunta interactivamente qué deseas eliminar:
- Contenedor del controlador
- Imágenes Docker
- CA del trust store del sistema
- Archivos de CA
- Certificados generados

## 🔧 Cómo Funciona

### Proceso de Instalación

```
┌─────────────────────────────────────────────────────────────┐
│  ./install-unified.sh install                               │
└────────────────┬────────────────────────────────────────────┘
                 │
    ┌────────────▼─────────────┐
    │ Paso 1: Generar CA       │
    │ - Crea imagen helper     │
    │ - Alpine + mkcert        │
    │ - Monta: ~/.local/share/ │
    │ - Ejecuta: mkcert        │
    │ - Genera rootCA.pem      │
    └────────────┬─────────────┘
                 │
    ┌────────────▼─────────────┐
    │ Paso 2: Instalar CA      │
    │ - cp rootCA.pem a:       │
    │   /usr/local/share/...   │
    │ - update-ca-certificates │
    │ - Firefox NSS (certutil) │
    │ - Chrome NSS (certutil)  │
    └────────────┬─────────────┘
                 │
    ┌────────────▼─────────────┐
    │ Paso 3: Iniciar App      │
    │ - Construye imagen       │
    │ - Inicia contenedor      │
    │ - Monta directorios:     │
    │   * CA files             │
    │   * Certificates         │
    │   * Traefik config       │
    │   * Docker socket        │
    └──────────────────────────┘
```

## 💡 Diferencias con Otros Métodos

### Comparación

| Característica | install.sh | install-ca-docker.sh | **install-unified.sh** |
|----------------|------------|----------------------|------------------------|
| **Instala mkcert en host** | ✅ Sí | ❌ No | ❌ No |
| **Genera CA con Docker** | ❌ No | ✅ Sí | ✅ Sí |
| **Instala CA automático** | ✅ Sí | ⚠️ Manual | ✅ Sí |
| **Configura navegadores** | ✅ Sí | ⚠️ Manual | ✅ Sí |
| **Inicia controlador** | ✅ Sí | ⚠️ Separado | ✅ Sí |
| **Comandos necesarios** | 1 | 3 | 1 |
| **Dependencias locales** | mkcert | ninguna | ninguna |

### ¿Cuál usar?

#### Usa `install-unified.sh` si:
- ✅ Quieres la instalación más fácil SIN instalar mkcert
- ✅ Prefieres un proceso totalmente unificado
- ✅ Quieres mínimas dependencias locales
- ✅ **Recomendado para la mayoría de usuarios**

#### Usa `install.sh` si:
- ✅ No te importa instalar mkcert en el host
- ✅ Quieres el método más tradicional

#### Usa `install-ca-docker.sh` si:
- ✅ Necesitas control manual de cada paso
- ✅ Prefieres ejecutar comandos por separado

## 📋 Requisitos

### Mínimos
- **Docker**: Instalado y corriendo
- **Sistema**: Linux (Ubuntu, Debian, Fedora, Arch, etc.)
- **Permisos**: Usuario con acceso a Docker

### Herramientas Nativas (ya incluidas en la mayoría de sistemas)
- `update-ca-certificates` (Debian/Ubuntu)
- `update-ca-trust` (Fedora/RHEL)
- `trust` (Arch)
- `sudo` (para instalación en trust store del sistema)

### NO Requiere
- ❌ mkcert en el host
- ❌ Go
- ❌ Compiladores
- ❌ Herramientas adicionales

## 🔐 Seguridad

### ¿Cómo instala la CA sin mkcert?

El script usa **comandos nativos del sistema operativo**:

#### Debian/Ubuntu
```bash
# Copia el certificado
sudo cp rootCA.pem /usr/local/share/ca-certificates/mkcert-rootCA.crt

# Actualiza el trust store (comando nativo del sistema)
sudo update-ca-certificates
```

#### Fedora/RHEL
```bash
# Copia el certificado
sudo cp rootCA.pem /etc/pki/ca-trust/source/anchors/mkcert-rootCA.crt

# Actualiza el trust store
sudo update-ca-trust
```

#### Navegadores (Firefox/Chrome)
```bash
# Usa Docker con certutil (ya incluido en la imagen helper)
docker run --rm \
  -v ~/.local/share/mkcert:/ca:ro \
  -v ~/.mozilla/firefox/profile:/profile \
  daas-mkcert-helper \
  certutil -A -n "mkcert CA" -t "C,," -i /ca/rootCA.pem -d sql:/profile
```

### Beneficios de Seguridad

- ✅ **Menos software instalado** = Menor superficie de ataque
- ✅ **Usa herramientas del sistema** = Confiables y mantenidas
- ✅ **Contenedores temporales** = Se eliminan después de usarse
- ✅ **Sin binarios de terceros** = Solo desde repos oficiales (Alpine)

## 📝 Ejemplos

### Instalación Básica

```bash
# Clonar el repositorio
git clone https://github.com/daas-consulting/daas-mkcert-controller.git
cd daas-mkcert-controller

# Instalar todo con un comando
./install-unified.sh install
```

Salida esperada:
```
=== Step 1/3: Generating CA using Docker ===
[INFO] Building helper Docker image with mkcert...
[INFO] ✓ Helper image built: daas-mkcert-helper:latest
[INFO] Running mkcert in container to generate CA...
[INFO] ✓ CA files generated successfully!

=== Step 2/3: Installing CA in local trust store ===
[INFO] Installing CA for Debian/Ubuntu-based systems...
[INFO] ✓ CA installed in system trust store
[INFO] ✓ Firefox NSS database updated
[INFO] ✓ Chrome NSS database updated

=== Step 3/3: Building and starting controller ===
[INFO] Building Docker image...
[INFO] ✓ Image built successfully
[INFO] Starting container...
[INFO] ✓ Container started successfully

✓ Installation complete!

Summary:
  ✓ CA generated using Docker (no local mkcert installed)
  ✓ CA installed in system trust store
  ✓ CA installed in Firefox/Chrome (if available)
  ✓ Controller container running

Next steps:
  1. Restart your browser to load the new CA
  2. Start containers with Traefik labels
  3. Certificates will be generated automatically
```

### Verificar Instalación

```bash
./install-unified.sh status
```

Salida:
```
CA Files:
[INFO] ✓ CA files found: /home/user/.local/share/mkcert
  - rootCA.pem
  - rootCA-key.pem

System Trust Store:
[INFO] ✓ CA installed in Debian/Ubuntu trust store

Controller Container:
[INFO] ✓ Container is running: daas-mkcert-controller
  ID: abc123def456
  Status: Up 2 minutes
  Image: daas-mkcert-controller:latest

Traefik:
[INFO] ✓ Traefik is running
```

### Desinstalación Completa

```bash
./install-unified.sh uninstall
```

El script pregunta interactivamente:
```
Remove Docker image? (y/N): y
[INFO] ✓ Image removed

Remove helper image? (y/N): y
[INFO] ✓ Helper image removed

Remove CA from system trust store? (y/N): y
[INFO] ✓ CA removed from system trust store

Remove CA files from /home/user/.local/share/mkcert? (y/N): y
[INFO] ✓ CA files removed

Remove generated certificates from /home/user/.daas-mkcert/certs? (y/N): y
[INFO] ✓ Certificates removed

✓ Uninstallation complete!
```

### Instalación con Directorios Personalizados

```bash
# Configurar variables de entorno
export TRAEFIK_DIR=/custom/traefik
export CERTS_DIR=/custom/certs
export MKCERT_CA_DIR=/custom/ca

# Instalar
./install-unified.sh install
```

## 🐛 Solución de Problemas

### Error: "Docker daemon is not running"

```bash
# Verificar que Docker está corriendo
sudo systemctl status docker

# Iniciar Docker
sudo systemctl start docker
```

### Error: "No read access to Docker socket"

```bash
# Añadir usuario al grupo docker
sudo usermod -aG docker $USER

# Cerrar sesión y volver a entrar
# O cambiar de grupo en la sesión actual
newgrp docker
```

### Error: "Could not install CA in system"

Esto es normal si no tienes sudo o lo declinaste. La CA se generó correctamente, pero no se instaló en el trust store del sistema.

**Solución**:
```bash
# Instalar manualmente con sudo
sudo cp ~/.local/share/mkcert/rootCA.pem /usr/local/share/ca-certificates/mkcert-rootCA.crt
sudo update-ca-certificates
```

### Los certificados no funcionan en el navegador

1. **Reinicia el navegador** después de la instalación
2. Verifica que la CA esté instalada:
   ```bash
   ./install-unified.sh status
   ```
3. En Firefox:
   - Ir a `about:preferences#privacy`
   - Buscar "Certificates" → "View Certificates"
   - Pestaña "Authorities"
   - Buscar "mkcert CA"

## 🔄 Flujo Completo de Trabajo

### 1. Instalación Inicial

```bash
./install-unified.sh install
```

### 2. Iniciar Traefik (si no está corriendo)

```bash
docker run -d --name traefik \
  -p 80:80 -p 443:443 -p 8080:8080 \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -v ~/.traefik:/etc/traefik \
  traefik:v2.10 \
  --api.insecure=true \
  --providers.docker=true \
  --entrypoints.web.address=:80 \
  --entrypoints.websecure.address=:443
```

### 3. Iniciar una Aplicación con TLS

```bash
docker run -d --name myapp \
  --label "traefik.enable=true" \
  --label "traefik.http.routers.myapp.rule=Host(\`myapp.localhost\`)" \
  --label "traefik.http.routers.myapp.tls=true" \
  nginx:alpine
```

### 4. Acceder a la Aplicación

Abrir navegador en: https://myapp.localhost

✅ El certificado será confiable automáticamente

### 5. Monitorear

```bash
# Ver logs del controlador
docker logs -f daas-mkcert-controller

# Ver certificados generados
ls -la ~/.daas-mkcert/certs/
```

## 📚 Documentación Adicional

- [README.md](README.md) - Documentación principal
- [CA-INSTALLATION.md](CA-INSTALLATION.md) - Comparación de todos los métodos
- [QUICKSTART.md](QUICKSTART.md) - Guía de inicio rápido
- [TESTING.md](TESTING.md) - Guía de pruebas

## ❓ Preguntas Frecuentes

### ¿Por qué este método es mejor?

Combina lo mejor de ambos mundos:
- **Sin mkcert en el host** (como install-ca-docker.sh)
- **Proceso totalmente automático** (como install.sh)
- **Mínimas dependencias**

### ¿Qué comandos ejecuta en mi sistema?

Solo comandos nativos del OS:
- `update-ca-certificates` (Debian/Ubuntu)
- `update-ca-trust` (Fedora/RHEL)
- `trust extract-compat` (Arch)
- Docker commands

### ¿Es seguro?

Sí:
- Usa comandos estándar del sistema
- La imagen helper se construye localmente
- Contenedores temporales se eliminan
- Sin binarios sospechosos

### ¿Puedo cambiar a otro método después?

Sí, los archivos de CA son compatibles entre todos los métodos.

### ¿Necesito sudo?

Sí, pero solo para instalar la CA en el trust store del sistema. Si no tienes sudo:
- La CA se genera igual
- El contenedor funciona igual
- Solo falta la instalación en el trust store del sistema

---

**Versión**: 1.2.0  
**Fecha**: 2026-02-10  
**Licencia**: MIT  
**Autor**: DAAS Consulting
