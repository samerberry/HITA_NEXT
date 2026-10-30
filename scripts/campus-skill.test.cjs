const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');

function loader(mocks = {}) {
  const cache = new Map();
  function load(file) {
    file = path.resolve(root, file);
    if (cache.has(file)) return cache.get(file).exports;
    const mod = { exports: {} }; cache.set(file, mod);
    let source = fs.readFileSync(file, 'utf8');
    if (file.endsWith('CampusSkillConfirmPage.ets')) {
      source = source.slice(0, source.indexOf('\n  @Builder')) + '\n}\n';
      source = source.replace(/^@(Entry|Component)\r?\n/gm, '')
        .replace(/@(State|StorageProp|Watch)(\([^)]*\))?\s*/g, '')
        .replace('struct CampusSkillConfirmPage', 'export class CampusSkillConfirmPage');
    }
    const text = ts.transpileModule(source, {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
    }).outputText;
    new Function('require', 'module', 'exports', text)(name => {
      if (mocks[name]) return mocks[name];
      for (const [suffix, value] of Object.entries(mocks)) if (name.endsWith(suffix)) return value;
      if (name.startsWith('@kit.')) return {};
      if (name.includes('/components/') || name.includes('/theme/')) return {};
      return load(path.resolve(path.dirname(file), name + '.ets'));
    }, mod, mod.exports);
    return mod.exports;
  }
  return load;
}

function harness() {
  let savedPrefs = '[]'; let flushFail = false;
  const state = { selected: 'term', table: { id: 'term', name: 'Autumn', startTime: Date.now() - 86400000 },
    events: [], notifications: 0, commits: 0, completions: [], launchFail: false };
  const db = {
    init: async () => {}, getTimetableById: async id => id === state.table?.id ? state.table : undefined,
    getEventsOfTimetable: async id => state.events.filter(e => e.timetableId === id).map(e => ({ ...e })),
    getEventById: async id => state.events.find(e => e.id === id),
    commitSkillEvent: async (event, before) => {
      const old = state.events.find(e => e.id === event.id);
      if (before && JSON.stringify(old) !== before) throw Error('课程已被修改或删除');
      if (!state.table) throw Error('目标课表已删除');
      state.events = state.events.filter(e => e.id !== event.id).concat({ ...event }); state.commits++; state.notifications++;
    }
  };
  const context = { abilityInfo: { bundleName: 'cn.berry.hitanext' }, startAbility: async () => {
    if (state.launchFail) throw Error('background');
  } };
  global.AppStorage = { setOrCreate() {} };
  const load = loader({
    '/RdbHelper': { RdbHelper: { getInstance: () => db } },
    '/TimetableSelectionStore': { TimetableSelectionStore: { getInstance: () => ({ init: async () => {}, load: async () => state.selected }) } },
    '/TimetableResolver': { TimetableResolver: { getForDisplay: async () => state.table } },
    '/ScheduleChangeSignal': { ScheduleChangeSignal: { notify: () => { state.notifications++; } } },
    '@kit.ArkData': { preferences: { getPreferences: async () => ({
      get: async () => savedPrefs, put: async (_, value) => { if (flushFail) throw Error('disk full'); savedPrefs = value; }, flush: async () => {}
    }) } },
    '@kit.AbilityKit': { scriptManager: { completeArkTSScriptInApp: async (...args) => state.completions.push(args[2]) } },
    '@kit.PerformanceAnalysisKit': { hilog: { info() {}, error() {} } }
  });
  const { CampusSkillService: service, CampusRequest } = load('feature/assistant/CampusSkillService.ets');
  const { EasEventItem } = load('common/model/timetable/TimetableModels.ets');
  const request = extra => Object.assign(new CampusRequest(), { requestKey: 'unique_key_001', name: 'Review',
    start: new Date(Math.ceil((Date.now() + 3600000) / 60000) * 60000).toISOString().replace('.000Z', 'Z'),
    end: new Date(Math.ceil((Date.now() + 7200000) / 60000) * 60000).toISOString().replace('.000Z', 'Z') }, extra);
  const event = extra => Object.assign(new EasEventItem(), { id: 'course', name: 'Math', type: 'CLASS',
    timetableId: 'term', from: Date.now() + 86400000, to: Date.now() + 90000000, fromNumber: 1, lastNumber: 2 }, extra);
  const script = new (load(path.resolve(root, '../../../skills/hita-campus/scripts/CampusSkill.ets')).default)();
  return { service, state, request, event, context, script,
    page: () => new (load('pages/CampusSkillConfirmPage.ets').CampusSkillConfirmPage)(),
    get prefs() { return JSON.parse(savedPrefs); },
    set prefs(value) { savedPrefs = JSON.stringify(value); }, failPrefs(value) { flushFail = value; } };
}

test('dates reject rollovers, ambiguous clocks, invalid hours and unbounded ranges', async () => {
  const h = harness();
  for (const date of ['2026-02-29', '2026-13-01', '2026-02-30', '11/02']) assert.throws(() => h.service.day(date));
  for (const time of ['2026-11-02T19:00:00', '2026-02-30T19:00:00+08:00', '2026-11-02T24:00:00Z']) assert.throws(() => h.service.instant(time));
  assert.equal(h.service.instant('2026-11-02T19:00:00+08:00'), Date.parse('2026-11-02T11:00:00Z'));
  await assert.rejects(h.service.query(h.context, 'schedule', h.request({ date: '2026-01-01', endDate: '2027-01-01' })), /93/);
});

test('queries honor current selection, include independent schedules and distinguish next class from exams', async () => {
  const h = harness(); const now = Date.now();
  h.state.events = [h.event({ id: 'later', from: now + 10000 }), h.event({ id: 'next', from: now + 1000 }),
    h.event({ id: 'exam', type: 'EXAM', from: now + 100 }), h.event({ id: 'other', timetableId: 'foreign', from: now + 1 }),
    h.event({ id: 'independent', type: 'OTHER', timetableId: '', from: now + 200 }), h.event({ id: 'past', from: now - 1000 })];
  assert.equal((await h.service.query(h.context, 'next', h.request())).events[0].eventId, 'next');
  assert.deepEqual((await h.service.query(h.context, 'exams', h.request())).events.map(e => e.eventId), ['exam']);
  const result = await h.service.query(h.context, 'schedule', h.request());
  assert.ok(result.events.some(e => e.eventId === 'independent'));
  assert.ok(!result.events.some(e => e.eventId === 'other'));
  h.state.selected = 'deleted'; await assert.rejects(h.service.query(h.context, 'schedule', h.request()), /课表/);
  h.state.selected = ''; assert.equal((await h.service.query(h.context, 'next', h.request())).timetable, 'Autumn');
});

test('prepare never writes; concurrent retries share one draft and changed payload rejects', async () => {
  const h = harness(), request = h.request();
  const [a, b] = await Promise.all([h.service.prepare(h.context, 'add', request), h.service.prepare(h.context, 'add', request)]);
  assert.equal(a.id, b.id); assert.equal(h.prefs.length, 1); assert.equal(h.state.commits, 0);
  await assert.rejects(h.service.prepare(h.context, 'add', h.request({ name: 'Different' })), /requestKey/);
  await h.service.finish(h.context, a.id, true); await h.service.finish(h.context, a.id, true);
  assert.equal(h.state.commits, 1); assert.equal(h.state.notifications, 1);
  assert.equal((await h.service.prepare(h.context, 'add', request)).status, 'saved');
});

test('cancel, expiry and persistence failure cannot write a timetable', async () => {
  const h = harness(); const op = await h.service.prepare(h.context, 'add', h.request());
  await h.service.finish(h.context, op.id, false); await h.service.finish(h.context, op.id, true);
  assert.equal(h.state.commits, 0); assert.equal((await h.service.operation(h.context, op.id)).status, 'cancelled');
  const op2 = await h.service.prepare(h.context, 'add', h.request({ requestKey: 'unique_key_002' }));
  const prefs = h.prefs; prefs.find(o => o.id === op2.id).createdAt -= 31 * 60000; h.prefs = prefs;
  await assert.rejects(h.service.finish(h.context, op2.id, true), /过期/);
  assert.equal((await h.service.prepare(h.context, 'add', h.request({ requestKey: 'unique_key_002' }))).status, 'expired');
  h.failPrefs(true); await assert.rejects(h.service.prepare(h.context, 'add', h.request({ requestKey: 'unique_key_003' })), /disk full/);
  assert.equal(h.state.commits, 0);
});

test('single-course edits preserve IDs and unrelated classes; stale changes and before-term edits reject', async () => {
  const h = harness(); h.state.events = [h.event(), h.event({ id: 'other' })];
  const op = await h.service.prepare(h.context, 'move', h.request({ eventId: 'course' }));
  assert.equal(op.event.id, 'course'); assert.equal(op.event.fromNumber, 0);
  h.state.events[0].teacher = 'changed';
  await assert.rejects(h.service.finish(h.context, op.id, true), /修改/); assert.equal(h.state.commits, 0);
  h.state.table.startTime = Date.now() + 86400000;
  await assert.rejects(h.service.prepare(h.context, 'add', h.request({ requestKey: 'unique_key_004' })), /开学/);
});

test('a room-only edit keeps period numbers; no-op edits cannot look already saved', async () => {
  const h = harness(); const request = h.request();
  const course = h.event({ from: Date.parse(request.start), to: Date.parse(request.end) }); h.state.events = [course];
  const op = await h.service.prepare(h.context, 'move', h.request({ eventId: course.id, place: 'New room' }));
  assert.equal(op.event.fromNumber, 1);
  await assert.rejects(h.service.prepare(h.context, 'move', h.request({ requestKey: 'unique_key_005', eventId: course.id })), /没有变化/);
  await h.service.finish(h.context, op.id, true);
  assert.equal(h.state.events[0].place, 'New room');
});

test('conflicts use the draft timetable even after the user switches tables', async () => {
  const h = harness(), request = h.request();
  h.state.events = [h.event({ from: Date.parse(request.start), to: Date.parse(request.end) })];
  const op = await h.service.prepare(h.context, 'add', request); h.state.selected = 'foreign';
  assert.equal((await h.service.conflicts(h.context, op))[0].id, 'course');
});

test('commit followed by status-store failure recovers success without a second insert', async () => {
  const h = harness(), op = await h.service.prepare(h.context, 'add', h.request());
  h.failPrefs(true); await assert.rejects(h.service.finish(h.context, op.id, true), /disk full/); h.failPrefs(false);
  assert.equal((await h.service.operation(h.context, op.id)).status, 'saved');
  await h.service.finish(h.context, op.id, true); assert.equal(h.state.commits, 1);
});

test('confirmation shows saved after a post-commit status failure, and cannot write a failed preparation', async () => {
  const h = harness(), op = await h.service.prepare(h.context, 'add', h.request());
  const page = h.page(); page.getUIContext = () => ({ getHostContext: () => h.context });
  Object.assign(page, { operation: op, operationId: op.id, busy: false });
  h.failPrefs(true); await page.finish(true);
  assert.equal(page.operation.status, 'saved'); assert.match(page.message, /已保存/);
  assert.equal(page.busy, false); assert.equal(h.state.commits, 1);
});

test('cancelling an older confirmation cannot close a newly arrived draft', async () => {
  const h = harness(), a = await h.service.prepare(h.context, 'add', h.request());
  const b = await h.service.prepare(h.context, 'add', h.request({ requestKey: 'second_key_001' }));
  const page = h.page(); let closes = 0; let release;
  page.getUIContext = () => ({ getHostContext: () => h.context, getRouter: () => ({ back: () => closes++ }) });
  Object.assign(page, { operation: a, operationId: a.id, busy: false });
  const finish = h.service.finish.bind(h.service);
  h.service.finish = async (...args) => { await new Promise(resolve => { release = resolve; }); await finish(...args); };
  const pending = page.finish(false);
  page.operationId = b.id; await page.reload(); release(); await pending;
  assert.equal(page.operation.id, b.id); assert.equal(page.operation.status, 'pending'); assert.equal(closes, 0);
  assert.equal(h.state.commits, 0);
});

test('script completes once on success, malformed input and forbidden confirmation; launch denial stays pending', async () => {
  const h = harness(), info = { context: h.context, requestCode: 'system-code' };
  await h.script.queryNextClass(info, '{}');
  await h.script.prepareSchedule(info, '{bad');
  await h.script.prepareSchedule(info, JSON.stringify({ ...h.request(), confirmed: true }));
  // Send only fields declared by this capability.
  const request = h.request(); const args = { requestKey: request.requestKey, name: request.name, start: request.start, end: request.end };
  h.state.launchFail = true; await h.script.prepareSchedule(info, JSON.stringify(args));
  assert.equal(h.state.completions.length, 4);
  assert.equal(h.state.completions[0].result.status, 'success');
  assert.equal(h.state.completions[1].code, 1); assert.equal(h.state.completions[2].code, 1);
  assert.equal(h.state.completions[3].result.status, 'pending');
  assert.equal(h.state.completions[3].result.confirmationOpened, false); assert.equal(h.state.commits, 0);
});

test('real database transaction rejects stale/deleted rows and rolls back a failed insert', async () => {
  const load = loader({ '@kit.ArkData': { relationalStore: { RdbPredicates: class {
    constructor(table) { this.table = table; this.filters = []; } equalTo(k, v) { this.filters.push([k, v]); return this; }
  } } }, '@kit.PerformanceAnalysisKit': { hilog: { error() {} } } });
  const { RdbHelper } = load('common/db/RdbHelper.ets');
  const { EasEventItem } = load('common/model/timetable/TimetableModels.ets');
  const original = Object.assign(new EasEventItem(), { id: 'c', timetableId: 't', from: 1000, to: 2000 });
  const edited = { ...original, from: 3000, to: 4000 };
  const rows = { events: [RdbHelper.eventValues(original)], timetable: [{ id: 't', startTime: 0, endTime: 5000 }] };
  let fail = false;
  const db = new RdbHelper(); db.store = { createTransaction: async () => {
    const next = structuredClone(rows);
    const matching = pred => next[pred.table].filter(r => pred.filters.every(([k, v]) => r[k] === v));
    return {
      query: async pred => { const r = matching(pred)[0]; return { goToNextRow: () => !!r, goToFirstRow: () => !!r,
        getColumnIndex: k => k, getLong: k => Number(r[k] || 0), getString: k => String(r[k] || ''), close() {} }; },
      update: async (value, pred) => { if (fail) throw Error('disk full'); const found = matching(pred); found.forEach(r => Object.assign(r, value)); return found.length; },
      insert: async (table, value) => { if (fail) throw Error('disk full'); next[table].push({ ...value }); return 1; },
      commit: async () => Object.assign(rows, next), rollback: async () => {}
    };
  } };
  await db.commitSkillEvent(edited, JSON.stringify(original)); assert.equal(rows.events[0].fromTime, 3000);
  await db.commitSkillEvent(edited, JSON.stringify(original)); assert.equal(rows.events.length, 1);
  rows.events[0].teacher = 'new';
  await assert.rejects(db.commitSkillEvent({ ...edited, from: 5000 }, JSON.stringify(original)), /修改或删除/);
  rows.events = []; await assert.rejects(db.commitSkillEvent(edited, JSON.stringify(original)), /修改或删除/);
  fail = true; await assert.rejects(db.commitSkillEvent(edited, ''), /disk full/); assert.equal(rows.events.length, 0);
  fail = false; rows.timetable = []; await assert.rejects(db.commitSkillEvent(edited, ''), /课表已删除/);
});
