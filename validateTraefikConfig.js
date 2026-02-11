'use strict';

const fs = require('fs');
const path = require('path');

/**
 * Expected Traefik providers configuration block.
 * The system requires that Traefik uses a file provider watching
 * the /etc/traefik/dynamic directory.
 */
const EXPECTED_PROVIDERS = {
  file: {
    directory: '/etc/traefik/dynamic',
    watch: true,
  },
};

/**
 * Marker comment inserted into modified Traefik config files so that
 * changes made by this tool can be identified and reverted.
 */
const CONFIG_MARKER = '# Modified by daas-mkcert-controller';

/**
 * Generate a backup filename with a timestamp and .bak extension.
 *
 * @param {string} filePath - Original file path.
 * @param {Date} [now] - Optional date for testing.
 * @returns {string} Backup file path.
 */
function buildBackupPath(filePath, now) {
  const d = now || new Date();
  const ts = [
    d.getFullYear(),
    String(d.getMonth() + 1).padStart(2, '0'),
    String(d.getDate()).padStart(2, '0'),
    '-',
    String(d.getHours()).padStart(2, '0'),
    String(d.getMinutes()).padStart(2, '0'),
    String(d.getSeconds()).padStart(2, '0'),
  ].join('');
  const ext = path.extname(filePath);
  const base = filePath.slice(0, filePath.length - ext.length);
  return `${base}-${ts}${ext}.bak`;
}

/**
 * Detect the Traefik static configuration file inside TRAEFIK_DIR.
 * Looks for traefik.yml, traefik.yaml, then traefik.toml (in that order).
 *
 * @param {string} traefikDir - The Traefik configuration directory.
 * @returns {string|null} Path to the config file, or null if not found.
 */
function findTraefikConfigFile(traefikDir) {
  const candidates = ['traefik.yml', 'traefik.yaml', 'traefik.toml'];
  for (const name of candidates) {
    const fullPath = path.join(traefikDir, name);
    if (fs.existsSync(fullPath)) {
      return fullPath;
    }
  }
  return null;
}

/**
 * Parse a simple YAML subset used for Traefik static config.
 * Returns the value at a dotted key path (e.g. "providers.file.directory").
 * This intentionally avoids pulling in a full YAML parser dependency.
 *
 * @param {string} content - YAML file content.
 * @param {string} keyPath - Dotted key path.
 * @returns {string|boolean|undefined} The value found, or undefined.
 */
function yamlGetValue(content, keyPath) {
  const keys = keyPath.split('.');
  const lines = content.split('\n');
  const indentStack = []; // tracks indent levels per depth
  let keyIdx = 0;

  for (const line of lines) {
    // Skip comments and blank lines
    const trimmed = line.replace(/\s+$/, '');
    if (trimmed === '' || /^\s*#/.test(trimmed)) continue;

    const match = trimmed.match(/^(\s*)([\w.-]+)\s*:\s*(.*)/);
    if (!match) continue;

    const indent = match[1].length;
    const key = match[2];
    const rawValue = match[3].trim();

    // Adjust depth based on indentation
    while (indentStack.length > 0 && indent <= indentStack[indentStack.length - 1]) {
      indentStack.pop();
      keyIdx = Math.min(keyIdx, indentStack.length);
    }

    if (key === keys[keyIdx]) {
      if (keyIdx === keys.length - 1) {
        // Found the target key
        if (rawValue === 'true') return true;
        if (rawValue === 'false') return false;
        // Remove surrounding quotes if present
        return rawValue.replace(/^['"]|['"]$/g, '');
      }
      // Descend one level
      indentStack.push(indent);
      keyIdx++;
    }
  }

  return undefined;
}

/**
 * Check whether the existing Traefik config already has the expected
 * providers.file configuration.
 *
 * @param {string} content - YAML file content.
 * @returns {boolean} true if config matches expectations.
 */
function hasExpectedProviders(content) {
  const dir = yamlGetValue(content, 'providers.file.directory');
  const watch = yamlGetValue(content, 'providers.file.watch');
  return dir === EXPECTED_PROVIDERS.file.directory && watch === true;
}

/**
 * Build the providers YAML block to append/replace in the config.
 *
 * @returns {string}
 */
function buildProvidersBlock() {
  return [
    '',
    CONFIG_MARKER,
    'providers:',
    '  file:',
    `    directory: ${EXPECTED_PROVIDERS.file.directory}`,
    '    watch: true',
  ].join('\n');
}

/**
 * Comment out existing providers lines in the YAML content.
 * Lines belonging to the top-level "providers:" block are prefixed with "# ".
 *
 * @param {string} content - Original YAML content.
 * @returns {string} Content with providers block commented out.
 */
function commentOutProviders(content) {
  const lines = content.split('\n');
  const result = [];
  let insideProviders = false;
  let providersIndent = -1;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const trimmed = line.trimStart();

    if (!insideProviders) {
      // Detect the start of a top-level "providers:" key
      if (/^providers\s*:/.test(trimmed) && (line.length - trimmed.length) === 0) {
        insideProviders = true;
        providersIndent = 0;
        result.push(`# ${line}`);
        continue;
      }
      result.push(line);
    } else {
      // Inside providers block – check if this line is still part of it
      if (trimmed === '' || /^\s*#/.test(line)) {
        // Blank or comment lines inside the block are preserved as comments
        result.push(trimmed === '' ? line : `# ${line}`);
        continue;
      }
      const currentIndent = line.length - trimmed.length;
      if (currentIndent > providersIndent) {
        // Still inside providers block
        result.push(`# ${line}`);
      } else {
        // Left the providers block
        insideProviders = false;
        result.push(line);
      }
    }
  }

  return result.join('\n');
}

/**
 * Check if the config file was previously modified by this tool.
 *
 * @param {string} content - File content.
 * @returns {boolean}
 */
function isModifiedByTool(content) {
  return content.includes(CONFIG_MARKER);
}

/**
 * Find the most recent backup file for a given config file path.
 *
 * @param {string} configPath - Path to the original config file.
 * @returns {string|null} Path to the most recent backup, or null.
 */
function findLatestBackup(configPath) {
  const dir = path.dirname(configPath);
  const ext = path.extname(configPath);
  const baseName = path.basename(configPath, ext);
  const pattern = new RegExp(
    `^${escapeRegExp(baseName)}-\\d{8}-\\d{6}${escapeRegExp(ext)}\\.bak$`
  );

  let files;
  try {
    files = fs.readdirSync(dir);
  } catch (_) {
    return null;
  }

  const backups = files.filter((f) => pattern.test(f)).sort();
  if (backups.length === 0) return null;
  return path.join(dir, backups[backups.length - 1]);
}

/**
 * Escape special regex characters in a string.
 * @param {string} str
 * @returns {string}
 */
function escapeRegExp(str) {
  return str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

/**
 * Validate (and optionally fix) the Traefik static configuration.
 *
 * If the config is missing the expected providers.file block the function will:
 *   1. Create a timestamped backup of the original file.
 *   2. Comment out any existing providers block.
 *   3. Append the expected providers block.
 *   4. Notify the caller about the changes and how to restart Traefik.
 *
 * @param {string} traefikDir - The Traefik configuration directory.
 * @param {Function} [log] - Logging callback (message, level).
 * @returns {{ valid: boolean, modified: boolean, configPath: string|null, backupPath: string|null, messages: string[] }}
 */
function validateTraefikConfig(traefikDir, log) {
  const noop = () => {};
  const _log = typeof log === 'function' ? log : noop;
  const result = {
    valid: false,
    modified: false,
    configPath: null,
    backupPath: null,
    messages: [],
  };

  // Ensure the dynamic directory exists
  const dynamicDir = path.join(traefikDir, 'dynamic');
  if (!fs.existsSync(dynamicDir)) {
    try {
      fs.mkdirSync(dynamicDir, { recursive: true, mode: 0o755 });
      _log(`Created dynamic config directory: ${dynamicDir}`, 'INFO');
    } catch (err) {
      _log(`Failed to create dynamic directory ${dynamicDir}: ${err.message}`, 'ERROR');
    }
  }

  // Find config file
  const configPath = findTraefikConfigFile(traefikDir);
  if (!configPath) {
    _log('No Traefik static configuration file found (traefik.yml/yaml/toml)', 'WARN');
    result.messages.push('No Traefik static configuration file found.');
    return result;
  }

  result.configPath = configPath;
  _log(`Found Traefik config: ${configPath}`, 'INFO');

  // Read current config
  let content;
  try {
    content = fs.readFileSync(configPath, 'utf8');
  } catch (err) {
    _log(`Failed to read Traefik config: ${err.message}`, 'ERROR');
    result.messages.push(`Failed to read config: ${err.message}`);
    return result;
  }

  // Check if it already has the expected configuration
  if (hasExpectedProviders(content)) {
    _log('✓ Traefik configuration already has the expected providers.file setup', 'INFO');
    result.valid = true;
    return result;
  }

  // Config is different – notify and fix
  _log('Traefik configuration does not match expected providers.file setup', 'WARN');
  result.messages.push(
    'Traefik static configuration changed: providers.file.directory must point to /etc/traefik/dynamic with watch: true'
  );

  // 1. Create backup
  const backupPath = buildBackupPath(configPath);
  try {
    fs.copyFileSync(configPath, backupPath);
    result.backupPath = backupPath;
    _log(`Backup created: ${backupPath}`, 'INFO');
    result.messages.push(`Backup of original config saved to: ${backupPath}`);
  } catch (err) {
    _log(`Failed to create backup: ${err.message}`, 'ERROR');
    result.messages.push(`Failed to create backup: ${err.message}`);
    return result;
  }

  // 2. Comment out existing providers and append expected block
  const commented = commentOutProviders(content);
  const newContent = commented + '\n' + buildProvidersBlock() + '\n';

  try {
    fs.writeFileSync(configPath, newContent);
    _log('✓ Traefik configuration updated with expected providers.file block', 'INFO');
    _log('  Previous providers configuration has been commented out', 'INFO');
    result.modified = true;
    result.valid = true;
    result.messages.push('Configuration updated. Previous providers section commented out.');
  } catch (err) {
    _log(`Failed to write updated config: ${err.message}`, 'ERROR');
    result.messages.push(`Failed to update config: ${err.message}`);
    return result;
  }

  // 3. Notify about restart
  _log('⚠ Traefik needs to be restarted to apply the new configuration', 'WARN');
  _log('  Run: docker restart <traefik-container-name>', 'WARN');
  result.messages.push('Traefik must be restarted. Run: docker restart <traefik-container-name>');

  return result;
}

/**
 * Revert changes made by this tool to the Traefik static configuration.
 * Finds the most recent backup and restores it.
 *
 * @param {string} traefikDir - The Traefik configuration directory.
 * @param {Function} [log] - Logging callback (message, level).
 * @returns {{ reverted: boolean, configPath: string|null, backupPath: string|null, messages: string[] }}
 */
function revertTraefikConfig(traefikDir, log) {
  const noop = () => {};
  const _log = typeof log === 'function' ? log : noop;
  const result = {
    reverted: false,
    configPath: null,
    backupPath: null,
    messages: [],
  };

  const configPath = findTraefikConfigFile(traefikDir);
  if (!configPath) {
    _log('No Traefik config file found, nothing to revert', 'INFO');
    result.messages.push('No Traefik config file found.');
    return result;
  }

  result.configPath = configPath;

  // Check if the file was modified by this tool
  let content;
  try {
    content = fs.readFileSync(configPath, 'utf8');
  } catch (err) {
    _log(`Failed to read config: ${err.message}`, 'ERROR');
    result.messages.push(`Failed to read config: ${err.message}`);
    return result;
  }

  if (!isModifiedByTool(content)) {
    _log('Traefik config was not modified by this tool, nothing to revert', 'INFO');
    result.messages.push('Config was not modified by this tool.');
    return result;
  }

  // Find the latest backup
  const backupPath = findLatestBackup(configPath);
  if (!backupPath) {
    _log('No backup file found to restore', 'WARN');
    result.messages.push('No backup file found. Cannot revert automatically.');
    return result;
  }

  result.backupPath = backupPath;
  _log(`Found backup to restore: ${backupPath}`, 'INFO');

  // Restore
  try {
    fs.copyFileSync(backupPath, configPath);
    result.reverted = true;
    _log(`✓ Traefik configuration reverted from backup: ${backupPath}`, 'INFO');
    result.messages.push(`Configuration restored from: ${backupPath}`);
    _log('⚠ Traefik needs to be restarted to apply the reverted configuration', 'WARN');
    _log('  Run: docker restart <traefik-container-name>', 'WARN');
    result.messages.push('Traefik must be restarted. Run: docker restart <traefik-container-name>');
  } catch (err) {
    _log(`Failed to restore backup: ${err.message}`, 'ERROR');
    result.messages.push(`Failed to restore: ${err.message}`);
  }

  return result;
}

module.exports = {
  validateTraefikConfig,
  revertTraefikConfig,
  // Exported for testing
  buildBackupPath,
  findTraefikConfigFile,
  hasExpectedProviders,
  commentOutProviders,
  buildProvidersBlock,
  isModifiedByTool,
  findLatestBackup,
  yamlGetValue,
  CONFIG_MARKER,
};
