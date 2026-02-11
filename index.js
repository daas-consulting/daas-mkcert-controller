#!/usr/bin/env node

const Docker = require('dockerode');
const chokidar = require('chokidar');
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');
const { printBanner, isBannerShown } = require('./banner');
const { parseBool } = require('./parseBool');
const { validateNotEmpty, validateDirectory } = require('./validateConfig');
const { parseTraefikLabels, extractDomainsFromLabels } = require('./traefikLabels');

// Configuration from environment variables
const INSTALL_CA = parseBool(process.env.INSTALL_CA, true, 'INSTALL_CA');
const TRAEFIK_DIR = validateNotEmpty(process.env.TRAEFIK_DIR || '/etc/traefik', 'TRAEFIK_DIR');
const CERTS_DIR = validateNotEmpty(process.env.CERTS_DIR || path.join(TRAEFIK_DIR, 'certs'), 'CERTS_DIR');
const MKCERT_CA_DIR = validateNotEmpty(process.env.MKCERT_CA_DIR || '/root/.local/share/mkcert', 'MKCERT_CA_DIR');
const THROTTLE_MS = parseInt(process.env.THROTTLE_MS || '300', 10);
const SCHEDULED_INTERVAL_MS = parseInt(process.env.SCHEDULED_INTERVAL_MS || '60000', 10); // 1 minute

const docker = new Docker({ socketPath: '/var/run/docker.sock' });
const processedDomains = new Set();

// Throttle and scheduling state
let reconcileTimer = null;
let isReconciling = false;
let scheduledTimer = null;
let lastReconcileTime = 0;

// ANSI color codes
const RESET = '\x1b[0m';
const GRAY = '\x1b[90m';
const RED = '\x1b[31m';
const RED_BOLD = '\x1b[1;31m';
const BG_RED_WHITE_BOLD = '\x1b[41;37;1m';
const BG_RED_WHITE = '\x1b[41;37m';
const GREEN = '\x1b[32m';
const YELLOW = '\x1b[33m';
const CYAN = '\x1b[36m';

// Syslog RFC 5424 severity mapping
const SYSLOG_SEVERITY = {
  EMERG: 0,
  ALERT: 1,
  CRIT: 2,
  ERROR: 3,
  WARN: 4,
  NOTICE: 5,
  INFO: 6,
  DEBUG: 7,
};

// Syslog facility: local0 (16)
const SYSLOG_FACILITY = 16;

const APP_NAME = 'daas-mkcert-controller';
const HOSTNAME = os.hostname();

// ANSI color sequences for each severity level
const LEVEL_COLORS = {
  EMERG: BG_RED_WHITE_BOLD,
  ALERT: BG_RED_WHITE,
  CRIT: RED_BOLD,
  ERROR: RED,
  WARN: YELLOW,
  NOTICE: CYAN,
  INFO: GREEN,
  DEBUG: GRAY,
};

// Logging utility - Syslog RFC 5424 format with ANSI colors
// Format: <PRI>VERSION TIMESTAMP HOSTNAME APP-NAME PROCID MSGID SD MSG
function log(message, level = 'INFO') {
  const severity = SYSLOG_SEVERITY[level] !== undefined ? SYSLOG_SEVERITY[level] : SYSLOG_SEVERITY.INFO;
  const priority = SYSLOG_FACILITY * 8 + severity;
  const timestamp = new Date().toISOString();
  const procId = process.pid;
  const color = LEVEL_COLORS[level] || LEVEL_COLORS.INFO;

  const header = `<${priority}>1 ${timestamp} ${HOSTNAME} ${APP_NAME} ${procId} - -`;
  const levelTag = `[${level}]`;

  console.log(`${header} ${color}${levelTag}${RESET} ${message}`);
}

// Validate read/write access to a directory
function validateAccess(dir, description) {
  try {
    validateDirectory(dir, description);
    log(`✓ Read/write access validated for ${description}: ${dir}`, 'INFO');
    return true;
  } catch (error) {
    log(`✗ ${error.message}`, 'ERROR');
    return false;
  }
}

// Verify mkcert CA exists (installation should be done on host, not in container)
function installCA() {
  if (!INSTALL_CA) {
    log('CA installation not requested (INSTALL_CA != true)', 'INFO');
    return true;
  }

  log('CA installation requested, validating access...', 'INFO');
  
  // Validate access to CA directory
  if (!validateAccess(MKCERT_CA_DIR, 'mkcert CA directory')) {
    log('Cannot verify CA: insufficient permissions', 'ERROR');
    return false;
  }

  try {
    // Check if CA already exists
    const rootCAKey = path.join(MKCERT_CA_DIR, 'rootCA-key.pem');
    const rootCA = path.join(MKCERT_CA_DIR, 'rootCA.pem');
    
    if (fs.existsSync(rootCAKey) && fs.existsSync(rootCA)) {
      log('✓ mkcert CA found and verified', 'INFO');
      log('Note: CA should be installed on Docker host, not inside container', 'INFO');
      return true;
    }

    log('✗ mkcert CA files not found', 'ERROR');
    log('Expected files:', 'ERROR');
    log(`  - ${rootCA}`, 'ERROR');
    log(`  - ${rootCAKey}`, 'ERROR');
    log('The CA must be installed on the Docker host machine before starting the controller', 'ERROR');
    log('Run the install.sh script with INSTALL_CA=true to install the CA on the host', 'ERROR');
    return false;
  } catch (error) {
    log(`✗ Failed to verify mkcert CA: ${error.message}`, 'ERROR');
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

// Generate certificate for a domain
function generateCertificate(domain) {
  try {
    const certPath = path.join(CERTS_DIR, `${domain}.pem`);
    const keyPath = path.join(CERTS_DIR, `${domain}-key.pem`);

    if (fs.existsSync(certPath) && fs.existsSync(keyPath)) {
      if (!processedDomains.has(domain)) {
        log(`Certificate files for ${domain} already exist`, 'INFO');
        processedDomains.add(domain);
      }
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

// Write TLS configuration file for Traefik
function writeTLSConfig(domains) {
  try {
    if (!fs.existsSync(TRAEFIK_DIR)) {
      log(`Creating Traefik directory: ${TRAEFIK_DIR}`, 'INFO');
      fs.mkdirSync(TRAEFIK_DIR, { recursive: true, mode: 0o755 });
    }

    const tlsConfigPath = path.join(TRAEFIK_DIR, 'tls.yml');
    
    if (domains.length === 0) {
      log('No domains to configure for TLS', 'DEBUG');
      return;
    }

    const certsRelPath = path.relative(TRAEFIK_DIR, CERTS_DIR);
    const certificates = domains.map(d => ({
      certFile: `${certsRelPath}/${d}.pem`,
      keyFile: `${certsRelPath}/${d}-key.pem`
    }));

    const yml = `# Auto-generated by daas-mkcert-controller
# Do not edit manually
tls:
  certificates:
${certificates.map(cert => `    - certFile: ${cert.certFile}
      keyFile: ${cert.keyFile}`).join('\n')}
`;

    fs.writeFileSync(tlsConfigPath, yml);
    log(`✓ TLS configuration updated with ${domains.length} certificate(s)`, 'INFO');
  } catch (error) {
    log(`✗ Failed to write TLS configuration: ${error.message}`, 'ERROR');
  }
}

// Throttled reconcile function
function scheduleReconcile() {
  if (reconcileTimer) {
    return; // Already scheduled
  }
  
  const now = Date.now();
  const timeSinceLastReconcile = now - lastReconcileTime;
  const delay = Math.max(0, THROTTLE_MS - timeSinceLastReconcile);
  
  reconcileTimer = setTimeout(async () => {
    reconcileTimer = null;
    await reconcile();
  }, delay);
  
  if (delay > 0) {
    log(`Reconcile scheduled in ${delay}ms`, 'DEBUG');
  }
}

// Main reconcile function - scans all containers and updates certificates
async function reconcile() {
  if (isReconciling) {
    log('Reconcile already in progress, skipping', 'DEBUG');
    return;
  }

  isReconciling = true;
  lastReconcileTime = Date.now();
  
  try {
    log('Starting reconciliation...', 'DEBUG');
    const containers = await docker.listContainers();
    const allDomains = new Set();
    
    for (const containerInfo of containers) {
      if (containerInfo.Labels) {
        const domains = extractDomainsFromLabels(containerInfo.Labels, log);
        domains.forEach(d => allDomains.add(d));
      }
    }
    
    const domainList = Array.from(allDomains);
    log(`Found ${domainList.length} TLS-enabled localhost domain(s)`, 'INFO');
    
    // Generate certificates for all domains
    domainList.forEach(domain => generateCertificate(domain));
    
    // Update TLS configuration file
    writeTLSConfig(domainList);
    
    log('✓ Reconciliation complete', 'DEBUG');
  } catch (error) {
    log(`✗ Error during reconciliation: ${error.message}`, 'ERROR');
  } finally {
    isReconciling = false;
  }
}

// Setup scheduled reconciliation (every minute)
function setupScheduledReconcile() {
  scheduledTimer = setInterval(async () => {
    if (!isReconciling) {
      log('Running scheduled reconciliation', 'DEBUG');
      await reconcile();
    } else {
      log('Skipping scheduled reconciliation (already running)', 'DEBUG');
    }
  }, SCHEDULED_INTERVAL_MS);
  
  log(`✓ Scheduled reconciliation every ${SCHEDULED_INTERVAL_MS / 1000}s`, 'INFO');
}

// Monitor Docker events
async function monitorDockerEvents() {
  log('Starting Docker events monitoring...', 'INFO');
  
  try {
    const stream = await docker.getEvents();
    
    stream.on('data', async (chunk) => {
      try {
        const event = JSON.parse(chunk.toString());
        
        // Listen for container events
        if (event.Type === 'container' && 
            (event.Action === 'start' || event.Action === 'create' || 
             event.Action === 'die' || event.Action === 'stop')) {
          const attrs = event.Actor.Attributes || {};
          log(`Docker event: ${event.Action} for container ${event.Actor.ID.substring(0, 12)} (name: ${attrs.name || 'unknown'}, image: ${attrs.image || 'unknown'})`, 'DEBUG');
          scheduleReconcile();
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
  await reconcile();
}

// Monitor Traefik configuration files
function monitorTraefikFiles() {
  if (!fs.existsSync(TRAEFIK_DIR)) {
    log(`Traefik directory not found: ${TRAEFIK_DIR}`, 'WARN');
    return;
  }

  log(`Starting Traefik files monitoring: ${TRAEFIK_DIR}`, 'INFO');
  
  const watcher = chokidar.watch(TRAEFIK_DIR, {
    persistent: true,
    ignoreInitial: true,
    depth: 2,
    ignored: /tls\.yml$/ // Ignore our own tls.yml file
  });

  watcher.on('add', (filePath) => {
    log(`Traefik file added: ${filePath}`, 'DEBUG');
    scheduleReconcile();
  });

  watcher.on('change', (filePath) => {
    log(`Traefik file changed: ${filePath}`, 'DEBUG');
    scheduleReconcile();
  });

  watcher.on('unlink', (filePath) => {
    log(`Traefik file removed: ${filePath}`, 'DEBUG');
    scheduleReconcile();
  });

  watcher.on('error', (error) => {
    log(`Traefik file watcher error: ${error.message}`, 'ERROR');
  });

  log('✓ Traefik files monitoring started', 'INFO');
}

// Main startup function
async function main() {
  if (!isBannerShown()) {
    printBanner();
  }
  log('=== daas-mkcert-controller starting ===', 'INFO');
  log(`Configuration:`, 'INFO');
  log(`  - INSTALL_CA: ${INSTALL_CA}`, 'INFO');
  log(`  - TRAEFIK_DIR: ${TRAEFIK_DIR}`, 'INFO');
  log(`  - CERTS_DIR: ${CERTS_DIR}`, 'INFO');
  log(`  - MKCERT_CA_DIR: ${MKCERT_CA_DIR}`, 'INFO');
  log(`  - THROTTLE_MS: ${THROTTLE_MS}`, 'INFO');
  log(`  - SCHEDULED_INTERVAL_MS: ${SCHEDULED_INTERVAL_MS}`, 'INFO');

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
  setupScheduledReconcile();

  log('=== daas-mkcert-controller is running ===', 'INFO');
  log('Press Ctrl+C to stop', 'INFO');
}

// Handle shutdown gracefully
process.on('SIGINT', () => {
  log('Shutting down...', 'INFO');
  if (reconcileTimer) clearTimeout(reconcileTimer);
  if (scheduledTimer) clearInterval(scheduledTimer);
  process.exit(0);
});

process.on('SIGTERM', () => {
  log('Shutting down...', 'INFO');
  if (reconcileTimer) clearTimeout(reconcileTimer);
  if (scheduledTimer) clearInterval(scheduledTimer);
  process.exit(0);
});

// Start the application
main().catch((error) => {
  log(`Fatal error: ${error.message}`, 'ERROR');
  console.error(error);
  process.exit(1);
});
