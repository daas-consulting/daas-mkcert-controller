#!/usr/bin/env node

const Docker = require('dockerode');
const chokidar = require('chokidar');
const { execSync, exec } = require('child_process');
const fs = require('fs');
const path = require('path');

// Configuration from environment variables
const INSTALL_CA = process.env.INSTALL_CA === 'true';
const TRAEFIK_DIR = process.env.TRAEFIK_DIR || '/etc/traefik';
const CERTS_DIR = process.env.CERTS_DIR || '/certs';
const MKCERT_CA_DIR = process.env.MKCERT_CA_DIR || '/root/.local/share/mkcert';

const docker = new Docker({ socketPath: '/var/run/docker.sock' });
const processedDomains = new Set();

// Logging utility
function log(message, level = 'INFO') {
  const timestamp = new Date().toISOString();
  console.log(`[${timestamp}] [${level}] ${message}`);
}

// Validate read/write access to a directory
function validateAccess(dir, description) {
  try {
    if (!fs.existsSync(dir)) {
      log(`Creating directory: ${dir}`, 'INFO');
      fs.mkdirSync(dir, { recursive: true, mode: 0o755 });
    }
    
    // Test write access
    const testFile = path.join(dir, '.access_test');
    fs.writeFileSync(testFile, 'test');
    fs.unlinkSync(testFile);
    
    log(`✓ Read/write access validated for ${description}: ${dir}`, 'INFO');
    return true;
  } catch (error) {
    log(`✗ No read/write access to ${description}: ${dir} - ${error.message}`, 'ERROR');
    return false;
  }
}

// Install mkcert CA if requested
function installCA() {
  if (!INSTALL_CA) {
    log('CA installation not requested (INSTALL_CA != true)', 'INFO');
    return true;
  }

  log('CA installation requested, validating access...', 'INFO');
  
  // Validate access to CA directory
  if (!validateAccess(MKCERT_CA_DIR, 'mkcert CA directory')) {
    log('Cannot install CA: insufficient permissions', 'ERROR');
    return false;
  }

  try {
    // Check if CA already exists
    const rootCAKey = path.join(MKCERT_CA_DIR, 'rootCA-key.pem');
    const rootCA = path.join(MKCERT_CA_DIR, 'rootCA.pem');
    
    if (fs.existsSync(rootCAKey) && fs.existsSync(rootCA)) {
      log('mkcert CA already exists', 'INFO');
      return true;
    }

    log('Installing mkcert CA...', 'INFO');
    execSync('mkcert -install', { stdio: 'inherit' });
    log('✓ mkcert CA installed successfully', 'INFO');
    return true;
  } catch (error) {
    log(`✗ Failed to install mkcert CA: ${error.message}`, 'ERROR');
    return false;
  }
}

// Check if Traefik is running
async function checkTraefikRunning() {
  try {
    const containers = await docker.listContainers();
    const traefikContainer = containers.find(c => 
      c.Names.some(name => name.includes('traefik')) ||
      c.Image.includes('traefik')
    );
    
    if (traefikContainer) {
      log(`✓ Traefik is running (container: ${traefikContainer.Names[0]})`, 'INFO');
      return true;
    } else {
      log('✗ Traefik is not running', 'ERROR');
      return false;
    }
  } catch (error) {
    log(`✗ Error checking Traefik status: ${error.message}`, 'ERROR');
    return false;
  }
}

// Extract localhost domains from Traefik labels
function extractDomainsFromLabels(labels) {
  const domains = new Set();
  
  for (const [key, value] of Object.entries(labels)) {
    // Look for Traefik router rules
    if (key.includes('traefik.http.routers') && key.endsWith('.rule')) {
      // Extract domains from rules like: Host(`example.localhost`) || Host(`app.localhost`)
      const matches = value.match(/Host\(`([^`]+\.localhost)`\)/g);
      if (matches) {
        matches.forEach(match => {
          const domain = match.match(/Host\(`([^`]+)`\)/)[1];
          if (domain.endsWith('.localhost')) {
            domains.add(domain);
          }
        });
      }
    }
  }
  
  return Array.from(domains);
}

// Generate certificate for a domain
function generateCertificate(domain) {
  if (processedDomains.has(domain)) {
    log(`Certificate for ${domain} already generated`, 'INFO');
    return;
  }

  try {
    const certPath = path.join(CERTS_DIR, `${domain}.pem`);
    const keyPath = path.join(CERTS_DIR, `${domain}-key.pem`);

    if (fs.existsSync(certPath) && fs.existsSync(keyPath)) {
      log(`Certificate files for ${domain} already exist`, 'INFO');
      processedDomains.add(domain);
      return;
    }

    log(`Generating certificate for: ${domain}`, 'INFO');
    execSync(`mkcert -cert-file "${certPath}" -key-file "${keyPath}" "${domain}"`, {
      cwd: CERTS_DIR,
      stdio: 'inherit'
    });
    
    log(`✓ Certificate generated for ${domain}`, 'INFO');
    processedDomains.add(domain);
  } catch (error) {
    log(`✗ Failed to generate certificate for ${domain}: ${error.message}`, 'ERROR');
  }
}

// Monitor Docker events
async function monitorDockerEvents() {
  log('Starting Docker events monitoring...', 'INFO');
  
  try {
    const stream = await docker.getEvents();
    
    stream.on('data', async (chunk) => {
      try {
        const event = JSON.parse(chunk.toString());
        
        // Listen for container start events
        if (event.Type === 'container' && (event.Action === 'start' || event.Action === 'create')) {
          const container = docker.getContainer(event.id);
          const info = await container.inspect();
          
          if (info.Config.Labels) {
            const domains = extractDomainsFromLabels(info.Config.Labels);
            if (domains.length > 0) {
              log(`Detected ${domains.length} localhost domain(s) in container ${info.Name}`, 'INFO');
              domains.forEach(domain => generateCertificate(domain));
            }
          }
        }
      } catch (error) {
        log(`Error processing Docker event: ${error.message}`, 'ERROR');
      }
    });

    stream.on('error', (error) => {
      log(`Docker events stream error: ${error.message}`, 'ERROR');
    });

    log('✓ Docker events monitoring started', 'INFO');
  } catch (error) {
    log(`✗ Failed to start Docker events monitoring: ${error.message}`, 'ERROR');
    throw error;
  }
}

// Scan existing containers on startup
async function scanExistingContainers() {
  log('Scanning existing containers for localhost domains...', 'INFO');
  
  try {
    const containers = await docker.listContainers();
    let totalDomains = 0;
    
    for (const containerInfo of containers) {
      if (containerInfo.Labels) {
        const domains = extractDomainsFromLabels(containerInfo.Labels);
        if (domains.length > 0) {
          log(`Found ${domains.length} localhost domain(s) in container ${containerInfo.Names[0]}`, 'INFO');
          domains.forEach(domain => generateCertificate(domain));
          totalDomains += domains.length;
        }
      }
    }
    
    log(`✓ Scan complete. Found ${totalDomains} localhost domain(s)`, 'INFO');
  } catch (error) {
    log(`✗ Error scanning existing containers: ${error.message}`, 'ERROR');
  }
}

// Monitor Traefik dynamic configuration files
function monitorTraefikFiles() {
  const dynamicPath = path.join(TRAEFIK_DIR, 'dynamic');
  
  if (!fs.existsSync(dynamicPath)) {
    log(`Traefik dynamic directory not found: ${dynamicPath}`, 'WARN');
    return;
  }

  log(`Starting Traefik files monitoring: ${dynamicPath}`, 'INFO');
  
  const watcher = chokidar.watch(dynamicPath, {
    persistent: true,
    ignoreInitial: false,
    depth: 2
  });

  watcher.on('add', (filePath) => {
    log(`Traefik file added: ${filePath}`, 'INFO');
    processTraefikFile(filePath);
  });

  watcher.on('change', (filePath) => {
    log(`Traefik file changed: ${filePath}`, 'INFO');
    processTraefikFile(filePath);
  });

  watcher.on('error', (error) => {
    log(`Traefik file watcher error: ${error.message}`, 'ERROR');
  });

  log('✓ Traefik files monitoring started', 'INFO');
}

// Process Traefik configuration file
function processTraefikFile(filePath) {
  try {
    const content = fs.readFileSync(filePath, 'utf8');
    
    // Try to parse as JSON or YAML
    let config;
    if (filePath.endsWith('.json')) {
      config = JSON.parse(content);
    } else if (filePath.endsWith('.yml') || filePath.endsWith('.yaml')) {
      // Simple YAML parsing for Host() rules
      const matches = content.match(/Host\(`([^`]+\.localhost)`\)/g);
      if (matches) {
        matches.forEach(match => {
          const domain = match.match(/Host\(`([^`]+)`\)/)[1];
          if (domain.endsWith('.localhost')) {
            generateCertificate(domain);
          }
        });
      }
      return;
    }
    
    // Process JSON config
    if (config && config.http && config.http.routers) {
      for (const router of Object.values(config.http.routers)) {
        if (router.rule) {
          const matches = router.rule.match(/Host\(`([^`]+\.localhost)`\)/g);
          if (matches) {
            matches.forEach(match => {
              const domain = match.match(/Host\(`([^`]+)`\)/)[1];
              generateCertificate(domain);
            });
          }
        }
      }
    }
  } catch (error) {
    log(`Error processing Traefik file ${filePath}: ${error.message}`, 'ERROR');
  }
}

// Main startup function
async function main() {
  log('=== daas-mkcert-controller starting ===', 'INFO');
  log(`Configuration:`, 'INFO');
  log(`  - INSTALL_CA: ${INSTALL_CA}`, 'INFO');
  log(`  - TRAEFIK_DIR: ${TRAEFIK_DIR}`, 'INFO');
  log(`  - CERTS_DIR: ${CERTS_DIR}`, 'INFO');
  log(`  - MKCERT_CA_DIR: ${MKCERT_CA_DIR}`, 'INFO');

  // Validate access to required directories
  if (!validateAccess(CERTS_DIR, 'certificates directory')) {
    log('Cannot start: insufficient permissions for certificates directory', 'ERROR');
    process.exit(1);
  }

  // Install CA if requested
  if (INSTALL_CA) {
    if (!installCA()) {
      log('Cannot start: CA installation failed', 'ERROR');
      process.exit(1);
    }
  }

  // Check if Traefik is running
  const traefikRunning = await checkTraefikRunning();
  if (!traefikRunning) {
    log('Cannot start: Traefik is not running', 'ERROR');
    process.exit(1);
  }

  // Start monitoring
  await scanExistingContainers();
  await monitorDockerEvents();
  monitorTraefikFiles();

  log('=== daas-mkcert-controller is running ===', 'INFO');
  log('Press Ctrl+C to stop', 'INFO');
}

// Handle shutdown gracefully
process.on('SIGINT', () => {
  log('Shutting down...', 'INFO');
  process.exit(0);
});

process.on('SIGTERM', () => {
  log('Shutting down...', 'INFO');
  process.exit(0);
});

// Start the application
main().catch((error) => {
  log(`Fatal error: ${error.message}`, 'ERROR');
  console.error(error);
  process.exit(1);
});
