'use strict';

const fs = require('fs');
const path = require('path');
const os = require('os');
const { validateNotEmpty, validateDirectory } = require('./validateConfig');

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

// Create a temporary directory for test isolation
const tmpBase = fs.mkdtempSync(path.join(os.tmpdir(), 'validateConfig-test-'));

console.log('validateNotEmpty() tests');
console.log('');

// --- Valid values ---
console.log('Valid non-empty values:');
assert(validateNotEmpty('hello', 'TEST') === 'hello', "validateNotEmpty('hello') returns 'hello'");
assert(validateNotEmpty('/some/path', 'TEST') === '/some/path', "validateNotEmpty('/some/path') returns '/some/path'");
assert(validateNotEmpty(' trimmed ', 'TEST') === 'trimmed', "validateNotEmpty(' trimmed ') trims whitespace");

console.log('');

// --- Empty / missing values ---
console.log('Empty and missing values:');
assertThrows(
  () => validateNotEmpty(undefined, 'MY_PARAM'),
  'is required',
  'throws when value is undefined'
);
assertThrows(
  () => validateNotEmpty(null, 'MY_PARAM'),
  'is required',
  'throws when value is null'
);
assertThrows(
  () => validateNotEmpty('', 'MY_PARAM'),
  'cannot be an empty string',
  'throws when value is empty string'
);
assertThrows(
  () => validateNotEmpty('   ', 'MY_PARAM'),
  'cannot be an empty string',
  'throws when value is only whitespace'
);

console.log('');

// --- Error messages include parameter name ---
console.log('Error messages include parameter name:');
assertThrows(
  () => validateNotEmpty('', 'TRAEFIK_DIR'),
  'TRAEFIK_DIR',
  'error message includes parameter name TRAEFIK_DIR'
);

console.log('');

console.log('validateDirectory() tests');
console.log('');

// --- Empty / missing directory values ---
console.log('Empty and missing directory values:');
assertThrows(
  () => validateDirectory(undefined, 'CERTS_DIR'),
  'is required',
  'throws when directory value is undefined'
);
assertThrows(
  () => validateDirectory('', 'CERTS_DIR'),
  'cannot be an empty string',
  'throws when directory value is empty string'
);
assertThrows(
  () => validateDirectory('   ', 'CERTS_DIR'),
  'cannot be an empty string',
  'throws when directory value is only whitespace'
);

console.log('');

// --- Valid writable directory ---
console.log('Valid writable directory:');
const writableDir = path.join(tmpBase, 'writable');
fs.mkdirSync(writableDir, { recursive: true, mode: 0o755 });
assert(
  validateDirectory(writableDir, 'TEST_DIR') === writableDir,
  'validates existing writable directory'
);

console.log('');

// --- Auto-create directory ---
console.log('Auto-create directory:');
const autoCreateDir = path.join(tmpBase, 'auto', 'nested', 'dir');
assert(
  validateDirectory(autoCreateDir, 'TEST_DIR') === autoCreateDir,
  'auto-creates nested directory'
);
assert(
  fs.existsSync(autoCreateDir),
  'auto-created directory exists on filesystem'
);

console.log('');

// --- Path is a file, not a directory ---
console.log('Path is a file, not a directory:');
const filePath = path.join(tmpBase, 'afile.txt');
fs.writeFileSync(filePath, 'not a directory');
assertThrows(
  () => validateDirectory(filePath, 'BAD_DIR'),
  'is not a directory',
  'throws when path is a file'
);

console.log('');

// --- Read-only directory (no write permission) ---
console.log('Read-only directory:');
const readonlyDir = path.join(tmpBase, 'readonly');
fs.mkdirSync(readonlyDir, { recursive: true, mode: 0o755 });
fs.chmodSync(readonlyDir, 0o444);
assertThrows(
  () => validateDirectory(readonlyDir, 'RO_DIR'),
  'No write permission',
  'throws when directory has no write permission'
);
// Restore permissions for cleanup
fs.chmodSync(readonlyDir, 0o755);

console.log('');

// --- Error messages include directory path ---
console.log('Error messages include remediation info:');
assertThrows(
  () => validateDirectory('', 'MKCERT_CA_DIR'),
  'MKCERT_CA_DIR',
  'error message includes parameter name for remediation'
);

console.log('');

// --- Cleanup ---
fs.rmSync(tmpBase, { recursive: true, force: true });

// --- Summary ---
console.log('---');
console.log(`Results: ${passed} passed, ${failed} failed`);

if (failed > 0) {
  process.exit(1);
}
