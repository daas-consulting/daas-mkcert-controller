FROM node:24.13.0-alpine

# Install required tools and mkcert binary
RUN apk add --no-cache \
    ca-certificates \
    nss-tools \
    && ARCH=$(uname -m) \
    && case "$ARCH" in \
        x86_64) MKCERT_ARCH="amd64" ;; \
        aarch64) MKCERT_ARCH="arm64" ;; \
        armv7l) MKCERT_ARCH="arm" ;; \
        *) echo "Unsupported architecture: $ARCH" && exit 1 ;; \
    esac \
    && wget -qO /usr/local/bin/mkcert "https://github.com/FiloSottile/mkcert/releases/download/v1.4.4/mkcert-v1.4.4-linux-${MKCERT_ARCH}" \
    && chmod +x /usr/local/bin/mkcert

# Create app directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm install --production

# Copy application code
COPY index.js banner.js parseBool.js validateConfig.js ./

# Create directories for certificates
RUN mkdir -p /certs

# Run as root to access Docker socket and install CA if needed
USER root

# Start the application
CMD ["node", "index.js"]
