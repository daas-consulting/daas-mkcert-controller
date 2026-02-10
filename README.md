# daas-mkcert-controller

Servicio Docker para desarrollo local que detecta dominios *.localhost usados por Traefik, genera certificados TLS válidos con mkcert y mantiene la configuración TLS sincronizada en caliente, sin reiniciar Traefik ni usar CAs públicas.

## 🚀 Características

- **Instalación con un solo comando**: Script Bash autoinstalable que construye, instala o desinstala completamente el servicio
- **CA instalada en el host**: La CA de mkcert se instala automáticamente en el host Docker (no en el contenedor) para que los navegadores confíen en los certificados
- **Auto-instalación de mkcert**: Si mkcert no está presente, el script lo descarga e instala automáticamente
- **Detección automática de dominios**: Monitorea eventos de Docker y labels de Traefik para detectar dominios `*.localhost` con TLS habilitado
- **Filtrado por TLS**: Solo genera certificados para rutas que tengan TLS explícitamente habilitado
- **Generación automática de certificados TLS**: Crea certificados válidos con mkcert sin intervención manual
- **Sincronización en caliente**: Monitorea archivos dinámicos de Traefik para mantener la configuración actualizada
- **Control de eventos (throttling)**: Procesa eventos con un throttle configurable (default 300ms) para evitar sobrecarga
- **Reconciliación programada**: Verificación automática cada minuto para mantener sincronizados los certificados
- **Configuración TLS automática**: Genera y mantiene actualizado el archivo `tls.yml` de Traefik
- **Validación exhaustiva**: Verifica permisos, directorios, dependencias y versiones antes de cualquier operación
- **Solo para Linux**: Optimizado específicamente para sistemas Linux
- **Node.js LTS**: Basado en Node.js v24.13.0 LTS

## 📋 Requisitos

- **Sistema Operativo**: Linux (único sistema soportado)
- **Docker**: Instalado y en ejecución
- **Traefik**: Debe estar corriendo antes de iniciar el controller
- **Permisos**: Acceso de lectura/escritura al socket de Docker y directorios de configuración

## 🔧 Instalación Rápida

### Opción 1: Instalación directa con curl

```bash
# Instalación básica (CA se instala por defecto)
curl -fsSL https://raw.githubusercontent.com/daas-consulting/daas-mkcert-controller/main/install.sh | bash

# Instalación sin CA
curl -fsSL https://raw.githubusercontent.com/daas-consulting/daas-mkcert-controller/main/install.sh | INSTALL_CA=false bash

# Instalación con directorios personalizados
curl -fsSL https://raw.githubusercontent.com/daas-consulting/daas-mkcert-controller/main/install.sh | \
  TRAEFIK_DIR=/custom/traefik \
  CERTS_DIR=/custom/certs \
  bash
```

### Opción 2: Descarga y ejecución local

```bash
# Descargar el script
wget https://raw.githubusercontent.com/daas-consulting/daas-mkcert-controller/main/install.sh

# Hacer ejecutable
chmod +x install.sh

# Instalar (CA por defecto)
./install.sh install

# Instalar sin CA
./install.sh install --disable-install-ca
# o
INSTALL_CA=false ./install.sh install
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

## 🔍 Funcionamiento

### 1. Validaciones previas

El script realiza las siguientes validaciones antes de cualquier operación:

- ✅ Verifica que el sistema sea Linux
- ✅ Valida instalación y accesibilidad de Docker
- ✅ Comprueba permisos del usuario para usar Docker
- ✅ Valida acceso de lectura/escritura a directorios necesarios
- ✅ Verifica variables de entorno requeridas
- ✅ Confirma que Traefik está corriendo
- ✅ Verifica dependencias locales (curl, etc.)
- ✅ Comprueba existencia y versión de la imagen local
- ✅ Verifica instalación de certificados y CA

### 2. Instalación de CA (por defecto activada)

Por defecto `INSTALL_CA=true`:

- Instala mkcert en el host si no está presente (soporta múltiples distribuciones Linux)
- Valida acceso de lectura/escritura al directorio de CA
- Instala la CA de mkcert en el **host machine** (no en el contenedor) para que los navegadores confíen en los certificados
- Si la CA ya existe, la instala en el trust store del sistema host
- Los archivos de CA se comparten con el contenedor via volumen Docker

**Importante**: La CA se instala en el sistema host (donde corre Docker y el navegador), no dentro del contenedor. Esto permite que los navegadores en tu máquina confíen en los certificados generados.

Para deshabilitarla, usa `--disable-install-ca` o `INSTALL_CA=false`.

### 3. Monitoreo y generación de certificados

El controller realiza las siguientes tareas:

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

El controller genera automáticamente el archivo `/etc/traefik/dynamic/tls.yml` con la configuración de todos los certificados:

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
├── install.sh          # Script de instalación autocontenido
├── package.json        # Dependencias Node.js
├── index.js           # Aplicación principal del controller
├── Dockerfile         # Imagen Docker con Node.js y mkcert
├── .dockerignore      # Archivos excluidos del build
├── .gitignore         # Archivos excluidos del repositorio
└── README.md          # Esta documentación
```

## 🔐 Seguridad y permisos

### Permisos requeridos

- **Socket Docker**: Lectura del socket `/var/run/docker.sock`
- **Directorio de certificados**: Lectura/escritura en `CERTS_DIR`
- **Directorio de Traefik**: Lectura de configuración dinámica
- **Directorio de CA**: Lectura/escritura (solo si `INSTALL_CA=true`)

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
curl -fsSL https://raw.githubusercontent.com/daas-consulting/daas-mkcert-controller/main/install.sh | bash

# 3. Verificar estado
docker logs -f daas-mkcert-controller
```

### Ejemplo 2: Instalación con CA personalizada

```bash
# Instalar con CA en directorio personalizado
INSTALL_CA=true \
MKCERT_CA_DIR=/custom/ca \
CERTS_DIR=/custom/certs \
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

## 🗑️ Desinstalación

```bash
# Desinstalar completamente
./install.sh uninstall

# El script preguntará si desea:
# - Eliminar la imagen Docker
# - Eliminar certificados generados
```

La desinstalación:
- ✅ Detiene y elimina el contenedor
- ✅ Opcionalmente elimina la imagen Docker
- ✅ Opcionalmente elimina certificados generados
- ✅ NO elimina la CA de mkcert (para preservar confianza del sistema)

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
