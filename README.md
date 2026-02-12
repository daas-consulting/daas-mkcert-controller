# daas-mkcert-controller

Servicio Docker para desarrollo local que detecta dominios `*.localhost` usados por Traefik, genera certificados TLS válidos con openssl y mantiene la configuración TLS sincronizada en caliente, sin reiniciar Traefik ni usar CAs públicas.

## Características

- **Instalación con un solo comando** — Script Bash unificado que construye, instala y configura todo el servicio
- **CA instalada en el host** — La CA se genera con openssl y se instala en el sistema host para que los navegadores confíen en los certificados
- **Confianza en navegadores** — Instala la CA en las bases de datos NSS de Chrome/Chromium y Firefox (incluye soporte para instalaciones snap y flatpak)
- **Detección automática de dominios** — Monitorea eventos de Docker y labels de Traefik para detectar dominios `*.localhost` con TLS habilitado
- **Generación automática de certificados** — Crea certificados válidos con openssl sin intervención manual
- **Metadatos de contenedor en certificados** — Enriquece los campos Subject (CN, O, OU) con el nombre del proyecto Docker Compose y servicio
- **Sincronización en caliente** — Mantiene la configuración TLS actualizada sin reiniciar Traefik
- **Validación de configuración de Traefik** — Verifica y corrige automáticamente el provider de archivos dinámicos durante la instalación
- **Reconciliación programada** — Verificación periódica para mantener certificados sincronizados
- **Mínimas dependencias** — Solo requiere Docker y herramientas nativas del sistema operativo
- **Solo Linux** — Optimizado para sistemas Linux

## Requisitos

- **Sistema operativo**: Linux
- **Docker**: Instalado y en ejecución
- **Traefik**: Debe estar corriendo como contenedor Docker
- **Permisos**: Acceso al socket de Docker y directorios de configuración

## Instalación

### Con un solo comando

```bash
curl -fsSL https://raw.githubusercontent.com/daas-consulting/daas-mkcert-controller/main/install.sh | bash
```

### Descarga y ejecución local

```bash
wget https://raw.githubusercontent.com/daas-consulting/daas-mkcert-controller/main/install.sh
chmod +x install.sh
./install.sh install
```

### Sin instalación de CA

```bash
./install.sh install --disable-install-ca
```

## Comandos

```bash
./install.sh install       # Instalar el servicio
./install.sh uninstall     # Desinstalar el servicio
./install.sh status        # Ver estado
./install.sh logs          # Ver logs en tiempo real
./install.sh help          # Mostrar ayuda
```

## Variables de entorno

| Variable | Descripción | Valor por defecto |
|----------|-------------|-------------------|
| `CONTAINER_NAME` | Nombre del contenedor | `daas-mkcert-controller` |
| `IMAGE_NAME` | Nombre de la imagen Docker | `daas-mkcert-controller` |
| `IMAGE_TAG` | Tag de la imagen | `latest` |
| `INSTALL_CA` | Instalar CA en el sistema | `true` |
| `TRAEFIK_DIR` | Directorio de configuración de Traefik | `/etc/traefik` (root) · `~/.traefik` (non-root) |
| `CERTS_DIR` | Directorio para certificados | `/var/lib/daas-mkcert/certs` (root) · `~/.daas-mkcert/certs` (non-root) |
| `MKCERT_CA_DIR` | Directorio de la CA | `~/.local/share/mkcert` |
| `THROTTLE_MS` | Throttle para eventos Docker (ms) | `300` |
| `SCHEDULED_INTERVAL_MS` | Intervalo de reconciliación (ms) | `60000` |

### Opciones de línea de comandos

| Opción | Descripción |
|--------|-------------|
| `--install-ca=VALUE` | Establece la instalación de CA (`true`/`false`/`yes`/`no`/`si`/`no`/`1`/`0`) |
| `--disable-install-ca` | Desactiva la instalación de CA |

**Prioridad**: Argumentos CLI > Variables de entorno > Valores por defecto

## Funcionamiento

### Proceso de instalación

1. Valida sistema operativo, Docker, permisos y directorios
2. Detecta la configuración de Traefik y sus volúmenes
3. Valida la configuración estática de Traefik (providers de archivos dinámicos)
4. Genera la CA usando openssl en un contenedor Docker temporal (sin instalar herramientas extra en el host)
5. Instala la CA en el trust store del sistema usando comandos nativos del OS
6. Instala la CA en las bases de datos NSS de Chrome/Chromium y Firefox (vía imagen helper Docker con `certutil`)
7. Construye la imagen Docker del controller
8. Inicia el contenedor del controller

### Instalación de CA en navegadores

Los navegadores basados en Chromium y Firefox no usan el trust store del sistema directamente. Utilizan bases de datos NSS (Network Security Services) propias:

| Navegador | Base de datos NSS |
|-----------|-------------------|
| Chrome/Chromium | `~/.pki/nssdb` |
| Firefox (estándar) | `~/.mozilla/firefox/<profile>/` |
| Firefox (snap) | `~/snap/firefox/common/.mozilla/firefox/<profile>/` |
| Firefox (flatpak) | `~/.var/app/org.mozilla.firefox/.mozilla/firefox/<profile>/` |

El instalador construye una imagen Docker auxiliar (`daas-mkcert-helper`) con `certutil` para inyectar la CA en estas bases de datos sin necesidad de instalar `libnss3-tools` en el host.

Si la imagen auxiliar no existe (por ejemplo, después de un `docker image prune`), el instalador la reconstruye automáticamente.

### Validación de configuración de Traefik

Durante la instalación, el sistema verifica que Traefik tenga configurado el provider de archivos dinámicos:
El controller genera automáticamente el archivo `/etc/traefik/dynamic/tls.yml` con la configuración de todos los certificados:

```yaml
providers:
  file:
    directory: /etc/traefik/dynamic
    watch: true
```

Si la configuración difiere:
- Crea un backup con timestamp del archivo original (`.bak`)
- Comenta la configuración anterior de providers
- Agrega la configuración esperada
- Notifica al usuario los cambios realizados y el comando para reiniciar Traefik

Al desinstalar, el sistema detecta los cambios y restaura la configuración original desde el backup.

### Monitoreo y generación de certificados

El controller ejecuta las siguientes tareas dentro del contenedor:

1. **Escaneo inicial** — Detecta dominios `*.localhost` con TLS habilitado en contenedores existentes
2. **Monitoreo de eventos Docker** — Detecta cambios en contenedores con throttling configurable
3. **Monitoreo de archivos Traefik** — Vigila cambios en configuración dinámica
4. **Reconciliación programada** — Sincroniza certificados periódicamente
5. **Generación de certificados** — Crea certificados TLS con openssl, incluyendo metadatos del contenedor en los campos Subject
6. **Configuración TLS** — Genera y mantiene el archivo `tls.yml` para Traefik

### Detección de dominios

El controller detecta dominios en labels de Docker que cumplan ambas condiciones:

1. `traefik.http.routers.<name>.rule` con `Host(`*.localhost`)`
2. `traefik.http.routers.<name>.tls=true`

Solo se generan certificados para rutas con TLS explícitamente habilitado.

## Ejemplos de uso

### Labels de Traefik

```yaml
services:
  myapp:
    image: nginx:alpine
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.myapp.rule=Host(`myapp.localhost`)"
      - "traefik.http.routers.myapp.tls=true"
```

### Múltiples dominios

```yaml
labels:
  - "traefik.http.routers.multi.rule=Host(`app1.localhost`) || Host(`app2.localhost`)"
  - "traefik.http.routers.multi.tls=true"
```

### Directorios personalizados

```bash
TRAEFIK_DIR=/custom/traefik CERTS_DIR=/custom/certs ./install.sh install
```

## Archivo TLS generado

El controller genera automáticamente `/etc/traefik/dynamic/tls.yml`:

```yaml
# Auto-generated by daas-mkcert-controller
# Do not edit manually
tls:
  certificates:
    - certFile: certs/myapp.localhost.pem
      keyFile: certs/myapp.localhost-key.pem
```

## Desinstalación

```bash
./install.sh uninstall
```

El script:
- Detiene y elimina el contenedor
- Restaura la configuración de Traefik desde el backup (si fue modificada)
- Ofrece eliminar imagen Docker, CA, y certificados

## Estructura del proyecto

```
daas-mkcert-controller/
├── install.sh               # Script de instalación unificado
├── index.js                 # Aplicación principal del controller
├── banner.js                # Banner ASCII
├── certSubject.js           # Construcción de Subject para certificados
├── certSubject.test.js      # Tests de certSubject
├── opensslCert.js           # Generación de certificados con openssl
├── opensslCert.test.js      # Tests de opensslCert
├── buildTLSConfig.js        # Generación de configuración TLS YAML
├── buildTLSConfig.test.js   # Tests de buildTLSConfig
├── validateCertificates.js  # Validación de certificados contra CA
├── validateCertificates.test.js # Tests de validateCertificates
├── parseBool.js             # Utilidad de parseo de booleanos
├── parseBool.test.js        # Tests de parseBool
├── validateConfig.js        # Validación de configuración y directorios
├── validateConfig.test.js   # Tests de validateConfig
├── traefikLabels.js         # Parsing de labels de Traefik
├── traefikLabels.test.js    # Tests de traefikLabels
├── Dockerfile               # Imagen Docker del controller
├── package.json             # Dependencias Node.js
├── .dockerignore            # Exclusiones del build Docker
├── .gitignore               # Exclusiones de git
├── LICENSE                  # Licencia MIT
└── README.md                # Documentación
```

## Testing

```bash
npm test
```

## Solución de problemas

### El contenedor no inicia

```bash
docker ps | grep traefik          # Verificar que Traefik está corriendo
docker logs daas-mkcert-controller # Revisar logs del controller
./install.sh status                # Verificar estado general
```

### No se generan certificados

- Verificar que las labels incluyen `traefik.http.routers.<name>.tls=true`
- Verificar que los dominios terminan en `.localhost`
- Revisar logs: `docker logs -f daas-mkcert-controller`

### El navegador no confía en los certificados

```bash
./install.sh status                # Verificar CA en NSS de Chrome/Firefox
./install.sh install               # Reinstalar — reconstruye helper e instala CA en NSS
```

Causas comunes:
- La imagen `daas-mkcert-helper` fue eliminada (por `docker image prune` o desinstalación parcial)
- Firefox instalado vía snap/flatpak — el instalador v1.3.0+ busca en rutas alternativas
- Después de reinstalar, **reiniciar el navegador** para que cargue la nueva CA

Verificación manual:
```bash
# Chrome/Chromium
docker run --rm -v ~/.pki/nssdb:/nssdb:ro daas-mkcert-helper:latest certutil -d sql:/nssdb -L | grep mkcert

# Firefox (snap)
docker run --rm -v ~/snap/firefox/common/.mozilla/firefox/<profile>:/p:ro daas-mkcert-helper:latest certutil -d sql:/p -L | grep mkcert
```

### Error de permisos

```bash
sudo usermod -aG docker $USER     # Añadir usuario al grupo docker
newgrp docker                      # Aplicar sin reiniciar sesión
```

## Licencia

MIT — ver [LICENSE](LICENSE).

## Changelog

### v1.4.0

- **Migración de mkcert a openssl** — Se reemplaza mkcert por openssl para la generación de certificados, permitiendo control total sobre los campos Subject de los certificados
- **Metadatos de contenedor en certificados** — Los certificados ahora incluyen información del proyecto Docker Compose (Organization) y servicio (Organizational Unit) en los campos Subject
- **CA con identidad DAAS** — El certificado CA se genera con Subject: `CN=DAAS Development CA / O=DAAS Consulting / OU=daas-mkcert-controller v1.4.0`
- **Nuevos módulos**: `certSubject.js` (construcción de Subject) y `opensslCert.js` (generación de certificados con openssl)
- **Imagen Docker más ligera** — Se elimina la descarga del binario de mkcert (~5 MB) y se usa openssl del sistema (~1.5 MB)
- **Imagen helper simplificada** — `daas-mkcert-helper` ya no necesita mkcert, solo nss-tools y openssl

### v1.3.0

- **Fix: CA no se instalaba en navegadores** — La imagen helper Docker (`daas-mkcert-helper`) solo se construía durante la generación de CA. Si la CA ya existía (reinstalación), la imagen no se construía y la instalación en NSS fallaba silenciosamente. Ahora `ensure_helper_image()` se ejecuta siempre antes de las operaciones NSS.
- **Soporte para Firefox snap y flatpak** — Se detectan perfiles de Firefox en `~/snap/firefox/common/.mozilla/firefox/` y `~/.var/app/org.mozilla.firefox/.mozilla/firefox/` además de la ruta estándar.
- **Mejora en manejo de errores NSS** — Los errores de instalación en NSS ya no se suprimen silenciosamente. Se reportan al usuario con instrucciones de remediación.
- **Comando `status` mejorado** — Ahora verifica y reporta el estado de las bases de datos NSS de Chrome y Firefox, no solo el trust store del sistema.

### v1.2.0

- Validación de certificados existentes contra la CA actual
- Remoción automática de certificados inválidos
- Fingerprint de CA para identificación única

### v1.1.0

- `buildTLSConfig` con `tls.stores.default.defaultCertificate`
- Soporte para múltiples hosts en `Host()` separados por coma

### v1.0.0

- Versión inicial

**DAAS Consulting**
