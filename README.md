# daas-mkcert-controller

Servicio Docker para desarrollo local que detecta dominios `*.localhost` usados por Traefik, genera certificados TLS válidos con mkcert y mantiene la configuración TLS sincronizada en caliente, sin reiniciar Traefik ni usar CAs públicas.

## Características

- **Instalación con un solo comando** — Script Bash unificado que construye, instala y configura todo el servicio
- **CA instalada en el host** — La CA de mkcert se instala en el sistema host para que los navegadores confíen en los certificados
- **Detección automática de dominios** — Monitorea eventos de Docker y labels de Traefik para detectar dominios `*.localhost` con TLS habilitado
- **Generación automática de certificados** — Crea certificados válidos con mkcert sin intervención manual
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
4. Genera la CA usando un contenedor Docker temporal (sin instalar mkcert en el host)
5. Instala la CA en el trust store del sistema usando comandos nativos del OS
6. Construye la imagen Docker del controller
7. Inicia el contenedor del controller

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
5. **Generación de certificados** — Crea certificados TLS con mkcert
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
├── install.sh              # Script de instalación unificado
├── index.js                # Aplicación principal del controller
├── banner.js               # Banner ASCII
├── parseBool.js            # Utilidad de parseo de booleanos
├── parseBool.test.js       # Tests de parseBool
├── validateConfig.js       # Validación de configuración y directorios
├── validateConfig.test.js  # Tests de validateConfig
├── traefikLabels.js        # Parsing de labels de Traefik
├── traefikLabels.test.js   # Tests de traefikLabels
├── Dockerfile              # Imagen Docker del controller
├── package.json            # Dependencias Node.js
├── .dockerignore           # Exclusiones del build Docker
├── .gitignore              # Exclusiones de git
├── LICENSE                 # Licencia MIT
└── README.md               # Documentación
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

### Error de permisos

```bash
sudo usermod -aG docker $USER     # Añadir usuario al grupo docker
newgrp docker                      # Aplicar sin reiniciar sesión
```

## Licencia

MIT — ver [LICENSE](LICENSE).

**DAAS Consulting**
