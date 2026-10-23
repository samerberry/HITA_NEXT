const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');
global.$r = name => ({ id: -1, type: 10001, params: [name] });
global.Curve = { EaseInOut: 'ease' };

const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
global.Scroller = class Scroller {
  currentOffset() {
    return { xOffset: 0, yOffset: 0 };
  }
};

// Execute the real controller methods with platform boundaries mocked.
// ArkUI builders are verified separately by the SDK build and device tests.
function load(file, mocks = {}, cache = new Map()) {
  file = path.resolve(root, file);
  if (cache.has(file)) return cache.get(file).exports;
  let source = fs.readFileSync(file, 'utf8');
  if (file.endsWith('ExamPage.ets') || file.endsWith('AddEventPage.ets')) {
    source = source.slice(0, source.indexOf('\n  build()')) + '\n}\n';
    source = source.replace(/^@(Entry|Component)\r?\n/gm, '')
      .replace(/@(State|Prop|StorageProp)(\([^)]*\))?\s+/g, '')
      .replace(/(?:export\s+)?struct ExamPage/, 'export class ExamPage')
      .replace('export struct EventEditorForm', 'export class EventEditorForm');
  }
  const mod = { exports: {} };
  cache.set(file, mod);
  const compiled = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const localRequire = name => {
    if (name in mocks) return mocks[name];
    if (name.startsWith('@kit.')) return {};
    if (name.endsWith('/RdbHelper') && mocks.db) {
      return { RdbHelper: { getInstance: () => mocks.db } };
    }
    if (name.endsWith('/CourseTimePickerDialog')) return { CourseTimePickerDialog: options => options };
    if (name.endsWith('/CourseTextPickerDialog')) return { CourseTextPickerDialog: options => options };
    if (name.endsWith('/CompatibleSheetMaterial')) return { CompatibleSheetMaterial: {
      isEnabled: () => false, cardColor: fallback => fallback
    } };
    if (name.endsWith('/CompatiblePickerMaterial')) return { CompatiblePickerMaterial: {
      isEnabled: () => false, textOptions: options => options, dialogMaterial: () => undefined
    } };
    if (name.endsWith('/TimetableSelectionStore')) {
      return { TimetableSelectionStore: { getInstance: () => ({
        init: async () => {}, load: async () => 'current'
      }) } };
    }
    if (name.endsWith('/EasSessionStore')) {
      return { EasSessionStore: { getInstance: () => mocks.sessionStore || {
        init: async () => {}, loadPreferred: async () => undefined
      } } };
    }
    if (name.endsWith('/EasApiClient')) {
      return { EasApiClient: mocks.EasApiClient || class {} };
    }
    if (name.endsWith('/EasDataProvider')) {
      return { EasDataProvider: mocks.EasDataProvider || class {
        constructor() {}
        async getExamTerms() { return []; }
        async getExamResult() { return { items: [], failedTypes: [] }; }
      } };
    }
    assert.ok(name.startsWith('.'), `Unexpected platform import ${name}`);
    return load(path.resolve(path.dirname(file), name + '.ets'), mocks, cache);
  };
  new Function('require', 'module', 'exports', compiled)(localRequire, mod, mod.exports);
  return mod.exports;
}

const { EasEventItem, EasEventType } = load('common/model/timetable/TimetableModels.ets');
const clone = item => Object.assign(new EasEventItem(), item);
function exam(id, timetableId = 'original') {
  return Object.assign(new EasEventItem(), {
    id, timetableId, type: EasEventType.EXAM, name: 'Same name',
    place: 'M-101', teacher: 'Teacher', subjectId: 'subject-a',
    from: new Date(2026, 9, 3, 9).getTime(), to: new Date(2026, 9, 3, 11).getTime(),
    fromNumber: 1, lastNumber: 2, createdAt: 1234
  });
}
function setup(seeds = [exam('a'), exam('b', 'current')], extras = {}) {
  const rows = new Map(seeds.map(e => [e.id, clone(e)]));
  const calls = { updates: [], inserts: [], deletes: [], colors: [], toasts: [], dialogs: [] };
  const db = {
    init: async () => {},
    getTimetables: async () => [{ id: 'current' }, { id: 'original' }],
    getTimetableById: async id => ['current', 'original'].includes(id) ? { id } : undefined,
    getEventsOfTimetable: async id => [...rows.values()].filter(e => e.timetableId === id).map(clone),
    getEventById: async id => rows.has(id) ? clone(rows.get(id)) : undefined,
    saveEvent: async e => { calls.inserts.push(e.id); rows.set(e.id, clone(e)); },
    updateEvent: async e => { calls.updates.push(e.id); rows.set(e.id, clone(e)); },
    saveExamColor: async (id, timetableId, color) => {
      const row = rows.get(id);
      if (!row || row.timetableId !== timetableId || row.type !== EasEventType.EXAM) {
        throw new Error('Exam no longer exists');
      }
      calls.colors.push({ id, timetableId, color });
      row.color = color;
    },
    deleteEvent: async id => { calls.deletes.push(id); rows.delete(id); }
  };
  const prompt = {
    showToast: item => calls.toasts.push(item.message),
    showDialog: async options => { calls.dialogs.push(options); return { index: 0 }; }
  };
  const ui = {
    animateTo: (_options, callback) => callback(),
    getHostContext: () => ({}),
    getRouter: () => ({ getParams: () => ({ id: 'unrelated-route-id' }), back: () => {} }),
    getPromptAction: () => prompt
  };
  const mocks = Object.assign({ db }, extras);
  const { ExamPage } = load('pages/ExamPage.ets', mocks);
  const { EventEditorForm } = load('pages/AddEventPage.ets', mocks);
  const page = new ExamPage();
  page.getUIContext = () => ui;
  const editor = new EventEditorForm();
  editor.getUIContext = () => ui;
  editor.sheetMode = true;
  editor.initialType = 'EXAM';
  editor.targetTimetableId = 'current';
  return { page, editor, rows, calls, db, prompt };
}

test('list keeps event identity, filters courses and sorts by time across timetables', async () => {
  const a = exam('a');
  const b = exam('b', 'current');
  b.from -= 86400000;
  const course = exam('class');
  course.type = EasEventType.CLASS;
  const { page } = setup([a, b, course]);
  await page.onPageShow();
  assert.deepEqual(page.exams.map(e => e.id), ['b', 'a']);
  assert.equal(page.exams[1].timetableId, 'original');
  const source = read('pages/ExamPage.ets');
  assert.match(source, /\(it: EasEventItem\) => it\.id/);
  assert.match(source, /eventId: this\.sheetEventId/);
  assert.match(source, /onClick\(\(\) => this\.openExamDetail\(it\)\)/);
  assert.match(source, /\.width\(18\)\s*\.height\(54\)\s*\.borderRadius\(9\)/);
  const list = source.slice(source.indexOf('List({ space: 8, scroller: this.pageScroller })'), source.indexOf('.bindSheet('));
  assert.match(list, /this\.examCard\(it\)/);
  assert.doesNotMatch(list, /openEditExam|confirmDeleteExam|sys\.symbol\.trash/);
  const detail = source.slice(source.indexOf('private examDetailSheet('));
  assert.match(detail, /Text\('编辑'\)[\s\S]*?this\.openEditExam\(event\)/);
  assert.match(detail, /Row\(\) \{\s*Blank\(\)\s*Text\('删除考试'\)/);
  assert.match(detail, /this\.confirmDeleteExam\(event\)/);
  const editor = read('pages/AddEventPage.ets');
  assert.match(editor, /\.layoutWeight\(1\)/);
  assert.match(editor, /Column\(\) \{[\s\S]*?Button\(this\.loading \? '正在读取'/);
  assert.match(editor, /\.padding\(\{[\s\S]*?top: 8,[\s\S]*?bottom: 10/);
  assert.match(source, /this\.headerAction\('查询'/);
  assert.match(source, /this\.headerAction\('添加'/);
  assert.match(source, /private headerAction\(label: string, enabled: boolean/);
  assert.match(read('pages/TimetableDetailPage.ets'),
    /height: this\.eventSheetMode === 2 \? '78%' : SheetSize\.FIT_CONTENT/);
});

test('editing targets the original timetable while adding uses current selection', async () => {
  const { page } = setup();
  page.openExamDetail(exam('a'));
  assert.equal(page.examSheetMode, 1);
  assert.equal(page.selectedExam.id, 'a');
  page.openEditExam(exam('a'));
  assert.equal(page.examSheetMode, 2);
  assert.equal(page.sheetEventId, 'a');
  assert.equal(page.targetTimetableId, 'original');
  assert.equal(page.sheetVisible, true);
  page.closeSheet();
  assert.equal(page.sheetEventId, 'a', 'keep identity during sheet dismissal');
  page.resetSheetState();
  await page.openAddExam();
  assert.equal(page.sheetEventId, '');
  assert.equal(page.targetTimetableId, 'current');
  assert.equal(page.examSheetMode, 2);
  assert.equal(page.selectedExam, undefined);
});

test('cancelled or dismissed deletion never writes to the database', async () => {
  const { page, prompt, calls } = setup();
  page.openExamDetail(exam('a'));
  await page.confirmDeleteExam(exam('a'));
  prompt.showDialog = async () => { throw new Error('dismissed'); };
  await page.confirmDeleteExam(exam('a'));
  assert.deepEqual(calls.deletes, []);
  assert.equal(page.pendingDeleteId, '');
  assert.equal(page.sheetVisible, true, 'cancellation keeps the detail sheet open');
});

test('confirmed deletion removes only the chosen ID, even with duplicate names and times', async () => {
  const { page, rows, prompt, calls } = setup();
  page.openExamDetail(exam('a'));
  prompt.showDialog = async () => ({ index: 1 });
  await page.confirmDeleteExam(exam('a'));
  assert.deepEqual(calls.deletes, ['a']);
  assert.equal(rows.has('b'), true);
  assert.deepEqual(page.exams.map(e => e.id), ['b']);
  assert.equal(page.pendingDeleteId, '');
  assert.equal(page.sheetVisible, false);
});

test('exam particles wait for sheet dismissal and are skipped after leaving the page', async () => {
  const { page, rows, prompt } = setup();
  await page.onPageShow();
  page.openExamDetail(exam('a'));
  prompt.showDialog = async () => ({ index: 1 });
  let finishEffect;
  page.deleteEffects.register('a', {
    start: finish => {
      assert.equal(rows.has('a'), false, 'the database deletion already succeeded');
      assert.equal(page.sheetVisible, false);
      finishEffect = finish;
    },
    stop: () => {}
  });
  const deletion = page.confirmDeleteExam(exam('a'));
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(finishEffect, undefined, 'particles must not start underneath the sheet');
  assert.equal(page.exams.length, 2, 'keep the visible card until the effect completes');
  page.finishDeleteSheetDismissal();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(typeof finishEffect, 'function');
  page.onPageHide();
  await deletion;
  assert.deepEqual(page.exams.map(e => e.id), ['b']);
  assert.equal(page.pendingDeleteId, '');
  assert.equal(page.deleteSheetTimer, -1);
});

test('a failed refresh after deletion cannot resurrect the deleted exam card', async () => {
  const { page, db, prompt } = setup();
  await page.onPageShow();
  prompt.showDialog = async () => ({ index: 1 });
  db.getTimetables = async () => { throw Error('read failed'); };
  await page.confirmDeleteExam(exam('a'));
  assert.deepEqual(page.exams.map(e => e.id), ['b']);
  assert.equal(page.loadError, true);
});

test('delete failure keeps the entry and displays an error; overlapping confirmations are blocked', async () => {
  const { page, prompt, db, rows, calls } = setup();
  page.openExamDetail(exam('a'));
  let resolve;
  prompt.showDialog = () => new Promise(done => { resolve = done; });
  db.deleteEvent = async () => { throw new Error('database unavailable'); };
  const first = page.confirmDeleteExam(exam('a'));
  await page.confirmDeleteExam(exam('b'));
  assert.equal(page.pendingDeleteId, 'a');
  resolve({ index: 1 });
  await first;
  assert.equal(rows.size, 2);
  assert.ok(calls.toasts.includes('删除失败，请重试'));
  assert.equal(page.pendingDeleteId, '');
  assert.equal(page.sheetVisible, true);
  assert.equal(page.examSheetMode, 1);
});

test('exam loading errors reset loading state without discarding the last list', async () => {
  const { page, db } = setup();
  await page.loadExams();
  db.getTimetables = async () => { throw new Error('unavailable'); };
  await page.loadExams();
  assert.equal(page.loadError, true);
  assert.equal(page.loading, false);
  assert.equal(page.exams.length, 2);
});

test('editor restores exam fields and updates in place without changing its identity or metadata', async () => {
  const original = exam('a');
  const { editor, calls, rows, page } = setup();
  editor.eventId = original.id;
  await editor.aboutToAppear();
  assert.equal(editor.sheetTitle(), '编辑考试');
  assert.equal(editor.name, original.name);
  assert.equal(editor.place, original.place);
  assert.equal(editor.teacher, original.teacher);
  assert.equal(editor.hour, 9);
  assert.equal(editor.endHour, 11);
  let saved = 0;
  editor.onSaved = () => { saved++; };
  editor.name = 'Updated exam';
  editor.place = 'M-202';
  editor.teacher = 'Updated teacher';
  editor.dayOffset++;
  editor.hour = 10;
  editor.endHour = 12;
  await editor.save();
  const updated = rows.get('a');
  for (const key of ['id', 'timetableId', 'type', 'subjectId', 'createdAt', 'fromNumber', 'lastNumber']) {
    assert.equal(updated[key], original[key], key);
  }
  assert.equal(updated.name, 'Updated exam');
  assert.equal(updated.place, 'M-202');
  assert.equal(updated.teacher, 'Updated teacher');
  assert.equal(updated.from, original.from + 25 * 3600000);
  assert.equal(updated.to, original.to + 25 * 3600000);
  assert.deepEqual(calls.updates, ['a']);
  assert.deepEqual(calls.inserts, []);
  assert.equal(saved, 1);
  await page.loadExams();
  assert.equal(page.exams.find(e => e.id === 'a').name, 'Updated exam');
});

test('adding from a sheet ignores unrelated route IDs and saving twice inserts only once', async () => {
  const { editor, rows, calls } = setup();
  await editor.aboutToAppear();
  assert.equal(editor.sheetTitle(), '添加考试');
  editor.name = 'New exam';
  await Promise.all([editor.save(), editor.save()]);
  assert.equal(calls.inserts.length, 1);
  const created = rows.get(calls.inserts[0]);
  assert.equal(created.type, EasEventType.EXAM);
  assert.equal(created.timetableId, 'current');
  assert.equal(editor.saving, false);
});

test('an old pending save cannot dismiss a newly opened sheet', async () => {
  const { editor, db, calls } = setup();
  editor.eventId = 'a';
  await editor.aboutToAppear();
  let finish;
  db.updateEvent = () => new Promise(resolve => { finish = resolve; });
  let notified = 0;
  editor.onSaved = () => { notified++; };
  const saving = editor.save();
  await new Promise(resolve => setImmediate(resolve));
  editor.aboutToDisappear();
  finish();
  await saving;
  assert.equal(notified, 0);
  assert.deepEqual(calls.toasts, []);
});

test('no timetable cannot open an orphan new exam, and failed loading cannot enable saving', async () => {
  const { page, editor, db, calls } = setup();
  db.getTimetables = async () => [];
  db.getTimetableById = async () => undefined;
  await page.openAddExam();
  assert.equal(page.sheetVisible, false);
  assert.equal(page.examSheetMode, 0);
  assert.ok(calls.toasts.includes('请先在课表管理中新建课表'));
  editor.eventId = 'a';
  db.getEventById = async () => { throw new Error('read failure'); };
  await editor.aboutToAppear();
  editor.name = 'Draft';
  await editor.save();
  assert.equal(editor.loadFailed, true);
  assert.equal(editor.loading, false);
  assert.deepEqual(calls.updates, []);
  assert.deepEqual(calls.inserts, []);
});

test('editing old exams preserves dates outside the new-entry date offset limit', async () => {
  const old = exam('old');
  old.from = new Date(2020, 1, 3, 9).getTime();
  old.to = new Date(2020, 1, 3, 11).getTime();
  const { editor, rows } = setup([old]);
  editor.eventId = old.id;
  await editor.aboutToAppear();
  await editor.save();
  assert.equal(rows.get(old.id).from, old.from);
  assert.equal(rows.get(old.id).to, old.to);
});

test('failed saves remain open, preserve stored data and permit retry', async () => {
  const { editor, db, rows } = setup();
  editor.eventId = 'a';
  await editor.aboutToAppear();
  const update = db.updateEvent;
  db.updateEvent = async () => { throw new Error('write failure'); };
  let saved = 0;
  editor.onSaved = () => { saved++; };
  editor.name = 'Retry name';
  await editor.save();
  assert.equal(saved, 0);
  assert.equal(editor.saved, false);
  assert.equal(editor.saving, false);
  assert.equal(editor.hint, '保存失败，请重试');
  assert.equal(rows.get('a').name, 'Same name');
  db.updateEvent = update;
  await editor.save();
  assert.equal(saved, 1);
  assert.equal(rows.get('a').name, 'Retry name');
});

test('missing events cannot be saved or accidentally recreated', async () => {
  for (const removedBeforeLoad of [true, false]) {
    const { editor, rows, calls } = setup();
    editor.eventId = 'a';
    if (removedBeforeLoad) rows.delete('a');
    await editor.aboutToAppear();
    rows.delete('a');
    editor.name = 'Stale edit';
    await editor.save();
    assert.equal(editor.loadFailed, true);
    assert.equal(rows.has('a'), false);
    assert.deepEqual(calls.inserts, []);
    assert.deepEqual(calls.updates, []);
  }
});

test('invalid names and time ranges do not write data', async () => {
  const { editor, calls } = setup();
  await editor.aboutToAppear();
  editor.name = '  ';
  await editor.save();
  assert.equal(editor.hint, '请填写名称');
  editor.name = 'Exam';
  editor.endHour = editor.hour;
  editor.endMinute = editor.minute;
  await editor.save();
  assert.equal(editor.hint, '结束时间必须晚于开始时间');
  assert.deepEqual(calls.inserts, []);
});

test('RDB edit uses a single UPDATE, preserves all columns and refuses missing IDs', async () => {
  class Predicates {
    constructor(table) { this.table = table; }
    equalTo(column, value) { this.column = column; this.value = value; return this; }
  }
  const { RdbHelper } = load('common/db/RdbHelper.ets', {
    '@kit.ArkData': { relationalStore: { RdbPredicates: Predicates } },
    '@kit.PerformanceAnalysisKit': { hilog: { error: () => {} } }
  });
  const db = new RdbHelper();
  const calls = [];
  db.store = {
    update: async (values, pred) => { calls.push({ values, pred }); return 1; },
    delete: async () => assert.fail('Must not delete before updating'),
    insert: async () => assert.fail('Must not recreate an existing record')
  };
  const original = exam('a');
  await db.updateEvent(original);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].pred.value, 'a');
  assert.equal(calls[0].pred.table, 'events');
  assert.equal(calls[0].values.fromTime, original.from);
  assert.equal(calls[0].values.createdAt, original.createdAt);
  db.store.update = async () => 0;
  await assert.rejects(db.updateEvent(original), /no longer exists/);
  db.store.update = async () => { throw new Error('write failure'); };
  await assert.rejects(db.updateEvent(original), /write failure/);
});

test('upcoming and past groups split on the exam end time', async () => {
  const live = exam('live');
  live.from = Date.now() - 60 * 1000;
  live.to = Date.now() + 60 * 60 * 1000;
  const done = exam('done', 'current');
  done.from = Date.now() - 3 * 86400000;
  done.to = Date.now() - 2 * 86400000;
  const { page } = setup([live, done]);
  await page.loadExams();
  assert.deepEqual(page.upcoming.map(e => e.id), ['live']);
  assert.deepEqual(page.past.map(e => e.id), ['done']);
});

test('initial loading stays active until the remote query settles, including failure and empty results', async () => {
  for (const outcome of ['success', 'empty', 'failure']) {
    let finish;
    class Provider {
      async getExamTerms() { return [{ name: '2026秋季' }]; }
      async getExamResult() {
        return new Promise((resolve, reject) => {
          finish = () => outcome === 'failure' ? reject(new Error('考试请求网络失败')) :
            resolve({ items: outcome === 'success' ? [{ courseName: 'New', examDate: '2026-12-20',
              examTime: '09:00-11:00', examLocation: 'A101' }] : [], failedTypes: [] });
        });
      }
    }
    const { page } = setup([exam('saved')], {
      EasDataProvider: Provider,
      sessionStore: { init: async () => {}, loadPreferred: async () => ({ campus: 'SHENZHEN' }) }
    });
    assert.equal(page.preparingQuery, true);
    const shown = page.onPageShow();
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(page.loading, false, 'local read has finished');
    assert.equal(page.exams.length, 1, 'local records are preserved');
    assert.equal(page.preparingQuery, true, 'do not reveal the old list between local and remote loading');
    assert.equal(page.querying, true);
    finish();
    await shown;
    assert.equal(page.preparingQuery, false);
    assert.equal(page.querying, false);
    assert.equal(page.queryWarning, outcome === 'failure');
    assert.equal(page.remoteExams.length, outcome === 'success' ? 1 : 0);
  }
});

test('the native loading branch precedes both cached lists and empty/error result views', () => {
  const page = read('pages/ExamPage.ets');
  const build = page.slice(page.indexOf('  build()'));
  const firstBranch = build.slice(0, build.indexOf('} else if'));
  assert.match(firstBranch, /this\.preparingQuery \|\| this\.querying/);
  assert.match(firstBranch, /LoadingProgress\(\)/);
  assert.match(firstBranch, /正在刷新考试安排/);
  assert.doesNotMatch(firstBranch, /暂无考试安排|remoteExamCard|examCard/);
  assert.match(build, /Text\(this\.queryWarning \? '考试查询失败' : '暂无考试安排'\)/);
});

test('query without a session asks the user to log in', async () => {
  const { page, calls } = setup();
  await page.queryEasExams();
  assert.ok(calls.toasts.includes('请先登录教务后再查询考试'));
  assert.equal(page.remoteExams.length, 0);
});

test('failed exam queries show actionable messages without internal error details', async () => {
  const failures = [
    ['教务会话已失效，请重新登录', '教务登录已过期，请重新登录后重试'],
    ['当前校区暂不支持考试查询，请手动添加考试', '当前校区暂不支持考试查询，请手动添加考试'],
    ['HTTP 500: <html>internal server error</html>', '考试查询失败，请稍后重试']
  ];
  for (const [detail, message] of failures) {
    class FakeProvider {
      async getExamTerms() { throw new Error(detail); }
    }
    const { page, calls } = setup([exam('a')], { EasDataProvider: FakeProvider });
    page.session = { campus: 'SHENZHEN' };
    await page.queryEasExams();
    assert.equal(page.queryMsg, message);
    assert.equal(page.querying, false);
    assert.equal(page.remoteExams.length, 0);
    assert.deepEqual(calls.inserts, []);
    assert.deepEqual(calls.updates, []);
  }
});

test('eas query keeps unmatched remotes and import writes an EXAM event', async () => {
  const { EasExamItem } = load('feature/eas/model/EasModels.ets');
  const remote = Object.assign(new EasExamItem(), {
    courseName: '线性代数',
    examDate: '2026-12-20',
    examTime: '09:00-11:00',
    examLocation: 'A-101',
    examType: '期末',
    termName: '2026秋季',
    campusName: '深圳校区'
  });
  class FakeProvider {
    constructor() {}
    async getExamTerms() { return [{ name: '2026秋季' }]; }
    async getExamResult() { return { items: [remote], failedTypes: [] }; }
  }
  const { page, calls, rows } = setup([exam('a')], { EasDataProvider: FakeProvider });
  page.session = { campus: 'SHENZHEN' };
  await page.loadExams();
  await page.queryEasExams();
  assert.equal(page.remoteExams.length, 1);
  assert.equal(page.queryMsg, '', 'successful results have no extra query heading or count');
  await page.importRemoteExam(remote);
  assert.equal(calls.inserts.length, 1);
  const created = rows.get(calls.inserts[0]);
  assert.equal(created.type, EasEventType.EXAM);
  assert.equal(created.name, '线性代数');
  assert.equal(created.place, 'A-101');
  assert.equal(created.timetableId, 'current');
  assert.equal(page.remoteExams.length, 0);
});

test('exam queries use the preferred campus and the selected current term instead of the first term', async () => {
  const preferred = { campus: 'WEIHAI' };
  const current = { name: '2026秋季', isCurrent: true };
  const calls = [];
  class Provider {
    async getExamTerms(s) {
      assert.equal(s, preferred);
      return [{ name: '2027春季', isCurrent: false }, current];
    }
    async getExamResult(s, term) {
      calls.push({ s, term });
      return { items: [], failedTypes: [] };
    }
  }
  const { page } = setup([], {
    sessionStore: { init: async () => {}, loadPreferred: async () => preferred },
    EasDataProvider: Provider
  });
  await page.onPageShow();
  assert.equal(page.hasSession, true);
  assert.equal(calls.length, 1, 'entering the page automatically queries once');
  assert.equal(calls[0].s, preferred);
  assert.equal(calls[0].term, current);
  assert.match(page.queryContext, /威海校区.*2026秋季/);
  assert.match(page.queryMsg, /本学期暂无教务考试安排/);
  assert.equal(page.queryWarning, false);
  await page.queryEasExams();
  assert.equal(calls.length, 2, 'manual refresh remains available');
});

test('entering without a saved session only loads local exams and does not prompt for login', async () => {
  let requests = 0;
  class Provider { async getExamTerms() { requests++; return []; } }
  const { page, calls } = setup([exam('local')], { EasDataProvider: Provider });
  await page.onPageShow();
  assert.equal(requests, 0);
  assert.equal(page.exams.length, 1);
  assert.deepEqual(calls.toasts, []);
});

test('leaving while the page initializes prevents a late automatic query', async () => {
  for (const stage of ['session', 'local']) {
    let finish;
    let requests = 0;
    class Provider { async getExamTerms() { requests++; return []; } }
    const { page, db } = setup([], {
      sessionStore: { init: async () => {}, loadPreferred: async () => stage === 'session'
        ? new Promise(resolve => { finish = () => resolve({ campus: 'SHENZHEN' }); })
        : { campus: 'SHENZHEN' } },
      EasDataProvider: Provider
    });
    if (stage === 'local') {
      db.getTimetables = () => new Promise(resolve => { finish = () => resolve([]); });
    }
    const shown = page.onPageShow();
    await new Promise(resolve => setImmediate(resolve));
    page.onPageHide();
    finish();
    await shown;
    assert.equal(requests, 0, stage);
  }
});

test('manual query during local loading prevents a duplicate auto query', async () => {
  let finish;
  let requests = 0;
  class Provider {
    async getExamTerms() { requests++; return [{ name: '2026秋季' }]; }
    async getExamResult() { return { items: [], failedTypes: [] }; }
  }
  const { page, db } = setup([], {
    sessionStore: { init: async () => {}, loadPreferred: async () => ({ campus: 'SHENZHEN' }) },
    EasDataProvider: Provider
  });
  db.getTimetables = () => new Promise(resolve => { finish = () => resolve([]); });
  const shown = page.onPageShow();
  await new Promise(resolve => setImmediate(resolve));
  await page.queryEasExams();
  finish();
  await shown;
  assert.equal(requests, 1);
  page.onPageHide();
  db.getTimetables = async () => [];
  await page.onPageShow();
  assert.equal(requests, 2, 'returning to the page automatically refreshes');
});

test('partial exam results never claim there are no exams or that the query completed fully', async () => {
  for (const items of [[], [{ courseName: '待定考试', examDate: '', examTime: '', examLocation: '' }]]) {
    class Provider {
      async getExamTerms() { return [{ name: '2026秋季' }]; }
      async getExamResult() { return { items, failedTypes: ['补考'] }; }
    }
    const { page } = setup([], { EasDataProvider: Provider });
    page.session = { campus: 'BENBU' };
    await page.queryEasExams();
    assert.equal(page.queryWarning, true);
    assert.match(page.queryMsg, /补考查询失败/);
    assert.doesNotMatch(page.queryMsg, /本学期暂无教务考试安排/);
    assert.equal(page.remoteExams.length, items.length);
  }
});

test('late exam requests cannot replace results or dismiss loading after leaving and starting a new query', async () => {
  let finishOld;
  let finishNew;
  let requests = 0;
  class Provider {
    async getExamTerms() { return [{ name: '2026秋季' }]; }
    async getExamResult() {
      requests++;
      return new Promise(resolve => {
        if (requests === 1) finishOld = resolve;
        else finishNew = resolve;
      });
    }
  }
  const { page } = setup([], { EasDataProvider: Provider });
  page.session = { campus: 'BENBU' };
  const first = page.queryEasExams();
  await new Promise(resolve => setImmediate(resolve));
  const duplicate = page.queryEasExams();
  await duplicate;
  assert.equal(requests, 1);
  page.onPageHide();
  page.session = { campus: 'WEIHAI' };
  const second = page.queryEasExams();
  await new Promise(resolve => setImmediate(resolve));
  finishOld({ items: [{ courseName: 'Old' }], failedTypes: [] });
  await first;
  assert.equal(page.querying, true);
  assert.deepEqual(page.remoteExams, []);
  finishNew({ items: [], failedTypes: [] });
  await second;
  assert.equal(page.querying, false);
  assert.match(page.queryContext, /威海校区/);
});

test('exams without complete valid times cannot be imported as a made-up two-hour event', async () => {
  const { page, calls } = setup([]);
  for (const [examDate, examTime] of [
    ['2026-12-20', '待通知'], ['2026-12-20', '09:00'], ['2026-02-30', '09:00-11:00']
  ]) {
    await page.importRemoteExam({
      courseName: 'Pending exam', examDate, examTime, examLocation: '', examType: '期末'
    });
  }
  assert.equal(calls.inserts.length, 0);
  assert.equal(calls.toasts.filter(text => text.includes('考试时间无法识别')).length, 3);
});

test('exam color previews are drafts; saving persists one exam and survives editing and reloading', async () => {
  const { page, editor, rows, calls } = setup();
  await page.loadExams();
  const selected = page.exams.find(event => event.id === 'a');
  page.openExamDetail(selected);
  page.toggleExamColor(0xFFB24B63);
  page.examColorPreview = 0xFF123456;
  assert.equal(rows.get('a').color, 0);
  assert.equal(selected.color, 0);
  page.toggleExamColor(0xFFB24B63);
  assert.equal(page.examColorEditing, false);
  assert.equal(rows.get('a').color, 0, 'cancel does not persist the preview');
  page.toggleExamColor(0xFFB24B63);
  await page.saveExamColor(selected, 0xFF123456);
  assert.deepEqual(calls.colors, [{ id: 'a', timetableId: 'original', color: 0xFF123456 }]);
  assert.equal(rows.get('b').color, 0, 'a linked or same-name exam must keep its own color');
  assert.equal(page.selectedExam.color, 0xFF123456);
  assert.equal(page.examColorEditing, false);
  editor.eventId = 'a';
  await editor.aboutToAppear();
  editor.name = 'Renamed exam';
  await editor.save();
  await page.loadExams();
  assert.equal(page.exams.find(event => event.id === 'a').color, 0xFF123456);
  assert.equal(rows.get('a').name, 'Renamed exam');
});

test('failed exam color saves keep existing data and the color editor available for retry', async () => {
  const { page, rows, db } = setup();
  await page.loadExams();
  page.openExamDetail(page.exams[0]);
  page.toggleExamColor(0xFFB24B63);
  const save = db.saveExamColor;
  db.saveExamColor = async () => { throw new Error('disk full'); };
  await assert.rejects(page.saveExamColor(page.selectedExam, 0xFF123456), /disk full/);
  assert.equal(page.examColorEditing, true);
  assert.equal(page.savingExamColor, false);
  assert.equal(page.selectedExam.color, 0);
  assert.equal(rows.get('a').color, 0);
  db.saveExamColor = save;
  await page.saveExamColor(page.selectedExam, 0xFF123456);
  assert.equal(page.examColorEditing, false);
});

test('pending remote colors stay with the full exam identity and are preserved on import', async () => {
  const remote = {
    courseName: 'Linear algebra', examDate: '2026-12-20', examTime: '09:00-11:00',
    examLocation: 'A-101', examType: '期末', termName: '2026秋季', campusName: '本部'
  };
  const { page, rows, calls } = setup([]);
  page.openRemoteDetail(remote);
  page.toggleExamColor(page.remoteExamColor(remote));
  page.examColorPreview = 0xFF123456;
  assert.notEqual(page.remoteExamColor(remote), 0xFF123456);
  await page.saveRemoteExamColor(remote, 0xFF123456);
  assert.equal(page.remoteExamColor({ ...remote }), 0xFF123456);
  assert.notEqual(page.remoteExamColor({ ...remote, examType: '补考' }), 0xFF123456);
  assert.notEqual(page.remoteExamColor({ ...remote, campusName: '威海校区' }), 0xFF123456);
  assert.equal(calls.inserts.length, 0, 'choosing a remote color alone must not create an exam');
  await page.importRemoteExam(remote);
  assert.equal(rows.get(calls.inserts[0]).color, 0xFF123456);
  assert.equal(page.exams[0].color, 0xFF123456);
});
