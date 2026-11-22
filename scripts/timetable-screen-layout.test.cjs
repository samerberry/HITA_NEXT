const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const source = fs.readFileSync(path.resolve(__dirname,
  '../entry/src/main/ets/feature/timetable/views/TimetableScreenLayout.ets'), 'utf8');
const js = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText;

function fixture() {
  const panel = { width: 1264, height: 1848, densityPixels: 2.75 };
  const display = { foldable: true, mode: 2, FoldDisplayMode: { FOLD_DISPLAY_MODE_MAIN: 2, FOLD_DISPLAY_MODE_SUB: 3 },
    isFoldable: () => display.foldable, getFoldDisplayMode: () => display.mode, getDefaultDisplaySync: () => panel };
  const deviceInfo = { deviceType: 'phone' };
  const exports = {};
  new Function('require', 'exports', js)(name => name === '@kit.ArkUI' ? { display } : { deviceInfo }, exports);
  return { panel, display, deviceInfo, active: exports.usesPhoneTimetable };
}

test('the device family wins over screen size for slab phones and tablets', () => {
  const { panel, display, deviceInfo, active } = fixture();
  display.foldable = false;
  Object.assign(panel, { width: 2400, height: 1800 });
  assert.equal(active(), true, 'even a wide or rotated slab phone uses readable hours');
  deviceInfo.deviceType = 'tablet';
  assert.equal(active(), false);
  display.foldable = true;
  assert.equal(active(), false, 'even a foldable tablet keeps all hours in view');
});

test('switching the active panel selects the same layout in either orientation', () => {
  const { panel, display, active } = fixture();
  for (const [label, mode, short, long, density, readable] of [
    ['tri-fold, one panel', 2, 1008, 2232, 2.875, true],
    ['tri-fold, two panels', 1, 2048, 2232, 2.875, false],
    ['tri-fold, three panels', 5, 2232, 3184, 2.875, false],
    ['book fold cover', 2, 1080, 2496, 3, true],
    ['book fold inside', 1, 1960, 2240, 3, false],
    ['wide fold cover', 2, 1264, 1848, 2.75, true],
    ['wide fold inside', 1, 1828, 2584, 2.75, false],
    ['flip inside', 2, 1080, 2520, 3, true],
    ['small wide fold inside in full mode', 1, 1320, 2120, 3, true],
    ['flip cover', 3, 480, 480, 2, true],
  ]) {
    display.mode = mode;
    for (const [width, height] of [[short, long], [long, short]]) {
      Object.assign(panel, { width, height, densityPixels: density });
      assert.equal(active(), readable, label);
    }
  }
});
