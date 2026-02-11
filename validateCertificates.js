'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

/**
 * Get the SHA-256 fingerprint of a CA certificate.
 * This fingerprint uniquely identifies the CA.
 *
 * @param {string} caPemPath - Path to the CA PEM file
 * @returns {string} SHA-256 fingerprint (colon-separated hex)
 */
function getCAFingerprint(caPemPath) {
  const caPem = fs.readFileSync(caPemPath);
  const ca = new crypto.X509Certificate(caPem);
  return ca.fingerprint256;
}

/**
 * Check if a certificate was issued by the given CA.
 *
 * @param {string} certPemPath - Path to the certificate PEM file
 * @param {string} caPemPath - Path to the CA PEM file
 * @returns {boolean} true if the certificate was issued by the CA
 */
function isCertIssuedByCA(certPemPath, caPemPath) {
  const certPem = fs.readFileSync(certPemPath);
  const caPem = fs.readFileSync(caPemPath);
  const cert = new crypto.X509Certificate(certPem);
  const ca = new crypto.X509Certificate(caPem);
  return cert.checkIssued(ca);
}

/**
 * Validate all existing certificates in a directory against the current CA.
 * Returns the list of domains whose certificates are NOT issued by the current CA.
 *
 * @param {string} certsDir - Directory containing certificate files
 * @param {string} caPemPath - Path to the CA PEM file
 * @param {Function} [log] - Optional logging function (message, level)
 * @returns {string[]} List of domain names with invalid certificates
 */
function validateExistingCertificates(certsDir, caPemPath, log) {
  const _log = typeof log === 'function' ? log : () => {};
  const invalidDomains = [];

  if (!fs.existsSync(certsDir)) {
    _log(`Certificates directory does not exist: ${certsDir}`, 'DEBUG');
    return invalidDomains;
  }

  if (!fs.existsSync(caPemPath)) {
    _log(`CA certificate not found: ${caPemPath}`, 'WARN');
    return invalidDomains;
  }

  const fingerprint = getCAFingerprint(caPemPath);
  _log(`Current CA fingerprint (SHA-256): ${fingerprint}`, 'INFO');

  let certFiles;
  try {
    certFiles = fs.readdirSync(certsDir)
      .filter(f => f.endsWith('.pem') && !f.endsWith('-key.pem'));
  } catch (error) {
    _log(`Error reading certificates directory: ${error.message}`, 'ERROR');
    return invalidDomains;
  }

  if (certFiles.length === 0) {
    _log('No existing certificates to validate', 'DEBUG');
    return invalidDomains;
  }

  _log(`Validating ${certFiles.length} existing certificate(s) against current CA...`, 'INFO');

  const caPem = fs.readFileSync(caPemPath);
  const ca = new crypto.X509Certificate(caPem);

  for (const certFile of certFiles) {
    const domain = certFile.replace(/\.pem$/, '');
    const certPath = path.join(certsDir, certFile);

    try {
      const certPem = fs.readFileSync(certPath);
      const cert = new crypto.X509Certificate(certPem);

      if (!cert.checkIssued(ca)) {
        _log(`Certificate for ${domain} was NOT issued by current CA`, 'WARN');
        invalidDomains.push(domain);
      } else {
        _log(`Certificate for ${domain} is valid (issued by current CA)`, 'DEBUG');
      }
    } catch (error) {
      _log(`Error validating certificate for ${domain}: ${error.message}`, 'WARN');
      invalidDomains.push(domain);
    }
  }

  return invalidDomains;
}

/**
 * Remove certificate and key files for the given domains.
 *
 * @param {string[]} domains - List of domain names to remove
 * @param {string} certsDir - Directory containing certificate files
 * @param {Function} [log] - Optional logging function (message, level)
 * @returns {number} Number of certificate pairs removed
 */
function removeInvalidCertificates(domains, certsDir, log) {
  const _log = typeof log === 'function' ? log : () => {};
  let removed = 0;

  for (const domain of domains) {
    const certPath = path.join(certsDir, `${domain}.pem`);
    const keyPath = path.join(certsDir, `${domain}-key.pem`);

    try {
      let didRemove = false;
      if (fs.existsSync(certPath)) {
        fs.unlinkSync(certPath);
        didRemove = true;
      }
      if (fs.existsSync(keyPath)) {
        fs.unlinkSync(keyPath);
        didRemove = true;
      }
      if (didRemove) {
        _log(`Removed invalid certificate for ${domain}`, 'INFO');
        removed++;
      }
    } catch (error) {
      _log(`Error removing certificate for ${domain}: ${error.message}`, 'ERROR');
    }
  }

  return removed;
}

module.exports = {
  getCAFingerprint,
  isCertIssuedByCA,
  validateExistingCertificates,
  removeInvalidCertificates,
};
