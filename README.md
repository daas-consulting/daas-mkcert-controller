# daas-mkcert-controller

Servicio Docker para desarrollo local que detecta dominios *.localhost usados por Traefik, genera certificados TLS válidos con mkcert y mantiene la configuración TLS sincronizada en caliente, sin reiniciar Traefik ni usar CAs públicas.

## 🚀 Características

- **Instalación con un solo comando**: Script Bash autoinstalable que construye, instala o desinstala completamente el servicio
- **Detección automática de dominios**: Monitorea eventos de Docker y labels de Traefik para detectar dominios `*.localhost`
- **Generación automática de certificados TLS**: Crea certificados válidos con mkcert sin intervención manual
- **Sincronización en caliente**: Monitorea archivos dinámicos de Traefik para mantener la configuración actualizada
- **Validación exhaustiva**: Verifica permisos, directorios y variables de entorno antes de cualquier operación
- **Solo para Linux**: Optimizado específicamente para sistemas Linux

## 📋 Requisitos

- **Sistema Operativo**: Linux (único sistema soportado)
- **Docker**: Instalado y en ejecución
- **Traefik**: Debe estar corriendo antes de iniciar el controller
- **Permisos**: Acceso de lectura/escritura al socket de Docker y directorios de configuración

## 🔧 Instalación Rápida

### Opción 1: Instalación directa con curl

```bash
# Instalación básica
curl -fsSL https://raw.githubusercontent.com/daas-consulting/daas-mkcert-controller/main/install.sh | bash

# Instalación con CA de mkcert
curl -fsSL https://raw.githubusercontent.com/daas-consulting/daas-mkcert-controller/main/install.sh | INSTALL_CA=true bash

# Instalación con directorios personalizados
curl -fsSL https://raw.githubusercontent.com/daas-consulting/daas-mkcert-controller/main/install.sh | \
  TRAEFIK_DIR=/custom/traefik \
  CERTS_DIR=/custom/certs \
  INSTALL_CA=true \
  bash
```

### Opción 2: Descarga y ejecución local

```bash
# Descargar el script
wget https://raw.githubusercontent.com/daas-consulting/daas-mkcert-controller/main/install.sh

# Hacer ejecutable
chmod +x install.sh

# Instalar
./install.sh install

# Instalar con CA
INSTALL_CA=true ./install.sh install
```

## 📖 Uso

### Comandos disponibles

```bash
# Instalar el servicio
./install.sh install

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
| `IMAGE_NAME` | Nombre de la imagen Docker | `daas-mkcert-controller:latest` |
| `INSTALL_CA` | Instalar CA de mkcert (`true`/`false`) | `false` |
| `TRAEFIK_DIR` | Directorio de configuración de Traefik | `/etc/traefik` |
| `CERTS_DIR` | Directorio para almacenar certificados | `/var/lib/daas-mkcert/certs` |
| `MKCERT_CA_DIR` | Directorio de la CA de mkcert | `~/.local/share/mkcert` |

## 🔍 Funcionamiento

### 1. Validaciones previas

El script realiza las siguientes validaciones antes de cualquier operación:

- ✅ Verifica que el sistema sea Linux
- ✅ Valida instalación y accesibilidad de Docker
- ✅ Comprueba permisos del usuario para usar Docker
- ✅ Valida acceso de lectura/escritura a directorios necesarios
- ✅ Verifica variables de entorno requeridas
- ✅ Confirma que Traefik está corriendo

### 2. Instalación de CA (opcional)

Si `INSTALL_CA=true`:

- Valida acceso de lectura/escritura al directorio de CA
- Instala la CA de mkcert si no existe
- Si ya existe, la reutiliza

### 3. Monitoreo y generación de certificados

El controller realiza las siguientes tareas:

1. **Escaneo inicial**: Busca dominios `*.localhost` en contenedores existentes
2. **Monitoreo de eventos Docker**: Detecta nuevos contenedores con labels de Traefik
3. **Monitoreo de archivos Traefik**: Vigila cambios en configuración dinámica
4. **Generación automática**: Crea certificados TLS para dominios detectados

### 4. Detección de dominios

El controller detecta dominios en:

- **Labels de Docker**: Lee labels de Traefik en contenedores (ej: `traefik.http.routers.*.rule`)
- **Archivos de Traefik**: Parsea archivos YAML/JSON en el directorio dinámico de Traefik

Ejemplo de label detectada:
```yaml
traefik.http.routers.myapp.rule: "Host(`myapp.localhost`)"
```

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

2. Comprobar que los dominios terminan en `.localhost`

3. Revisar logs para errores de mkcert:
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

## 📝 Ejemplos de uso

### Ejemplo 1: Instalación básica

```bash
# 1. Asegurar que Traefik está corriendo
docker ps | grep traefik

# 2. Instalar el controller
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
