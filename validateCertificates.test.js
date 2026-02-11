'use strict';

const { getCAFingerprint, isCertIssuedByCA, validateExistingCertificates, removeInvalidCertificates } = require('./validateCertificates');
const { execSync } = require('child_process');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const os = require('os');

let passed = 0;
let failed = 0;

function assert(condition, message) {
  if (condition) {
    passed++;
    console.log(`  ✓ ${message}`);
  } else {
    failed++;
    console.error(`  ✗ FAIL: ${message}`);
  }
}

function assertThrows(fn, expectedMsg, message) {
  try {
    fn();
    failed++;
    console.error(`  ✗ FAIL: ${message} (did not throw)`);
  } catch (err) {
    if (expectedMsg && !err.message.includes(expectedMsg)) {
      failed++;
      console.error(`  ✗ FAIL: ${message} (wrong message: ${err.message})`);
    } else {
      passed++;
      console.log(`  ✓ ${message}`);
    }
  }
}

// --- Setup: Create temporary CA and certificates ---
const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'validate-certs-test-'));
const caDir = path.join(tmpDir, 'ca');
const ca2Dir = path.join(tmpDir, 'ca2');
const certsDir = path.join(tmpDir, 'certs');
const emptyCertsDir = path.join(tmpDir, 'empty-certs');

fs.mkdirSync(caDir, { recursive: true });
fs.mkdirSync(ca2Dir, { recursive: true });
fs.mkdirSync(certsDir, { recursive: true });
fs.mkdirSync(emptyCertsDir, { recursive: true });

const caPemPath = path.join(caDir, 'rootCA.pem');
const caKeyPath = path.join(caDir, 'rootCA-key.pem');
const ca2PemPath = path.join(ca2Dir, 'rootCA.pem');
const ca2KeyPath = path.join(ca2Dir, 'rootCA-key.pem');

// Generate CA 1
execSync(`openssl req -x509 -new -nodes -newkey rsa:2048 -keyout "${caKeyPath}" -out "${caPemPath}" -days 1 -subj "/CN=Test CA 1"`, { stdio: 'pipe' });

// Generate CA 2 (different CA)
execSync(`openssl req -x509 -new -nodes -newkey rsa:2048 -keyout "${ca2KeyPath}" -out "${ca2PemPath}" -days 1 -subj "/CN=Test CA 2"`, { stdio: 'pipe' });

// Generate a certificate signed by CA 1
const cert1Domain = 'app.localhost';
const cert1KeyPath = path.join(certsDir, `${cert1Domain}-key.pem`);
const cert1Path = path.join(certsDir, `${cert1Domain}.pem`);
const cert1CsrPath = path.join(tmpDir, 'cert1.csr');

execSync(`openssl genrsa -out "${cert1KeyPath}" 2048`, { stdio: 'pipe' });
execSync(`openssl req -new -key "${cert1KeyPath}" -out "${cert1CsrPath}" -subj "/CN=${cert1Domain}"`, { stdio: 'pipe' });
execSync(`openssl x509 -req -in "${cert1CsrPath}" -CA "${caPemPath}" -CAkey "${caKeyPath}" -CAcreateserial -out "${cert1Path}" -days 1`, { stdio: 'pipe' });

// Generate a certificate signed by CA 2 (will be "invalid" relative to CA 1)
const cert2Domain = 'api.localhost';
const cert2KeyPath = path.join(certsDir, `${cert2Domain}-key.pem`);
const cert2Path = path.join(certsDir, `${cert2Domain}.pem`);
const cert2CsrPath = path.join(tmpDir, 'cert2.csr');

execSync(`openssl genrsa -out "${cert2KeyPath}" 2048`, { stdio: 'pipe' });
execSync(`openssl req -new -key "${cert2KeyPath}" -out "${cert2CsrPath}" -subj "/CN=${cert2Domain}"`, { stdio: 'pipe' });
execSync(`openssl x509 -req -in "${cert2CsrPath}" -CA "${ca2PemPath}" -CAkey "${ca2KeyPath}" -CAcreateserial -out "${cert2Path}" -days 1`, { stdio: 'pipe' });

console.log('validateCertificates tests');
console.log('');

// --- getCAFingerprint ---
console.log('getCAFingerprint():');
{
  const fp = getCAFingerprint(caPemPath);
  assert(typeof fp === 'string', 'returns a string');
  assert(fp.includes(':'), 'fingerprint is colon-separated hex');
  assert(fp.length > 0, 'fingerprint is non-empty');

  // Same CA should always produce same fingerprint
  const fp2 = getCAFingerprint(caPemPath);
  assert(fp === fp2, 'same CA produces same fingerprint');

  // Different CA should produce different fingerprint
  const fp3 = getCAFingerprint(ca2PemPath);
  assert(fp !== fp3, 'different CAs produce different fingerprints');
}

{
  assertThrows(
    () => getCAFingerprint('/nonexistent/path/rootCA.pem'),
    'no such file',
    'throws when CA file does not exist'
  );
}

console.log('');

// --- isCertIssuedByCA ---
console.log('isCertIssuedByCA():');
{
  assert(isCertIssuedByCA(cert1Path, caPemPath) === true, 'cert signed by CA1 is recognized as issued by CA1');
  assert(isCertIssuedByCA(cert2Path, ca2PemPath) === true, 'cert signed by CA2 is recognized as issued by CA2');
  assert(isCertIssuedByCA(cert2Path, caPemPath) === false, 'cert signed by CA2 is NOT recognized as issued by CA1');
  assert(isCertIssuedByCA(cert1Path, ca2PemPath) === false, 'cert signed by CA1 is NOT recognized as issued by CA2');
}

console.log('');

// --- validateExistingCertificates ---
console.log('validateExistingCertificates():');

// Valid certificates (all signed by CA1, checking against CA1)
{
  const validCertsDir = path.join(tmpDir, 'valid-certs');
  fs.mkdirSync(validCertsDir, { recursive: true });
  
  // Copy only cert1 (signed by CA1)
  fs.copyFileSync(cert1Path, path.join(validCertsDir, `${cert1Domain}.pem`));
  fs.copyFileSync(cert1KeyPath, path.join(validCertsDir, `${cert1Domain}-key.pem`));
  
  const invalid = validateExistingCertificates(validCertsDir, caPemPath);
  assert(invalid.length === 0, 'no invalid certificates when all match CA');
}

// Mixed certificates (some valid, some invalid)
{
  const logged = [];
  const invalid = validateExistingCertificates(certsDir, caPemPath, (msg, level) => {
    logged.push({ msg, level });
  });
  
  assert(invalid.length === 1, 'detects 1 invalid certificate');
  assert(invalid.includes(cert2Domain), 'identifies the certificate signed by wrong CA');
  assert(!invalid.includes(cert1Domain), 'does not flag valid certificate');
  assert(logged.some(l => l.msg.includes('fingerprint')), 'logs CA fingerprint');
  assert(logged.some(l => l.msg.includes('NOT issued') && l.level === 'WARN'), 'logs warning for invalid cert');
}

// Empty certificates directory
{
  const invalid = validateExistingCertificates(emptyCertsDir, caPemPath);
  assert(invalid.length === 0, 'empty directory returns no invalid domains');
}

// Non-existent certificates directory
{
  const invalid = validateExistingCertificates('/nonexistent/dir', caPemPath);
  assert(invalid.length === 0, 'nonexistent directory returns no invalid domains');
}

// Non-existent CA file
{
  const invalid = validateExistingCertificates(certsDir, '/nonexistent/rootCA.pem');
  assert(invalid.length === 0, 'nonexistent CA returns no invalid domains');
}

console.log('');

// --- removeInvalidCertificates ---
console.log('removeInvalidCertificates():');
{
  const removeCertsDir = path.join(tmpDir, 'remove-certs');
  fs.mkdirSync(removeCertsDir, { recursive: true });
  
  // Create cert and key files
  fs.copyFileSync(cert2Path, path.join(removeCertsDir, `${cert2Domain}.pem`));
  fs.copyFileSync(cert2KeyPath, path.join(removeCertsDir, `${cert2Domain}-key.pem`));
  
  const logged = [];
  const removed = removeInvalidCertificates([cert2Domain], removeCertsDir, (msg, level) => {
    logged.push({ msg, level });
  });
  
  assert(removed === 1, 'reports 1 removed');
  assert(!fs.existsSync(path.join(removeCertsDir, `${cert2Domain}.pem`)), 'cert file is deleted');
  assert(!fs.existsSync(path.join(removeCertsDir, `${cert2Domain}-key.pem`)), 'key file is deleted');
  assert(logged.some(l => l.msg.includes('Removed')), 'logs removal');
}

// Remove non-existent domain (should not throw)
{
  const removed = removeInvalidCertificates(['nonexistent.localhost'], certsDir);
  assert(removed === 0, 'removing nonexistent domain returns 0');
}

// Empty domains list
{
  const removed = removeInvalidCertificates([], certsDir);
  assert(removed === 0, 'empty domains list returns 0');
}

console.log('');

// --- Cleanup ---
fs.rmSync(tmpDir, { recursive: true, force: true });

// --- Summary ---
console.log('---');
console.log(`Results: ${passed} passed, ${failed} failed`);

if (failed > 0) {
  process.exit(1);
}
