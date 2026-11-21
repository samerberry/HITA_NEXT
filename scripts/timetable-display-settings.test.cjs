const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const cache = new Map();
let preferencesStore;
function load(name) {
  const file = path.resolve(root, name);
  if (cache.has(file)) return cache.get(file).exports;
  let source = fs.readFileSync(file, 'utf8');
  if (file.endsWith('TimetableDisplaySettings.ets')) {
    source = source.slice(0, source.indexOf('\n  @Builder')) + '\n}';
    source = source.replace(/^@Component\r?\n/gm, '').replace(/@(Prop|State)\s+/g, '')
      .replace('export struct TimetableDisplaySettings', 'export class TimetableDisplaySettings');
  }
  const output = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const mod = { exports: {} }; cache.set(file, mod);
  const req = key => {
    if (key === '@kit.ArkData') return { preferences: { getPreferences: async () => preferencesStore } };
    if (key.startsWith('@kit.')) return {};
    return load(path.resolve(path.dirname(file), key + '.ets'));
  };
  new Function('require', 'module', 'exports', output)(req, mod, mod.exports);
  return mod.exports;
}
const { TimetableDisplayOptions: Options } = load('feature/timetable/data/TimetableDisplayOptions.ets');
const { TimetableDisplayStore: Store } = load('feature/timetable/data/TimetableDisplayStore.ets');
const { TimetableDisplaySettings: Panel } = load('feature/timetable/views/TimetableDisplaySettings.ets');
const key = 'timetable_display_options';
function deferred() { let resolve; const promise = new Promise(done => { resolve = done; }); return { promise, resolve }; }
async function harness() {
  const data = new Map([['timetable_text_color', '#123456'], ['active_timetable_id', 'table-1']]);
  let flush = async () => {};
  preferencesStore = {
    async get(key, fallback) { return data.has(key) ? data.get(key) : fallback; },
    async put(key, value) { data.set(key, value); },
    async flush() { await flush(); }
  };
  const store = new Store(); await store.init({});
  return { store, data, setFlush(fn) { flush = fn; } };
}
test('missing or corrupt display settings retain existing timetable appearance and adapt the default line color', () => {
  for (const raw of ['', '{', 'null', '[]', 'true', '"str"', '{}']) {
    assert.deepEqual(Options.parse(raw), new Options());
  }
  const defaults = new Options();
  assert.equal(defaults.drawTimeLines, true); assert.equal(defaults.eveningHint, true);
  assert.equal(defaults.wallpaperMask, 0);
  assert.equal(defaults.lineColor(false), '#D7DEE8'); assert.equal(defaults.lineColor(true), '#3A414B');
  const sanitized = Options.parse(JSON.stringify({ drawTimeLines: false, eveningHint: false,
    timeLineColor: '#aabbcc', wallpaperMask: 500 }));
  assert.equal(sanitized.drawTimeLines, false); assert.equal(sanitized.eveningHint, false);
  assert.equal(sanitized.wallpaperMask, 80); assert.equal(sanitized.lineColor(true), '#AABBCC');
  assert.equal(Options.parse('{"wallpaperMask":-10}').wallpaperMask, 0);
  assert.deepEqual(Options.parse('{"drawTimeLines":"false","eveningHint":0,"timeLineColor":"red","wallpaperMask":"20"}'), defaults);
  const copy = sanitized.copy(); copy.timeLineColor = '#112233';
  assert.equal(sanitized.timeLineColor, '#AABBCC');
});

test('all display options persist without overwriting legacy text color or timetable selection', async () => {
  const { store, data } = await harness();
  const options = Options.parse('{"drawTimeLines":false,"eveningHint":false,"timeLineColor":"#E53935","wallpaperMask":42}');
  await store.save(options);
  const reopened = new Store(); await reopened.init({});
  assert.deepEqual(await reopened.load(), options);
  assert.equal(data.get('timetable_text_color'), '#123456');
  assert.equal(data.get('active_timetable_id'), 'table-1');
});

test('queued writes snapshot their options and the latest requested state wins', async () => {
  const h = await harness(); const firstFlush = deferred(); let count = 0;
  h.setFlush(async () => { if (++count === 1) await firstFlush.promise; });
  const first = new Options(); first.wallpaperMask = 20;
  const one = h.store.save(first); first.wallpaperMask = 80;
  const second = new Options(); second.wallpaperMask = 45; second.eveningHint = false;
  const two = h.store.save(second);
  for (let i = 0; i < 6; i++) await Promise.resolve();
  assert.equal(JSON.parse(h.data.get(key)).wallpaperMask, 20);
  firstFlush.resolve(); await Promise.all([one, two]);
  assert.deepEqual(await h.store.load(), second);
});

test('failed flush restores previous preferences and does not block subsequent saves', async () => {
  const h = await harness(); await h.store.save(new Options());
  const next = new Options(); next.eveningHint = false;
  h.setFlush(async () => { throw new Error('disk unavailable'); });
  await assert.rejects(h.store.save(next), /save failed/);
  assert.equal((await h.store.load()).eveningHint, true);
  h.setFlush(async () => {}); await h.store.save(next);
  assert.equal((await h.store.load()).eveningHint, false);
  await assert.rejects(new Store().save(next), /unavailable/);
});

test('panel toggles, mask and both color editors use independent values without replacing other options', async () => {
  const page = new Panel(); const writes = [];
  page.onSave = async options => { writes.push(options); page.options = options.copy(); };
  page.aboutToAppear();
  await page.switchLines(false); await page.switchEvening(false);
  page.maskValue = 35; await page.saveMask();
  page.editing = 'line'; await page.saveColor(0xFFE53935);
  let text = ''; page.onTextColorSave = async color => { text = color; };
  page.editing = 'text'; await page.saveColor(0xFFFFFFFF);
  assert.equal(writes.length, 4); assert.equal(text, '#FFFFFF');
  assert.equal(page.options.drawTimeLines, false); assert.equal(page.options.eveningHint, false);
  assert.equal(page.options.wallpaperMask, 35); assert.equal(page.options.timeLineColor, '#E53935');
  assert.equal(page.editing, '');
});

test('failed changes leave saved switches intact, roll back mask preview and retain the color editor for retry', async () => {
  const panel = new Panel(); const previews = [];
  panel.onMaskPreview = value => previews.push(value);
  panel.onSave = async () => { throw new Error('disk'); };
  await panel.switchLines(false);
  assert.equal(panel.options.drawTimeLines, true);
  panel.maskValue = 70; await panel.saveMask();
  assert.equal(panel.maskValue, 0); assert.equal(previews.at(-1), 0);
  panel.editing = 'line'; await assert.rejects(panel.saveColor(0xFF123456));
  assert.equal(panel.editing, 'line'); assert.equal(panel.saving, false);
  assert.match(panel.errorText, /未保存/);
});

test('dismissing during a slider drag commits its last preview value once', async () => {
  const panel = new Panel(); const writes = [];
  panel.onSave = async options => { writes.push(options); panel.options = options.copy(); };
  panel.maskValue = 37; panel.aboutToDisappear();
  for (let i = 0; i < 6; i++) await Promise.resolve();
  assert.equal(writes.length, 1); assert.equal(writes[0].wallpaperMask, 37);
  panel.aboutToDisappear(); assert.equal(writes.length, 1);
});

test('both palette entries can return to automatic without losing unrelated display settings', async () => {
  const panel = new Panel();
  panel.onSave = async options => { panel.options = options.copy(); };
  panel.onTextColorSave = async color => { panel.textColor = color; };
  panel.options.wallpaperMask = 40;
  panel.options.drawTimeLines = false;
  panel.editing = 'line'; panel.adaptiveLineColor = '#FFFFFF';
  assert.equal(panel.automaticColor(), true);
  await panel.switchAutomatic(false);
  assert.equal(panel.options.timeLineColor, '#FFFFFF');
  await panel.switchAutomatic(true);
  assert.equal(panel.options.timeLineColor, '');
  panel.editing = 'text'; panel.adaptiveTextColor = '#333333';
  assert.equal(panel.automaticColor(), true);
  await panel.switchAutomatic(false);
  assert.equal(panel.textColor, '#333333');
  await panel.switchAutomatic(true);
  assert.equal(panel.textColor, 'auto');
  panel.onTextColorSave = async () => { throw new Error('disk'); };
  await panel.switchAutomatic(false);
  assert.equal(panel.textColor, 'auto');
  assert.equal(panel.saving, false);
  assert.equal(panel.options.wallpaperMask, 40);
  assert.equal(panel.options.drawTimeLines, false);
});

test('native switch state synchronization does not rewrite manual colors or trigger redundant saves', async () => {
  const panel = new Panel();
  let writes = 0;
  panel.onSave = async () => { writes++; };
  panel.onTextColorSave = async () => { writes++; };
  panel.options.timeLineColor = '#D7DEE8';
  panel.adaptiveLineColor = '#FFFFFF';
  panel.editing = 'line';
  await panel.switchAutomatic(false);
  assert.equal(panel.options.timeLineColor, '#D7DEE8');
  panel.editing = 'text';
  panel.textColor = '#E53935';
  await panel.switchAutomatic(false);
  await panel.switchLines(true);
  await panel.switchEvening(true);
  assert.equal(writes, 0);
});

test('evening hints respect the preference without changing course/exam detection or return-week behavior', () => {
  const home = fs.readFileSync(path.join(root, 'pages/Home.ets'), 'utf8');
  const method = home.slice(home.indexOf('  private updateEveningCourseHint()'), home.indexOf('  private hasTimetableBackground()'));
  const inset = home.slice(home.indexOf('  private timetableScrollEndInset()'), home.indexOf('  private railMode()'));
  const code = ts.transpileModule('class Page {' + method + inset + '}', {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  let detects = 0;
  let maxOffset = 0;
  const page = new Function('eventsOfWeek', 'hasEveningCourse', 'eveningHintVisible', 'DOCK_ACTION_SIZE', 'HitaDesign',
    code + '; return new Page();')(() => ['exam'], () => { detects++; return true; },
    (_hasCourse, _offset, end) => { maxOffset = end; return true; }, 56, { spaceMd: 16, spaceSm: 12 });
  Object.assign(page, { timetableDisplay: new Options(), currentTimetable: {}, timetableAreaH: 700,
    navBarInset: 24, railMode: () => false,
    timetableChromeH: 160, timetableCanvasHeight: 1000, timetableScroller: { currentOffset: () => ({ yOffset: 0 }) } });
  page.updateEveningCourseHint(); assert.equal(page.showEveningCourseHint, true);
  assert.equal(maxOffset, 160 + 1000 - 700 + 56 + 12 + 24 + 16);
  page.timetableDisplay.eveningHint = false; page.updateEveningCourseHint();
  assert.equal(page.showEveningCourseHint, false); assert.equal(detects, 1);
  page.timetableDisplay.eveningHint = true; page.updateEveningCourseHint();
  assert.equal(page.showEveningCourseHint, true);
  page.railMode = () => true;
  page.updateEveningCourseHint();
  assert.equal(maxOffset, 160 + 1000 - 700 + 24 + 16);
  assert.match(home, /Scroll\(this\.timetableScroller\)[\s\S]*?Blank\(\)\.height\(this\.timetableScrollEndInset\(\)\)/);
  assert.match(home, /returnVisible: this\.showReturnToCurrentWeek\(\)/);
});
