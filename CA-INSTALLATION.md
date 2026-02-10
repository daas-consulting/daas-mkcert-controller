# CA Installation Methods

Este documento explica las dos formas de instalar la CA de mkcert para `daas-mkcert-controller`.

---

## 📋 Resumen de Opciones

| Método | Instalación de mkcert | Facilidad | Recomendado para |
|--------|----------------------|-----------|------------------|
| **Método 1: Automático (install.sh)** | Sí, en el host | ⭐⭐⭐⭐⭐ Muy fácil | La mayoría de usuarios |
| **Método 2: Docker (install-ca-docker.sh)** | No, solo usa Docker | ⭐⭐⭐ Moderado | Usuarios que prefieren no instalar software en el host |

---

## 🚀 Método 1: Instalación Automática (Recomendado)

### Descripción
Este método instala `mkcert` en tu máquina host y configura la CA automáticamente.

### Ventajas
✅ Completamente automático  
✅ Instala la CA en todos los navegadores y el sistema  
✅ No requiere pasos manuales  
✅ Funciona en Ubuntu, Debian, Fedora, Arch, y más  

### Desventajas
❌ Requiere instalar mkcert en el host  
❌ Puede requerir sudo para algunos pasos  

### Uso

```bash
# Instalación con un comando (instala mkcert y CA automáticamente)
curl -fsSL https://raw.githubusercontent.com/daas-consulting/daas-mkcert-controller/main/install.sh | bash

# O descarga y ejecuta localmente
wget https://raw.githubusercontent.com/daas-consulting/daas-mkcert-controller/main/install.sh
chmod +x install.sh
./install.sh install
```

### ¿Qué hace este método?

1. **Instala mkcert en tu sistema** (si no está instalado):
   - Intenta usar el gestor de paquetes (apt, dnf, pacman)
   - Si falla, descarga el binario desde GitHub
   - Lo instala en `~/.local/bin/mkcert`

2. **Crea e instala la CA**:
   - Ejecuta `mkcert -install` en el host
   - Instala la CA en el trust store del sistema
   - Configura Firefox, Chrome, y otros navegadores
   - Crea archivos en `~/.local/share/mkcert/`

3. **Inicia el contenedor**:
   - Monta el directorio de CA como volumen
   - El contenedor usa la CA para generar certificados

### Respuesta a las preguntas

> ¿La solución implementada instala mkcerts en la maquina local?

**Sí**, este método instala mkcert en la máquina local (host). Esto es necesario para:
- Instalar la CA en el trust store del sistema operativo
- Configurar los navegadores (Firefox, Chrome) para confiar en la CA
- Garantizar que los certificados generados sean confiables

---

## 🐳 Método 2: Instalación Basada en Docker (Alternativa)

### Descripción
Este método usa contenedores Docker para generar la CA sin instalar mkcert en el host.

### Ventajas
✅ No instala mkcert en el host  
✅ Todo se ejecuta en contenedores  
✅ Útil para entornos donde no se puede instalar software  

### Desventajas
❌ Requiere pasos manuales adicionales  
❌ Más complejo de usar  
❌ Aún requiere sudo para instalar la CA en el sistema  

### Uso

```bash
# 1. Generar archivos de CA usando Docker
./install-ca-docker.sh generate

# 2. Instalar CA en el trust store del sistema (requiere sudo)
./install-ca-docker.sh install

# 3. Verificar el estado
./install-ca-docker.sh status

# 4. Continuar con la instalación normal del controlador
./install.sh install
```

### ¿Qué hace este método?

1. **Genera archivos de CA usando Docker**:
   - Crea un contenedor temporal con mkcert
   - Ejecuta `mkcert -install` dentro del contenedor
   - Guarda los archivos CA en `~/.local/share/mkcert/` (volumen montado)

2. **Instala la CA en el sistema** (paso manual):
   - Copia `rootCA.pem` al directorio de certificados del sistema
   - Ejecuta `update-ca-certificates` (Debian/Ubuntu)
   - O `update-ca-trust` (Fedora/RHEL)
   - Configura Firefox y Chrome NSS databases

3. **Inicia el controlador normalmente**:
   - Usa `./install.sh install` como de costumbre
   - El contenedor usará la CA existente

### Respuesta a las preguntas

> ¿Hay forma de gestionar esto desde la imagen de docker, haciendo los mapeos de directorios locales?

**Sí**, este método usa Docker para generar los archivos de CA. Sin embargo, hay limitaciones:

**Lo que SÍ puede hacer Docker:**
- ✅ Generar los archivos de CA (rootCA.pem, rootCA-key.pem)
- ✅ Usar volúmenes para compartir estos archivos con el host
- ✅ Generar certificados usando la CA

**Lo que NO puede hacer Docker (requiere host):**
- ❌ Instalar la CA en el trust store del sistema operativo del host
- ❌ Configurar automáticamente Firefox/Chrome en el host
- ❌ Ejecutar `update-ca-certificates` en el host

**Motivo**: Los navegadores y el sistema operativo del host necesitan confiar en la CA, y esto solo puede hacerse modificando archivos del host que requieren privilegios elevados.

---

## 🔍 Comparación Detallada

### Flujo del Método 1 (Automático)

```
┌─────────────────────────────────────────┐
│          ./install.sh install          │
└──────────────────┬──────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────┐
│  1. Instala mkcert en el host          │
│     - Via apt/dnf/pacman                │
│     - O descarga binario                │
└──────────────────┬──────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────┐
│  2. Ejecuta: mkcert -install (en host) │
│     - Crea rootCA.pem y rootCA-key.pem  │
│     - Instala en sistema                │
│     - Configura Firefox/Chrome          │
└──────────────────┬──────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────┐
│  3. Inicia contenedor Docker           │
│     - Monta ~/.local/share/mkcert       │
│     - Usa CA para generar certificados  │
└─────────────────────────────────────────┘
```

### Flujo del Método 2 (Docker)

```
┌─────────────────────────────────────────┐
│    ./install-ca-docker.sh generate     │
└──────────────────┬──────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────┐
│  1. Crea contenedor temporal           │
│     - Imagen Alpine + mkcert            │
│     - Monta ~/.local/share/mkcert       │
└──────────────────┬──────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────┐
│  2. Dentro del contenedor:             │
│     - Ejecuta: mkcert -install          │
│     - Genera rootCA.pem, rootCA-key.pem │
│     - (Trust store del contenedor)      │
└──────────────────┬──────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────┐
│    ./install-ca-docker.sh install      │
│    (REQUIERE EJECUTAR MANUALMENTE)      │
└──────────────────┬──────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────┐
│  3. Copia CA al sistema host           │
│     - sudo cp a /usr/local/share/...    │
│     - sudo update-ca-certificates       │
│     - Configura Firefox/Chrome NSS      │
└──────────────────┬──────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────┐
│       ./install.sh install             │
└──────────────────┬──────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────┐
│  4. Inicia contenedor del controlador  │
│     - Monta ~/.local/share/mkcert       │
│     - Usa CA existente                  │
└─────────────────────────────────────────┘
```

---

## 🎯 ¿Cuál método elegir?

### Usa el Método 1 (Automático) si:
- ✅ Quieres la instalación más fácil y rápida
- ✅ No te importa instalar mkcert en tu sistema
- ✅ Quieres que todo funcione automáticamente
- ✅ Eres un usuario típico

**Recomendación**: Este es el método recomendado para el 95% de los usuarios.

### Usa el Método 2 (Docker) si:
- ✅ No quieres instalar mkcert en el host
- ✅ Trabajas en un entorno restringido
- ✅ Prefieres gestionar todo con Docker
- ✅ No te importa ejecutar pasos manuales adicionales

**Nota**: Incluso con este método, aún necesitarás ejecutar comandos con sudo en el host para instalar la CA en el trust store del sistema.

---

## 🔐 Seguridad

Ambos métodos son seguros:

- **Archivos de CA**: Se almacenan en `~/.local/share/mkcert/` (mismo en ambos métodos)
- **Trust store**: Ambos métodos instalan la CA en el trust store del sistema host
- **mkcert**: Es una herramienta oficial y confiable de Filippo Valsorda
- **Docker**: Las imágenes se construyen localmente, no se descargan binarios sin verificar

---

## 📚 Recursos Adicionales

- [Documentación de mkcert](https://github.com/FiloSottile/mkcert)
- [Cómo funcionan los certificados TLS](https://letsencrypt.org/how-it-works/)
- [README principal](README.md)
- [Guía de pruebas](TESTING.md)

---

## ❓ Preguntas Frecuentes

### ¿Por qué no se puede hacer todo desde Docker?

Porque la instalación de CA en el trust store del sistema operativo requiere:
1. Copiar archivos a directorios del sistema (requiere sudo)
2. Ejecutar comandos del sistema (`update-ca-certificates`)
3. Modificar bases de datos NSS de Firefox/Chrome en el host

Docker no puede hacer esto automáticamente sin comprometer la seguridad.

### ¿Puedo usar el Método 2 sin sudo?

No completamente. Puedes generar los archivos de CA sin sudo, pero necesitarás sudo para instalarlos en el trust store del sistema. Sin esto, los certificados no serán confiables.

### ¿Los archivos de CA son los mismos en ambos métodos?

Sí, ambos métodos generan los mismos archivos:
- `rootCA.pem` - Certificado de la CA
- `rootCA-key.pem` - Clave privada de la CA

La diferencia está en cómo se instalan en el trust store.

### ¿Puedo cambiar de un método a otro?

Sí, los archivos de CA son compatibles. Si generaste la CA con el Método 2, puedes instalar mkcert después y usará los mismos archivos.

### ¿Es seguro instalar mkcert en mi sistema?

Sí, mkcert es una herramienta ampliamente usada y confiable para desarrollo local. Solo crea certificados para localhost y dominios locales, no para internet.

---

**Versión del documento**: 1.0.0  
**Última actualización**: 2026-02-10
