'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { generateCACertificate, generateLeafCertificate } = require('./opensslCert');
const { buildCASubject, buildLeafSubject } = require('./certSubject');

let passed = 0;
let failed = 0;

function test(name, fn) {
  try {
    fn();
    console.log(`  ✓ ${name}`);
    passed++;
  } catch (e) {
    console.error(`  ✗ ${name}`);
    console.error(`    ${e.message}`);
    failed++;
  }
}

// Check if openssl is available
function opensslAvailable() {
  try {
    require('child_process').execSync('openssl version', { stdio: 'pipe' });
    return true;
  } catch (_) {
    return false;
  }
}

console.log('opensslCert.js tests:');

if (!opensslAvailable()) {
  console.log('  ⚠ openssl not available, skipping opensslCert tests');
  console.log(`\n  Results: 0 passed, 0 failed (skipped)\n`);
  process.exit(0);
}

const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'opensslcert-test-'));
const caCertPath = path.join(tmpDir, 'rootCA.pem');
const caKeyPath = path.join(tmpDir, 'rootCA-key.pem');

// Generate CA for tests
const caSubject = buildCASubject('1.4.0');
generateCACertificate({
  certPath: caCertPath,
  keyPath: caKeyPath,
  subject: caSubject,
});

console.log('\n  generateCACertificate:');

test('creates CA certificate and key files', () => {
  assert.ok(fs.existsSync(caCertPath), 'CA cert should exist');
  assert.ok(fs.existsSync(caKeyPath), 'CA key should exist');
});

test('CA certificate is self-signed', () => {
  const caPem = fs.readFileSync(caCertPath);
  const ca = new crypto.X509Certificate(caPem);
  assert.ok(ca.checkIssued(ca), 'CA should be self-signed');
});

test('CA certificate has correct subject fields', () => {
  const caPem = fs.readFileSync(caCertPath);
  const ca = new crypto.X509Certificate(caPem);
  assert.ok(ca.subject.includes('CN=DAAS Development CA'), `Subject should contain CN, got: ${ca.subject}`);
  assert.ok(ca.subject.includes('O=DAAS Consulting'), `Subject should contain O, got: ${ca.subject}`);
  assert.ok(ca.subject.includes('OU=daas-mkcert-controller v1.4.0'), `Subject should contain OU, got: ${ca.subject}`);
});

test('CA certificate is a CA (basicConstraints)', () => {
  const caPem = fs.readFileSync(caCertPath);
  const ca = new crypto.X509Certificate(caPem);
  // CA:TRUE should be present
  assert.ok(ca.ca, 'Certificate should be a CA');
});

console.log('\n  generateLeafCertificate:');

const leafCertPath = path.join(tmpDir, 'test.localhost.pem');
const leafKeyPath = path.join(tmpDir, 'test.localhost-key.pem');
const leafSubject = buildLeafSubject('test.localhost', {
  project: 'my-project',
  service: 'web-server',
});

generateLeafCertificate({
  domain: 'test.localhost',
  certPath: leafCertPath,
  keyPath: leafKeyPath,
  caCertPath: caCertPath,
  caKeyPath: caKeyPath,
  subject: leafSubject,
});

test('creates leaf certificate and key files', () => {
  assert.ok(fs.existsSync(leafCertPath), 'Leaf cert should exist');
  assert.ok(fs.existsSync(leafKeyPath), 'Leaf key should exist');
});

test('leaf certificate is issued by CA', () => {
  const leafPem = fs.readFileSync(leafCertPath);
  const caPem = fs.readFileSync(caCertPath);
  const leaf = new crypto.X509Certificate(leafPem);
  const ca = new crypto.X509Certificate(caPem);
  assert.ok(leaf.checkIssued(ca), 'Leaf should be issued by CA');
});

test('leaf certificate has correct subject fields', () => {
  const leafPem = fs.readFileSync(leafCertPath);
  const leaf = new crypto.X509Certificate(leafPem);
  assert.ok(leaf.subject.includes('CN=test.localhost'), `Subject should contain CN, got: ${leaf.subject}`);
  assert.ok(leaf.subject.includes('O=my-project'), `Subject should contain O, got: ${leaf.subject}`);
  assert.ok(leaf.subject.includes('OU=web-server | daas-mkcert-controller'), `Subject should contain OU, got: ${leaf.subject}`);
});

test('leaf certificate has correct SAN', () => {
  const leafPem = fs.readFileSync(leafCertPath);
  const leaf = new crypto.X509Certificate(leafPem);
  assert.ok(
    leaf.subjectAltName && leaf.subjectAltName.includes('DNS:test.localhost'),
    `SAN should contain DNS:test.localhost, got: ${leaf.subjectAltName}`
  );
});

test('leaf certificate is not a CA', () => {
  const leafPem = fs.readFileSync(leafCertPath);
  const leaf = new crypto.X509Certificate(leafPem);
  assert.ok(!leaf.ca, 'Leaf certificate should not be a CA');
});

test('leaf certificate issuer matches CA subject', () => {
  const leafPem = fs.readFileSync(leafCertPath);
  const caPem = fs.readFileSync(caCertPath);
  const leaf = new crypto.X509Certificate(leafPem);
  const ca = new crypto.X509Certificate(caPem);
  assert.strictEqual(leaf.issuer, ca.subject, 'Leaf issuer should match CA subject');
});

// Test with minimal metadata (fallback paths)
console.log('\n  generateLeafCertificate (fallback metadata):');

const fallbackCertPath = path.join(tmpDir, 'fallback.localhost.pem');
const fallbackKeyPath = path.join(tmpDir, 'fallback.localhost-key.pem');
const fallbackSubject = buildLeafSubject('fallback.localhost', {
  project: '',
  service: '',
});

generateLeafCertificate({
  domain: 'fallback.localhost',
  certPath: fallbackCertPath,
  keyPath: fallbackKeyPath,
  caCertPath: caCertPath,
  caKeyPath: caKeyPath,
  subject: fallbackSubject,
});

test('fallback cert uses tool name as Organization', () => {
  const certPem = fs.readFileSync(fallbackCertPath);
  const cert = new crypto.X509Certificate(certPem);
  assert.ok(cert.subject.includes('O=daas-mkcert-controller'), `Should fallback O, got: ${cert.subject}`);
});

// Cleanup
try {
  fs.rmSync(tmpDir, { recursive: true, force: true });
} catch (_) {
  // Ignore cleanup errors
}

console.log(`\n  Results: ${passed} passed, ${failed} failed\n`);
if (failed > 0) process.exit(1);
