'use strict';

const assert = require('assert');
const {
  extractContainerMetadata,
  buildLeafSubject,
  buildCASubject,
  DEFAULTS,
} = require('./certSubject');

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

console.log('certSubject.js tests:');

// --- extractContainerMetadata ---
console.log('\n  extractContainerMetadata:');

test('extracts compose project and service from labels', () => {
  const labels = {
    'com.docker.compose.project': 'laboratorio-asserca',
    'com.docker.compose.service': 'bff-production',
  };
  const meta = extractContainerMetadata(labels);
  assert.strictEqual(meta.project, 'laboratorio-asserca');
  assert.strictEqual(meta.service, 'bff-production');
});

test('falls back to container name when no compose labels', () => {
  const meta = extractContainerMetadata({}, '/my-container-1');
  assert.strictEqual(meta.project, 'my-container');
  assert.strictEqual(meta.service, '');
});

test('handles container name without leading slash', () => {
  const meta = extractContainerMetadata({}, 'webapp-3');
  assert.strictEqual(meta.project, 'webapp');
  assert.strictEqual(meta.service, '');
});

test('returns empty strings when no labels and no container name', () => {
  const meta = extractContainerMetadata({});
  assert.strictEqual(meta.project, '');
  assert.strictEqual(meta.service, '');
});

test('ignores container name when compose labels are present', () => {
  const labels = {
    'com.docker.compose.project': 'myproject',
    'com.docker.compose.service': 'api',
  };
  const meta = extractContainerMetadata(labels, '/some-container-1');
  assert.strictEqual(meta.project, 'myproject');
  assert.strictEqual(meta.service, 'api');
});

// --- buildLeafSubject ---
console.log('\n  buildLeafSubject:');

test('builds full subject with project and service', () => {
  const subject = buildLeafSubject('app.localhost', {
    project: 'laboratorio-asserca',
    service: 'bff-production',
  });
  assert.strictEqual(
    subject,
    '/CN=app.localhost/O=laboratorio-asserca/OU=bff-production | daas-mkcert-controller'
  );
});

test('builds subject without service', () => {
  const subject = buildLeafSubject('app.localhost', {
    project: 'myproject',
    service: '',
  });
  assert.strictEqual(
    subject,
    '/CN=app.localhost/O=myproject/OU=daas-mkcert-controller'
  );
});

test('falls back to tool name for O when no project', () => {
  const subject = buildLeafSubject('app.localhost', {
    project: '',
    service: '',
  });
  assert.strictEqual(
    subject,
    '/CN=app.localhost/O=daas-mkcert-controller/OU=daas-mkcert-controller'
  );
});

test('uses custom tool name', () => {
  const subject = buildLeafSubject(
    'test.localhost',
    { project: 'proj', service: 'svc' },
    'custom-tool'
  );
  assert.strictEqual(
    subject,
    '/CN=test.localhost/O=proj/OU=svc | custom-tool'
  );
});

// --- buildCASubject ---
console.log('\n  buildCASubject:');

test('builds CA subject with version', () => {
  const subject = buildCASubject('1.4.0');
  assert.strictEqual(
    subject,
    '/CN=DAAS Development CA/O=DAAS Consulting/OU=daas-mkcert-controller v1.4.0'
  );
});

test('builds CA subject with custom options', () => {
  const subject = buildCASubject('2.0.0', {
    cn: 'My Custom CA',
    organization: 'My Org',
    toolName: 'my-tool',
  });
  assert.strictEqual(
    subject,
    '/CN=My Custom CA/O=My Org/OU=my-tool v2.0.0'
  );
});

test('uses defaults when no options provided', () => {
  const subject = buildCASubject('0.1.0');
  assert.ok(subject.includes(DEFAULTS.caCN));
  assert.ok(subject.includes(DEFAULTS.caOrganization));
  assert.ok(subject.includes(DEFAULTS.toolName));
});

// --- Summary ---
console.log(`\n  Results: ${passed} passed, ${failed} failed\n`);
if (failed > 0) process.exit(1);
