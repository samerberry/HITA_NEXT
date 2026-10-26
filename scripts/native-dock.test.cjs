const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');
const lightModule = { exports: {} };

const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const envelopeModule = { exports: {} };
new Function('module', 'exports', ts.transpileModule(read('common/util/ImmersiveLightEffect.ets'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText)(envelopeModule, envelopeModule.exports);
new Function('require', 'module', 'exports', ts.transpileModule(read('common/util/DockLightEffect.ets'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText)(() => envelopeModule.exports, lightModule, lightModule.exports);
const handednessModule = { exports: {} };
new Function('module', 'exports', ts.transpileModule(read('common/util/DockHandedness.ets'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText)(handednessModule, handednessModule.exports);

function material(overrides = {}) {
  const uiMaterial = {
    MaterialLevel: { EXQUISITE: 'exquisite', GENTLE: 'gentle' },
    ImmersiveStyle: { ULTRA_THIN: 'ultra-thin', THIN: 'thin' },
    isImmersiveMaterialSupported: () => true,
    getGlobalMaterialLevel: () => 'exquisite',
    ImmersiveMaterial: class { constructor(options) { Object.assign(this, options); } },
    ...overrides
  };
  const mod = { exports: {} };
  const output = ts.transpileModule(read('common/theme/ImmersiveDockModifier.ets'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const platform = name => {
    if (name === '../util/DockLightEffect') return lightModule.exports;
    if (name === '../util/DockHandedness') return handednessModule.exports;
    if (name === '@kit.BasicServicesKit') return { Available: () => value => value };
    assert.equal(name, '@kit.ArkUI');
    return { uiMaterial };
  };
  new Function('require', 'module', 'exports', 'Color', output)(
    platform, mod, mod.exports, { Transparent: 'transparent', White: 'white' });
  return mod.exports.DockBarMaterial;
}

test('native dock retains fixed dimensions, safe-area margin and default mask', () => {
  const style = material().floatingStyle(36);
  assert.deepEqual(style.barWidth, { smallBarWidth: 212, mediumBarWidth: 212, largeBarWidth: 212 });
  assert.equal(style.barBottomMargin, 36);
  assert.equal(style.maskColor, '#66F1F3F5');
  assert.equal(style.maskHeight, 92);
  assert.deepEqual({ ...style.systemMaterial }, {
    style: 'ultra-thin', applyShadow: true, colorInvert: true,
    interactive: true, lightEffect: null
  });
});

test('timetable wallpaper hides only the background mask, not the dock material', () => {
  const style = material().floatingStyle(12, true);
  assert.equal(style.maskColor, 'transparent');
  assert.equal(style.maskHeight, 0);
  assert.ok(style.systemMaterial);
  const home = read('pages/Home.ets');
  assert.match(home, /new CompatibleDockModifier\(12 \+ this\.navBarInset,\s*this\.selectedNav === TAB_TIMETABLE && this\.hasTimetableBackground\(\), this\.darkMode,\s*deviceInfo\.apiAvailable\('27\.0\.0'\) \|\| this\.dockHandednessActive, this\.railMode\(\)\)/);
});

test('smart grip: the native bar follows the hand only when asked, with the shared side margin', () => {
  assert.equal(material().floatingStyle(12).adaptToHandedness, false);
  const style = material().floatingStyle(12, false, false, 0, true);
  assert.equal(style.adaptToHandedness, true);
  assert.equal(style.barSideMargin, 16);
  const { dockSideOffset } = handednessModule.exports;
  // 360 vp phone: (360 - 212) / 2 - 16 = 58 vp of travel to either side.
  assert.equal(dockSideOffset(360, 0), 0);
  assert.equal(dockSideOffset(360, -1), -58);
  assert.equal(dockSideOffset(360, 1), 58);
  // Never travel past the margin or invert on narrow or unmeasured layouts.
  assert.equal(dockSideOffset(240, 1), 0);
  assert.equal(dockSideOffset(0, -1), 0);
  assert.equal(dockSideOffset(NaN, 1), 0);
});

test('smart grip wiring: observer lifecycle, and API 26 light / API 23 dock follow the bar', () => {
  const home = read('pages/Home.ets');
  assert.match(home, /onPageShow\(\): Promise<void> \{\s*this\.pageVisible = true;\s*this\.startDockHandedness\(\);/);
  assert.match(home, /onPageHide\(\): void \{\s*this\.pageVisible = false;\s*this\.dockHandObserver\.stop\(\);/);
  assert.match(home, /aboutToDisappear\(\): void \{\s*this\.pageVisible = false;\s*this\.dockHandObserver\.stop\(\);/);
  const start = home.slice(home.indexOf('  private startDockHandedness()'), home.indexOf('  private dockOffset()'));
  // API 27+ bottom bars follow the hand natively; rails need readings only on a fully opened tri-fold.
  assert.ok(start.includes("const needed: boolean = this.railMode() ? this.foldRailDevice : !deviceInfo.apiAvailable('27.0.0');"));
  assert.match(start, /if \(!needed\) \{\s*this\.dockHandObserver\.stop\(\);/);
  assert.match(start, /this\.dockSide = 0;/, 'an unavailable sensor keeps the dock centred');
  assert.match(start, /this\.dockHandednessActive = subscribed;/);
  // The light follows the grip through the measured bar position (see dock-rail tests).
  assert.match(home, /const shift: number = [\s\S]*?this\.dockOffset\(\) : 0;/);
  assert.match(home, /FrostedDock\(\{[\s\S]*?sideOffset: this\.dockOffset\(\),/);
  const dock = read('common/components/FrostedDock.ets');
  assert.match(dock, /\.offset\(\{ x: this\.sideOffset, y: 0 \}\)/);
  assert.match(dock, /const left: number = \(this\.areaWidth - DOCK_WIDTH\) \/ 2 \+ this\.sideOffset;/);
});

test('the API 26 canvas owns light timing while later APIs can retain native white feedback', () => {
  const dock = material();
  for (const dark of [false, true]) {
    const tap = dock.floatingStyle(36, false, dark, 0).systemMaterial;
    const hold = dock.floatingStyle(36, false, dark, 1).systemMaterial;
    assert.equal(tap.lightEffect, null);
    assert.deepEqual(hold.lightEffect, { color: '#ffFFFFFF' });
    assert.deepEqual({ ...tap, lightEffect: hold.lightEffect }, { ...hold });
    const middle = dock.floatingStyle(36, false, dark, 0.675).systemMaterial.lightEffect.color;
    assert.match(middle, /^#[0-9a-f]{2}FFFFFF$/);
    assert.ok(parseInt(middle.slice(1, 3), 16) > 89 && parseInt(middle.slice(1, 3), 16) < 255);
  }
});

test('the dark dock changes only its mask color and keeps wallpaper unobscured', () => {
  const dock = material();
  const light = dock.floatingStyle(36, false, false);
  const dark = dock.floatingStyle(36, false, true);
  assert.equal(dark.maskColor, '#99101214');
  assert.deepEqual({ ...dark, maskColor: light.maskColor }, light);
  assert.equal(dock.floatingStyle(36, true, true).maskColor, 'transparent');
  assert.equal(dock.floatingStyle(36, true, true).maskHeight, 0);
});

test('dock material follows device quality and falls back when quality lookup fails', () => {
  for (const level of ['gentle', 'unknown']) {
    assert.equal(material({ getGlobalMaterialLevel: () => level }).floatingStyle(12).systemMaterial.style, 'thin');
  }
  const style = material({ getGlobalMaterialLevel: () => { throw new Error('unavailable'); } }).floatingStyle(12);
  assert.equal(style.systemMaterial.style, 'thin');
});

test('unsupported materials never prevent rendering the fallback dock', () => {
  for (const overrides of [
    { isImmersiveMaterialSupported: () => false },
    { isImmersiveMaterialSupported: () => { throw new Error('unavailable'); } },
    { ImmersiveMaterial: class { constructor() { throw new Error('unavailable'); } } }
  ]) {
    const style = material(overrides).floatingStyle(24);
    assert.equal(style.systemMaterial, undefined);
    assert.equal(style.barBottomMargin, 24);
    assert.equal(style.maskHeight, 92);
  }
});

test('one native tab bar owns only Today, Timetable and More', () => {
  const home = read('pages/Home.ets');
  const shell = home.slice(home.indexOf('  build() {'), home.indexOf('  activeSheet()'));
  assert.match(shell, /Tabs\(\{ barPosition: BarPosition\.End, controller: this\.tabsController, barModifier: this\.dockBarModifier \}\)/);
  assert.equal((shell.match(/TabContent\(\)/g) || []).length, 3);
  assert.deepEqual([...shell.matchAll(/\.tabBar\(this\.dockTab\(\$r\('[^']+'\), '([^']+)'\)\)/g)]
    .map(match => match[1]), ['今日', '时间表', '更多']);
  assert.match(home, /const NAV_TAB_COUNT: number = 3/);
  assert.doesNotMatch(home, /AssistantTab|NewsTab|assistantMounted|newsMounted|mountTabsNear/);
  assert.match(shell, /\.barOverlap\(true\)/);
  assert.match(shell, /\.barHeight\(deviceInfo\.apiAvailable\('26\.0\.0'\) && !this\.railMode\(\) \? 56 : 0\)/);
  assert.match(shell, /\.barBackgroundColor\(Color\.Transparent\)/);
  assert.match(home, /normal\.fontColor\(\[\$r\('sys\.color\.ohos_id_color_text_secondary'\)\]\)/);
  assert.match(home, /selected\.fontColor\(\[\$r\('sys\.color\.ohos_id_color_text_primary'\)\]\)/);
  assert.ok(!fs.existsSync(path.join(root, 'common/theme/DockGlass.ets')));
  assert.doesNotMatch(home, /DockGlass|pillNavigation|navDroplet|tabSwiper/);
});

test('standalone news fills the screen and keeps the final rows above the system gesture bar', () => {
  const news = read('pages/NewsPage.ets');
  const expansions = news.match(/expandSafeArea\(\[SafeAreaType\.SYSTEM\], \[SafeAreaEdge\.BOTTOM\]\)/g) || [];
  assert.ok(expansions.length >= 4);
  assert.equal((news.match(/Column\(\)\.height\(12 \+ this\.navBarInset\)/g) || []).length, 1);
  assert.match(read('pages/PortalsPage.ets'), /Column\(\)\.height\(12 \+ this\.navBarInset\)/);
  assert.doesNotMatch(news, /\.padding\(\{ left: 16, right: 16, bottom: 12 \}\)/);
});
