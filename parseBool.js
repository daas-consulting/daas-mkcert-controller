'use strict';

/**
 * Parse a boolean value from a string using locale-aware regex patterns.
 *
 * Truthy pattern: ^(1|t(rue)?|s(i)?|y(es)?)  (case-insensitive)
 * Falsy  pattern: ^(0|f(alse)?|n(o)?)         (case-insensitive)
 *
 * @param {string|undefined} value - The string value to parse.
 * @param {boolean|undefined} defaultValue - Default when value is undefined/null/empty.
 *   Pass undefined to make the parameter required (throws on missing value).
 * @param {string} [name] - Parameter name used in error messages.
 * @returns {boolean} The parsed boolean value.
 * @throws {Error} When value cannot be parsed or is missing and no default is provided.
 */
function parseBool(value, defaultValue, name) {
  const label = name ? `'${name}'` : 'boolean parameter';

  if (value === undefined || value === null || value === '') {
    if (defaultValue === undefined) {
      throw new Error(`Required ${label} is not configured`);
    }
    return defaultValue;
  }

  const v = String(value).trim().toLowerCase();

  if (/^(1|t(rue)?|s(i)?|y(es)?)$/.test(v)) {
    return true;
  }

  if (/^(0|f(alse)?|n(o)?)$/.test(v)) {
    return false;
  }

  throw new Error(`Invalid value for ${label}: '${value}'. Use true/false, yes/no, si/no, 1/0`);
}

module.exports = { parseBool };
