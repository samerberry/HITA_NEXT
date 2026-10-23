const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const root = path.resolve(__dirname, '../entry/src/main');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const compile = source => ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText;

function compatible(api, supported = true) {
  const calls = [];
  const interactions = [];
  const native = {};
  Object.defineProperty(native, 'SheetMaterial', { get() {
    assert.equal(api, 26, 'other APIs must not evaluate the native sheet module');
    return {
      supported: () => supported,
      options: (options, interactive) => {
        calls.push(options); interactions.push(interactive);
        return { ...options, immersive: true };
      }
    };
  } });
  const source = read('ets/common/theme/CompatibleSheetMaterial.ets');
  assert.match(source, /import lazy \{ SheetMaterial \}/);
  const mod = { exports: {} };
  new Function('require', 'module', 'exports', 'Color', '$r', compile(source.replace('import lazy ', 'import ')))(
    name => name === '@kit.BasicServicesKit' ? { deviceInfo: {
      apiAvailable: version => api >= Number(version.split('.')[0])
    } } : native, mod, mod.exports, { Transparent: 'transparent' }, name => name);
  return { Sheet: mod.exports.CompatibleSheetMaterial, calls, interactions };
}

function nativeMaterial(overrides = {}) {
  const uiMaterial = {
    isImmersiveMaterialSupported: () => true,
    ImmersiveStyle: { THICK: 'thick' },
    ImmersiveMaterial: class { constructor(options) { Object.assign(this, options); } },
    ...overrides
  };
  const mod = { exports: {} };
  new Function('require', 'module', 'exports', 'Color',
    compile(read('ets/common/theme/ImmersiveSheetMaterial.ets')))(
    name => name === '@kit.BasicServicesKit' ? { Available: () => value => value } : { uiMaterial },
    mod, mod.exports, { White: 'white', Transparent: 'transparent' });
  return mod.exports.SheetMaterial;
}

test('new sheet effects are exclusive to API 26, with no native evaluation on any other API', () => {
  for (const api of [23, 24, 25, 27, 28]) {
    const { Sheet, calls } = compatible(api);
    const options = Object.freeze({ backgroundColor: 'legacy', height: 'fit-content', showClose: false });
    assert.equal(Sheet.isEnabled(), false);
    assert.equal(Sheet.options(options), options);
    assert.equal(Sheet.options(options, false), options);
    assert.equal(Sheet.bodyColor('legacy'), 'legacy');
    assert.equal(Sheet.cardColor('legacy-card'), 'legacy-card');
    assert.deepEqual(calls, []);
  }
});

test('API 26 opts into requested sheets, while unsupported hardware retains opaque legacy surfaces', () => {
  for (const supported of [true, false]) {
    const { Sheet, calls } = compatible(26, supported);
    const options = { backgroundColor: 'legacy', height: 'large' };
    assert.equal(Sheet.isEnabled(), supported);
    assert.equal(Sheet.options(options, false), options, 'unrequested surfaces are not opted in');
    assert.deepEqual(calls, []);
    assert.equal(Sheet.bodyColor('legacy'), supported ? 'transparent' : 'legacy');
    assert.equal(Sheet.cardColor('legacy-card'), supported ? 'app.color.hita_immersive_sheet_card' : 'legacy-card');
    const result = Sheet.options(options);
    if (supported) {
      assert.equal(result.immersive, true);
      assert.deepEqual(calls, [options]);
    } else {
      assert.equal(result, options);
      assert.deepEqual(calls, []);
    }
  }
});

test('sheet material retains sizing, mask, dismissal and callback identities without inverting color previews', () => {
  const onDisappear = () => {}, onWillDisappear = () => {};
  const retained = { height: 'fit-content', dragBar: true, showClose: false, preferType: 'bottom',
    maskColor: 'mask', onDisappear, onWillDisappear };
  const result = nativeMaterial().options({ ...retained, backgroundColor: 'legacy' });
  assert.equal(result.backgroundColor, 'transparent');
  assert.deepEqual({ ...result.systemMaterial }, {
    style: 'thick', colorInvert: false, interactive: true, lightEffect: null
  });
  for (const [key, value] of Object.entries(retained)) assert.equal(result[key], value, key);
});

test('display settings keep sheet material without deforming switches and sliders', () => {
  const { Sheet, interactions } = compatible(26);
  const input = { height: 'fit-content', dragBar: true };
  Sheet.options(input, true, false);
  assert.deepEqual(interactions, [false]);
  const output = nativeMaterial().options({ ...input }, false);
  assert.equal(output.systemMaterial.interactive, false);
  assert.equal(output.height, input.height);
  const home = read('ets/pages/Home.ets');
  const display = home.slice(home.indexOf('        TimetableDisplaySettings({'),
    home.indexOf('      } else if (this.courseSheetOpen && this.selectedCourse'));
  assert.doesNotMatch(display, /CompatibleLightModifier/);
  assert.match(read('ets/feature/timetable/views/TimetableDisplaySettings.ets'), /CompatibleMaterialModifier/);
});

test('unavailable capability and constructor failures preserve sheet fallback options', () => {
  assert.equal(nativeMaterial({ isImmersiveMaterialSupported: () => false }).supported(), false);
  assert.equal(nativeMaterial({ isImmersiveMaterialSupported() { throw Error('unavailable'); } }).supported(), false);
  const options = Object.freeze({ height: 'large', backgroundColor: 'legacy', dragBar: true });
  const native = nativeMaterial({ ImmersiveMaterial: class { constructor() { throw Error('unavailable'); } } });
  assert.equal(native.options(options), options);
});

test('authentication cards use translucent theme backgrounds below the documented 60 percent limit', () => {
  for (const theme of ['base', 'dark']) {
    const colors = JSON.parse(read('resources/' + theme + '/element/color.json')).color;
    const color = colors.find(item => item.name === 'hita_immersive_sheet_card').value;
    assert.match(color, /^#[0-9A-F]{8}$/);
    assert.ok(parseInt(color.slice(1, 3), 16) / 255 < 0.6);
    assert.ok(parseInt(color.slice(1, 3), 16) / 255 > 0.5);
  }
  const login = read('ets/feature/eas/webLogin/EasLoginPage.ets');
  assert.equal((login.match(/CompatibleSheetMaterial.bodyColor/g) || []).length, 2);
  assert.match(login, /\.forceDarkAccess\(false\)/);
  const home = read('ets/pages/Home.ets');
  assert.equal((home.match(/CompatibleSheetMaterial.cardColor/g) || []).length, 2);
});

test('Home retains one sheet lifecycle for authentication, timetable and calendar confirmation materials', () => {
  const home = read('ets/pages/Home.ets');
  assert.equal((home.match(/\.bindSheet\(/g) || []).length, 1);
  assert.match(home, /\.bindSheet\(\$\$this.activeSheetVisible, this.activeSheet\(\), CompatibleSheetMaterial.options\(\{/);
  assert.match(home, /\}, this.loginSheetOpen \|\| this.sessionSheetOpen \|\| this.courseSheetOpen \|\| this.timetableDisplayOpen \|\|\s*this.calendarExportSheetOpen \|\| this.widgetBackgroundSheetOpen \|\| this.importTimetableSheetOpen \|\|\s*this.academicPanelOpen,\s*!this.timetableDisplayOpen\)\)/);
  assert.match(home, /showClose: false/);
  assert.match(home, /height: this.widgetBackgroundSheetOpen \|\| this.importTimetableSheetOpen \|\| this.academicPanelOpen \? SheetSize.LARGE :\s*\(this.loginSheetOpen \? SheetSize.LARGE : SheetSize.FIT_CONTENT\)/);
  assert.match(home, /onWillDisappear: \(\) => \{\s*this.closeActiveSheet\(\)/);
  const detail = read('ets/pages/TimetableDetailPage.ets');
  assert.match(detail, /\.bindSheet\(\$\$this\.sheetVisible, this\.eventSheetContent\(\), CompatibleSheetMaterial.options\(\{/);
  assert.match(detail, /\}, this\.eventSheetMode === 2\)\)/);
});

test('more opens the reusable timetable importer as an expanded sheet while preserving its standalone route', () => {
  const home = read('ets/pages/Home.ets');
  const more = home.slice(home.indexOf('  tabMine()'), home.indexOf('  userCard()'));
  assert.match(more, /'导入课表',[\s\S]*?this\.openImportTimetableSheet\(\)/);
  assert.match(home, /private openImportTimetableSheet\(\): void \{\s*if \(!this\.canOpenSheet\(\)\) \{\s*return;\s*\}\s*this\.importTimetableSheetOpen = true;\s*this\.activeSheetVisible = true;/);
  assert.match(home, /ImportTimetablePanel\(\{\s*presentedAsSheet: true,[\s\S]*?onClose: \(\) => this\.closeActiveSheet\(\),[\s\S]*?onImported: \(\) => \{ void this\.refreshSummaries\(\); \}/);
  const panel = read('ets/pages/ImportTimetablePanel.ets');
  assert.match(panel, /\.padding\(\{ top: this\.presentedAsSheet \? 0 : this\.statusBarInset \}\)/);
  assert.match(panel, /CompatibleSheetMaterial\.bodyColor\(PAGE_BG\)/);
  assert.match(panel, /new CompatibleLightModifier\(24, this\.presentedAsSheet &&\s*CompatibleSheetMaterial\.isEnabled\(\), true\)/);
  assert.match(panel, /ImmersiveHeader\(\{ barHeight: HEADER_HEIGHT, materialEnabled: !this\.presentedAsSheet \|\|\s*CompatibleSheetMaterial\.isEnabled\(\) \}\)/);
  assert.match(panel, /new CompatibleMaterialModifier\(\$r\('app\.color\.hita_selected_ebf4fc'\), false,\s*!this\.presentedAsSheet \|\| CompatibleSheetMaterial\.isEnabled\(\)\)/);
  assert.match(read('ets/pages/ImportTimetablePage.ets'), /ImportTimetablePanel\(\{ presentedAsSheet: false \}\)/);
});

test('calendar confirmation uses the guarded sheet material without changing export or cancel controls', () => {
  const home = read('ets/pages/Home.ets');
  const sheet = home.slice(home.indexOf('  calendarExportConfirmationSheet('), home.indexOf('  tabToday('));
  assert.match(sheet, /Text\('导出至手机日历'\)/);
  assert.match(sheet, /onClick\(\(\) => this.cancelCalendarExport\(\)\)/);
  assert.match(sheet, /onClick\(\(\) => this.exportToCalendar\(\)\)/);
  assert.equal((sheet.match(/\.enabled\(!this.calendarExporting\)/g) || []).length, 2);
  assert.doesNotMatch(sheet, /\.backgroundColor\(COLOR_SURFACE\)|systemMaterial/);
  assert.match(sheet, /ImmersiveHeader\(\{ barHeight: 46 \}\)/);
});

test('course palette button keeps a stable circle host, original preview and toggle callbacks', () => {
  const home = read('ets/pages/Home.ets');
  const course = home.slice(home.indexOf('  courseDetailSheet('), home.indexOf('  courseDetailRow('));
  assert.match(course, /ImmersiveHeader\(\{ barHeight: 44, materialEnabled: CompatibleSheetMaterial.isEnabled\(\) \}\)/);
  assert.match(course, /\.width\(44\).height\(44\).padding\(0\).flexShrink\(0\)/);
  assert.match(course, /\.width\(44\).height\(44\).flexShrink\(0\)/);
  assert.match(course, /new CompatibleMaterialModifier\(COLOR_NAV_ACTIVE, false, CompatibleSheetMaterial.isEnabled\(\)\)/);
  assert.match(course, /this.courseColorPreview = event.color;\s*this.courseColorEditing = !this.courseColorEditing/);
  assert.match(course, /onSave: async \(color: number\) => \{ await this.saveCourseColor\(event, color\)/);
  assert.match(course, /onCancel: \(\) => \{ this.courseColorEditing = false/);
});

test('course and timetable text color actions share the material footer while retaining the legacy fallback', () => {
  const home = read('ets/pages/Home.ets');
  assert.equal((home.match(/immersiveControls: true/g) || []).length, 1);
  assert.match(home, /initialColor: event.color,\s*immersiveControls: true/);
  const display = read('ets/feature/timetable/views/TimetableDisplaySettings.ets');
  assert.match(display, /textMode: this\.editing === 'text',[\s\S]*immersiveControls: true/);
  assert.match(display, /new CompatibleMaterialModifier/);
  assert.doesNotMatch(read('ets/pages/ExamPage.ets'), /immersiveControls/);
  const editor = read('ets/feature/timetable/views/CourseColorEditor.ets');
  assert.match(editor, /@Prop immersiveControls: boolean = false/);
  assert.match(editor, /if \(this.immersiveControls && CompatibleSheetMaterial.isEnabled\(\)\) \{\s*ImmersiveHeader/);
  const footer = editor.slice(editor.indexOf('      if (this.immersiveControls'));
  assert.equal((footer.match(/new CompatibleMaterialModifier/g) || []).length, 2);
  assert.equal((footer.match(/\.enabled\(!this.saving\)/g) || []).length, 4);
  assert.equal((footer.match(/onClick\(\(\) => this.onCancel\(\)\)/g) || []).length, 2);
  assert.equal((footer.match(/onClick\(\(\) => this.save\(\)\)/g) || []).length, 2);
  assert.match(footer, /else \{\s*Row\(\{ space: 12 \}\)/);
  assert.match(editor, /timetableBlockColor\(this.color\(\)\)/);
});

test('Add Course material hosts only the action and leaves the original label branch on other APIs', () => {
  const detail = read('ets/pages/TimetableDetailPage.ets');
  const info = detail.slice(detail.indexOf('  private infoCard('), detail.indexOf('  private subjectCard('));
  assert.match(info, /Column\(\) \{\s*Row\(\) \{\s*Column\(\)/);
  assert.match(info, /if \(CompatibleSheetMaterial.isEnabled\(\)\) \{\s*Column\(\) \{\s*(?:\/\/[^\n]*\n\s*)?ImmersiveHeader\(\{ barHeight: 68 \}\)/);
  assert.match(info, /\.width\(104\)\s*\.height\(44\)/);
  assert.match(info, /\.width\(128\)\s*\.height\(68\)/);
  assert.match(info, /else \{\s*Text\('添加课程'\)[\s\S]*\.height\(32\)/);
  assert.equal((info.match(/this.openAddEvent\(\)/g) || []).length, 2);
});

test('appearance options keep selection, accessibility and saving guards with exact API 26 material gating', () => {
  const home = read('ets/pages/Home.ets');
  const options = home.slice(home.indexOf('  appearanceOption('), home.indexOf('  userCard('));
  assert.match(home, /ImmersiveHeader\(\{ barHeight: 60, materialEnabled: CompatibleSheetMaterial.isEnabled\(\) \}\)/);
  assert.match(options, /Radio\(\{ value: mode, group: 'appearance_mode' \}\)/);
  assert.match(options, /\.checked\(this.appearanceMode === mode\)/);
  assert.match(options, /new CompatibleMaterialModifier\([\s\S]*false, CompatibleSheetMaterial.isEnabled\(\)\)/);
  assert.match(options, /\.enabled\(!this.appearanceBusy\)/);
  assert.match(options, /void this.selectAppearance\(mode\)/);
});
