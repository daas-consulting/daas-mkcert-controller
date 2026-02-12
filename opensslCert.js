'use strict';

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

/**
 * Generate a leaf certificate signed by the given CA using openssl.
 *
 * @param {Object} options
 * @param {string} options.domain - Domain name for the certificate
 * @param {string} options.certPath - Output path for the certificate PEM
 * @param {string} options.keyPath - Output path for the private key PEM
 * @param {string} options.caCertPath - Path to the CA certificate PEM
 * @param {string} options.caKeyPath - Path to the CA private key PEM
 * @param {string} options.subject - OpenSSL subject string (e.g. "/CN=.../O=.../OU=...")
 * @param {number} [options.days=825] - Certificate validity in days
 */
function generateLeafCertificate(options) {
  const {
    domain,
    certPath,
    keyPath,
    caCertPath,
    caKeyPath,
    subject,
    days = 825,
  } = options;

  // Create a temporary directory for CSR and extension config
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'daas-cert-'));
  const csrPath = path.join(tmpDir, 'cert.csr');
  const extPath = path.join(tmpDir, 'cert.ext');

  try {
    // Write extension config with SAN
    const extContent = [
      'authorityKeyIdentifier=keyid,issuer',
      'basicConstraints=CA:FALSE',
      'keyUsage=digitalSignature,keyEncipherment',
      'extendedKeyUsage=serverAuth',
      `subjectAltName=DNS:${domain}`,
    ].join('\n');
    fs.writeFileSync(extPath, extContent);

    // Generate private key
    execSync(`openssl genrsa -out "${keyPath}" 2048 2>/dev/null`);

    // Generate CSR
    execSync(
      `openssl req -new -key "${keyPath}" -out "${csrPath}" -subj "${subject}"`,
      { stdio: 'pipe' }
    );

    // Sign with CA
    execSync(
      `openssl x509 -req -in "${csrPath}" -CA "${caCertPath}" -CAkey "${caKeyPath}"` +
        ` -CAcreateserial -out "${certPath}" -days ${days} -sha256 -extfile "${extPath}"`,
      { stdio: 'pipe' }
    );
  } finally {
    // Clean up temp files
    try {
      fs.rmSync(tmpDir, { recursive: true, force: true });
    } catch (_) {
      // Ignore cleanup errors
    }
  }
}

/**
 * Generate a self-signed CA certificate using openssl.
 *
 * @param {Object} options
 * @param {string} options.certPath - Output path for the CA certificate PEM
 * @param {string} options.keyPath - Output path for the CA private key PEM
 * @param {string} options.subject - OpenSSL subject string for the CA
 * @param {number} [options.days=3650] - CA validity in days (default ~10 years)
 */
function generateCACertificate(options) {
  const { certPath, keyPath, subject, days = 3650 } = options;

  // Generate CA private key
  execSync(`openssl genrsa -out "${keyPath}" 4096 2>/dev/null`);

  // Generate self-signed CA certificate
  execSync(
    `openssl req -x509 -new -nodes -key "${keyPath}" -sha256` +
      ` -days ${days} -out "${certPath}" -subj "${subject}"`,
    { stdio: 'pipe' }
  );
}

module.exports = {
  generateLeafCertificate,
  generateCACertificate,
};
