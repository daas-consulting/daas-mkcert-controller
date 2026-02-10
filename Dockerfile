FROM node:24.13.0-alpine

# Install mkcert and required tools
RUN apk add --no-cache \
    ca-certificates \
    nss-tools \
    mkcert

# Create app directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm install --production

# Copy application code
COPY index.js banner.js parseBool.js ./

# Create directories for certificates
RUN mkdir -p /certs

# Run as root to access Docker socket and install CA if needed
USER root

# Start the application
CMD ["node", "index.js"]
