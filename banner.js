'use strict';

const path = require('path');

/**
 * Prints the daas ASCII logo banner with colored output.
 * Uses figlet graffiti font for "daas" with lolcat-style rainbow colors.
 */
function printBanner() {
  const pkg = require(path.join(__dirname, 'package.json'));
  const version = `v${pkg.version}`;
  const product = 'mkcert-controller';
  const company = 'consulting';
  const brand = 'daas';

  // Figlet "daas" in graffiti font (pre-generated)
  const artLines = [
    '       .___                     ',
    '     __| _/____  _____    ______',
    '    / __ |\\__  \\ \\__  \\  /  ___/',
    '   / /_/ | / __ \\_/ __ \\_\\___ \\ ',
    '   \\____ |(____  (____  /____  >',
    '        \\/     \\/     \\/     \\/ ',
  ];

  // Determine total width based on the longest art line + padding
  const totalWidth = 34;

  // Pad art lines to totalWidth with trailing spaces and add left padding
  const paddedArt = artLines.map((line) => {
    if (line.length < totalWidth) {
      return line + ' '.repeat(totalWidth - line.length);
    }
    return line;
  });

  // Build top bar: " daas" left, "mkcert-controller " right
  const topLeft = ` ${brand}`;
  const topRight = `${product} `;
  const topPad = totalWidth - topLeft.length - topRight.length;
  const topBar = topLeft + ' '.repeat(Math.max(topPad, 1)) + topRight;

  // Build bottom bar: " mkcert-controller" left, "consulting " right
  const botLeft = ` ${product}`;
  const botRight = `${company} `;
  const botPad = totalWidth - botLeft.length - botRight.length;
  const botBar = botLeft + ' '.repeat(Math.max(botPad, 1)) + botRight;

  // Build version bar: version right-aligned with trailing space
  const verRight = `${version} `;
  const verBar = ' '.repeat(totalWidth - verRight.length) + verRight;

  // ANSI color codes
  const RESET = '\x1b[0m';
  const BLUE_BG_WHITE = '\x1b[44;37m'; // Blue background, white text
  const PURPLE_BG_WHITE = '\x1b[45;37m'; // Purple/magenta background, white text

  // Lolcat-style rainbow color palette (256-color)
  const rainbowColors = [118, 154, 148, 184, 178, 214, 208, 209, 203];

  /**
   * Apply lolcat-style rainbow coloring to a line of text.
   * Colors shift across characters, creating a gradient effect.
   */
  function colorizeArtLine(line, lineIndex) {
    let result = '';
    for (let i = 0; i < line.length; i++) {
      const colorIdx = Math.floor(
        ((i + lineIndex * 2) / line.length) * rainbowColors.length
      );
      const color =
        rainbowColors[Math.min(colorIdx, rainbowColors.length - 1)];
      result += `\x1b[38;5;${color}m${line[i]}\x1b[39m`;
    }
    return result;
  }

  // Print the banner
  const output = [];

  // Top bar (blue background, white text)
  output.push(`${BLUE_BG_WHITE}${topBar}${RESET}`);

  // Colored figlet art
  paddedArt.forEach((line, idx) => {
    output.push(colorizeArtLine(line, idx));
  });

  // Bottom bar (blue background, white text)
  output.push(`${BLUE_BG_WHITE}${botBar}${RESET}`);

  // Version bar (purple background, white text)
  output.push(`${PURPLE_BG_WHITE}${verBar}${RESET}`);

  // Empty line after banner
  output.push('');

  console.log(output.join('\n'));
}

module.exports = { printBanner };
