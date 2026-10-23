const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const compile = source => ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText;

function compatible(api) {
  const calls = [];
  const material = {};
  Object.defineProperty(material, 'HeaderMaterial', { get() {
    assert.ok(api >= 26, 'old devices must not evaluate the API 26 module');
    return { apply: (...args) => calls.push(args) };
  } });
  const mod = { exports: {} };
  const source = read('common/theme/CompatibleMaterialModifier.ets');
  assert.match(source, /import lazy \{ HeaderMaterial \}/);
  new Function('require', 'module', 'exports', '$r', compile(source.replace('import lazy ', 'import ')))(
    name => name === '@kit.BasicServicesKit' ? { deviceInfo: { apiAvailable: version => {
      assert.equal(version, '26.0.0');
      return api >= 26;
    } } } : material, mod, mod.exports, name => name);
  return { Modifier: mod.exports.CompatibleMaterialModifier, calls };
}

test('API 23-25 leave every legacy surface and foreground unchanged without touching new APIs', () => {
  for (const api of [23, 24, 25]) {
    const { Modifier, calls } = compatible(api);
    const instance = new Proxy({}, { get() { throw new Error('legacy UI must not be modified'); } });
    for (const color of ['blue', 'transparent', { id: 123 }]) {
      new Modifier(color).applyNormalAttribute(instance);
      new Modifier(color, true).applyNormalAttribute(instance);
      assert.equal(Modifier.foreground(color), color);
    }
    assert.deepEqual(calls, []);
  }
});

test('API 26 and newer apply material to the actual UI node and use invertible foreground resources', () => {
  for (const api of [26, 27]) {
    const { Modifier, calls } = compatible(api);
    const instance = {};
    new Modifier('blue', true).applyNormalAttribute(instance);
    new Modifier('control').applyNormalAttribute(instance);
    assert.deepEqual(calls, [[instance, 'blue', true, undefined, undefined],
      [instance, 'control', false, undefined, undefined]]);
    assert.equal(Modifier.foreground('blue'), 'sys.color.ohos_id_color_text_primary');
  }
});

test('course tints reach the native material only on supported API levels', () => {
  for (const api of [23, 24, 25, 26, 27]) {
    const { Modifier, calls } = compatible(api);
    const instance = {};
    const base = 0xFF346541;
    const tint = 0xE6346541;
    new Modifier(base, true, true, tint).applyNormalAttribute(instance);
    assert.deepEqual(calls, api >= 26 ? [[instance, base, true, tint, undefined]] : []);
  }
});

test('disabled control modifiers leave the node untouched even on API 26 and newer', () => {
  for (const api of [23, 26, 27]) {
    const { Modifier, calls } = compatible(api);
    const instance = new Proxy({}, { get() { assert.fail('disabled material must not modify attributes'); } });
    new Modifier('legacy', false, false).applyNormalAttribute(instance);
    assert.deepEqual(calls, []);
  }
});

function nativeMaterial(overrides = {}) {
  const uiMaterial = {
    isImmersiveMaterialSupported: () => true,
    getGlobalMaterialLevel: () => 'exquisite',
    MaterialLevel: { EXQUISITE: 'exquisite' },
    ImmersiveStyle: { ULTRA_THIN: 'ultra-thin', THIN: 'thin', REGULAR: 'regular' },
    ImmersiveMaterial: class { constructor(options) { Object.assign(this, options); } },
    ...overrides
  };
  const mod = { exports: {} };
  new Function('require', 'module', 'exports', 'Color', '$r',
    compile(read('common/theme/ImmersiveHeaderMaterial.ets')))(
    name => {
      if (name === '@kit.BasicServicesKit') return { Available: () => value => value,
        deviceInfo: { apiAvailable: version => (overrides.api ?? 26) >= Number(version.split('.')[0]) } };
      if (name.includes('CompatibleLightModifier')) return {
        CompatibleLightModifier: class { applyNormalAttribute() {} }
      };
      return { uiMaterial };
    },
    mod, mod.exports, { White: 'white', Transparent: 'transparent' }, name => name);
  return mod.exports.HeaderMaterial;
}

test('native controls enable light feedback, elastic interaction and adaptive thin material', () => {
  for (const [level, style] of [['exquisite', 'ultra-thin'], ['gentle', 'thin'], ['smooth', 'thin']]) {
    const calls = [];
    nativeMaterial({ getGlobalMaterialLevel: () => level }).apply({
      systemMaterial: value => calls.push(['material', { ...value }]),
      backgroundColor: value => calls.push(['background', value])
    }, 'legacy', false);
    assert.deepEqual(calls, [
      ['background', 'transparent'],
      ['material', { style, materialColor: 'transparent', colorInvert: true,
        applyShadow: false, interactive: true, lightEffect: null }]
    ]);
  }
});

test('the Today surface keeps a translucent blue tint and stable white text', () => {
  let options;
  nativeMaterial().apply({ systemMaterial: value => { options = value; }, backgroundColor() {} }, 'blue', true);
  assert.equal(options.style, 'regular');
  assert.equal(options.materialColor, 'app.color.hita_immersive_hero_tint');
  assert.equal(options.colorInvert, false);
  assert.equal(options.applyShadow, true);
  assert.equal(options.interactive, true);
  for (const theme of ['base', 'dark']) {
    const colors = JSON.parse(read(`../resources/${theme}/element/color.json`)).color;
    const tint = colors.find(color => color.name === 'hita_immersive_hero_tint').value;
    assert.match(tint, /^#[0-9A-F]{8}$/);
    const alpha = parseInt(tint.slice(1, 3), 16);
    assert.ok(alpha > 0 && alpha < 255, 'an opaque tint hides the native material');
  }
});

test('timetable materials keep each course hue without enabling background color inversion', () => {
  for (const tint of [0xE62F56B0, 0xE6437654, 0xE68A2E42, 0xE68346A0]) {
    const material = nativeMaterial().create(true, tint);
    assert.equal(material.style, 'regular');
    assert.equal(material.materialColor, tint);
    assert.equal(material.colorInvert, false);
    assert.equal(material.interactive, true);
    assert.equal(material.lightEffect, null);
  }
  let fill = 0xFF8346A0;
  nativeMaterial({ isImmersiveMaterialSupported: () => false }).apply({
    systemMaterial() { assert.fail('unavailable materials must keep the course fill'); },
    backgroundColor: value => { fill = value; }
  }, fill, true, 0xE68346A0);
  assert.equal(fill, 0xFF8346A0);
  nativeMaterial().apply({
    systemMaterial() { throw new Error('native failure'); },
    backgroundColor: value => { fill = value; }
  }, 0xFF8346A0, true, 0xE68346A0);
  assert.equal(fill, 0xFF8346A0);
});

test('compact colored actions can turn off native shadows without changing other colored cards', () => {
  const { Modifier, calls } = compatible(26);
  const instance = {};
  new Modifier('#E84040', true, true, '#EBE84040', false).applyNormalAttribute(instance);
  assert.deepEqual(calls, [[instance, '#E84040', true, '#EBE84040', false]]);
  const red = nativeMaterial().create(true, '#EBE84040', false);
  assert.equal(red.materialColor, '#EBE84040');
  assert.equal(red.applyShadow, false);
  assert.equal(red.interactive, true);
  assert.equal(red.colorInvert, false);
  assert.equal(nativeMaterial().create(true).applyShadow, true);
  assert.equal(nativeMaterial().create(false).applyShadow, false);
});

test('unsupported devices and native failures preserve a usable legacy fill', () => {
  for (const overrides of [
    { isImmersiveMaterialSupported: () => false },
    { isImmersiveMaterialSupported: () => { throw new Error('unavailable'); } },
    { ImmersiveMaterial: class { constructor() { throw new Error('unavailable'); } } }
  ]) {
    let fill = 'legacy';
    nativeMaterial(overrides).apply({
      systemMaterial() { assert.fail('must not apply an unavailable material'); },
      backgroundColor: value => { fill = value; }
    }, 'legacy', false);
    assert.equal(fill, 'legacy');
  }
  let fill = 'legacy';
  nativeMaterial().apply({ systemMaterial() { throw new Error('native failure'); },
    backgroundColor: value => { fill = value; } }, 'legacy', false);
  assert.equal(fill, 'legacy');
  let style;
  nativeMaterial({ getGlobalMaterialLevel() { throw new Error('unknown level'); } }).apply({
    systemMaterial: value => { style = value.style; }, backgroundColor() {}
  }, 'legacy', false);
  assert.equal(style, 'thin');
});

test('native segmented controls reuse the shadow-free material and safely omit unsupported material', () => {
  const material = nativeMaterial().create();
  assert.equal(material.style, 'ultra-thin');
  assert.equal(material.applyShadow, false);
  assert.equal(material.interactive, true);
  assert.equal(material.lightEffect, null);
  assert.equal(material.colorInvert, true);
  assert.equal(nativeMaterial({ isImmersiveMaterialSupported: () => false }).create(), undefined);
  assert.equal(nativeMaterial({ isImmersiveMaterialSupported() { throw Error('unavailable'); } }).create(), undefined);
});

test('later APIs retain the original native white light instead of the API 26 animation layer', () => {
  for (const api of [27, 28]) {
    assert.deepEqual(nativeMaterial({ api }).create().lightEffect, { color: 'white' });
  }
});

test('title hosts only instantiate Navigation on API 26 and retain the original builder on API 23-25', () => {
  const source = read('common/components/ImmersiveHeader.ets')
    .replace('@Component', '')
    .replace('export struct', 'export class')
    .replace(/@(Prop|BuilderParam) /g, '')
    .replace('Navigation() {}', 'Navigation()');
  for (const [api, enabled] of [[23, true], [24, true], [25, true], [26, true], [27, true],
    [23, false], [26, false], [27, false]]) {
    let title;
    let renders = 0;
    const calls = [];
    const native = new Proxy({}, { get: (_, name) => (...args) => {
      calls.push([name, ...args]);
      if (name === 'title') title = args[0];
      return native;
    } });
    const mod = { exports: {} };
    new Function('require', 'module', 'exports', 'Navigation', 'NavigationMode', 'Color', 'HitTestMode',
      compile(source))(() => ({ deviceInfo: { apiAvailable: () => api >= 26 } }),
      mod, mod.exports, () => { assert.ok(api >= 26); return native; },
      { Stack: 'stack' }, { Transparent: 'transparent' }, { Transparent: 'transparent' });
    const header = new mod.exports.ImmersiveHeader();
    header.barHeight = 64;
    header.materialEnabled = enabled;
    header.content = () => { renders++; };
    header.build();
    if (api < 26 || !enabled) {
      assert.equal(renders, 1);
      assert.deepEqual(calls, []);
    } else {
      assert.equal(title.height, 64);
      title.builder();
      assert.equal(renders, 1);
      assert.ok(calls.some(call => call[0] === 'hideBackButton' && call[1] === true));
      assert.ok(calls.some(call => call[0] === 'ignoreLayoutSafeArea' && call[1].length === 0));
    }
  }
});

test('every shared back button is hosted in a supported native title region', () => {
  const files = fs.readdirSync(path.join(root, 'pages')).map(file => `pages/${file}`)
    .concat('feature/eas/webLogin/EasLoginPage.ets');
  for (const file of files) {
    const source = read(file);
    const backs = (source.match(/HeaderBackButton\(\{/g) || []).length;
    if (!backs) continue;
    if (file === 'pages/NewsPage.ets') {
      assert.match(source, /header: \(\) => \{ this\.headerContent\(\); \}/);
      assert.match(source, /headerContent\(\) \{\s*Row\(\) \{\s*HeaderBackButton/);
      continue;
    }
    const hosted = (source.match(/ImmersiveHeader\(\{[^}]{0,400}\}\) \{\s*Row\([^\n]*\) \{\s*HeaderBackButton\(\{/g) || []).length;
    assert.equal(hosted, backs, file);
  }
  assert.match(read('common/components/HeaderBackButton.ets'), /attributeModifier\(new CompatibleMaterialModifier/);
});

test('news floats its original full-width dock without extending the title blur mask below it on API 26', () => {
  const page = read('pages/NewsPage.ets');
  assert.match(page, /import lazy \{ ImmersiveNewsLayout \}/);
  assert.match(page, /import lazy \{ ImmersiveNewsTabs \}/);
  assert.match(page, /if \(deviceInfo\.apiAvailable\('26\.0\.0'\)\) \{\s*ImmersiveNewsLayout/);
  assert.match(page, /else \{\s*this\.headerContent\(\);\s*this\.dockContent\(\);\s*this\.newsList\(\);/);
  const dock = page.slice(page.indexOf('  dockContent()'), page.indexOf('  segment('));
  assert.match(dock, /\.width\('100%'\)/);
  assert.match(dock, /padding\(\{ left: 16, right: 16, bottom: 8 \}\)/);
  assert.doesNotMatch(dock, /252|HeaderFadeMask/);
  assert.match(dock, /if \(deviceInfo\.apiAvailable\('26\.0\.0'\)\) \{\s*ImmersiveNewsTabs/);
  assert.match(dock, /selectedIndex: this\.selected/);
  assert.match(dock, /onSelect: \(index: number\) => \{ this\.selectTab\(index\); \}/);
  assert.match(dock, /else \{\s*Row\(\{ space: 4 \}\)/);
  assert.match(page, /titleHeight: 60 \+ this\.statusBarInset/);
  assert.match(page, /dock: \(\) => \{ this\.dockContent\(\); \}/);
  assert.match(page, /ListItem\(\) \{\s*Column\(\)\.height\(112 \+ this\.statusBarInset\)/);
  assert.match(page, /if \(!deviceInfo\.apiAvailable\('26\.0\.0'\)\) \{\s*HeaderFadeMask/);
  const layout = read('common/components/ImmersiveNewsLayout.ets');
  assert.match(layout, /Stack\(\{ alignContent: Alignment\.Top \}\)/);
  assert.match(layout, /Column\(\) \{\s*this\.content\(\)/);
  assert.match(layout, /linearGradientBlur\(20/);
  assert.match(layout, /direction: GradientDirection\.Bottom/);
  assert.match(layout, /ImmersiveHeader\(\{ barHeight: this\.titleHeight \}\) \{\s*this\.header\(\)/);
  assert.match(layout, /ImmersiveHeader\(\{ barHeight: 52 \}\) \{\s*this\.dock\(\)/);
  assert.match(layout, /margin\(\{ top: this\.titleHeight \}\)/);
  assert.match(layout, /\.height\(52\)\s*\.hitTestBehavior\(HitTestMode\.Transparent\)/);
  assert.doesNotMatch(layout, /HeaderFadeMask|linearGradient\(|scrollEffectOptions/);
});

test('news blur eases across the last 52vp of the heading and ends before the dock at every viewport height', () => {
  const source = read('common/components/ImmersiveNewsLayout.ets');
  const method = source.slice(source.indexOf('  private blurStops()'), source.indexOf('  build()'));
  const mod = { exports: {} };
  new Function('module', 'exports', compile('export class Layout {' + method + '}'))(mod, mod.exports);
  for (const height of [320, 700, 800, 1200]) {
    for (const inset of [0, 24, 39, 64]) {
      const layout = new mod.exports.Layout();
      layout.contentHeight = height;
      layout.titleHeight = 60 + inset;
      const stops = layout.blurStops();
      assert.deepEqual(stops.map(stop => stop[0]), [1, 1, 0.84375, 0.5, 0.15625, 0, 0]);
      for (let i = 0; i <= 4; i++) {
        assert.ok(Math.abs(stops[i + 1][1] * height - (layout.titleHeight - 52 + i * 13)) < 0.0001);
      }
      const slopes = stops.slice(1, 5).map((stop, i) =>
        (stop[0] - stops[i + 2][0]) / ((stops[i + 2][1] - stop[1]) * height));
      assert.ok(slopes[0] < slopes[1] && slopes[3] < slopes[2], 'ease both ends into the unblurred and blurred regions');
      assert.ok(stops.every((stop, i) => stop[1] >= 0 && stop[1] <= 1 &&
        (i === 0 || (stop[1] >= stops[i - 1][1] && stop[0] <= stops[i - 1][0]))));
    }
  }
});

test('manager export material is on a fixed circle button, not on the glyph bounds', () => {
  const page = read('pages/TimetableManagerPage.ets');
  assert.match(page, /else if \(deviceInfo\.apiAvailable\('26\.0\.0'\)\) \{\s*Button/);
  assert.match(page, /Button\(\{ type: ButtonType\.Circle \}\) \{\s*SymbolGlyph\(\$r\('sys\.symbol\.doc_plaintext'\)\)[^}]+?;\s*\}\s*\.width\(44\)\s*\.height\(44\)\s*\.padding\(0\)/);
  assert.match(page, /else \{\s*SymbolGlyph\(\$r\('sys\.symbol\.doc_plaintext'\)\)\s*\.fontSize\(20\)\s*\.fontColor\(\[HitaColors\.primary\]\)\s*\.width\(44\)\s*\.height\(44\)/);
});

test('timetable manager actions and campus selector receive the shadow-free control material', () => {
  const manager = read('pages/TimetableManagerPage.ets');
  const header = manager.slice(manager.indexOf('ImmersiveHeader({ barHeight: HEADER_HEIGHT })'));
  assert.equal((header.match(/new CompatibleMaterialModifier\(Color\.Transparent\)/g) || []).length, 2);
  assert.match(header, /fontColor\(HitaColors\.error\)/);
  assert.match(header, /this\.confirmDelete\(\)/);
  assert.match(header, /this\.showExportMenu\(\)/);
  const home = read('pages/Home.ets');
  const campus = home.slice(home.indexOf('ImmersiveHeader({ barHeight: 57 })'));
  assert.match(campus, /sessionCampusButton\('SHENZHEN'[\s\S]*sessionCampusButton\('BENBU'[\s\S]*sessionCampusButton\('WEIHAI'/);
  assert.match(campus, /new CompatibleMaterialModifier\(\$r\('app\.color\.hita_control_eaf0f7'\)\)/);
});

test('news uses the native tab segment for drag selection, with 4vp insets and no selection shadow', () => {
  const source = read('common/components/ImmersiveNewsTabs.ets')
    .replace('@Component', '').replace('export struct', 'export class')
    .replace(/@Prop /g, '');
  const categories = [{ id: 'blog', name: 'Blog' }, { id: '10', name: 'Notices' }];
  for (const material of [undefined, { immersive: true }]) {
    let options;
    let width;
    const mod = { exports: {} };
    new Function('require', 'module', 'exports', '$r', 'Color', 'FontWeight',
      compile(source))(name => {
      if (name === '@kit.ArkUI') return {
        ColorMetrics: { resourceColor: color => color },
        LengthMetrics: { vp: value => value, fp: value => value },
        SegmentButtonV2Items: class { constructor(items) { return items; } },
        TabSegmentButtonV2: config => {
          options = config;
          return { width(value) { width = value; return this; }, attributeModifier() {} };
        }
      };
      if (name === '@kit.BasicServicesKit') return { Available: () => value => value };
      if (name.includes('ImmersiveHeaderMaterial')) return { HeaderMaterial: { create: () => material } };
      if (name.includes('CompatibleLightModifier')) return { CompatibleLightModifier: class {} };
      if (name.includes('NewsService')) return { NewsService: { CATEGORIES: categories } };
      throw Error('Unexpected import ' + name);
    }, mod, mod.exports, name => name, { Transparent: 'transparent' },
    { Regular: 'regular', Medium: 'medium' });
    const tabs = new mod.exports.ImmersiveNewsTabs();
    const selections = [];
    tabs.onSelect = index => { selections.push(index); };
    for (const selected of [0, 1, 0]) {
      tabs.selectedIndex = selected;
      tabs.build();
      assert.equal(options.selectedIndex, selected);
      assert.equal(options.buttonPadding, 4);
      assert.equal(options.buttonMinHeight, options.itemMinHeight + 8);
      assert.equal(options.itemSpace, 0);
      assert.deepEqual(options.itemShadow, { radius: 0, color: 'transparent', offsetX: 0, offsetY: 0 });
      assert.equal(options.enableStateAnimation, true);
      assert.equal(options.backgroundSystemMaterial, material);
      assert.equal(options.buttonBackgroundColor, material ? 'transparent' : 'app.color.hita_control_eaf0f7');
      assert.equal(options.itemSelectedBackgroundColor, 'app.color.hita_immersive_segment_selected');
      assert.equal(options.onItemClicked, undefined, 'selection changes should not trigger duplicate reloads');
      assert.deepEqual(options.items.map(item => item.text), categories.map(category => category.name));
      assert.ok(options.items.every(item => item.accessibilityText === item.text));
      assert.equal(width, '100%');
      options.$selectedIndex(1 - selected);
    }
    assert.deepEqual(selections, [1, 0, 1]);
  }
});

test('news immersive selection stays below 20 percent opacity in both themes', () => {
  for (const theme of ['base', 'dark']) {
    const colors = JSON.parse(read('../resources/' + theme + '/element/color.json')).color;
    const fill = colors.find(color => color.name === 'hita_immersive_segment_selected').value;
    assert.match(fill, /^#[0-9A-F]{8}$/);
    const alpha = parseInt(fill.slice(1, 3), 16) / 255;
    assert.ok(alpha > 0 && alpha < 0.2);
    assert.equal(fill.slice(3), theme === 'base' ? '000000' : 'FFFFFF');
  }
});

test('assistant provider segments keep selection callbacks and fallback fills when native material is unavailable', () => {
  const source = read('common/components/ImmersiveAssistantProviders.ets')
    .replace('@Component', '').replace('export struct', 'export class').replace(/@Prop /g, '');
  for (const material of [undefined, { immersive: true }]) {
    let options;
    const mod = { exports: {} };
    new Function('require', 'module', 'exports', '$r', 'Color', 'FontWeight', compile(source))(name => {
      if (name === '@kit.ArkUI') return {
        ColorMetrics: { resourceColor: color => color },
        LengthMetrics: { vp: value => value, fp: value => value },
        SegmentButtonV2Items: class { constructor(items) { return items; } },
        TabSegmentButtonV2: config => { options = config; return {
          width() { return this; }, attributeModifier() {}
        }; }
      };
      if (name === '@kit.BasicServicesKit') return { Available: () => value => value };
      if (name.includes('ImmersiveHeaderMaterial')) return { HeaderMaterial: { create: () => material } };
      if (name.includes('CompatibleLightModifier')) return { CompatibleLightModifier: class {} };
      throw Error('Unexpected import ' + name);
    }, mod, mod.exports, name => name, { Transparent: 'transparent' },
    { Regular: 'regular', Medium: 'medium' });
    const picker = new mod.exports.ImmersiveAssistantProviders();
    const selections = [];
    picker.onSelect = index => { selections.push(index); };
    for (const selected of [0, 1, 0]) {
      picker.selectedIndex = selected;
      picker.build();
      assert.equal(options.selectedIndex, selected);
      assert.equal(options.backgroundSystemMaterial, material);
      assert.equal(options.buttonBackgroundColor, material ? 'transparent' : 'app.color.hita_control_eaf0f7');
      assert.deepEqual(options.items.map(item => item.text), ['DeepSeek', '智谱 GLM']);
      options.$selectedIndex(1 - selected);
    }
    assert.deepEqual(selections, [1, 0, 1]);
  }
  const page = read('pages/AssistantPage.ets');
  assert.match(page, /import lazy \{ ImmersiveAssistantProviders \}/);
  assert.match(page, /if \(deviceInfo\.apiAvailable\('26\.0\.0'\)\) \{\s*ImmersiveAssistantProviders/);
  assert.match(page, /else \{\s*Row\(\{ space: 4 \}\) \{\s*this\.providerOption/);
});
