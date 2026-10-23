const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');
const source = fs.readFileSync(path.resolve(__dirname, '../entry/src/main/ets/pages/TimetableManagerPage.ets'), 'utf8');
const between = (start, end) => source.slice(source.indexOf(start), source.indexOf(end));

function page(save) {
  const create = between('  private async createEmptyTimetable()', '  /** Export the selected/current');
  const menu = between('  private showExportMenu()', '  private confirmDelete()');
  const compiled = ts.transpileModule(`class TimetableManagerPage {
    adding = false; loading = false; deleting = false; exporting = false;
    static defaultName() { return 'Test term'; }
    ${create}
    ${menu}
  }`, { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText;
  const calls = { selected: [], routed: [], exported: [], toasts: [] };
  const host = new Function('RdbHelper', 'TimetableSelectionStore', 'EasTimetable', 'WEEK_MS',
    compiled + '; return new TimetableManagerPage();')(
    { getInstance: () => ({ saveTimetable: save }) },
    { getInstance: () => ({ save: async id => calls.selected.push(id) }) },
    class { id = 'new'; static mondayMsOf(time) { return time; } }, 7 * 86400000
  );
  host.getUIContext = () => ({
    getRouter: () => ({ pushUrl: options => calls.routed.push(options) }),
    getPromptAction: () => ({ showToast: options => calls.toasts.push(options.message) })
  });
  host.load = async () => {};
  host.exportTimetable = timetable => calls.exported.push(timetable.id);
  host.timetables = [{ id: 'newest' }, { id: 'current' }];
  host.activeTimetableId = 'current';
  return { host, calls };
}

test('rapid create clicks produce one timetable and only select it after the save succeeds', async () => {
  let finish, writes = 0;
  const { host, calls } = page(() => {
    writes++;
    return new Promise(resolve => { finish = resolve; });
  });
  const first = host.createEmptyTimetable();
  await host.createEmptyTimetable();
  assert.equal(writes, 1);
  assert.equal(host.adding, true);
  assert.deepEqual(calls.selected, []);
  finish();
  await first;
  assert.deepEqual(calls.selected, ['new']);
  assert.equal(calls.routed.length, 1);
  assert.equal(host.adding, false);
});

test('creation failures retain the current selection and release the action guard', async () => {
  const { host, calls } = page(async () => { throw Error('disk full'); });
  await host.createEmptyTimetable();
  assert.equal(host.activeTimetableId, 'current');
  assert.deepEqual(calls.selected, []);
  assert.deepEqual(calls.routed, []);
  assert.equal(calls.toasts.length, 1);
  assert.equal(host.adding, false);
});

test('export uses the current timetable rather than the first row and handles missing selections', () => {
  const { host, calls } = page(async () => {});
  host.showExportMenu();
  assert.deepEqual(calls.exported, ['current']);
  host.activeTimetableId = 'deleted';
  host.showExportMenu();
  assert.deepEqual(calls.exported, ['current', 'newest']);
  host.timetables = [];
  host.showExportMenu();
  assert.equal(calls.exported.length, 2);
  assert.equal(calls.toasts.length, 1);
});

const home = fs.readFileSync(path.resolve(__dirname, '../entry/src/main/ets/pages/Home.ets'), 'utf8');
const homeMethod = (start, end) => home.slice(home.indexOf(start), home.indexOf(end, home.indexOf(start)));

function summaryHarness() {
  const table = id => ({ id, name: id, code: 'LOCAL:' + id, startTime: 0, getWeekNumber: () => 1 });
  const state = { tables: ['a', 'b', 'c'].map(table), selectedId: 'a', events: async () => [] };
  const rdb = {
    init: async () => {},
    getTimetables: async () => state.tables.slice(),
    getTimetableById: async id => state.tables.find(item => item.id === id),
    getEventsOfTimetable: () => state.events(),
    getSubjectsOfTimetable: async () => []
  };
  const resolver = fs.readFileSync(path.resolve(__dirname,
    '../entry/src/main/ets/feature/timetable/data/TimetableResolver.ets'), 'utf8');
  const module = { exports: {} };
  new Function('exports', ts.transpileModule(resolver, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText)(module.exports);
  const code = `class Home {
    summaryRequestGeneration = 0; skippingCourse = false; nowTick = Date.now();
    courseDeleteEffects = { resume() {} };
    getUIContext() { return { getHostContext: () => ({}), setKeyboardAvoidMode() {} }; }
    startClock() {}
    checkTimetableUpdate() {}
    updateTodayHighlights() {}
    drawTimetableNow() {}
    static defaultCanvasColor() { return 1; }
    ${homeMethod('  async onPageShow()', '  onPageHide()')}
    ${homeMethod('  async refreshSummaries(', '  private classReminderSubtitle()')}
  }`;
  const page = new Function('RdbHelper', 'EasSessionStore', 'TimetableSelectionStore', 'TimetableResolver',
    'EasEventType', 'DAY_MS', 'KeyboardAvoidMode', 'WidgetBackgroundStore', 'NextClassWidgetService',
    ts.transpileModule(code, {
      compilerOptions: { target: ts.ScriptTarget.ES2020 }
    }).outputText + '; return new Home();')(
    { getInstance: () => rdb },
    { getInstance: () => ({ loadPreferred: async () => undefined }) },
    { getInstance: () => ({
      load: async () => state.selectedId,
      clearIf: async id => { if (state.selectedId === id) state.selectedId = ''; }
    }) }, module.exports.TimetableResolver, { EXAM: 'EXAM' }, 86400000, { NONE: 0 },
    { hasBackground: () => false }, { scheduleRefresh() {} });
  return { page, state, table };
}

test('returning from the manager refreshes count and recent timetable after deletions, including the last one', async () => {
  const { page, state, table } = summaryHarness();
  await page.onPageShow();
  assert.equal(page.timetableCount, 3);
  assert.equal(page.recentTimetable.id, 'a');
  state.tables = state.tables.filter(item => item.id !== 'a');
  await page.onPageShow();
  assert.equal(page.timetableCount, 2);
  assert.equal(page.recentTimetable.id, 'b');
  assert.equal(page.currentTimetable.id, 'b');
  assert.equal(state.selectedId, '', 'clear the selection of a removed timetable');
  state.tables = [];
  await page.onPageShow();
  assert.equal(page.timetableCount, 0);
  assert.equal(page.recentTimetable, undefined);
  assert.equal(page.currentTimetable, undefined);
  assert.equal(page.hasTimetable, false);
  state.tables = [table('new')];
  await page.onPageShow();
  assert.equal(page.timetableCount, 1);
  assert.equal(page.recentTimetable.id, 'new');
});

test('a refresh started before deletion cannot restore the old count after returning to More', async () => {
  const { page, state } = summaryHarness();
  let finish, notifyRead;
  const readStarted = new Promise(resolve => { notifyRead = resolve; });
  state.events = () => {
    notifyRead();
    return new Promise(resolve => { finish = resolve; });
  };
  const oldRefresh = page.onPageShow();
  await readStarted;
  state.tables = [];
  await page.onPageShow();
  finish([]);
  await oldRefresh;
  assert.equal(page.timetableCount, 0);
  assert.equal(page.recentTimetable, undefined);
  assert.equal(page.hasTimetable, false);
});

test('More shortcuts bind changing count and recent name by reference instead of freezing builder values', () => {
  assert.match(home, /moreShortcut\(options: MoreShortcutOptions\)/);
  assert.match(home, /this\.moreShortcut\(\{\s*symbol: [^\n]+\s*title: '最近课表',\s*subtitle: this\.recentTimetable/);
  assert.match(home, /this\.moreShortcut\(\{\s*symbol: [^\n]+\s*title: '课表管理',\s*subtitle: this\.timetableCount/);
  const builder = homeMethod('  moreShortcut(', '  moreSectionTitle(');
  assert.match(builder, /Text\(options\.subtitle\)/);
  assert.match(builder, /\.onClick\(options\.action\)/);
  assert.doesNotMatch(builder, /const .* = options\.subtitle/);
});
