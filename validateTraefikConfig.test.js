'use strict';

const fs = require('fs');
const path = require('path');
const os = require('os');
const {
  buildBackupPath,
  findTraefikConfigFile,
  hasExpectedProviders,
  commentOutProviders,
  buildProvidersBlock,
  isModifiedByTool,
  findLatestBackup,
  yamlGetValue,
  validateTraefikConfig,
  revertTraefikConfig,
  CONFIG_MARKER,
} = require('./validateTraefikConfig');

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

// Create a temporary directory for test isolation
const tmpBase = fs.mkdtempSync(path.join(os.tmpdir(), 'validateTraefikConfig-test-'));

// ───────────────────────────────────────────────
console.log('buildBackupPath() tests');
console.log('');

{
  const d = new Date(2025, 0, 15, 9, 30, 45); // Jan 15 2025 09:30:45
  const result = buildBackupPath('/etc/traefik/traefik.yml', d);
  assert(
    result === '/etc/traefik/traefik-20250115-093045.yml.bak',
    'builds correct backup path with datetime'
  );
}

{
  const d = new Date(2025, 11, 1, 23, 5, 3); // Dec 01 2025 23:05:03
  const result = buildBackupPath('/home/user/.traefik/traefik.yaml', d);
  assert(
    result === '/home/user/.traefik/traefik-20251201-230503.yaml.bak',
    'pads single-digit month/day/hour/minute/second'
  );
}

console.log('');

// ───────────────────────────────────────────────
console.log('findTraefikConfigFile() tests');
console.log('');

{
  const dir = path.join(tmpBase, 'find-yml');
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, 'traefik.yml'), 'entryPoints:');
  assert(
    findTraefikConfigFile(dir) === path.join(dir, 'traefik.yml'),
    'finds traefik.yml'
  );
}

{
  const dir = path.join(tmpBase, 'find-yaml');
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, 'traefik.yaml'), 'entryPoints:');
  assert(
    findTraefikConfigFile(dir) === path.join(dir, 'traefik.yaml'),
    'finds traefik.yaml'
  );
}

{
  const dir = path.join(tmpBase, 'find-toml');
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, 'traefik.toml'), '[entryPoints]');
  assert(
    findTraefikConfigFile(dir) === path.join(dir, 'traefik.toml'),
    'finds traefik.toml'
  );
}

{
  const dir = path.join(tmpBase, 'find-none');
  fs.mkdirSync(dir, { recursive: true });
  assert(
    findTraefikConfigFile(dir) === null,
    'returns null when no config file found'
  );
}

{
  const dir = path.join(tmpBase, 'find-priority');
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, 'traefik.yml'), 'yml');
  fs.writeFileSync(path.join(dir, 'traefik.yaml'), 'yaml');
  assert(
    findTraefikConfigFile(dir) === path.join(dir, 'traefik.yml'),
    'prefers traefik.yml over traefik.yaml'
  );
}

console.log('');

// ───────────────────────────────────────────────
console.log('yamlGetValue() tests');
console.log('');

{
  const content = [
    'providers:',
    '  file:',
    '    directory: /etc/traefik/dynamic',
    '    watch: true',
  ].join('\n');
  assert(
    yamlGetValue(content, 'providers.file.directory') === '/etc/traefik/dynamic',
    'reads nested YAML value'
  );
  assert(
    yamlGetValue(content, 'providers.file.watch') === true,
    'reads boolean true value'
  );
}

{
  const content = [
    'entryPoints:',
    '  web:',
    '    address: ":80"',
    'providers:',
    '  file:',
    '    directory: /some/other/dir',
    '    watch: false',
  ].join('\n');
  assert(
    yamlGetValue(content, 'providers.file.directory') === '/some/other/dir',
    'reads value from config with multiple top-level keys'
  );
  assert(
    yamlGetValue(content, 'providers.file.watch') === false,
    'reads boolean false value'
  );
}

{
  const content = [
    'entryPoints:',
    '  web:',
    '    address: ":80"',
  ].join('\n');
  assert(
    yamlGetValue(content, 'providers.file.directory') === undefined,
    'returns undefined for missing key'
  );
}

{
  const content = [
    '# This is a comment',
    'providers:',
    '  # Another comment',
    '  file:',
    '    directory: /etc/traefik/dynamic',
  ].join('\n');
  assert(
    yamlGetValue(content, 'providers.file.directory') === '/etc/traefik/dynamic',
    'skips comments when parsing'
  );
}

console.log('');

// ───────────────────────────────────────────────
console.log('hasExpectedProviders() tests');
console.log('');

{
  const content = [
    'providers:',
    '  file:',
    '    directory: /etc/traefik/dynamic',
    '    watch: true',
  ].join('\n');
  assert(
    hasExpectedProviders(content) === true,
    'returns true when config matches expected providers'
  );
}

{
  const content = [
    'providers:',
    '  file:',
    '    directory: /some/other/dir',
    '    watch: true',
  ].join('\n');
  assert(
    hasExpectedProviders(content) === false,
    'returns false when directory differs'
  );
}

{
  const content = [
    'providers:',
    '  file:',
    '    directory: /etc/traefik/dynamic',
    '    watch: false',
  ].join('\n');
  assert(
    hasExpectedProviders(content) === false,
    'returns false when watch is false'
  );
}

{
  const content = [
    'entryPoints:',
    '  web:',
    '    address: ":80"',
  ].join('\n');
  assert(
    hasExpectedProviders(content) === false,
    'returns false when providers block is missing'
  );
}

console.log('');

// ───────────────────────────────────────────────
console.log('commentOutProviders() tests');
console.log('');

{
  const content = [
    'entryPoints:',
    '  web:',
    '    address: ":80"',
    'providers:',
    '  file:',
    '    directory: /old/dir',
    '    watch: false',
    'api:',
    '  dashboard: true',
  ].join('\n');
  const result = commentOutProviders(content);
  assert(
    result.includes('# providers:'),
    'comments out providers key'
  );
  assert(
    result.includes('#   file:'),
    'comments out file key'
  );
  assert(
    result.includes('#     directory: /old/dir'),
    'comments out directory'
  );
  assert(
    result.includes('#     watch: false'),
    'comments out watch'
  );
  assert(
    result.includes('entryPoints:') && !result.includes('# entryPoints:'),
    'does not comment out other top-level keys'
  );
  assert(
    result.includes('api:') && !result.includes('# api:'),
    'does not comment out api key after providers block'
  );
}

console.log('');

// ───────────────────────────────────────────────
console.log('buildProvidersBlock() tests');
console.log('');

{
  const block = buildProvidersBlock();
  assert(
    block.includes(CONFIG_MARKER),
    'includes marker comment'
  );
  assert(
    block.includes('providers:'),
    'includes providers key'
  );
  assert(
    block.includes('directory: /etc/traefik/dynamic'),
    'includes expected directory'
  );
  assert(
    block.includes('watch: true'),
    'includes watch: true'
  );
}

console.log('');

// ───────────────────────────────────────────────
console.log('isModifiedByTool() tests');
console.log('');

{
  assert(
    isModifiedByTool(`some content\n${CONFIG_MARKER}\nmore content`) === true,
    'returns true when marker is present'
  );
  assert(
    isModifiedByTool('some content without marker') === false,
    'returns false when marker is absent'
  );
}

console.log('');

// ───────────────────────────────────────────────
console.log('findLatestBackup() tests');
console.log('');

{
  const dir = path.join(tmpBase, 'backups');
  fs.mkdirSync(dir, { recursive: true });
  const configPath = path.join(dir, 'traefik.yml');
  fs.writeFileSync(configPath, 'config');
  fs.writeFileSync(path.join(dir, 'traefik-20250101-100000.yml.bak'), 'old');
  fs.writeFileSync(path.join(dir, 'traefik-20250615-120000.yml.bak'), 'newer');
  fs.writeFileSync(path.join(dir, 'traefik-20250310-080000.yml.bak'), 'middle');
  assert(
    findLatestBackup(configPath) === path.join(dir, 'traefik-20250615-120000.yml.bak'),
    'finds the most recent backup by name sorting'
  );
}

{
  const dir = path.join(tmpBase, 'no-backups');
  fs.mkdirSync(dir, { recursive: true });
  const configPath = path.join(dir, 'traefik.yml');
  fs.writeFileSync(configPath, 'config');
  assert(
    findLatestBackup(configPath) === null,
    'returns null when no backups exist'
  );
}

console.log('');

// ───────────────────────────────────────────────
console.log('validateTraefikConfig() tests');
console.log('');

// Already valid config
{
  const dir = path.join(tmpBase, 'validate-valid');
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(
    path.join(dir, 'traefik.yml'),
    [
      'entryPoints:',
      '  web:',
      '    address: ":80"',
      'providers:',
      '  file:',
      '    directory: /etc/traefik/dynamic',
      '    watch: true',
    ].join('\n')
  );
  const result = validateTraefikConfig(dir);
  assert(result.valid === true, 'valid when config matches expected');
  assert(result.modified === false, 'not modified when already valid');
  assert(result.backupPath === null, 'no backup created when already valid');
}

// Config with wrong directory
{
  const dir = path.join(tmpBase, 'validate-wrong');
  fs.mkdirSync(dir, { recursive: true });
  const configContent = [
    'entryPoints:',
    '  web:',
    '    address: ":80"',
    'providers:',
    '  file:',
    '    directory: /old/dir',
    '    watch: false',
  ].join('\n');
  fs.writeFileSync(path.join(dir, 'traefik.yml'), configContent);

  const logged = [];
  const result = validateTraefikConfig(dir, (msg, level) => logged.push({ msg, level }));
  assert(result.valid === true, 'valid after modification');
  assert(result.modified === true, 'modified when config was wrong');
  assert(result.backupPath !== null, 'backup path is set');
  assert(fs.existsSync(result.backupPath), 'backup file exists');
  // Verify backup contains original content
  assert(
    fs.readFileSync(result.backupPath, 'utf8') === configContent,
    'backup contains original content'
  );
  // Verify modified config has expected providers
  const newContent = fs.readFileSync(path.join(dir, 'traefik.yml'), 'utf8');
  assert(
    newContent.includes(CONFIG_MARKER),
    'modified config includes marker'
  );
  assert(
    newContent.includes('directory: /etc/traefik/dynamic'),
    'modified config has expected directory'
  );
  assert(
    newContent.includes('# providers:'),
    'modified config has old providers commented out'
  );
  // Verify restart notification
  const warnMsgs = logged.filter((l) => l.level === 'WARN');
  assert(
    warnMsgs.some((m) => m.msg.includes('docker restart')),
    'notifies user about docker restart command'
  );
}

// No config file
{
  const dir = path.join(tmpBase, 'validate-no-config');
  fs.mkdirSync(dir, { recursive: true });
  const result = validateTraefikConfig(dir);
  assert(result.valid === false, 'not valid when no config file found');
  assert(result.configPath === null, 'configPath is null when no file found');
}

// Config without providers section
{
  const dir = path.join(tmpBase, 'validate-no-providers');
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(
    path.join(dir, 'traefik.yml'),
    [
      'entryPoints:',
      '  web:',
      '    address: ":80"',
      'api:',
      '  dashboard: true',
    ].join('\n')
  );
  const result = validateTraefikConfig(dir);
  assert(result.valid === true, 'valid after adding providers to config without one');
  assert(result.modified === true, 'modified when providers section was missing');
  const newContent = fs.readFileSync(path.join(dir, 'traefik.yml'), 'utf8');
  assert(
    newContent.includes('directory: /etc/traefik/dynamic'),
    'appended expected providers block'
  );
}

console.log('');

// ───────────────────────────────────────────────
console.log('revertTraefikConfig() tests');
console.log('');

// Revert modified config
{
  const dir = path.join(tmpBase, 'revert-ok');
  fs.mkdirSync(dir, { recursive: true });

  const originalContent = [
    'entryPoints:',
    '  web:',
    '    address: ":80"',
    'providers:',
    '  file:',
    '    directory: /old/dir',
    '    watch: false',
  ].join('\n');

  // First, validate to create the modification + backup
  fs.writeFileSync(path.join(dir, 'traefik.yml'), originalContent);
  const valResult = validateTraefikConfig(dir);
  assert(valResult.modified === true, 'setup: config was modified');

  // Now revert
  const logged = [];
  const result = revertTraefikConfig(dir, (msg, level) => logged.push({ msg, level }));
  assert(result.reverted === true, 'revert succeeded');
  assert(result.backupPath !== null, 'backup path used for revert');

  // Verify content was restored
  const restored = fs.readFileSync(path.join(dir, 'traefik.yml'), 'utf8');
  assert(
    restored === originalContent,
    'config restored to original content'
  );

  // Verify restart notification
  const warnMsgs = logged.filter((l) => l.level === 'WARN');
  assert(
    warnMsgs.some((m) => m.msg.includes('docker restart')),
    'revert notifies user about docker restart command'
  );
}

// Nothing to revert (not modified by tool)
{
  const dir = path.join(tmpBase, 'revert-no-marker');
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(
    path.join(dir, 'traefik.yml'),
    [
      'providers:',
      '  file:',
      '    directory: /etc/traefik/dynamic',
      '    watch: true',
    ].join('\n')
  );
  const result = revertTraefikConfig(dir);
  assert(result.reverted === false, 'no revert when config not modified by tool');
}

// No config file to revert
{
  const dir = path.join(tmpBase, 'revert-no-file');
  fs.mkdirSync(dir, { recursive: true });
  const result = revertTraefikConfig(dir);
  assert(result.reverted === false, 'no revert when no config file exists');
}

// Creates dynamic directory
{
  const dir = path.join(tmpBase, 'validate-creates-dynamic');
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(
    path.join(dir, 'traefik.yml'),
    [
      'providers:',
      '  file:',
      '    directory: /etc/traefik/dynamic',
      '    watch: true',
    ].join('\n')
  );
  const dynamicDir = path.join(dir, 'dynamic');
  assert(!fs.existsSync(dynamicDir), 'setup: dynamic dir does not exist');
  validateTraefikConfig(dir);
  assert(fs.existsSync(dynamicDir), 'dynamic directory created by validation');
}

console.log('');

// --- Cleanup ---
fs.rmSync(tmpBase, { recursive: true, force: true });

// --- Summary ---
console.log('---');
console.log(`Results: ${passed} passed, ${failed} failed`);

if (failed > 0) {
  process.exit(1);
}
