FROM node:24.13.0-alpine

# Install required tools and mkcert binary
RUN apk add --no-cache \
    ca-certificates \
    nss-tools \
    && ARCH=$(uname -m) \
    && case "$ARCH" in \
        x86_64) MKCERT_ARCH="amd64"; MKCERT_SHA256="6d31c65b03972c6dc4a14ab429f2928300518b26503f58723e532d1b0a3bbb52" ;; \
        aarch64) MKCERT_ARCH="arm64"; MKCERT_SHA256="b98f2cc69fd9147fe4d405d859c57504571adec0d3611c3eefd04107c7ac00d0" ;; \
        armv7l) MKCERT_ARCH="arm"; MKCERT_SHA256="2f22ff62dfc13357e147e027117724e7ce1ff810e30d2b061b05b668ecb4f1d7" ;; \
        *) echo "Unsupported architecture: $ARCH" && exit 1 ;; \
    esac \
    && wget -qO /usr/local/bin/mkcert "https://github.com/FiloSottile/mkcert/releases/download/v1.4.4/mkcert-v1.4.4-linux-${MKCERT_ARCH}" \
    && echo "${MKCERT_SHA256}  /usr/local/bin/mkcert" | sha256sum -c - \
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
