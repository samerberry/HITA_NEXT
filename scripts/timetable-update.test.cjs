const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const WEEK = 7 * 24 * 60 * 60 * 1000;

function setup() {
  const cache = new Map();
  const prefs = new Map();
  const state = { termCalls: 0, courseCalls: 0, saves: [], merges: [], events: [], subjects: [], courses: [], terms: [],
    base: [] };
  const preferences = {
    getPreferences: async () => ({
      get: async (key, fallback) => prefs.has(key) ? prefs.get(key) : fallback,
      put: async (key, value) => { prefs.set(key, value); },
      delete: async key => { prefs.delete(key); }, flush: async () => {}
    })
  };
  const appState = new Map();
  global.AppStorage = { get: key => appState.get(key), setOrCreate: (key, value) => appState.set(key, value) };
  const fakes = {
    'common/db/RdbHelper.ets': () => ({ RdbHelper: { getInstance: () => state.rdb } }),
    'feature/eas/EasDataProvider.ets': () => ({
      EasDataProvider: class {
        constructor() { this.importWarnings = []; }
        async getAllTerms() { state.termCalls++; return state.terms; }
        async getTimetableOfTerm() { state.courseCalls++; return state.courses.map(course => Object.assign(new EasCourseItem(), course)); }
        async getLegacyCourseAttributes() { return { rows: [], diag: '' }; }
        async getStartDate() { return state.startDate; }
        async getShenzhenScheduleStructure() { return []; }
      }
    })
  };
  let EasCourseItem;
  function load(file) {
    file = path.resolve(root, file);
    if (cache.has(file)) return cache.get(file).exports;
    const mod = { exports: {} };
    cache.set(file, mod);
    const relative = path.relative(root, file).replace(/\\/g, '/');
    if (fakes[relative]) {
      mod.exports = fakes[relative]();
      return mod.exports;
    }
    const localRequire = name => {
      if (name === '@kit.ArkData') return { preferences };
      if (name === '@kit.PerformanceAnalysisKit') return { hilog: { info() {}, warn() {}, error() {} } };
      if (name.startsWith('@kit.')) return {};
      assert.ok(name.startsWith('.'), name);
      return load(path.resolve(path.dirname(file), name + '.ets'));
    };
    const output = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
    }).outputText;
    new Function('require', 'module', 'exports', output)(localRequire, mod, mod.exports);
    return mod.exports;
  }
  ({ EasCourseItem } = load('feature/eas/model/EasModels.ets'));
  const { EasTermItem } = load('feature/eas/model/EasModels.ets');
  const models = load('common/model/timetable/TimetableModels.ets');
  const { EasSession, EasCampus } = load('feature/eas/EasSession.ets');
  const { EasSessionStore } = load('feature/eas/EasSessionStore.ets');
  const { EasTimetableImporter } = load('feature/eas/EasTimetableImporter.ets');
  const { TimetableUpdateDiff, TimetableChangeKind } = load('feature/timetable/data/TimetableUpdateDiff.ets');
  const { TimetableUpdateStore } = load('feature/timetable/data/TimetableUpdateStore.ets');

  const timetable = new models.EasTimetable();
  timetable.code = 'SHENZHEN:2026-20271';
  timetable.name = '2026秋季';
  timetable.startTime = models.EasTimetable.mondayMsOf(new Date(2026, 8, 7).getTime());
  timetable.endTime = timetable.startTime + 20 * WEEK - 1;
  timetable.scheduleStructure = models.EasTimetable.getDefaultTimeStructure();
  state.startDate = timetable.startTime;
  state.rdb = {
    init: async () => {},
    getTimetableByEasCode: async code => {
      if (code !== timetable.code) return undefined;
      const copy = Object.assign(new models.EasTimetable(), timetable);
      copy.scheduleStructure = timetable.scheduleStructure;
      return copy;
    },
    getSubjectsOfTimetable: async () => state.subjects.slice(),
    getEventsOfTimetable: async () => state.events.map(event => Object.assign(new models.EasEventItem(), event)),
    getImportBase: async () => state.base.slice(),
    saveImportBase: async (id, entries) => { state.base = entries.slice(); },
    saveImportedTimetable: async (t, subjects, events, replace, base = []) => {
      state.saves.push({ t, subjects, events, replace });
      state.events = state.events.filter(event => event.type !== models.EasEventType.CLASS).concat(events);
      state.subjects = subjects.slice();
      if (base.length > 0) state.base = base.slice();
    },
    applyTimetableMerge: async (id, newSubjects, inserts, updates, deletes, base) => {
      state.merges.push({ newSubjects, inserts, updates, deletes });
      const removed = new Set(deletes.map(event => event.id));
      const changed = new Map(updates.map(event => [event.id, event]));
      state.events = state.events.filter(event => !removed.has(event.id))
        .map(event => changed.has(event.id) ? changed.get(event.id) : event).concat(inserts);
      state.subjects = state.subjects.concat(newSubjects);
      state.base = base.slice();
    }
  };
  const term = new EasTermItem();
  term.yearCode = '2026-2027'; term.yearName = '2026'; term.termCode = '1'; term.termName = '秋季'; term.isCurrent = true;
  state.terms = [term];
  const course = (name, day, begin, weeks, classroom = 'A101', teacher = '张老师') => ({
    name, dayOfWeek: day, beginSection: begin, sectionCount: 2, weekNumbers: weeks, classroom, teacher
  });
  async function login(expired = false) {
    const store = EasSessionStore.getInstance();
    await store.init({});
    const s = new EasSession();
    s.campus = EasCampus.SHENZHEN;
    s.webCookies.set('SESSION', 'synthetic');
    await store.save(s);
    if (expired) await store.markExpired(await store.load(EasCampus.SHENZHEN));
  }
  const weekOf = event => Math.floor((models.EasTimetable.mondayMsOf(event.from) - timetable.startTime) / WEEK) + 1;
  const find = (name, week) => state.events.filter(event => event.name === name && weekOf(event) === week);
  return { state, prefs, timetable, course, login, models, EasTimetableImporter, TimetableUpdateDiff,
    TimetableChangeKind, TimetableUpdateStore, find };
}

const range = (from, to) => Array.from({ length: to - from + 1 }, (_, i) => from + i);

test('a school change is applied only to untouched classes; skipped, edited and added classes stay as they are', async () => {
  const h = setup();
  await h.login();
  h.state.courses = [h.course('高等数学', 2, 3, range(1, 16)), h.course('大学物理', 4, 1, range(1, 16), 'A201')];
  assert.equal((await h.EasTimetableImporter.importCurrent({})).success, true);
  assert.equal(h.state.events.length, 32);
  assert.equal(await h.EasTimetableImporter.checkForUpdate({}, h.timetable), undefined);

  // Local changes made in the app: skip a class, edit a class, add a class.
  const skipped = h.find('高等数学', 1)[0];
  h.state.events = h.state.events.filter(event => event.id !== skipped.id);
  h.find('大学物理', 2)[0].place = '我的教室';
  const own = Object.assign(new h.models.EasEventItem(), {
    name: '自习', timetableId: h.timetable.id, from: h.timetable.startTime + 5 * 86400000 + 9 * 3600000,
    to: h.timetable.startTime + 5 * 86400000 + 11 * 3600000, fromNumber: 3, lastNumber: 4
  });
  h.state.events.push(own);
  assert.equal(await h.EasTimetableImporter.checkForUpdate({}, h.timetable), undefined,
    'local changes alone are never reported as school updates');

  // The school moves 高等数学 to another room, changes 大学物理's teacher and cancels its last week.
  h.state.courses = [h.course('高等数学', 2, 3, range(1, 16), 'B202'),
    h.course('大学物理', 4, 1, range(1, 15), 'A201', '李老师')];
  const update = await h.EasTimetableImporter.checkForUpdate({}, h.timetable);
  assert.ok(update);
  const lines = update.changes.map(change => h.TimetableUpdateDiff.describe(change));
  assert.deepEqual(lines, [
    '变更 大学物理 周四 1-2节 第1、3-15周 · 教师 张老师 → 李老师',
    '变更 高等数学 周二 3-4节 第2-16周 · 地点 A101 → B202',
    '取消 大学物理 周四 1-2节 第16周'
  ]);
  await h.EasTimetableImporter.applyUpdate({}, update);
  assert.equal(h.state.saves.length, 1, 'updates never replace the whole timetable');
  assert.equal(h.find('高等数学', 1).length, 0, 'a skipped class does not come back');
  assert.equal(h.find('高等数学', 5)[0].place, 'B202');
  assert.equal(h.find('大学物理', 2)[0].place, '我的教室', 'an edited class keeps the user version');
  assert.equal(h.find('大学物理', 2)[0].teacher, '张老师');
  assert.equal(h.find('大学物理', 3)[0].teacher, '李老师');
  assert.equal(h.find('大学物理', 16).length, 0);
  assert.ok(h.state.events.some(event => event.id === own.id), 'a class added in the app is kept');
  assert.equal(h.state.events.length, 31);
  assert.equal(await h.EasTimetableImporter.checkForUpdate({}, h.timetable), undefined);

  // The edited class stays the user's version in later updates too.
  h.state.courses[1].classroom = 'C301';
  const later = await h.EasTimetableImporter.checkForUpdate({}, h.timetable);
  await h.EasTimetableImporter.dismissUpdate({}, later);
  assert.equal(await h.EasTimetableImporter.checkForUpdate({}, h.timetable), undefined, 'declined versions stay quiet');
  assert.equal(h.find('大学物理', 3)[0].place, 'A201', 'declining writes nothing');
});

test('school additions insert new classes with their new subject, but not a class the user already added', async () => {
  const h = setup();
  await h.login();
  h.state.courses = [h.course('线性代数', 1, 1, range(1, 4))];
  await h.EasTimetableImporter.importCurrent({});
  const mine = Object.assign(new h.models.EasEventItem(), h.find('线性代数', 1)[0], { id: 'mine', name: '离散数学' });
  h.state.events.push(mine);
  h.state.courses.push(h.course('离散数学', 1, 1, [1, 2]));
  const update = await h.EasTimetableImporter.checkForUpdate({}, h.timetable);
  assert.deepEqual(update.changes.map(change => h.TimetableUpdateDiff.describe(change)),
    ['新增 离散数学 周一 1-2节 第2周 · A101']);
  assert.deepEqual(update.newSubjects.map(subject => subject.name), ['离散数学']);
  await h.EasTimetableImporter.applyUpdate({}, update);
  assert.equal(h.find('离散数学', 1).length, 1, 'the user copy is not duplicated');
  assert.equal(h.find('离散数学', 2).length, 1);
  assert.deepEqual(h.state.subjects.map(subject => subject.name).sort(), ['离散数学', '线性代数']);
});

test('timetables imported before this version adopt the current school data silently, then follow later changes', async () => {
  const h = setup();
  await h.login();
  h.state.courses = [h.course('英语', 3, 5, range(1, 8))];
  await h.EasTimetableImporter.importCurrent({});
  h.state.base = [];
  h.prefs.clear();
  await h.login();
  h.find('英语', 2)[0].teacher = '外教';
  h.state.events = h.state.events.filter(event => weekOfEvent(h, event) !== 3);
  assert.equal(await h.EasTimetableImporter.checkForUpdate({}, h.timetable), undefined);
  assert.equal(h.state.base.length, 8, 'the current school version becomes the base');
  assert.equal(h.state.merges.length, 0);
  h.state.courses[0].classroom = 'D404';
  const update = await h.EasTimetableImporter.checkForUpdate({}, h.timetable);
  assert.deepEqual(update.changes.map(change => h.TimetableUpdateDiff.describe(change)),
    ['变更 英语 周三 5-6节 第1、4-8周 · 地点 A101 → D404']);
});

test('a missing base is recorded even when the school version was already marked as seen', async () => {
  const h = setup();
  await h.login();
  h.state.courses = [h.course('英语', 3, 5, range(1, 4))];
  await h.EasTimetableImporter.importCurrent({});
  h.state.base = [];
  assert.equal(await h.EasTimetableImporter.checkForUpdate({}, h.timetable), undefined);
  assert.equal(h.state.base.length, 4, 'otherwise the next real school change would be adopted silently');
  h.state.courses[0].classroom = 'D404';
  const update = await h.EasTimetableImporter.checkForUpdate({}, h.timetable);
  assert.deepEqual(update.changes.map(change => h.TimetableUpdateDiff.describe(change)),
    ['变更 英语 周三 5-6节 第1-4周 · 地点 A101 → D404']);
});

function weekOfEvent(h, event) {
  return Math.floor((h.models.EasTimetable.mondayMsOf(event.from) - h.timetable.startTime) / WEEK) + 1;
}

test('a timetable imported by hand records its school version and base', async () => {
  const h = setup();
  await h.login();
  h.state.courses = [h.course('线性代数', 1, 1, range(1, 8))];
  const result = await h.EasTimetableImporter.importCurrent({});
  assert.equal(result.success, true, result.message);
  const seenKeys = [...h.prefs.keys()].filter(key => key.startsWith('timetable_remote_seen_'));
  assert.deepEqual(seenKeys, ['timetable_remote_seen_' + h.timetable.id]);
  assert.equal(h.state.base.length, 8);
  assert.equal(await h.EasTimetableImporter.checkForUpdate({}, h.timetable), undefined);
  assert.equal(h.state.saves.length, 1);
});

test('the check keeps the local start date and section structure', async () => {
  const h = setup();
  await h.login();
  h.state.base = [new h.models.EasImportBaseEntry('占位', 0, 1, '')];
  h.timetable.startTime += WEEK;
  h.timetable.scheduleStructure = h.timetable.scheduleStructure.slice(0, 6);
  h.state.courses = [h.course('程序设计', 3, 5, [1])];
  const update = await h.EasTimetableImporter.checkForUpdate({}, h.timetable);
  assert.equal(update.plan.timetable.startTime, h.timetable.startTime);
  assert.equal(update.plan.timetable.scheduleStructure.length, 6);
  const event = update.merge.inserts[0];
  assert.equal(h.models.EasTimetable.mondayMsOf(event.from), h.timetable.startTime);
  assert.equal(event.fromNumber, 5);
});

test('no request is made for timetables without a school source or a usable login, and empty results are ignored', async () => {
  const h = setup();
  const manual = Object.assign(new h.models.EasTimetable(), h.timetable);
  manual.code = '';
  await h.login();
  assert.equal(await h.EasTimetableImporter.checkForUpdate({}, manual), undefined);
  manual.code = 'ICS:import';
  assert.equal(await h.EasTimetableImporter.checkForUpdate({}, manual), undefined);
  assert.equal(h.state.termCalls, 0);

  const expired = setup();
  await expired.login(true);
  assert.equal(await expired.EasTimetableImporter.checkForUpdate({}, expired.timetable), undefined);
  assert.equal(expired.state.termCalls, 0);

  const empty = setup();
  await empty.login();
  empty.state.courses = [];
  assert.equal(await empty.EasTimetableImporter.checkForUpdate({}, empty.timetable), undefined);
  assert.equal(empty.state.courseCalls, 1);
});

test('the check interval survives a restart, while a missing login or a clock moved back never blocks checks', async () => {
  const HOUR = 3600000;
  const realNow = Date.now;
  let now = Date.UTC(2026, 9, 22, 12);
  Date.now = () => now;
  try {
    const anonymous = setup();
    await anonymous.EasTimetableImporter.checkForUpdate({}, anonymous.timetable, HOUR);
    assert.equal(anonymous.prefs.has('timetable_update_checked_' + anonymous.timetable.id), false,
      'without a login nothing is checked, so the next check is not delayed');

    const h = setup();
    await h.login();
    h.state.courses = [h.course('线性代数', 1, 1, range(1, 8))];
    const restart = () => { h.TimetableUpdateStore.instance = undefined; };
    await h.EasTimetableImporter.checkForUpdate({}, h.timetable, HOUR);
    assert.equal(h.state.termCalls, 1);
    assert.equal(h.prefs.get('timetable_update_checked_' + h.timetable.id), now);

    restart();
    now += HOUR - 1;
    assert.equal(await h.EasTimetableImporter.checkForUpdate({}, h.timetable, HOUR), undefined);
    assert.equal(h.state.termCalls, 1, 'a cold start within the hour sends no request');

    restart();
    now += 1;
    await h.EasTimetableImporter.checkForUpdate({}, h.timetable, HOUR);
    assert.equal(h.state.termCalls, 2);

    now -= 5 * HOUR;
    await h.EasTimetableImporter.checkForUpdate({}, h.timetable, HOUR);
    assert.equal(h.state.termCalls, 3, 'a check time in the future does not suppress checks');
  } finally {
    Date.now = realNow;
  }
});

// ---------------------------------------------------------------------------
// Pure merge
// ---------------------------------------------------------------------------

function event(models, name, from, hours = 2, extra = {}) {
  const e = new models.EasEventItem();
  e.type = models.EasEventType.CLASS;
  e.name = name; e.from = from; e.to = from + hours * 3600000;
  e.place = 'A101'; e.teacher = '张老师'; e.fromNumber = 1; e.lastNumber = 2;
  return Object.assign(e, extra);
}

test('merge pairs moved classes, merges weeks and ignores exams and ids', () => {
  const h = setup();
  const { models, TimetableUpdateDiff: Diff, TimetableChangeKind: Kind } = h;
  const start = h.timetable.startTime + 8 * 3600000;
  const local = [];
  const remote = [];
  for (let week = 0; week < 4; week++) {
    local.push(event(models, '英语', start + week * WEEK));
    remote.push(event(models, '英语', start + week * WEEK));
  }
  const base = Diff.baseMap(Diff.baseOf(local));
  assert.deepEqual(Diff.merge(h.timetable.startTime, local, base, remote).changes, []);
  const exam = event(models, '期末考试', start, 2, { type: models.EasEventType.EXAM });
  assert.deepEqual(Diff.merge(h.timetable.startTime, local.concat([exam]), base, remote).changes, []);
  assert.equal(Diff.fingerprint(remote), Diff.fingerprint(remote.slice().reverse().map(e => Object.assign(
    new models.EasEventItem(), e, { id: 'other' }))));

  remote[2] = event(models, '英语', start + 2 * WEEK + 2 * 24 * 3600000, 2, { fromNumber: 3, lastNumber: 4 });
  remote[3].teacher = '李老师';
  const plan = Diff.merge(h.timetable.startTime, local, base, remote);
  assert.deepEqual(plan.changes.map(g => g.kind), [Kind.MOVED, Kind.DETAILS]);
  assert.equal(Diff.describe(plan.changes[0]), '调整 英语 周一 1-2节 → 周三 3-4节 第3周');
  assert.equal(Diff.describe(plan.changes[1]), '变更 英语 周一 1-2节 第4周 · 教师 张老师 → 李老师');
  assert.deepEqual([plan.inserts.length, plan.updates.length, plan.deletes.length], [1, 1, 1]);
  assert.equal(plan.updates[0].id, local[3].id, 'an update keeps the local class id');
  assert.notEqual(Diff.fingerprint(remote), Diff.fingerprint(local));
});

test('merge keeps the user version in every conflict', () => {
  const h = setup();
  const { models, TimetableUpdateDiff: Diff } = h;
  const start = h.timetable.startTime + 8 * 3600000;
  const school = [0, 1, 2, 3].map(week => event(models, '化学', start + week * WEEK));
  const base = Diff.baseMap(Diff.baseOf(school));
  const local = school.map(e => Object.assign(new models.EasEventItem(), e));
  local[0].place = '实验楼';                // week 1: edited by the user
  local.splice(1, 1);                      // week 2: skipped by the user
  const added = event(models, '社团', start + 3 * 3600000);
  local.push(added);                       // added by the user
  const untouched = local.find(e => e.from === school[3].from);
  // The school cancels weeks 1 and 4 and moves the skipped week 2 class to another room.
  const remote = [Object.assign(new models.EasEventItem(), school[1], { place: 'B101' }),
    Object.assign(new models.EasEventItem(), school[2])];
  const plan = Diff.merge(h.timetable.startTime, local, base, remote);
  assert.deepEqual(plan.updates, [], 'a skipped class is not revived by a room change');
  assert.deepEqual(plan.inserts, []);
  assert.deepEqual(plan.deletes.map(e => e.id), [untouched.id],
    'an edited class survives cancellation; only the untouched cancelled class is removed');
  assert.ok(!plan.deletes.includes(added));
  const legacy = Diff.merge(h.timetable.startTime, local, undefined, remote);
  assert.deepEqual([legacy.inserts, legacy.updates, legacy.deletes, legacy.changes], [[], [], [], []]);
  assert.equal(legacy.base.length, 2);
});

test('week ranges and change rows stay readable', () => {
  const h = setup();
  const Diff = h.TimetableUpdateDiff;
  assert.equal(Diff.weeksText([1, 2, 3, 5, 7, 8]), '第1-3、5、7-8周');
  assert.equal(Diff.weeksText([9]), '第9周');
  const removed = { kind: h.TimetableChangeKind.REMOVED, name: 'NULL', slot: '周一 1-2节', newSlot: '', detail: '', weeks: [3, 4] };
  assert.equal(Diff.kindLabel(removed.kind), '取消');
  assert.equal(Diff.displayName(removed.name), '未命名课程');
  assert.equal(Diff.detailText(removed), '周一 1-2节 第3-4周');
  assert.equal(Diff.describe(removed), '取消 未命名课程 周一 1-2节 第3-4周');
});
