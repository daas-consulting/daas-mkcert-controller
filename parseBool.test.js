'use strict';

const { parseBool } = require('./parseBool');

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

console.log('parseBool() tests');
console.log('');

// --- Truthy values ---
console.log('Truthy values:');
['1', 't', 'true', 'TRUE', 'True', 's', 'si', 'SI', 'Si', 'y', 'yes', 'YES', 'Yes'].forEach(val => {
  assert(parseBool(val, undefined, 'test') === true, `parseBool('${val}') === true`);
});

console.log('');

// --- Falsy values ---
console.log('Falsy values:');
['0', 'f', 'false', 'FALSE', 'False', 'n', 'no', 'NO', 'No'].forEach(val => {
  assert(parseBool(val, undefined, 'test') === false, `parseBool('${val}') === false`);
});

console.log('');

// --- Default values ---
console.log('Default values:');
assert(parseBool(undefined, true) === true, 'undefined with default true returns true');
assert(parseBool(undefined, false) === false, 'undefined with default false returns false');
assert(parseBool(null, true) === true, 'null with default true returns true');
assert(parseBool('', false) === false, 'empty string with default false returns false');

console.log('');

// --- Priority: explicit value over default ---
console.log('Priority (explicit value over default):');
assert(parseBool('false', true) === false, 'explicit false overrides default true');
assert(parseBool('true', false) === true, 'explicit true overrides default false');
assert(parseBool('0', true) === false, 'explicit 0 overrides default true');
assert(parseBool('1', false) === true, 'explicit 1 overrides default false');
assert(parseBool('no', true) === false, 'explicit no overrides default true');
assert(parseBool('yes', false) === true, 'explicit yes overrides default false');
assert(parseBool('si', false) === true, 'explicit si overrides default false');

console.log('');

// --- Required parameter (no default) ---
console.log('Required parameter (no default):');
assertThrows(
  () => parseBool(undefined, undefined, 'MY_PARAM'),
  'Required',
  'throws when required param is undefined'
);
assertThrows(
  () => parseBool(null, undefined, 'MY_PARAM'),
  'Required',
  'throws when required param is null'
);
assertThrows(
  () => parseBool('', undefined, 'MY_PARAM'),
  'Required',
  'throws when required param is empty string'
);

console.log('');

// --- Invalid values ---
console.log('Invalid values:');
assertThrows(
  () => parseBool('maybe', true, 'test'),
  'Invalid value',
  'throws on invalid value "maybe"'
);
assertThrows(
  () => parseBool('2', true, 'test'),
  'Invalid value',
  'throws on invalid value "2"'
);
assertThrows(
  () => parseBool('oui', true, 'test'),
  'Invalid value',
  'throws on invalid value "oui"'
);

console.log('');

// --- Whitespace handling ---
console.log('Whitespace handling:');
assert(parseBool(' true ', undefined, 'test') === true, 'trims whitespace for " true "');
assert(parseBool(' false ', undefined, 'test') === false, 'trims whitespace for " false "');

console.log('');

// --- Summary ---
console.log('---');
console.log(`Results: ${passed} passed, ${failed} failed`);

if (failed > 0) {
  process.exit(1);
}
