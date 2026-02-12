FROM node:24.13.0-alpine

# Install required tools (openssl replaces mkcert for certificate generation)
RUN apk add --no-cache \
    ca-certificates \
    openssl

# Create app directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm install --production

# Copy application code
COPY index.js banner.js parseBool.js validateConfig.js traefikLabels.js buildTLSConfig.js validateCertificates.js certSubject.js opensslCert.js ./

# Create directories for certificates
RUN mkdir -p /etc/traefik/dynamic/certs

# Run as root to access Docker socket and install CA if needed
USER root

# Start the application
CMD ["node", "index.js"]
