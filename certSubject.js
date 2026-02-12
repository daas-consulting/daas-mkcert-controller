'use strict';

/**
 * Default values for certificate subject fields.
 */
const DEFAULTS = {
  caOrganization: 'DAAS Consulting',
  caCN: 'DAAS Development CA',
  toolName: 'daas-mkcert-controller',
};

/**
 * Extract meaningful metadata from Docker container labels.
 *
 * Looks for Docker Compose labels to identify the project and service.
 * Falls back to container name if Compose labels are not present.
 *
 * @param {Object} labels - Docker container labels
 * @param {string} [containerName] - Container name as fallback
 * @returns {{ project: string, service: string }}
 */
function extractContainerMetadata(labels, containerName) {
  const project = labels['com.docker.compose.project'] || '';
  const service = labels['com.docker.compose.service'] || '';

  // Fallback: derive from container name (strip trailing -N replica suffix)
  if (!project && containerName) {
    const cleaned = containerName.replace(/^\//, '').replace(/-\d+$/, '');
    return { project: cleaned, service: '' };
  }

  return { project, service };
}

/**
 * Build the Subject string for a leaf (domain) certificate.
 *
 * Format: /CN=<domain>/O=<project>/OU=<service> | daas-mkcert-controller
 *
 * @param {string} domain - The domain name (e.g. "app.localhost")
 * @param {{ project: string, service: string }} metadata - Container metadata
 * @param {string} [toolName] - Tool name for OU suffix
 * @returns {string} OpenSSL subject string
 */
function buildLeafSubject(domain, metadata, toolName) {
  const tool = toolName || DEFAULTS.toolName;
  const cn = domain;
  const o = metadata.project || tool;
  const ouParts = [];
  if (metadata.service) ouParts.push(metadata.service);
  ouParts.push(tool);
  const ou = ouParts.join(' | ');

  return `/CN=${cn}/O=${o}/OU=${ou}`;
}

/**
 * Build the Subject string for the CA certificate.
 *
 * Format: /CN=DAAS Development CA/O=DAAS Consulting/OU=daas-mkcert-controller vX.Y.Z
 *
 * @param {string} version - Controller version (e.g. "1.4.0")
 * @param {Object} [options] - Optional overrides
 * @param {string} [options.cn] - Custom CN
 * @param {string} [options.organization] - Custom Organization
 * @param {string} [options.toolName] - Custom tool name
 * @returns {string} OpenSSL subject string
 */
function buildCASubject(version, options) {
  const opts = options || {};
  const cn = opts.cn || DEFAULTS.caCN;
  const o = opts.organization || DEFAULTS.caOrganization;
  const tool = opts.toolName || DEFAULTS.toolName;
  const ou = `${tool} v${version}`;

  return `/CN=${cn}/O=${o}/OU=${ou}`;
}

module.exports = {
  DEFAULTS,
  extractContainerMetadata,
  buildLeafSubject,
  buildCASubject,
};
