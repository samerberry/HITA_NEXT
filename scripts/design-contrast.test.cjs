const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

function luminance(hex) {
  const rgb = hex.slice(1).match(/../g).map(v => parseInt(v, 16) / 255)
    .map(v => v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4);
  return rgb[0] * 0.2126 + rgb[1] * 0.7152 + rgb[2] * 0.0722;
}

function contrast(a, b) {
  const values = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (values[0] + 0.05) / (values[1] + 0.05);
}

for (const mode of ['base', 'dark']) {
  const file = path.join(__dirname, '../entry/src/main/resources', mode, 'element/color.json');
  const colors = Object.fromEntries(JSON.parse(fs.readFileSync(file, 'utf8')).color.map(c => [c.name, c.value]));
  test(`${mode}: normal text and primary actions remain readable on their surfaces`, () => {
    for (const background of ['hita_surface', 'hita_page', 'hita_surface_soft', 'hita_selected']) {
      for (const foreground of ['hita_text', 'hita_text_secondary', 'hita_primary']) {
        const ratio = contrast(colors[foreground], colors[background]);
        assert.ok(ratio >= 4.5, `${foreground} on ${background}: ${ratio.toFixed(2)}`);
      }
    }
    for (const fill of ['hita_primary_fill', 'hita_error_fill']) {
      assert.ok(contrast('#FFFFFF', colors[fill]) >= 4.5, `white on ${fill}`);
    }
  });
}
