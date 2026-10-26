const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const root = path.resolve(__dirname, '../entry/src/main');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const DARK = 0, LIGHT = 1, SYSTEM = -1;
const MODE_KEY = 'hita_appearance_mode', DARK_KEY = 'hita_appearance_dark';

// Execute the actual appearance controller. Only HarmonyOS platform APIs are mocked.
function setup({ saved, system = LIGHT, disk = new Map(), readFailure = false } = {}) {
  if (saved !== undefined) disk.set('mode', saved);
  const storage = new Map();
  const calls = { colors: [], backgrounds: [], bars: [], warnings: [] };
  const faults = { flush: false, color: false };
  const context = { config: { colorMode: system }, getApplicationContext: () => app };
  const app = {
    setColorMode(mode) {
      if (faults.color) {
        faults.color = false;
        throw new Error('color failed');
      }
      calls.colors.push(mode);
    }
  };
  const prefs = {
    getSync: (key, fallback) => disk.has(key) ? disk.get(key) : fallback,
    put: async (key, value) => { disk.set(key, value); },
    flush: async () => {
      if (faults.flush) {
        faults.flush = false;
        throw new Error('disk full');
      }
    }
  };
  const nativeWindow = {
    setWindowBackgroundColor: async color => { calls.backgrounds.push(color); },
    setWindowSystemBarProperties: async bars => { calls.bars.push(bars); }
  };
  const modules = {
    '@kit.AbilityKit': { ConfigurationConstant: { ColorMode: {
      COLOR_MODE_DARK: DARK, COLOR_MODE_LIGHT: LIGHT, COLOR_MODE_NOT_SET: SYSTEM
    } } },
    '@kit.ArkData': { preferences: { getPreferencesSync() {
      if (readFailure) throw new Error('preferences unavailable');
      return prefs;
    } } },
    '@kit.PerformanceAnalysisKit': { hilog: { warn: (...args) => calls.warnings.push(args) } }
  };
  const compiled = ts.transpileModule(read('ets/common/theme/AppearanceStore.ets'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const mod = { exports: {} };
  new Function('require', 'module', 'exports', 'AppStorage', compiled)(
    name => { assert.ok(name in modules, name); return modules[name]; },
    mod, mod.exports, { setOrCreate: (key, value) => storage.set(key, value) });
  const store = mod.exports.AppearanceStore.getInstance();
  store.initialize(context);
  const deliver = color => {
    context.config.colorMode = color;
    store.onConfigurationUpdate(context.config);
  };
  return { store, context, storage, calls, disk, faults, nativeWindow, deliver,
    flushBars: async () => { await store.barUpdate; }, ...mod.exports };
}

test('new installations and unknown saved values follow the system without overriding it during onCreate', () => {
  for (const saved of [undefined, 'unknown', 1, true]) {
    for (const system of [DARK, LIGHT]) {
      const env = setup({ saved, system });
      assert.equal(env.storage.get(MODE_KEY), 'system');
      assert.equal(env.storage.get(DARK_KEY), system === DARK);
      assert.deepEqual(env.calls.colors, []);
      env.store.onContentReady();
      assert.deepEqual(env.calls.colors, [SYSTEM]);
    }
  }
});

test('fixed dark and light survive a cold start independently of the device theme', async () => {
  for (const [mode, color, dark] of [['dark', DARK, true], ['light', LIGHT, false]]) {
    const env = setup({ system: dark ? LIGHT : DARK });
    env.store.onContentReady();
    await env.store.select(mode);
    assert.equal(env.disk.get('mode'), mode);
    assert.equal(env.storage.get(DARK_KEY), dark);
    assert.equal(env.calls.colors.at(-1), color);
    const restarted = setup({ disk: env.disk, system: dark ? LIGHT : DARK });
    assert.equal(restarted.storage.get(MODE_KEY), mode);
    assert.equal(restarted.storage.get(DARK_KEY), dark);
    assert.deepEqual(restarted.calls.colors, []);
    restarted.store.onContentReady();
    assert.deepEqual(restarted.calls.colors, [color]);
  }
});

test('follow-system reacts to configuration changes and ignores non-color updates', () => {
  const env = setup();
  env.store.onContentReady();
  env.deliver(DARK);
  assert.equal(env.storage.get(DARK_KEY), true);
  env.store.onConfigurationUpdate({ language: 'zh' });
  assert.equal(env.storage.get(DARK_KEY), true);
  env.deliver(LIGHT);
  assert.equal(env.storage.get(DARK_KEY), false);
  assert.deepEqual(env.calls.colors, [SYSTEM]);
});

test('forced modes cannot be changed by a device configuration callback', () => {
  for (const saved of ['dark', 'light']) {
    const env = setup({ saved });
    env.store.onContentReady();
    for (const color of [DARK, LIGHT]) {
      env.deliver(color);
      assert.equal(env.storage.get(DARK_KEY), saved === 'dark');
    }
    assert.equal(env.storage.get(MODE_KEY), saved);
  }
});

test('switching back to system clears the app override, then uses the framework effective color', async () => {
  for (const [saved, systemColor] of [['dark', LIGHT], ['light', DARK]]) {
    const env = setup({ saved, system: systemColor });
    env.store.onContentReady();
    await env.store.select('system');
    assert.equal(env.calls.colors.at(-1), SYSTEM);
    assert.equal(env.storage.get(MODE_KEY), 'system');
    // An old forced application config is not the current system preference.
    env.deliver(systemColor);
    assert.equal(env.storage.get(DARK_KEY), systemColor === DARK);
    env.deliver(systemColor === DARK ? LIGHT : DARK);
    assert.equal(env.storage.get(DARK_KEY), systemColor !== DARK);
  }
});

test('failed persistence or framework update rolls back the saved preference and effective theme', async () => {
  for (const failure of ['flush', 'color']) {
    const env = setup({ saved: 'light' });
    env.store.onContentReady();
    env.faults[failure] = true;
    await assert.rejects(env.store.select('dark'), /APPEARANCE_SAVE_FAILED/);
    assert.equal(env.disk.get('mode'), 'light');
    assert.equal(env.storage.get(MODE_KEY), 'light');
    assert.equal(env.storage.get(DARK_KEY), false);
    assert.equal(env.calls.colors.at(-1), LIGHT);
    await env.store.select('dark');
    assert.equal(env.storage.get(DARK_KEY), true);
  }
});

test('early selection, unavailable preferences and concurrent writes cannot corrupt the mode', async () => {
  const env = setup();
  await assert.rejects(env.store.select('dark'), /APPEARANCE_NOT_READY/);
  env.store.onContentReady();
  const pending = env.store.select('dark');
  await assert.rejects(env.store.select('light'), /APPEARANCE_NOT_READY/);
  await pending;
  assert.equal(env.storage.get(MODE_KEY), 'dark');
  const calls = env.calls.colors.length;
  await env.store.select('dark');
  assert.equal(env.calls.colors.length, calls);
  const unavailable = setup({ readFailure: true, system: DARK });
  unavailable.store.onContentReady();
  assert.equal(unavailable.storage.get(DARK_KEY), true);
  await assert.rejects(unavailable.store.select('light'), /APPEARANCE_NOT_READY/);
});

test('system bars follow the effective theme and preserve transparent insets', async () => {
  const env = setup();
  env.store.attachWindow(env.nativeWindow);
  env.store.onContentReady();
  await env.flushBars();
  assert.equal(env.calls.backgrounds.at(-1), '#F5F6F8');
  assert.equal(env.calls.bars.at(-1).statusBarContentColor, '#14213D');
  await env.store.select('dark');
  await env.flushBars();
  assert.equal(env.calls.backgrounds.at(-1), '#101214');
  assert.deepEqual(env.calls.bars.at(-1), {
    statusBarColor: '#00000000', statusBarContentColor: '#ECEFF4',
    navigationBarColor: '#00000000', navigationBarContentColor: '#BCC3CF'
  });
  env.store.detachWindow();
  const count = env.calls.bars.length;
  env.deliver(LIGHT);
  await env.flushBars();
  assert.equal(env.calls.bars.length, count);
});

test('wallpaper can adapt system-bar text without changing app appearance and restore it when leaving', async () => {
  const env = setup();
  env.store.attachWindow(env.nativeWindow); env.store.onContentReady();
  env.store.setPageBarColors('#FFFFFF', '#FFFFFF');
  await env.flushBars();
  assert.equal(env.calls.bars.at(-1).statusBarContentColor, '#FFFFFF');
  assert.equal(env.calls.backgrounds.at(-1), '#F5F6F8');
  const count = env.calls.bars.length;
  env.store.setPageBarColors('#FFFFFF', '#FFFFFF');
  await env.flushBars();
  assert.equal(env.calls.bars.length, count);
  // A light bottom sheet needs its normal navigation indicator, while the dark wallpaper remains above it.
  env.store.setPageBarColors('#FFFFFF', '');
  await env.flushBars();
  assert.equal(env.calls.bars.at(-1).navigationBarContentColor, '#4E5C72');
  await env.store.select('dark');
  env.store.setPageBarColors('#333333', '#333333');
  await env.flushBars();
  assert.equal(env.calls.bars.at(-1).statusBarContentColor, '#333333');
  env.store.setPageBarColors();
  await env.flushBars();
  assert.equal(env.calls.bars.at(-1).statusBarContentColor, '#ECEFF4');
  assert.equal(env.calls.bars.at(-1).navigationBarContentColor, '#BCC3CF');
});

function colors(qualifier) {
  return JSON.parse(read(`resources/${qualifier}/element/color.json`)).color;
}

function contrast(a, b) {
  const luminance = hex => {
    const channels = hex.slice(1).match(/../g).map(v => parseInt(v, 16) / 255)
      .map(v => v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4);
    return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722;
  };
  const x = luminance(a), y = luminance(b);
  return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05);
}

test('every color resource has a dark counterpart, without duplicate names or missing references', () => {
  const light = colors('base'), dark = colors('dark');
  const names = new Set(light.map(c => c.name));
  assert.equal(names.size, light.length);
  assert.equal(new Set(dark.map(c => c.name)).size, dark.length);
  assert.deepEqual([...names].sort(), dark.map(c => c.name).sort());
  const files = fs.readdirSync(path.join(root, 'ets'), { recursive: true })
    .filter(file => file.endsWith('.ets'));
  for (const file of files) {
    for (const match of read(`ets/${file}`).matchAll(/\$r\('app\.color\.([^']+)'\)/g)) {
      assert.ok(names.has(match[1]), `${file}: ${match[1]}`);
    }
  }
});

test('dark text, selected controls and filled actions retain readable contrast', () => {
  const dark = Object.fromEntries(colors('dark').map(c => [c.name, c.value]));
  for (const foreground of ['hita_text', 'hita_text_secondary', 'hita_text_hint', 'hita_primary']) {
    for (const background of ['hita_page', 'hita_surface', 'hita_control', 'hita_selected']) {
      assert.ok(contrast(dark[foreground], dark[background]) >= 4.5, `${foreground} on ${background}`);
    }
  }
  for (const fill of ['hita_primary_fill', 'hita_error_fill', 'hita_hero_chip']) {
    assert.ok(contrast('#FFFFFF', dark[fill]) >= 4.5, fill);
  }
});

test('settings expose exactly three choices and timetable redraw is bound to the appearance state', () => {
  const home = read('ets/pages/Home.ets');
  assert.deepEqual([...home.matchAll(/this\.appearanceOption\(AppearanceMode\.(\w+), '([^']+)'\)/g)]
    .map(m => [m[1], m[2]]), [['DARK', '开启'], ['LIGHT', '关闭'], ['SYSTEM', '跟随系统']]);
  const settings = home.slice(home.indexOf("this.moreSectionTitle('设置')"));
  assert.match(settings, /this\.appearanceSettings\(\)/);
  assert.match(home, /@StorageProp\('hita_appearance_dark'\) @Watch\('onAppearanceChanged'\)/);
  assert.match(home, /private onAppearanceChanged\(\): void \{\s*this\.drawTimetableNow\(\)/);
  assert.doesNotMatch(home, /\.fontColor\(this\.timetableTextColor\)/);
  const ability = read('ets/entryability/EntryAbility.ets');
  assert.match(ability, /onConfigurationUpdate\(config: Configuration\)/);
  assert.match(ability, /loadContent\('pages\/Home',[\s\S]*AppearanceStore\.getInstance\(\)\.onContentReady\(\)/);
});

test('appearance matches surrounding settings rows and reveals choices only when expanded', () => {
  const home = read('ets/pages/Home.ets');
  assert.match(home, /@State appearanceExpanded: boolean = false/);
  const setting = home.slice(home.indexOf('  appearanceSettings() {'), home.indexOf('  appearanceOption('));
  assert.match(setting, /SymbolGlyph\(\$r\('sys\.symbol\.moon'\)\)/);
  assert.match(setting, /this\.appearanceMode === AppearanceMode\.DARK \? '已开启'/);
  assert.match(setting, /this\.appearanceMode === AppearanceMode\.LIGHT \? '已关闭' : '跟随系统'/);
  assert.match(setting, /animateTo\(\{ duration: 300, curve: Curve\.EaseInOut \}/);
  assert.match(setting, /this\.appearanceExpanded = !this\.appearanceExpanded/);
  assert.match(setting, /if \(this\.appearanceExpanded\) \{\s*Column\(\) \{\s*ImmersiveHeader\(\{ barHeight: 60, materialEnabled: CompatibleSheetMaterial\.isEnabled\(\) \}\) \{\s*Row[\s\S]*this\.appearanceOption\(AppearanceMode\.SYSTEM/);
  assert.match(setting, /\.padding\(\{ left: 16, right: 16, top: 4, bottom: 12 \}\)/);
  // 展开动画与其他折叠面板一致：外层普通 Column 承载 OPACITY 过渡，材质头部在其内部。
  assert.match(setting, /\.transition\(TransitionEffect\.OPACITY\)/);
  assert.doesNotMatch(setting, /this\.selectAppearance|AppearanceStore/);
  assert.match(setting, /\.rotate\(\{ angle: this\.appearanceExpanded \? 90 : 0 \}\)/);
  assert.match(setting, /\.accessibilityDescription\(this\.appearanceExpanded \? '已展开' : '已收起'\)/);
  // Bind state inside the builder: value parameters freeze labels and arrow rotation.
  assert.doesNotMatch(setting, /this\.moreNavigationRow\(/);
  const row = home.slice(home.indexOf('  moreNavigationRow('));
  for (const style of ['.width(40)', '.height(40)', '.borderRadius(20)', '.fontSize(HitaDesign.title)',
    '.fontSize(HitaDesign.body)', '.fontSize(HitaDesign.label)', '.constraintSize({ minHeight: HitaDesign.rowMinHeight })', '.padding({ left: 16, right: 16 })',
    '.margin({ left: 12 })', '.backgroundColor(COLOR_NAV_ACTIVE)']) {
    assert.ok(row.includes(style), `Reference row: ${style}`);
    assert.ok(setting.includes(style), `Appearance row: ${style}`);
  }
  const choices = home.slice(home.indexOf('  appearanceOption('), home.indexOf('  userCard()'));
  assert.match(choices, /Radio\(\{ value: mode, group: 'appearance_mode' \}\)/);
  assert.match(choices, /\.width\(0\)\s*\.layoutWeight\(1\)/);
  assert.doesNotMatch(choices, /\.layoutWeight\(mode/);
  assert.doesNotMatch(choices, /appearanceExpanded/);
});

test('browser appearance follows the app, while authentication avoids forced captcha recoloring', () => {
  for (const file of ['ets/pages/WebBrowserPage.ets', 'ets/feature/eas/webLogin/EasLoginPage.ets']) {
    const source = read(file);
    assert.match(source, /@StorageProp\('hita_appearance_dark'\)/);
    assert.match(source, /\.darkMode\(this\.darkMode \? WebDarkMode\.On : WebDarkMode\.Off\)/);
  }
  assert.match(read('ets/feature/eas/webLogin/EasLoginPage.ets'), /\.forceDarkAccess\(false\)/);
});
