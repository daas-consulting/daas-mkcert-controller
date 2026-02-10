'use strict';

const fs = require('fs');
const path = require('path');

/**
 * Validate that a string parameter is not empty after trimming.
 *
 * @param {string|undefined} value - The value to validate.
 * @param {string} name - Parameter name used in error messages.
 * @returns {string} The trimmed value.
 * @throws {Error} When value is undefined, null, or empty after trimming.
 */
function validateNotEmpty(value, name) {
  if (value === undefined || value === null) {
    throw new Error(
      `Parameter '${name}' is required but was not provided. ` +
      `Set the '${name}' environment variable to a non-empty value.`
    );
  }

  const trimmed = String(value).trim();

  if (trimmed === '') {
    throw new Error(
      `Parameter '${name}' cannot be an empty string. ` +
      `Set the '${name}' environment variable to a non-empty value.`
    );
  }

  return trimmed;
}

/**
 * Validate that a directory path is not empty, exists (or can be created),
 * and is accessible with read/write permissions.
 *
 * @param {string} dir - The directory path to validate.
 * @param {string} name - Parameter name used in error messages.
 * @returns {string} The validated directory path.
 * @throws {Error} When the directory cannot be accessed or created.
 */
function validateDirectory(dir, name) {
  const validated = validateNotEmpty(dir, name);

  if (!fs.existsSync(validated)) {
    try {
      fs.mkdirSync(validated, { recursive: true, mode: 0o755 });
    } catch (error) {
      throw new Error(
        `Directory '${validated}' for parameter '${name}' does not exist and could not be created: ${error.message}. ` +
        `Ensure the parent directory exists and has the correct permissions, or create '${validated}' manually.`
      );
    }
  }

  // Verify it is a directory
  try {
    const stats = fs.statSync(validated);
    if (!stats.isDirectory()) {
      throw new Error(
        `Path '${validated}' for parameter '${name}' exists but is not a directory. ` +
        `Ensure '${name}' points to a valid directory path.`
      );
    }
  } catch (error) {
    if (error.message.includes('is not a directory')) {
      throw error;
    }
    throw new Error(
      `Cannot access path '${validated}' for parameter '${name}': ${error.message}. ` +
      `Ensure the path exists and has the correct permissions.`
    );
  }

  // Test read/write access
  const testFile = path.join(validated, '.access_test');
  try {
    fs.writeFileSync(testFile, 'test');
  } catch (error) {
    throw new Error(
      `No write permission on directory '${validated}' for parameter '${name}': ${error.message}. ` +
      `Ensure the process has write access to '${validated}'.`
    );
  }

  try {
    fs.readFileSync(testFile);
  } catch (error) {
    throw new Error(
      `No read permission on directory '${validated}' for parameter '${name}': ${error.message}. ` +
      `Ensure the process has read access to '${validated}'.`
    );
  }

  try {
    fs.unlinkSync(testFile);
  } catch (_) {
    // Best effort cleanup
  }

  return validated;
}

module.exports = { validateNotEmpty, validateDirectory };
