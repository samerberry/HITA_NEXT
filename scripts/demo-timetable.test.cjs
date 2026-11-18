const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');

function setup() {
  const cache = new Map();
  const prefs = new Map();
  const appState = new Map();
  const tables = new Map();
  const subjects = new Map();
  const events = new Map();
  const bases = new Map();
  let requests = 0;
  global.AppStorage = { get: key => appState.get(key), setOrCreate: (key, value) => appState.set(key, value) };
  const rdb = {
    init: async () => {},
    getTimetableByEasCode: async code => [...tables.values()].find(table => table.code === code),
    getTimetableById: async id => tables.get(id),
    getSubjectsOfTimetable: async id => (subjects.get(id) || []).slice(),
    getEventsOfTimetable: async id => (events.get(id) || []).slice(),
    getImportBase: async id => (bases.get(id) || []).slice(),
    saveImportedTimetable: async (table, nextSubjects, nextEvents, replace, base) => {
      tables.set(table.id, table);
      subjects.set(table.id, nextSubjects.slice());
      events.set(table.id, nextEvents.slice());
      bases.set(table.id, base.slice());
    },
    applyTimetableMerge: async (id, addedSubjects, inserts, updates, deletes, base) => {
      const removed = new Set(deletes.map(event => event.id));
      const changed = new Map(updates.map(event => [event.id, event]));
      events.set(id, (events.get(id) || []).filter(event => !removed.has(event.id))
        .map(event => changed.get(event.id) || event).concat(inserts));
      subjects.set(id, (subjects.get(id) || []).concat(addedSubjects));
      bases.set(id, base.slice());
    }
  };
  function load(file) {
    file = path.resolve(root, file);
    if (cache.has(file)) return cache.get(file).exports;
    const mod = { exports: {} }; cache.set(file, mod);
    if (file === path.join(root, 'common/db/RdbHelper.ets')) {
      mod.exports = { RdbHelper: { getInstance: () => rdb } }; return mod.exports;
    }
    const req = name => {
      if (name === '@kit.PerformanceAnalysisKit') return { hilog: { info() {}, warn() {}, error() {} } };
      if (name === '@kit.ArkData') return { preferences: { getPreferences: async () => ({
        get: async (key, fallback) => prefs.has(key) ? prefs.get(key) : fallback,
        put: async (key, value) => { prefs.set(key, value); },
        delete: async key => { prefs.delete(key); }, flush: async () => {}
      }) } };
      if (name === '@kit.NetworkKit') return { http: { createHttp() {
        requests++; throw new Error('demo attempted a real HTTP request');
      } } };
      if (name.startsWith('@kit.')) return {};
      return load(path.resolve(path.dirname(file), name + '.ets'));
    };
    const compiled = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
    }).outputText;
    new Function('require', 'module', 'exports', compiled)(req, mod, mod.exports);
    return mod.exports;
  }
  const { DemoAccount } = load('feature/eas/demo/DemoAccount.ets');
  const { DemoTimetableData } = load('feature/eas/demo/DemoTimetableData.ets');
  const { EasDataProvider } = load('feature/eas/EasDataProvider.ets');
  const { EasApiClient } = load('feature/eas/EasApiClient.ets');
  const { EasTimetableImporter } = load('feature/eas/EasTimetableImporter.ets');
  const { EasSessionStore } = load('feature/eas/EasSessionStore.ets');
  return { load, tables, events, subjects, rdb, DemoAccount, DemoTimetableData, EasTimetableImporter,
    EasSessionStore, provider: new EasDataProvider(new EasApiClient()), getRequests: () => requests };
}

test('the compiled fixture faithfully preserves all 193 original ICS classes, teachers, locations and times', async () => {
  const h = setup();
  const { IcsParser } = h.load('common/util/ICSImport.ets');
  const original = IcsParser.parse(fs.readFileSync(path.resolve(__dirname,
    '../entry/src/main/resources/rawfile/demo/timetable-2026-2027-1.ics'), 'utf8'));
  assert.equal(original.events.length, 193);
  const demo = h.DemoAccount.createSession();
  const term = h.DemoTimetableData.term();
  const courses = await h.provider.getTimetableOfTerm(demo, term);
  const plan = await h.EasTimetableImporter.buildImport(h.rdb, demo, term, courses,
    await h.provider.getShenzhenScheduleStructure(demo, term), await h.provider.getStartDate(demo, term));
  assert.equal(plan.events.length, 193);
  assert.equal(plan.subjects.length, 21);
  assert.equal(plan.timetable.code, 'DEMO:SHENZHEN:2026-20271');
  assert.equal(plan.timetable.startTime, new Date(2026, 7, 31).getTime());
  assert.equal(plan.timetable.getWeekNumber(original.events[0].from), 2);
  for (let i = 0; i < original.events.length; i++) {
    const wanted = original.events[i];
    const actual = plan.events[i];
    assert.equal(actual.name, wanted.summary);
    assert.equal(actual.place, wanted.location);
    assert.equal(actual.teacher, /教师：([^\n]+)/.exec(wanted.description)[1].trim());
    assert.equal(actual.from, wanted.from);
    assert.equal(actual.to, wanted.to);
    const section = /第(\d+)-(\d+)节/.exec(wanted.description);
    assert.equal(actual.fromNumber, Number(section[1]));
    assert.equal(actual.lastNumber, Number(section[2]));
  }
  assert.equal(h.getRequests(), 0);
});

test('demo provider exposes a connected term with empty scores/exams without issuing HTTP', async () => {
  const h = setup();
  const demo = h.DemoAccount.createSession();
  const terms = await h.provider.getAllTerms(demo);
  const { EasSessionStatus } = h.load('feature/eas/EasSessionStatus.ets');
  assert.equal(await h.provider.checkSessionStatus(demo), EasSessionStatus.CONNECTED);
  assert.equal(terms.length, 1);
  assert.equal(terms[0].getCode(), '2026-20271');
  assert.equal((await h.provider.getExamTerms(demo))[0].getCode(), terms[0].getCode());
  const scores = await h.provider.getPersonalScores(demo, terms[0]);
  assert.equal(scores.ok, true); assert.deepEqual(scores.items, []);
  assert.deepEqual(await h.provider.getExamItems(demo, terms[0]), []);
  assert.deepEqual((await h.provider.getExamResult(demo, undefined)).items, []);
  const unknown = h.DemoTimetableData.term(); unknown.termCode = '2';
  assert.deepEqual(await h.provider.getTimetableOfTerm(demo, unknown), []);
  assert.equal(await h.provider.getStartDate(demo, unknown), undefined);
  assert.equal(h.getRequests(), 0);
});

test('repeated login/import reuses the demo timetable, preserves edits and isolates a real Shenzhen timetable', async () => {
  const h = setup();
  const { EasTimetable, EasEventItem } = h.load('common/model/timetable/TimetableModels.ets');
  const { EasCampus, EasSession } = h.load('feature/eas/EasSession.ets');
  const real = Object.assign(new EasTimetable(), { id: 'real', code: 'SHENZHEN:2026-20271', name: '真实课表' });
  const realEvent = Object.assign(new EasEventItem(), { id: 'real-class', name: '真实课程' });
  h.tables.set(real.id, real); h.events.set(real.id, [realEvent]);
  const store = h.EasSessionStore.getInstance(); await store.init({});
  const realSession = new EasSession(); realSession.campus = EasCampus.SHENZHEN;
  realSession.webCookies.set('SESSION', 'real-session'); await store.save(realSession);
  assert.equal(await store.save(h.DemoAccount.createSession(EasCampus.WEIHAI)), true);
  const first = await h.EasTimetableImporter.importCurrent({});
  assert.equal(first.success, true, first.message);
  assert.notEqual(first.timetable.id, real.id);
  assert.equal(first.timetable.code, h.DemoTimetableData.CODE);
  assert.deepEqual(first.timetable.scheduleStructure, h.DemoTimetableData.schedule());
  const firstIds = h.events.get(first.timetable.id).map(event => event.id);
  assert.equal(await store.save(h.DemoAccount.createSession(EasCampus.BENBU)), true);
  const second = await h.EasTimetableImporter.importCurrent({});
  assert.equal(second.success, true, second.message);
  assert.equal(second.timetable.id, first.timetable.id);
  assert.deepEqual(h.events.get(first.timetable.id).map(event => event.id), firstIds);
  assert.equal(h.events.get(first.timetable.id).length, 193);
  assert.equal(h.tables.size, 2);
  const retained = h.events.get(first.timetable.id); retained[0].place = '自选地点'; retained.splice(1, 1);
  const third = await h.EasTimetableImporter.importCurrent({});
  assert.equal(third.success, true, third.message);
  assert.equal(h.events.get(first.timetable.id).length, 192);
  assert.equal(h.events.get(first.timetable.id)[0].place, '自选地点');
  assert.equal(await store.save(h.DemoAccount.createSession(EasCampus.SHENZHEN)), false);
  assert.equal((await store.load(EasCampus.SHENZHEN)).webCookies.get('SESSION'), 'real-session');
  await store.save(realSession);
  assert.equal(await h.EasTimetableImporter.checkForUpdate({}, first.timetable), undefined);
  assert.deepEqual(h.events.get(real.id), [realEvent]);
  assert.equal(h.getRequests(), 0);
});
