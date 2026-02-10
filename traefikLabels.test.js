'use strict';

const { parseTraefikLabels, extractDomainsFromLabels } = require('./traefikLabels');

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

function assertDeepEqual(actual, expected, message) {
  const a = JSON.stringify(actual.sort());
  const e = JSON.stringify(expected.sort());
  if (a === e) {
    passed++;
    console.log(`  ✓ ${message}`);
  } else {
    failed++;
    console.error(`  ✗ FAIL: ${message}`);
    console.error(`    Expected: ${e}`);
    console.error(`    Actual:   ${a}`);
  }
}

console.log('parseTraefikLabels() tests');
console.log('');

// --- parseTraefikLabels ---
console.log('Basic router parsing:');

assert(
  Object.keys(parseTraefikLabels({})).length === 0,
  'empty labels returns empty object'
);

{
  const labels = {
    'traefik.http.routers.myapp.rule': 'Host(`myapp.localhost`)',
    'traefik.http.routers.myapp.tls': 'true',
  };
  const routers = parseTraefikLabels(labels);
  assert(routers['myapp'] !== undefined, 'parses router name from labels');
  assert(routers['myapp'].rule === 'Host(`myapp.localhost`)', 'parses router rule');
  assert(routers['myapp'].tls === 'true', 'parses router tls property');
}

{
  const labels = {
    'traefik.http.routers.app-tls.rule': 'Host(`app.localhost`)',
    'traefik.http.routers.app-tls.tls': 'true',
    'traefik.http.routers.app.rule': 'Host(`app.localhost`)',
    'traefik.http.routers.app.tls': 'false',
  };
  const routers = parseTraefikLabels(labels);
  assert(Object.keys(routers).length === 2, 'parses multiple routers');
  assert(routers['app-tls'].tls === 'true', 'first router has tls=true');
  assert(routers['app'].tls === 'false', 'second router has tls=false');
}

console.log('');
console.log('Non-router labels ignored:');
{
  const labels = {
    'traefik.enable': 'true',
    'traefik.docker.network': 'traefik',
    'traefik.http.services.myapp.loadbalancer.server.port': '8080',
    'traefik.http.routers.myapp.rule': 'Host(`myapp.localhost`)',
  };
  const routers = parseTraefikLabels(labels);
  assert(Object.keys(routers).length === 1, 'only parses router labels');
  assert(routers['myapp'].rule === 'Host(`myapp.localhost`)', 'non-router labels are ignored');
}

console.log('');
console.log('extractDomainsFromLabels() tests');
console.log('');

// --- Single host ---
console.log('Single host:');
{
  const labels = {
    'traefik.http.routers.myapp.rule': 'Host(`myapp.localhost`)',
    'traefik.http.routers.myapp.tls': 'true',
  };
  assertDeepEqual(
    extractDomainsFromLabels(labels),
    ['myapp.localhost'],
    'extracts single .localhost domain'
  );
}

console.log('');
console.log('Multiple comma-separated hosts in single Host():');
{
  // This is the exact case from the bug report
  const labels = {
    'traefik.http.routers.bff-production-local-tls.entrypoints': 'websecure',
    'traefik.http.routers.bff-production-local-tls.rule': 'Host(`bff.local.laboratorio-asserca.localhost`, `bff.production.local.laboratorio-asserca.localhost`)',
    'traefik.http.routers.bff-production-local-tls.service': 'bff-production-local',
    'traefik.http.routers.bff-production-local-tls.tls': 'true',
    'traefik.http.routers.bff-production-local.entrypoints': 'web',
    'traefik.http.routers.bff-production-local.rule': 'Host(`bff.local.laboratorio-asserca.localhost`, `bff.production.local.laboratorio-asserca.localhost`)',
    'traefik.http.routers.bff-production-local.service': 'bff-production-local',
    'traefik.http.routers.bff-production-local.tls': 'false',
    'traefik.http.services.bff-production-local-tls.loadbalancer.server.port': '8080',
    'traefik.http.services.bff-production-local.loadbalancer.server.port': '8080',
  };
  assertDeepEqual(
    extractDomainsFromLabels(labels),
    ['bff.local.laboratorio-asserca.localhost', 'bff.production.local.laboratorio-asserca.localhost'],
    'extracts both domains from comma-separated Host() with TLS enabled'
  );
}

console.log('');
console.log('TLS not enabled:');
{
  const labels = {
    'traefik.http.routers.myapp.rule': 'Host(`myapp.localhost`)',
    'traefik.http.routers.myapp.tls': 'false',
  };
  assertDeepEqual(
    extractDomainsFromLabels(labels),
    [],
    'returns no domains when TLS is false'
  );
}

{
  const labels = {
    'traefik.http.routers.myapp.rule': 'Host(`myapp.localhost`)',
  };
  assertDeepEqual(
    extractDomainsFromLabels(labels),
    [],
    'returns no domains when TLS label is missing'
  );
}

console.log('');
console.log('Non-.localhost domains filtered:');
{
  const labels = {
    'traefik.http.routers.myapp.rule': 'Host(`myapp.example.com`)',
    'traefik.http.routers.myapp.tls': 'true',
  };
  assertDeepEqual(
    extractDomainsFromLabels(labels),
    [],
    'ignores non-.localhost domains'
  );
}

{
  const labels = {
    'traefik.http.routers.myapp.rule': 'Host(`myapp.localhost`, `myapp.example.com`)',
    'traefik.http.routers.myapp.tls': 'true',
  };
  assertDeepEqual(
    extractDomainsFromLabels(labels),
    ['myapp.localhost'],
    'extracts only .localhost domains from mixed host list'
  );
}

console.log('');
console.log('Multiple routers with mixed TLS:');
{
  const labels = {
    'traefik.http.routers.app-tls.rule': 'Host(`app.localhost`)',
    'traefik.http.routers.app-tls.tls': 'true',
    'traefik.http.routers.app.rule': 'Host(`app.localhost`)',
    'traefik.http.routers.app.tls': 'false',
  };
  assertDeepEqual(
    extractDomainsFromLabels(labels),
    ['app.localhost'],
    'only extracts domains from TLS-enabled routers'
  );
}

console.log('');
console.log('Multiple Host() expressions with || (OR):');
{
  const labels = {
    'traefik.http.routers.myapp.rule': 'Host(`app1.localhost`) || Host(`app2.localhost`)',
    'traefik.http.routers.myapp.tls': 'true',
  };
  assertDeepEqual(
    extractDomainsFromLabels(labels),
    ['app1.localhost', 'app2.localhost'],
    'extracts domains from multiple Host() expressions separated by ||'
  );
}

console.log('');
console.log('Deduplication:');
{
  const labels = {
    'traefik.http.routers.app-tls.rule': 'Host(`myapp.localhost`)',
    'traefik.http.routers.app-tls.tls': 'true',
    'traefik.http.routers.app-secure.rule': 'Host(`myapp.localhost`)',
    'traefik.http.routers.app-secure.tls': 'true',
  };
  assertDeepEqual(
    extractDomainsFromLabels(labels),
    ['myapp.localhost'],
    'deduplicates domains across routers'
  );
}

console.log('');
console.log('Logger callback:');
{
  const logged = [];
  const labels = {
    'traefik.http.routers.myapp.rule': 'Host(`myapp.localhost`)',
    'traefik.http.routers.myapp.tls': 'true',
  };
  extractDomainsFromLabels(labels, (msg, level) => logged.push({ msg, level }));
  assert(logged.length === 1, 'log callback is called once per domain');
  assert(logged[0].level === 'DEBUG', 'log callback receives DEBUG level');
  assert(logged[0].msg.includes('myapp.localhost'), 'log callback receives domain in message');
}

console.log('');

// --- Summary ---
console.log('---');
console.log(`Results: ${passed} passed, ${failed} failed`);

if (failed > 0) {
  process.exit(1);
}
