const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = relative => fs.readFileSync(path.join(root, relative), 'utf8');
const compile = source => ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText;

function pickerCompatibility(api, supported) {
  const calls = [];
  const native = {};
  Object.defineProperty(native, 'PickerMaterial', { get() {
    assert.equal(api, 26, 'other APIs cannot evaluate native picker materials');
    return {
      supported: () => supported,
      textOptions: options => { calls.push(['text', options]); return { ...options, immersive: true }; },
      create: () => { calls.push(['custom']); return { immersive: true }; }
    };
  } });
  const source = read('common/theme/CompatiblePickerMaterial.ets');
  assert.match(source, /import lazy \{ PickerMaterial \}/);
  const mod = { exports: {} };
  new Function('require', 'module', 'exports', compile(source.replace('import lazy ', 'import ')))(
    name => name === '@kit.BasicServicesKit' ? { deviceInfo: {
      apiAvailable: version => api >= Number(version.split('.')[0])
    } } : native, mod, mod.exports);
  return { Picker: mod.exports.CompatiblePickerMaterial, calls };
}

test('course picker materials are restricted to supported API 26 devices and requested surfaces', () => {
  const onAccept = () => {};
  const options = Object.freeze({ range: ['A', 'B'], selected: 1, canLoop: false, onAccept });
  for (const api of [23, 24, 25, 26, 27, 28]) {
    for (const supported of [false, true]) {
      const { Picker, calls } = pickerCompatibility(api, supported);
      const enabled = api === 26 && supported;
      assert.equal(Picker.isEnabled(), enabled);
      assert.equal(Picker.textOptions(options, false), options);
      assert.equal(Picker.dialogMaterial(false), undefined);
      assert.deepEqual(calls, []);
      const text = Picker.textOptions(options, true);
      const custom = Picker.dialogMaterial(true);
      if (enabled) {
        assert.equal(text.immersive, true);
        assert.equal(custom.immersive, true);
        assert.equal(text.onAccept, onAccept);
        assert.equal(text.range, options.range);
        assert.deepEqual(calls.map(call => call[0]), ['text', 'custom']);
      } else {
        assert.equal(text, options);
        assert.equal(custom, undefined);
        assert.deepEqual(calls, []);
      }
    }
  }
});

function nativePicker(overrides = {}) {
  const uiMaterial = {
    isImmersiveMaterialSupported: () => true,
    ImmersiveStyle: { THICK: 'thick' },
    ImmersiveMaterial: class { constructor(options) { Object.assign(this, options); } },
    ...overrides
  };
  const mod = { exports: {} };
  new Function('require', 'module', 'exports', 'Color',
    compile(read('common/theme/ImmersivePickerMaterial.ets')))(
    name => name === '@kit.BasicServicesKit' ? { Available: () => value => value } : { uiMaterial },
    mod, mod.exports, { White: 'white', Transparent: 'transparent' });
  return mod.exports.PickerMaterial;
}

test('native picker materials keep white feedback, readable course labels and callback identities', () => {
  const native = nativePicker();
  for (const method of ['textOptions']) {
    const onAccept = () => {};
    const options = { backgroundColor: 'legacy', range: ['Math', 'Physics'], selected: 1, onAccept,
      canLoop: false, alignment: 'bottom' };
    const result = native[method](options);
    assert.equal(result.backgroundColor, 'transparent');
    assert.deepEqual({ ...result.systemMaterial }, {
      style: 'thick', colorInvert: false, interactive: true, lightEffect: null
    });
    assert.equal(result.onAccept, onAccept);
    assert.equal(result.selected, 1);
    assert.equal(result.range, options.range);
    assert.equal(result.canLoop, false);
  }
  assert.deepEqual({ ...native.create() }, {
    style: 'thick', colorInvert: false, interactive: true, lightEffect: null
  });
});

test('picker capability and material failures preserve the original dialog options', () => {
  for (const capability of [() => false, () => { throw Error('unavailable'); }]) {
    assert.equal(nativePicker({ isImmersiveMaterialSupported: capability }).supported(), false);
  }
  const native = nativePicker({ ImmersiveMaterial: class { constructor() { throw Error('unsupported'); } } });
  for (const method of ['textOptions']) {
    const options = Object.freeze({ backgroundColor: 'legacy', selected: 2, range: ['A', 'B', 'C'] });
    assert.equal(native[method](options), options);
  }
  assert.equal(native.create(), undefined);
});

function segment(api, immersive = false, material) {
  if (arguments.length < 3) material = { native: true };
  let options;
  let width;
  const nativeCalls = [];
  const source = read('feature/timetable/views/' +
    (immersive ? 'ImmersiveCourseModeSegment.ets' : 'CourseModeSegment.ets'))
    .replace('import lazy ', 'import ')
    .replace('@Component', '').replace('export struct', 'export class').replace(/@Prop /g, '');
  const native = {};
  Object.defineProperty(native, 'ImmersiveCourseModeSegment', { get() {
    assert.equal(api, 26, 'the native segment material module stays unused on other APIs');
    return config => nativeCalls.push(config);
  } });
  const mod = { exports: {} };
  new Function('require', 'module', 'exports', '$r', 'Color', 'FontWeight', compile(source))(
    name => {
      if (name === '@kit.ArkUI') return {
        SegmentButtonV2Items: class { constructor(items) { return items; } },
        LengthMetrics: { vp: value => value, fp: value => value },
        ColorMetrics: { resourceColor: color => color },
        TabSegmentButtonV2: config => {
          options = config;
          return { width(value) { width = value; return this; }, clip() { return this; }, attributeModifier() {} };
        }
      };
      if (name === '@kit.BasicServicesKit') return {
        deviceInfo: { apiAvailable: version => api >= Number(version.split('.')[0]) },
        Available: () => value => value
      };
      if (name.endsWith('/CourseControlHost')) return { CourseControlHost: () => {} };
      if (name.endsWith('/ImmersiveHeaderMaterial')) return { HeaderMaterial: { create: () => material } };
      if (name.endsWith('/CompatibleLightModifier')) return { CompatibleLightModifier: class {} };
      if (name === './ImmersiveCourseModeSegment') return native;
      throw Error('unexpected import: ' + name);
    }, mod, mod.exports, name => name, { Transparent: 'transparent' },
    { Regular: 'regular', Medium: 'medium' });
  const component = new mod.exports[immersive ? 'ImmersiveCourseModeSegment' : 'CourseModeSegment']();
  return { component, nativeCalls, render() { component.build(); return { options, width }; } };
}

test('both course modes use one native segment with authoritative selected indices on API 23-25', () => {
  for (const api of [23, 24, 25, 27]) {
    for (const labels of [['具体时间', '按节次'], ['单日', '每周']]) {
      const h = segment(api);
      h.component.labels = labels;
      h.component.aboutToAppear();
      const selected = [];
      h.component.onSelect = index => selected.push(index);
      for (const index of [0, 1, 0]) {
        h.component.selectedIndex = index;
        const { options, width } = h.render();
        assert.deepEqual(options.items.map(item => item.text), labels);
        assert.ok(options.items.every(item => item.accessibilityText === item.text));
        assert.equal(options.selectedIndex, index);
        assert.equal(options.itemSpace, 0);
        assert.equal(options.enableStateAnimation, true);
        assert.equal(options.backgroundSystemMaterial, undefined);
        assert.equal(options.onItemClicked, undefined, 'only one selection callback is used');
        assert.equal(width, '100%');
        options.$selectedIndex(1 - index);
      }
      assert.deepEqual(selected, [1, 0, 1]);
      assert.deepEqual(h.nativeCalls, []);
    }
  }
});

test('API 26 segments use the native material backplate with 4vp insets and no selection shadow', () => {
  const wrapper = segment(26);
  wrapper.component.labels = ['单日', '每周'];
  wrapper.component.selectedIndex = 1;
  wrapper.component.aboutToAppear();
  wrapper.render();
  assert.equal(wrapper.nativeCalls.length, 1);
  assert.deepEqual(wrapper.nativeCalls[0].labels, ['单日', '每周']);
  assert.equal(wrapper.nativeCalls[0].selectedIndex, 1);
  for (const material of [undefined, { native: true }]) {
    const h = segment(26, true, material);
    h.component.labels = ['具体时间', '按节次'];
    h.component.aboutToAppear();
    const { options } = h.render();
    assert.deepEqual(options.items.map(item => item.text), ['具体时间', '按节次']);
    assert.equal(options.backgroundSystemMaterial, material);
    assert.equal(options.buttonPadding, 4);
    assert.equal(options.buttonMinHeight, options.itemMinHeight + 8);
    assert.equal(options.itemSpace, 0);
    assert.deepEqual(options.itemShadow, { radius: 0, color: 'transparent', offsetX: 0, offsetY: 0 });
  }
});

test('floating course hosts keep their elevation during a drag and clear it on release, cancel or removal', () => {
  const file = read('feature/timetable/views/CourseControlHost.ets');
  const source = (file.slice(0, file.indexOf('\n  build()')) + '\n}\n')
    .replace('@Component', '').replace('export struct', 'export class')
    .replace(/@(State|Prop|BuilderParam) /g, '');
  const mod = { exports: {} };
  const touchTypes = { Down: 0, Move: 1, Up: 2, Cancel: 3 };
  new Function('require', 'module', 'exports', 'TouchType', compile(source))(
    () => ({}), mod, mod.exports, touchTypes);
  const host = new mod.exports.CourseControlHost();
  const changes = [];
  host.onPressingChanged = pressed => changes.push(pressed);
  for (const terminal of [touchTypes.Up, touchTypes.Cancel, 'remove']) {
    host.observeTouch(Object.freeze({ type: touchTypes.Down }));
    host.observeTouch(Object.freeze({ type: touchTypes.Down }));
    host.observeTouch(Object.freeze({ type: touchTypes.Move }));
    assert.equal(host.pressing, true, 'dragging keeps the original material above its neighbours');
    if (terminal === 'remove') host.aboutToDisappear();
    else host.observeTouch(Object.freeze({ type: terminal }));
    assert.equal(host.pressing, false);
    host.aboutToDisappear();
  }
  assert.deepEqual(changes, [true, false, true, false, true, false]);
});

for (const weekdayMode of [false, true]) {
test(`${weekdayMode ? 'weekday' : 'week'} elevation follows the touched cell without clearing another active cell or changing selection`, () => {
  const file = read('feature/timetable/views/CourseWeekPicker.ets');
  const source = (file.slice(0, file.indexOf('\n  build()')) + '\n}\n')
    .replace('@Component', '').replace('export struct', 'export class')
    .replace(/@(State|Prop|Link|Builder)\s+/g, '');
  const calls = [];
  const node = new Proxy({}, { get: () => () => node });
  const mod = { exports: {} };
  new Function('require', 'module', 'exports', 'Text', '$r', 'FontWeight', 'TextAlign', compile(source))(
    name => {
      if (name.endsWith('/HitaDesign')) {
        const tokens = { exports: {} };
        new Function('require', 'module', 'exports', compile(read('common/theme/HitaDesign.ets')))(() => ({}), tokens, tokens.exports);
        return tokens.exports;
      }
      if (name.endsWith('/CourseControlHost')) return { COURSE_CONTROL_OVERFLOW: 16, CourseControlHost: options => calls.push(options) };
      if (name.endsWith('/CourseDateSelection')) {
        const dates = { exports: {} };
        new Function('require', 'module', 'exports', compile(read('feature/timetable/CourseDateSelection.ets')))(() => ({}), dates, dates.exports);
        return dates.exports;
      }
      if (name.endsWith('/CompatibleSheetMaterial')) return { CompatibleSheetMaterial: { isEnabled: () => true } };
      if (name.endsWith('/CompatibleMaterialModifier')) return { CompatibleMaterialModifier: class {} };
      return {};
    }, mod, mod.exports, () => node, name => name, { Medium: 'medium' }, { Center: 'center' });
  const picker = new mod.exports.CourseWeekPicker();
  picker.weekdayMode = weekdayMode;
  picker.chosen = [1, 2, 3];
  picker.cell(1);
  picker.cell(2);
  calls[0].onPressingChanged(true);
  assert.equal(picker.activeWeek, 1);
  calls[1].onPressingChanged(true);
  assert.equal(picker.activeWeek, 2);
  calls[0].onPressingChanged(false);
  assert.equal(picker.activeWeek, 2);
  calls[1].onPressingChanged(false);
  assert.equal(picker.activeWeek, -1);
  assert.deepEqual(picker.chosen, [1, 2, 3]);
  assert.doesNotMatch(file, /Button\('滑动选择'\)/);
  assert.doesNotMatch(file, /enableEditMode|onEditModeChange/);
  assert.match(file, /direction: PanDirection.Horizontal/);
  assert.match(file, /enableScrollInteraction\(false\)/);
  const choosing = [];
  picker.onChoosingChanged = value => choosing.push(value);
  picker.gridWidth = 382;
  picker.weeks = Array.from({length: weekdayMode ? 7 : 17}, (_, i) => i + 1);
  picker.chosen = [];
  const columns = weekdayMode ? 7 : 5;
  const gap = weekdayMode ? 4 : 8;
  const stride = (350 + gap) / columns;
  const x = index => 16 + index * stride + 10;
  picker.beginStroke(x(0), 30);
  picker.continueStroke(x(3), 30);
  picker.continueStroke(x(1), 30);
  assert.deepEqual(picker.chosen, [1, 2, 3, 4], 'fast strokes fill gaps and retracing does not toggle');
  picker.finishStroke();
  picker.beginStroke(x(0), 30);
  picker.continueStroke(x(3), 30);
  picker.finishStroke();
  assert.deepEqual(picker.chosen, [], 'starting on a selected cell erases the stroke');
  picker.beginStroke(1, 1);
  assert.equal(picker.painting, false, 'material overflow is not selectable');
  picker.beginStroke(x(0), 30);
  picker.aboutToDisappear();
  assert.equal(picker.painting, false);
  assert.equal(choosing.at(-1), false, 'removal releases page scrolling');


});
}
