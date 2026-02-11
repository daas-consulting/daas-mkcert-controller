# daas-mkcert-controller

Servicio Docker para desarrollo local que detecta dominios *.localhost usados por Traefik, genera certificados TLS válidos con mkcert y mantiene la configuración TLS sincronizada en caliente, sin reiniciar Traefik ni usar CAs públicas.

## 🚀 Características

- **Instalación con un solo comando**: Script Bash autoinstalable que construye, instala o desinstala completamente el servicio
- **CA instalada en el host**: La CA de mkcert se instala automáticamente en el host Docker (no en el contenedor) para que los navegadores confíen en los certificados
- **Único método de instalación**: Unificado todo en uno
- **Detección automática de dominios**: Monitorea eventos de Docker y labels de Traefik para detectar dominios `*.localhost` con TLS habilitado desde un contenedor
- **Filtrado por TLS**: Solo genera certificados para rutas que tengan TLS explícitamente habilitado desde un contenedor
- **Generación automática de certificados TLS**: Crea certificados válidos con mkcert sin intervención manual desde un contenedor
- **Sincronización en caliente**: Monitorea archivos dinámicos de Traefik para mantener la configuración actualizada desde un contenedor
- **Control de eventos (throttling)**: Procesa eventos con un throttle configurable (default 300ms) para evitar sobrecarga desde un contenedor
- **Reconciliación programada**: Verificación automática cada minuto para mantener sincronizados los certificados desde un contenedor
- **Configuración TLS automática**: Genera y mantiene actualizado el archivo `tls.yml` de Traefik
- **Validación exhaustiva**: Verifica permisos, directorios, dependencias y versiones antes de cualquier operación
- **Mínimas dependencias**: Solo Docker + herramientas nativas del sistema operativo
- **Solo para Linux**: Optimizado específicamente para sistemas Linux
- **Node.js LTS**: Basado en Node.js v24.13.0 LTS

## 📋 Requisitos

- **Sistema Operativo**: Linux (único sistema soportado)
- **Docker**: Instalado y en ejecución
- **Traefik**: Debe estar corriendo antes de iniciar el controller
- **Permisos**: Acceso de lectura/escritura al socket de Docker y directorios de configuración

### No requiere

- ❌ mkcert en el host
- ❌ Go
- ❌ Compiladores
- ❌ Herramientas adicionales

## 🔧 Instalación

### Instalación con un solo comando (curl)

```bash
# Un solo comando instala TODO:
# 1. Genera CA usando Docker (sin mkcert en host)
# 2. Instala CA en trust store (comandos nativos del OS)
# 3. Configura Firefox/Chrome
# 4. Construye la imagen Docker
# 5. Inicia el controlador

curl -fsSL https://raw.githubusercontent.com/daas-consulting/daas-mkcert-controller/main/install.sh | bash
```

### Descarga y ejecución local

```bash
# Descargar el script
wget https://raw.githubusercontent.com/daas-consulting/daas-mkcert-controller/main/install.sh
chmod +x install.sh

# Instalar (CA por defecto)
./install.sh install

# Instalar sin CA
./install.sh install --disable-install-ca
# o
INSTALL_CA=false ./install.sh install

# Instalación con directorios personalizados
TRAEFIK_DIR=/custom/traefik CERTS_DIR=/custom/certs ./install.sh install
```

## 📖 Uso

### Comandos disponibles

```bash
# Instalar el servicio (CA se instala por defecto)
./install.sh install

# Instalar sin CA
./install.sh install --disable-install-ca

# Desinstalar el servicio
./install.sh uninstall

# Ver estado del servicio
./install.sh status

# Ver logs en tiempo real
./install.sh logs

# Mostrar ayuda
./install.sh help
```

### Variables de entorno

| Variable | Descripción | Valor por defecto |
|----------|-------------|-------------------|
| `CONTAINER_NAME` | Nombre del contenedor | `daas-mkcert-controller` |
| `IMAGE_NAME` | Nombre de la imagen Docker | `daas-mkcert-controller` |
| `IMAGE_TAG` | Tag de la imagen Docker | `latest` |
| `INSTALL_CA` | Instalar CA de mkcert (`true`/`false`) | `true` |
| `TRAEFIK_DIR` | Directorio de configuración de Traefik | `/etc/traefik` (root) · `~/.traefik` (non-root) |
| `CERTS_DIR` | Directorio para almacenar certificados | `/var/lib/daas-mkcert/certs` (root) · `~/.daas-mkcert/certs` (non-root) |
| `MKCERT_CA_DIR` | Directorio de la CA de mkcert | `~/.local/share/mkcert` |
| `THROTTLE_MS` | Tiempo de throttle para eventos (ms) | `300` |
| `SCHEDULED_INTERVAL_MS` | Intervalo de reconciliación programada (ms) | `60000` (1 minuto) |

### Opciones de línea de comandos

| Opción | Descripción |
|--------|-------------|
| `--install-ca=VALUE` | Establece la instalación de CA (true/false/yes/no/si/no/1/0) |
| `--disable-install-ca` | Desactiva la instalación automática de CA (alias de `--install-ca=false`) |

**Prioridad**: Argumentos de línea de comandos > Variables de entorno > Valores por defecto

## 🔍 Funcionamiento

### 1. Validaciones previas

El script realiza las siguientes validaciones antes de cualquier operación:

- ✅ Verifica que el sistema sea Linux
- ✅ Valida instalación y accesibilidad de Docker
- ✅ Comprueba permisos del usuario para usar Docker
- ✅ Valida acceso de lectura/escritura a directorios necesarios
- ✅ Verifica variables de entorno requeridas
- ✅ Confirma que Traefik está corriendo
- ✅ Verifica instalación de certificados y CA

### 2. Instalación de CA (por defecto activada)

Por defecto `INSTALL_CA=true`:

- Genera los archivos de CA usando un contenedor Docker temporal con mkcert (no se instala mkcert en el host)
- Instala la CA en el trust store del sistema usando comandos nativos del OS:
  - **Debian/Ubuntu**: `update-ca-certificates`
  - **Fedora/RHEL**: `update-ca-trust`
  - **Arch**: `trust extract-compat`
- Configura Firefox y Chrome NSS databases si están instalados
- Los archivos de CA se comparten con el contenedor del controller via volumen Docker

**Importante**: La CA se instala en el sistema host (donde corre Docker y el navegador), no dentro del contenedor. Esto permite que los navegadores en tu máquina confíen en los certificados generados.

Para deshabilitarla, usa `--disable-install-ca` o `INSTALL_CA=false`.

### 3. Monitoreo y generación de certificados

El controller realiza las siguientes tareas desde un contenedor:

1. **Escaneo inicial**: Busca dominios `*.localhost` con TLS habilitado en contenedores existentes
2. **Monitoreo de eventos Docker**: Detecta nuevos contenedores y cambios con throttling (default 300ms)
3. **Monitoreo de archivos Traefik**: Vigila cambios en configuración dinámica
4. **Reconciliación programada**: Verifica y sincroniza certificados cada minuto
5. **Generación automática**: Crea certificados TLS solo para dominios con TLS habilitado
6. **Actualización de configuración**: Genera automáticamente el archivo `tls.yml` para Traefik

### 4. Detección de dominios (solo con TLS habilitado)

El controller detecta dominios en labels de Docker que cumplan **ambas** condiciones:

1. **Label de regla**: `traefik.http.routers.<name>.rule` con `Host(\`*.localhost\`)`
2. **Label de TLS**: `traefik.http.routers.<name>.tls=true`

**Importante**: Solo se generan certificados para rutas que tienen TLS explícitamente habilitado.

Ejemplo de labels correctas:
```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.myapp.rule=Host(`myapp.localhost`)"
  - "traefik.http.routers.myapp.tls=true"  # ← Requerido para generar certificado
```

### 5. Archivo de configuración TLS

El controller genera automáticamente el archivo `/etc/traefik/tls.yml` con la configuración de todos los certificados:

```yaml
# Auto-generated by daas-mkcert-controller
# Do not edit manually
tls:
  certificates:
    - certFile: /certs/myapp.localhost.pem
      keyFile: /certs/myapp.localhost-key.pem
    - certFile: /certs/api.localhost.pem
      keyFile: /certs/api.localhost-key.pem
```

Este archivo se actualiza automáticamente cada vez que se detectan cambios en los contenedores o en la configuración de Traefik.

## 📂 Estructura del proyecto

```
daas-mkcert-controller/
├── install.sh              # Script de instalación autocontenido
├── package.json            # Dependencias Node.js
├── index.js                # Aplicación principal del controller
├── banner.js               # Banner ASCII con colores
├── parseBool.js            # Utilidad de parseo de booleanos
├── parseBool.test.js       # Tests para parseBool
├── validateConfig.js       # Validación de configuración y directorios
├── validateConfig.test.js  # Tests para validateConfig
├── Dockerfile              # Imagen Docker con Node.js y mkcert
├── .dockerignore           # Archivos excluidos del build
├── .gitignore              # Archivos excluidos del repositorio
├── LICENSE                 # Licencia MIT
└── README.md               # Esta documentación
```

## 🔐 Seguridad y permisos

### Permisos requeridos

- **Socket Docker**: Lectura del socket `/var/run/docker.sock`
- **Directorio de certificados**: Lectura/escritura en `CERTS_DIR`
- **Directorio de Traefik**: Lectura de configuración dinámica
- **Directorio de CA**: Lectura/escritura (solo si `INSTALL_CA=true`)

### Cómo funciona la instalación de CA sin mkcert en el host

El script usa **comandos nativos del sistema operativo**:

**Debian/Ubuntu:**
```bash
sudo cp rootCA.pem /usr/local/share/ca-certificates/mkcert-rootCA.crt
sudo update-ca-certificates
```

**Fedora/RHEL:**
```bash
sudo cp rootCA.pem /etc/pki/ca-trust/source/anchors/mkcert-rootCA.crt
sudo update-ca-trust
```

**Arch:**
```bash
sudo cp rootCA.pem /etc/ca-certificates/trust-source/anchors/mkcert-rootCA.crt
sudo trust extract-compat
```

### Recomendaciones

1. **Ejecutar con usuario no-root**: Añadir usuario al grupo docker
   ```bash
   sudo usermod -aG docker $USER
   ```

2. **Directorios con permisos apropiados**:
   ```bash
   sudo chown -R $USER:docker /var/lib/daas-mkcert/certs
   ```

3. **Socket Docker accesible**:
   ```bash
   sudo chmod 666 /var/run/docker.sock
   ```

## 🛠️ Solución de problemas

### El contenedor no inicia

1. Verificar que Traefik está corriendo:
   ```bash
   docker ps | grep traefik
   ```

2. Revisar logs del controller:
   ```bash
   docker logs daas-mkcert-controller
   ```

3. Verificar permisos:
   ```bash
   ./install.sh status
   ```

### No se generan certificados

1. Verificar labels de Traefik en contenedores:
   ```bash
   docker inspect <container> | grep traefik
   ```

2. Verificar que las rutas tienen TLS habilitado:
   ```bash
   docker inspect <container> | grep -A 2 "traefik.http.routers"
   # Debe tener: traefik.http.routers.<name>.tls=true
   ```

3. Comprobar que los dominios terminan en `.localhost`

4. Revisar logs para errores de mkcert:
   ```bash
   docker logs -f daas-mkcert-controller
   ```

### Error de permisos

1. Verificar acceso al socket Docker:
   ```bash
   ls -l /var/run/docker.sock
   ```

2. Verificar permisos de directorios:
   ```bash
   ls -ld $CERTS_DIR $TRAEFIK_DIR
   ```

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

# Cerrar sesión y volver a entrar, o:
newgrp docker
```

### Error: "Could not install CA in system"

Esto es normal si no tienes sudo o lo declinaste. La CA se generó correctamente, pero no se instaló en el trust store del sistema.

```bash
# Instalar manualmente con sudo
sudo cp ~/.local/share/mkcert/rootCA.pem /usr/local/share/ca-certificates/mkcert-rootCA.crt
sudo update-ca-certificates
```

### Los certificados no funcionan en el navegador

1. **Reinicia el navegador** después de la instalación
2. Verifica que la CA esté instalada:
   ```bash
   ./install.sh status
   ```
3. En Firefox: ir a `about:preferences#privacy` → "Certificates" → "View Certificates" → "Authorities" → buscar "mkcert CA"

### Throttling y reconciliación

El sistema procesa eventos con throttling para evitar sobrecarga:
- **Throttling de eventos**: Máximo una reconciliación cada 300ms (configurable con `THROTTLE_MS`)
- **Reconciliación programada**: Se ejecuta cada 60 segundos (configurable con `SCHEDULED_INTERVAL_MS`)
- Si ya hay una reconciliación en curso, las nuevas se omiten

## 📝 Ejemplos de uso

### Ejemplo 1: Instalación básica

```bash
# 1. Asegurar que Traefik está corriendo
docker ps | grep traefik

# 2. Instalar el controller (CA se instala por defecto)
./install.sh install

# 3. Verificar estado
./install.sh status

# 4. Ver logs
./install.sh logs
```

### Ejemplo 2: Instalación con directorios personalizados

```bash
TRAEFIK_DIR=/custom/traefik \
CERTS_DIR=/custom/certs \
MKCERT_CA_DIR=/custom/ca \
./install.sh install
```

### Ejemplo 3: Contenedor con Traefik labels

```yaml
version: '3'
services:
  myapp:
    image: nginx:alpine
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.myapp.rule=Host(`myapp.localhost`)"
      - "traefik.http.routers.myapp.tls=true"
```

Cuando este contenedor se inicie, el controller automáticamente:
1. Detectará el dominio `myapp.localhost`
2. Generará certificados en `$CERTS_DIR/myapp.localhost.pem` y `myapp.localhost-key.pem`
3. Actualizará la configuración TLS de Traefik

### Ejemplo 4: Múltiples dominios

```yaml
labels:
  - "traefik.http.routers.multi.rule=Host(`app1.localhost`) || Host(`app2.localhost`)"
  - "traefik.http.routers.multi.tls=true"
```

### Ejemplo 5: Verificación rápida

```bash
# 1. Estado del controller
./install.sh status

# 2. Logs recientes
docker logs --tail 50 daas-mkcert-controller

# 3. Certificados generados
ls -lh ~/.daas-mkcert/certs/

# 4. Traefik corriendo
docker ps | grep traefik
```

## 🗑️ Desinstalación

```bash
# Desinstalar completamente
./install.sh uninstall
```

El script preguntará interactivamente:
- ✅ Detiene y elimina el contenedor
- ❓ ¿Eliminar la imagen Docker?
- ❓ ¿Eliminar la imagen helper?
- ❓ ¿Eliminar la CA del trust store del sistema?
- ❓ ¿Eliminar archivos de CA?
- ❓ ¿Eliminar certificados generados?

## 🧪 Testing

### Ejecutar tests unitarios

```bash
npm test
# Ejecuta: node parseBool.test.js && node validateConfig.test.js
```

### Tests manuales

```bash
# Test de ayuda
./install.sh help

# Test de estado
./install.sh status

# Test de validación de variables
INSTALL_CA=true ./install.sh help
```

## 🤝 Contribuir

Las contribuciones son bienvenidas. Por favor:

1. Fork el repositorio
2. Crea una rama para tu feature (`git checkout -b feature/AmazingFeature`)
3. Commit tus cambios (`git commit -m 'Add some AmazingFeature'`)
4. Push a la rama (`git push origin feature/AmazingFeature`)
5. Abre un Pull Request

## 📄 Licencia

Este proyecto está licenciado bajo la Licencia MIT - ver el archivo LICENSE para detalles.

## ✨ Autor

**DAAS Consulting**

---

## 🔗 Enlaces útiles

- [Documentación de mkcert](https://github.com/FiloSottile/mkcert)
- [Documentación de Traefik](https://doc.traefik.io/traefik/)
- [Docker Documentation](https://docs.docker.com/)
