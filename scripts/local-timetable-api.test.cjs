const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const mirrorPath = '/app/files/active_timetable_id.txt';
const dayAt = (day, hour = 0, month = 9, year = 2026) => new Date(year, month, day, hour).getTime();

function harness() {
  const state = { selected: 'selected', mirror: undefined, tables: [], events: [], fail: '', calls: [] };
  const rdb = {
    async init() { if (state.fail === 'init') throw Error('private database path'); },
    async getTimetables(strict) {
      assert.equal(strict, true);
      if (state.fail === 'tables') throw Error('private database path');
      return [...state.tables].sort((a, b) => b.startTime - a.startTime);
    },
    async getTimetableById(id, strict) {
      assert.equal(strict, true);
      if (state.fail === 'table') throw Error('private database path');
      return state.tables.find(table => table.id === id);
    },
    async getEventsOfTimetable(id, strict) {
      assert.equal(strict, true);
      state.calls.push(id);
      if (state.fail === 'events' || (state.fail === 'standalone' && id === '')) throw Error('private database path');
      return state.events.filter(event => event.timetableId === id).map(event => Object.assign(Object.create(Object.getPrototypeOf(event)), event));
    }
  };
  const overrides = {
    '@kit.PerformanceAnalysisKit': { hilog: { info() {}, warn() {}, error() {} } },
    '@kit.AbilityKit': { InsightIntentExecutor: class {} },
    '@kit.ArkData': { preferences: { getPreferences: async () => {
      if (state.fail === 'preferences') throw Error('private preference path');
      return { get: async key => { assert.equal(key, 'active_timetable_id'); return state.selected; } };
    } } },
    '@kit.CoreFileKit': { fileIo: {
      accessSync: file => { assert.equal(file, mirrorPath); return state.mirror !== undefined; },
      readTextSync: file => {
        assert.equal(file, mirrorPath);
        if (state.fail === 'mirror') throw Error('private mirror path');
        return state.mirror;
      }
    } },
    '@kit.LocalizationKit': { i18n: { getTimeZone: () => ({ getID: () => {
      if (state.fail === 'timezone') throw Error('not available');
      return Intl.DateTimeFormat().resolvedOptions().timeZone;
    } }) } },
    '@kit.NetworkKit': { http: { createHttp: () => { throw Error('Local query must not access the network'); } } }
  };
  const cache = new Map();
  function load(file, reload = false) {
    file = path.resolve(root, file);
    if (reload) cache.delete(file);
    if (cache.has(file)) return cache.get(file).exports;
    const mod = { exports: {} }; cache.set(file, mod);
    const compiled = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
    }).outputText;
    new Function('require', 'module', 'exports', compiled)(name => {
      if (name.endsWith('/RdbHelper')) return { RdbHelper: { getInstance: () => rdb } };
      if (overrides[name]) return overrides[name];
      if (name.startsWith('@kit.')) return {};
      return load(path.resolve(path.dirname(file), name + '.ets'));
    }, mod, mod.exports);
    return mod.exports;
  }
  const model = load('common/model/timetable/TimetableModels.ets');
  const table = (id, code = 'BENBU:' + id) => Object.assign(new model.EasTimetable(), {
    id, code, name: '课表 ' + id, startTime: dayAt(31, 0, 7), endTime: dayAt(1, 0, 1, 2027) - 1
  });
  const event = (id, date = 30, type = 'CLASS', timetableId = 'selected') => Object.assign(new model.EasEventItem(), {
    id, type, timetableId, subjectId: 'math', name: '高等数学', teacher: '张老师', place: 'A101',
    from: dayAt(date, 8), to: dayAt(date, 10), fromNumber: 1, lastNumber: 2
  });
  state.tables = [table('selected'), table('other')];
  state.events = [event('lesson-a'), event('lesson-b', 31), event('exam', 31, 'EXAM'),
    event('standalone', 31, 'EXAM', ''), event('foreign', 30, 'CLASS', 'other')];
  const { LocalTimetableApi: api } = load('feature/assistant/LocalTimetableApi.ets');
  const context = { getApplicationContext: () => ({ filesDir: '/app/files' }) };
  return { state, table, event, api, context, load, query: params => api.query(context, params) };
}

test('no-argument query returns the selected timetable and standalone events, with stable identities and no credentials', async () => {
  const h = harness();
  h.state.events[0].cookie = 'DO-NOT-EXPORT';
  h.state.tables[0].apiKey = 'DO-NOT-EXPORT';
  const response = await h.query();
  assert.equal(response.code, 0);
  assert.equal(response.result.timetableId, 'selected');
  assert.equal(response.result.total, 4);
  assert.equal(response.result.returned, 4);
  assert.equal(response.result.isComplete, true);
  assert.equal(response.result.hasMore, false);
  assert.equal(response.result.nextOffset, -1);
  assert.deepEqual(response.result.courses.map(item => item.id), ['lesson-a', 'exam', 'lesson-b', 'standalone']);
  assert.ok(response.result.courses.some(item => item.type === 'EXAM'));
  assert.match(response.result.currentTime, /^\d{4}-\d{2}-\d{2}T.*[+-]\d{2}:\d{2}$/);
  assert.equal(response.result.timeZone, Intl.DateTimeFormat().resolvedOptions().timeZone);
  assert.equal(Date.parse(response.result.courses[0].startTime), dayAt(30, 8));
  assert.doesNotMatch(JSON.stringify(response), /DO-NOT-EXPORT|cookie|apiKey|color|createdAt/);
});

test('fresh selection mirror wins over stale preferences and does not rewrite preferences or files', async () => {
  const h = harness();
  h.state.mirror = 'other\n';
  h.state.fail = 'preferences';
  const result = await h.query();
  assert.equal(result.code, 0);
  assert.equal(result.result.timetableId, 'other');
  assert.deepEqual(result.result.courses.map(item => item.id), ['foreign', 'standalone']);
});

test('stale selection uses imported-first fallback, while an explicitly selected local timetable stays selected', async () => {
  const h = harness();
  const local = h.table('local', 'LOCAL:custom');
  local.startTime += 86400000;
  h.state.tables.unshift(local);
  h.state.selected = 'deleted';
  assert.equal((await h.query()).result.timetableId, 'selected');
  h.state.selected = 'local';
  assert.equal((await h.query()).result.timetableId, 'local');
  h.state.selected = '';
  h.state.tables = [h.table('demo', 'LOCAL_DEMO_001'), local];
  assert.equal((await h.query()).result.timetableId, 'local');
});

test('no timetable, an empty timetable, and unreadable data have distinct results', async () => {
  const h = harness();
  h.state.tables = [];
  let response = await h.query();
  assert.equal(response.code, 1);
  assert.equal(response.result.hasTimetable, false);
  assert.equal(response.result.isComplete, false);
  h.state.tables = [h.table('selected')]; h.state.events = [];
  response = await h.query();
  assert.equal(response.code, 0);
  assert.equal(response.result.hasTimetable, true);
  assert.equal(response.result.total, 0);
  assert.equal(response.result.isComplete, true);
  h.state.fail = 'events';
  assert.equal((await h.query()).code, 3);
});

test('selection, initialization, fallback, and event failures never become a successful empty answer', async () => {
  for (const failure of ['init', 'table', 'tables', 'events', 'standalone', 'preferences', 'mirror']) {
    const h = harness(); h.state.fail = failure;
    if (failure === 'tables') h.state.selected = '';
    if (failure === 'mirror') h.state.mirror = 'selected';
    const response = await h.query();
    assert.equal(response.code, 3, failure);
    assert.equal(response.result.isComplete, false, failure);
    assert.deepEqual(response.result.courses, [], failure);
    assert.doesNotMatch(JSON.stringify(response), /private/, failure);
  }
  const h = harness(); h.state.selected = 42;
  assert.equal((await h.query()).code, 3);
});

test('date ranges include the whole end day, accept a single date, and include overlapping overnight lessons', async () => {
  const h = harness();
  h.state.events.push(Object.assign(h.event('overnight', 29), { from: dayAt(29, 23), to: dayAt(30, 1) }));
  let response = await h.query({ startDate: '2026-10-30' });
  assert.equal(response.code, 0);
  assert.equal(response.result.endDate, '2026-10-30');
  assert.deepEqual(response.result.courses.map(item => item.id), ['overnight', 'lesson-a']);
  response = await h.query({ endDate: '2026-10-30' });
  assert.equal(response.result.startDate, '2026-10-30');
  assert.equal(response.result.total, 2);
  response = await h.query({ startDate: '2026-10-30', endDate: '2026-10-31' });
  assert.equal(response.result.total, 5);
  response = await h.query({ startDate: '2026-11-01' });
  assert.equal(response.code, 0);
  assert.equal(response.result.total, 0);
});

test('local calendar boundaries are correct across daylight saving transitions', async () => {
  const h = harness();
  h.state.events = [
    Object.assign(h.event('early'), { from: dayAt(8, 0, 2), to: dayAt(8, 1, 2) }),
    Object.assign(h.event('late'), { from: dayAt(8, 23, 2), to: dayAt(9, 0, 2) }),
    Object.assign(h.event('tomorrow'), { from: dayAt(9, 0, 2), to: dayAt(9, 1, 2) })
  ];
  const result = await h.query({ startDate: '2026-03-08' });
  assert.deepEqual(result.result.courses.map(item => item.id), ['early', 'late']);
});

test('malformed dates, reversed ranges, and invalid pagination fail before touching local data', async () => {
  for (const params of [
    { startDate: '2026-02-29' }, { startDate: '2026-13-01' }, { startDate: '2026-04-31' },
    { startDate: '将来某一天' }, { startDate: '2026-10-30T00:00:00Z' }, { startDate: '0001-01-01' },
    { startDate: 12 }, { endDate: null }, { startDate: '2026-10-31', endDate: '2026-10-30' },
    { offset: -1 }, { offset: 0.5 }, { offset: '0' }, { offset: Infinity },
    { limit: 0 }, { limit: 501 }, { limit: NaN }, { limit: '2' }
  ]) {
    const h = harness();
    assert.equal((await h.query(params)).code, 2, JSON.stringify(params));
    assert.deepEqual(h.state.calls, []);
  }
  assert.equal((await harness().query({ startDate: '2028-02-29' })).code, 0);
});

test('pagination reports exact totals and never labels a later page as the whole timetable', async () => {
  const h = harness();
  const first = (await h.query({ limit: 2 })).result;
  assert.equal(first.total, 4);
  assert.equal(first.hasMore, true);
  assert.equal(first.isComplete, false);
  assert.equal(first.nextOffset, 2);
  const second = (await h.query({ limit: 2, offset: first.nextOffset })).result;
  assert.equal(second.hasMore, false);
  assert.equal(second.isComplete, false);
  assert.equal(second.nextOffset, -1);
  assert.equal(new Set(first.courses.concat(second.courses).map(item => item.id)).size, 4);
  const beyond = (await h.query({ offset: 99 })).result;
  assert.equal(beyond.total, 4);
  assert.equal(beyond.returned, 0);
  assert.equal(beyond.hasMore, false);
  assert.equal(beyond.isComplete, false);
});

test('tag rows are omitted, distinct same-time class/exam identities survive, and corrupt times fail explicitly', async () => {
  const h = harness();
  h.state.events.push(h.event('tag', 30, 'TAG'));
  assert.equal((await h.query()).result.total, 4);
  h.state.events[0].to = h.state.events[0].from;
  assert.equal((await h.query()).code, 3);
});

test('timezone label fallback still returns valid local timestamps', async () => {
  const h = harness(); h.state.fail = 'timezone';
  const response = await h.query();
  assert.equal(response.code, 0);
  assert.match(response.result.timeZone, /^UTC[+-]\d{2}:\d{2}$/);
});

test('the local reader retains the selected timetable and standalone exams without a cloud call', async () => {
  const h = harness();
  const { LocalTimetableReader } = h.load('feature/timetable/data/LocalTimetableReader.ets');
  const snapshot = await LocalTimetableReader.load(h.context);
  assert.equal(snapshot.timetable.id, 'selected');
  assert.deepEqual(snapshot.events.map(event => event.id), ['lesson-a', 'exam', 'lesson-b', 'standalone']);
  assert.deepEqual(h.state.calls, ['selected', '']);
});

test('background intent waits for application startup and returns a JSON text tool result', async () => {
  const h = harness();
  const Executor = h.load('entryability/TimetableIntentExecutor.ets').default;
  const { TimetableExecutionContext: runtime } = h.load('feature/assistant/TimetableExecutionContext.ets');
  let finishStartup;
  const startup = new Promise(resolve => { finishStartup = resolve; });
  runtime.attach(h.context, startup);
  const pending = new Executor().onExecuteInUIAbilityBackgroundMode('Timetable', { limit: 2 });
  await Promise.resolve();
  assert.deepEqual(h.state.calls, [], 'no read before backup recovery/startup completes');
  finishStartup();
  const result = await pending;
  assert.equal(result.code, 0);
  assert.equal(JSON.parse(result.result.data).returned, 2);
  assert.equal(JSON.parse(result.result.data).hasMore, true);
  assert.equal(Object.getPrototypeOf(result.result), Object.prototype);
  assert.deepEqual(JSON.parse(JSON.stringify(result)), result);
  runtime.detach(h.context);
});

test('unknown tools, missing context, failed startup and destroyed context never read a timetable', async () => {
  const h = harness();
  const Executor = h.load('entryability/TimetableIntentExecutor.ets').default;
  const { TimetableExecutionContext: runtime } = h.load('feature/assistant/TimetableExecutionContext.ets');
  const executor = new Executor();
  assert.equal((await executor.onExecuteInUIAbilityBackgroundMode('OtherTool', {})).code, 4);
  assert.equal((await executor.onExecuteInUIAbilityBackgroundMode('Timetable', {})).code, 3);
  runtime.attach(h.context, Promise.reject(Error('private recovery details')));
  let result = await executor.onExecuteInUIAbilityBackgroundMode('Timetable', {});
  assert.equal(result.code, 3);
  assert.doesNotMatch(JSON.stringify(result), /private/);
  let finishStartup;
  runtime.attach(h.context, new Promise(resolve => { finishStartup = resolve; }));
  const pending = executor.onExecuteInUIAbilityBackgroundMode('Timetable', {});
  runtime.detach(h.context); finishStartup(); result = await pending;
  assert.equal(result.code, 3);
  assert.deepEqual(h.state.calls, []);
});

test('system reloading the intent entry preserves shared application context and startup barrier', async () => {
  const h = harness();
  const { TimetableExecutionContext: runtime } = h.load('feature/assistant/TimetableExecutionContext.ets');
  const firstEntry = h.load('entryability/TimetableIntentExecutor.ets').default;
  let ready;
  runtime.attach(h.context, new Promise(resolve => { ready = resolve; }));
  const systemEntry = h.load('entryability/TimetableIntentExecutor.ets', true).default;
  assert.notEqual(firstEntry, systemEntry, 'the system loads a fresh executor entry');
  const pending = new systemEntry().onExecuteInUIAbilityBackgroundMode('Timetable', { limit: 1 });
  await Promise.resolve();
  assert.deepEqual(h.state.calls, [], 'entry reloading must not bypass backup recovery');
  ready();
  const response = await pending;
  assert.equal(response.code, 0);
  assert.equal(JSON.parse(response.result.data).returned, 1);
  runtime.detach(h.context);
});

test('an older ability cannot detach a newer context or finish a query against replacement startup state', async () => {
  const h = harness();
  const { TimetableExecutionContext: runtime } = h.load('feature/assistant/TimetableExecutionContext.ets');
  const Executor = h.load('entryability/TimetableIntentExecutor.ets').default;
  let finishOld;
  runtime.attach(h.context, new Promise(resolve => { finishOld = resolve; }));
  const pending = new Executor().onExecuteInUIAbilityBackgroundMode('Timetable', {});
  const replacement = { getApplicationContext: h.context.getApplicationContext };
  runtime.attach(replacement, Promise.resolve());
  runtime.detach(h.context);
  assert.equal(runtime.current().context, replacement);
  finishOld();
  assert.equal((await pending).code, 3);
  assert.deepEqual(h.state.calls, []);
  assert.equal((await new Executor().onExecuteInUIAbilityBackgroundMode('Timetable', {})).code, 0);
  runtime.detach(replacement);
});

test('the single declared output leaf preserves nested courses, unicode, quotes, dates and pagination', async () => {
  const h = harness();
  h.state.events[0].name = '实验："光学"\n第一组';
  h.state.events[0].place = '主楼\\北侧 A101';
  const Executor = h.load('entryability/TimetableIntentExecutor.ets').default;
  const { TimetableExecutionContext: runtime } = h.load('feature/assistant/TimetableExecutionContext.ets');
  runtime.attach(h.context, Promise.resolve());
  const output = await new Executor().onExecuteInUIAbilityBackgroundMode('Timetable', { limit: 2 });
  // Simulate a platform retaining only explicitly declared primitive output leaves.
  const visible = { code: output.code, result: { data: output.result.data } };
  assert.equal(typeof visible.result.data, 'string');
  const data = JSON.parse(visible.result.data);
  assert.equal(data.total, 4);
  assert.equal(data.returned, 2);
  assert.equal(data.hasMore, true);
  assert.equal(data.nextOffset, 2);
  assert.equal(data.courses[0].name, h.state.events[0].name);
  assert.equal(data.courses[0].place, h.state.events[0].place);
  assert.equal(data.courses[0].type, 'CLASS');
  assert.equal(data.courses[0].dayOfWeek, 5);
  assert.equal(data.courses[0].teachingWeek, 9);
  assert.equal(Date.parse(data.courses[0].startTime), h.state.events[0].from);
});

test('device input accepts optional blank values and integer text without weakening local API validation', async () => {
  const h = harness();
  const Executor = h.load('entryability/TimetableIntentExecutor.ets').default;
  const { TimetableExecutionContext: runtime } = h.load('feature/assistant/TimetableExecutionContext.ets');
  runtime.attach(h.context, Promise.resolve());
  const result = await new Executor().onExecuteInUIAbilityBackgroundMode('Timetable', {
    startDate: null, endDate: '', offset: ' 1 ', limit: '1'
  });
  assert.equal(result.code, 0);
  const data = JSON.parse(result.result.data);
  assert.equal(data.offset, 1);
  assert.equal(data.limit, 1);
  assert.equal(data.returned, 1);
  assert.equal(data.courses[0].id, 'exam');
  assert.equal((await h.query({ limit: '1' })).code, 2, 'app-local callers retain their typed contract');
});

test('device input rejects malformed numeric text and invalid dates before reading the database', async () => {
  for (const params of [
    { limit: '1x' }, { limit: '1.5' }, { limit: '0' }, { limit: '501' },
    { limit: true }, { offset: '-1' }, { offset: '9007199254740993' },
    { startDate: '2026-02-29' }, { startDate: {} }
  ]) {
    const h = harness();
    const Executor = h.load('entryability/TimetableIntentExecutor.ets').default;
    const { TimetableExecutionContext: runtime } = h.load('feature/assistant/TimetableExecutionContext.ets');
    runtime.attach(h.context, Promise.resolve());
    const result = await new Executor().onExecuteInUIAbilityBackgroundMode('Timetable', params);
    assert.equal(result.code, 2, JSON.stringify(params));
    assert.deepEqual(h.state.calls, []);
    assert.equal(JSON.parse(result.result.data).isComplete, false);
  }
});

test('JSON text transport preserves the distinction between read failures and a successful empty range', async () => {
  const h = harness();
  const Executor = h.load('entryability/TimetableIntentExecutor.ets').default;
  const { TimetableExecutionContext: runtime } = h.load('feature/assistant/TimetableExecutionContext.ets');
  runtime.attach(h.context, Promise.resolve());
  const executor = new Executor();
  h.state.fail = 'events';
  const failure = await executor.onExecuteInUIAbilityBackgroundMode('Timetable', {});
  assert.equal(failure.code, 3);
  assert.equal(JSON.parse(failure.result.data).isComplete, false);
  h.state.fail = '';
  const empty = await executor.onExecuteInUIAbilityBackgroundMode('Timetable', { startDate: '2026-11-01' });
  assert.equal(empty.code, 0);
  assert.equal(JSON.parse(empty.result.data).isComplete, true);
  assert.deepEqual(JSON.parse(empty.result.data).courses, []);
});

test('registered native intent identifies the same background tool and a real executor file', () => {
  const module = JSON.parse(fs.readFileSync(path.resolve(root, '../module.json5'), 'utf8'));
  assert.ok(module.module.metadata.some(item => item.name === 'ohos.insightIntent' && item.resource === '$profile:insight_intent'));
  const profile = JSON.parse(fs.readFileSync(path.resolve(root, '../resources/base/profile/insight_intent.json'), 'utf8'));
  const entry = profile.insightIntents.find(item => item.intentName === 'Timetable');
  assert.equal(entry.intentVersion, '0.1.0');
  assert.deepEqual(entry.uiAbility, { ability: 'EntryAbility', executeMode: ['background'] });
  assert.ok(fs.existsSync(path.resolve(root, '..', entry.srcEntry)));
});

test('teaching-week queries use the app calendar: Sep 18 is week 3, Oct 16 is week 7', async () => {
  const h = harness();
  const lesson = (id, date, month = 8) => Object.assign(h.event(id), {
    from: dayAt(date, 8, month), to: dayAt(date, 10, month)
  });
  h.state.events = [lesson('week-7-friday', 16, 9), lesson('week-3-thursday', 17),
    lesson('week-3-friday', 18), lesson('week-4-friday', 25)];
  const response = await h.query({ teachingWeek: 3, dayOfWeek: 5, limit: 10 });
  assert.equal(response.code, 0);
  assert.equal(response.result.startDate, '2026-09-18');
  assert.equal(response.result.endDate, '2026-09-18');
  assert.equal(response.result.isComplete, true);
  assert.deepEqual(response.result.courses.map(c => [c.id, c.teachingWeek, c.dayOfWeek]),
    [['week-3-friday', 3, 5]]);
  const seventh = (await h.query({ teachingWeek: 7, dayOfWeek: 5 })).result;
  assert.equal(seventh.startDate, '2026-10-16');
  assert.deepEqual(seventh.courses.map(c => c.id), ['week-7-friday']);
  const wholeWeek = (await h.query({ teachingWeek: 3 })).result;
  assert.equal(wholeWeek.startDate, '2026-09-14');
  assert.equal(wholeWeek.endDate, '2026-09-20');
  assert.equal(wholeWeek.total, 2);
  h.state.tables[0].startTime = dayAt(7, 0, 8);
  assert.equal((await h.query({ teachingWeek: 3, dayOfWeek: 5 })).result.courses[0].id,
    'week-4-friday', 'changing the app semester start changes the query without model arithmetic');
});

test('weekday filters respect date ranges and teaching-week pagination', async () => {
  const h = harness();
  const friday = (await h.query({ dayOfWeek: 5, startDate: '2026-10-26', endDate: '2026-11-01' })).result;
  assert.deepEqual(friday.courses.map(c => c.id), ['lesson-a']);
  const first = (await h.query({ teachingWeek: 9, dayOfWeek: 6, limit: 1 })).result;
  assert.equal(first.total, 3);
  assert.equal(first.hasMore, true);
  const rest = (await h.query({ teachingWeek: 9, dayOfWeek: 6, offset: first.nextOffset, limit: 10 })).result;
  assert.equal(rest.total, 3);
  assert.equal(rest.returned, 2);
  assert.equal(rest.hasMore, false);
  assert.equal((await h.query({ teachingWeek: 4, dayOfWeek: 5 })).result.total, 0);
});

test('nextClass uses the device clock, excludes exams and active classes, and preserves earliest ties', async t => {
  const h = harness();
  t.mock.method(Date, 'now', () => dayAt(31, 9));
  const timed = (id, hour, type = 'CLASS') => Object.assign(h.event(id, 31, type), {
    from: dayAt(31, hour), to: dayAt(31, hour + 2)
  });
  h.state.events = [timed('active', 8), timed('just-started', 9), timed('exam', 9, 'EXAM'),
    timed('next-b', 10), timed('later', 11), timed('next-a', 10)];
  const first = (await h.query({ queryMode: 'nextClass', limit: 1 })).result;
  assert.equal(first.queryMode, 'nextClass');
  assert.equal(first.total, 2);
  assert.equal(first.courses[0].id, 'next-a');
  assert.equal(first.hasMore, true);
  const second = (await h.query({ queryMode: 'nextClass', limit: 1, offset: first.nextOffset })).result;
  assert.equal(second.courses[0].id, 'next-b');
  assert.equal(second.hasMore, false);
  h.state.events = h.state.events.filter(c => c.from <= Date.now() || c.type === 'EXAM');
  const none = await h.query({ queryMode: 'nextClass' });
  assert.equal(none.code, 0);
  assert.equal(none.result.total, 0);
  assert.equal(none.result.isComplete, true);
});

test('currentClass includes just-started classes and excludes ended classes and exams', async t => {
  const h = harness();
  t.mock.method(Date, 'now', () => dayAt(31, 9));
  h.state.events = [h.event('active', 31), h.event('exam', 31, 'EXAM'),
    Object.assign(h.event('ended', 31), { to: dayAt(31, 9) }),
    Object.assign(h.event('started', 31), { from: dayAt(31, 9) })];
  const result = (await h.query({ queryMode: 'currentClass' })).result;
  assert.deepEqual(result.courses.map(c => c.id), ['active', 'started']);
});

test('upcomingExams returns the November exam rather than a September class with the same name', async t => {
  const h = harness();
  t.mock.method(Date, 'now', () => dayAt(31, 9));
  const at = (id, day, month, type) => Object.assign(h.event(id, day, type), {
    name: '微积分A', from: dayAt(day, 8, month), to: dayAt(day, 10, month)
  });
  h.state.events = [at('class', 14, 8, 'CLASS'), at('past-exam', 30, 9, 'EXAM'),
    at('next-exam', 7, 10, 'EXAM'), at('future-class', 1, 10, 'CLASS'),
    at('later-exam', 8, 10, 'EXAM')];
  const response = await h.query({ queryMode: 'upcomingExams', limit: 1 });
  assert.equal(response.code, 0);
  assert.equal(response.result.total, 2);
  assert.equal(response.result.courses[0].id, 'next-exam');
  assert.match(response.result.courses[0].startTime, /^2026-11-07T08:00/);
  const rest = (await h.query({ queryMode: 'upcomingExams', offset: 1, limit: 10 })).result;
  assert.deepEqual(rest.courses.map(c => c.id), ['later-exam']);
  h.state.events = h.state.events.filter(c => c.type === 'CLASS');
  const empty = (await h.query({ queryMode: 'upcomingExams' })).result;
  assert.equal(empty.total, 0);
  assert.equal(empty.isComplete, true);
});

test('invalid or conflicting semantic conditions fail before reading data', async () => {
  for (const params of [
    { teachingWeek: 0 }, { teachingWeek: 1.5 }, { teachingWeek: 1001 }, { teachingWeek: '3' },
    { dayOfWeek: 0 }, { dayOfWeek: 8 }, { dayOfWeek: true }, { queryMode: 'next' },
    { teachingWeek: 3, startDate: '2026-10-16' },
    { queryMode: 'firstClass' }, { queryMode: 'nextClass', dayOfWeek: 5 },
    { queryMode: 'currentClass', endDate: '2026-10-31' }
  ]) {
    const h = harness();
    assert.equal((await h.query(params)).code, 2, JSON.stringify(params));
    assert.deepEqual(h.state.calls, []);
  }
});

test('relative weekdays use device calendar weeks across Sunday, Monday and year boundaries', async t => {
  const h = harness();
  let now = dayAt(31, 4);
  t.mock.method(Date, 'now', () => now);
  for (const [clock, relativeDate, expected] of [
    [dayAt(31, 4), '下周一', '2026-11-02'],
    [dayAt(1, 23, 10), '下星期一', '2026-11-02'],
    [dayAt(2, 0, 10), '下周一', '2026-11-09'],
    [dayAt(31, 23, 11), 'nextMonday', '2027-01-04'],
    [dayAt(1, 1, 0, 2027), '上周日', '2026-12-27'],
    [dayAt(31, 23, 11), '明天', '2027-01-01'],
    [dayAt(28, 23, 1, 2028), '后天', '2028-03-01'],
    [dayAt(31, 4), '本周一', '2026-10-26']
  ]) {
    now = clock;
    const response = await h.query({ relativeDate });
    assert.equal(response.code, 0);
    assert.equal(response.result.startDate, expected, `${relativeDate} at ${new Date(clock)}`);
    assert.equal(response.result.endDate, expected);
  }
  const nextWeek = (await h.query({ relativeDate: 'nextWeek' })).result;
  assert.equal(nextWeek.startDate, '2026-11-02');
  assert.equal(nextWeek.endDate, '2026-11-08');
  const friday = (await h.query({ relativeDate: 'nextWeek', dayOfWeek: 5 })).result;
  assert.equal(friday.startDate, '2026-11-06');
  assert.equal(friday.endDate, '2026-11-06');
});

test('relative dates honor local calendar days across daylight-saving changes', async t => {
  const h = harness();
  // When run under America/New_York these dates cross 23- and 25-hour days.
  let now = dayAt(7, 23, 2);
  t.mock.method(Date, 'now', () => now);
  assert.equal((await h.query({ relativeDate: 'dayAfterTomorrow' })).result.startDate, '2026-03-09');
  now = dayAt(31, 23);
  const week = (await h.query({ relativeDate: 'nextWeek' })).result;
  assert.equal(week.startDate, '2026-11-02');
  assert.equal(week.endDate, '2026-11-08');
});

test('first class on a relative day excludes exams, retains earliest ties and respects pagination', async t => {
  const h = harness();
  t.mock.method(Date, 'now', () => dayAt(31, 4));
  const at = (id, day, hour, type = 'CLASS') => Object.assign(h.event(id, day, type), {
    from: dayAt(day, hour, 10), to: dayAt(day, hour + 1, 10)
  });
  h.state.events = [at('later', 2, 10), at('first-b', 2, 8), at('first-a', 2, 8),
    at('exam', 2, 7, 'EXAM'), at('note', 2, 6, 'OTHER'), at('tuesday', 3, 8),
    Object.assign(at('overnight', 1, 23), { to: dayAt(2, 1, 10) })];
  const first = await h.query({ relativeDate: '下周一', queryMode: 'firstClass', limit: 1 });
  assert.equal(first.code, 0);
  assert.equal(first.result.startDate, '2026-11-02');
  assert.equal(first.result.queryMode, 'firstClass');
  assert.equal(first.result.total, 2);
  assert.equal(first.result.hasMore, true);
  assert.equal(first.result.courses[0].id, 'first-a');
  const next = (await h.query({ relativeDate: 'nextMonday', queryMode: 'firstClass',
    offset: first.result.nextOffset, limit: 1 })).result;
  assert.equal(next.courses[0].id, 'first-b');
  assert.equal(next.hasMore, false);
  // An explicitly requested day is authoritative, even if its first class has started.
  t.mock.method(Date, 'now', () => dayAt(2, 9, 10));
  const past = (await h.query({ startDate: '2026-11-02', queryMode: 'firstClass' })).result;
  assert.deepEqual(past.courses.map(c => c.id), ['first-a', 'first-b']);
  const upcoming = (await h.query({ queryMode: 'nextClass' })).result;
  assert.deepEqual(upcoming.courses.map(c => c.id), ['later']);
  const empty = await h.query({ startDate: '2026-11-04', queryMode: 'firstClass' });
  assert.equal(empty.code, 0);
  assert.equal(empty.result.total, 0);
  assert.equal(empty.result.isComplete, true);
  h.state.events = h.state.events.filter(e => e.type !== 'CLASS');
  const noClass = (await h.query({ startDate: '2026-11-02', queryMode: 'firstClass' })).result;
  assert.equal(noClass.total, 0);
  assert.equal(noClass.isComplete, true);
});

test('scoped legacy nextClass queries return the first class in that scope without dropping its date', async t => {
  const h = harness();
  t.mock.method(Date, 'now', () => dayAt(31, 4));
  for (const scope of [
    { startDate: '2026-10-30' }, { teachingWeek: 9, dayOfWeek: 5 },
    { relativeDate: '本周五' }, { startDate: '本周五', endDate: 'thisFriday' }
  ]) {
    const response = await h.query({ ...scope, queryMode: 'nextClass' });
    assert.equal(response.code, 0);
    assert.equal(response.result.queryMode, 'firstClass');
    assert.equal(response.result.startDate, '2026-10-30');
    assert.deepEqual(response.result.courses.map(c => c.id), ['lesson-a']);
  }
});

test('ambiguous or conflicting relative dates fail before reading the database', async () => {
  for (const params of [
    { relativeDate: 1 }, { relativeDate: '下下周' }, { relativeDate: '周末以后' },
    { relativeDate: 'nextMonday', dayOfWeek: 2 }, { relativeDate: 'nextWeek', teachingWeek: 3 },
    { relativeDate: 'tomorrow', startDate: '2026-11-02' },
    { startDate: '下周一', endDate: '下周二' }, { startDate: '下周一', endDate: '2026-11-02' },
    { relativeDate: 'tomorrow', queryMode: 'currentClass' },
    { relativeDate: 'tomorrow', queryMode: 'upcomingExams' }
  ]) {
    const h = harness();
    const response = await h.query(params);
    assert.equal(response.code, 2, JSON.stringify(params));
    assert.deepEqual(h.state.calls, []);
  }
});

test('intent accepts relative dates through new and existing platform fields and transports resolved dates', async t => {
  const h = harness();
  t.mock.method(Date, 'now', () => dayAt(31, 4));
  const Executor = h.load('entryability/TimetableIntentExecutor.ets').default;
  h.load('feature/assistant/TimetableExecutionContext.ets').TimetableExecutionContext.attach(h.context, Promise.resolve());
  for (const params of [
    { relativeDate: 'nextWeek', dayOfWeek: '1', queryMode: 'firstClass' },
    { startDate: '下周一', endDate: null, queryMode: 'nextClass' }
  ]) {
    const response = await new Executor().onExecuteInUIAbilityBackgroundMode('Timetable', params);
    const data = JSON.parse(response.result.data);
    assert.equal(response.code, 0);
    assert.equal(data.startDate, '2026-11-02');
    assert.equal(data.endDate, '2026-11-02');
    assert.equal(data.queryMode, 'firstClass');
  }
});

test('intent forwards semantic parameters and adapts optional numeric strings', async () => {
  const h = harness();
  const Executor = h.load('entryability/TimetableIntentExecutor.ets').default;
  const { TimetableExecutionContext: runtime } = h.load('feature/assistant/TimetableExecutionContext.ets');
  runtime.attach(h.context, Promise.resolve());
  const result = await new Executor().onExecuteInUIAbilityBackgroundMode('Timetable', {
    teachingWeek: '9', dayOfWeek: '5', queryMode: 'range', startDate: null, limit: '10'
  });
  assert.equal(result.code, 0);
  const data = JSON.parse(result.result.data);
  assert.equal(data.startDate, '2026-10-30');
  assert.deepEqual(data.courses.map(c => c.id), ['lesson-a']);
  const invalid = await new Executor().onExecuteInUIAbilityBackgroundMode('Timetable', { teachingWeek: '3.5' });
  assert.equal(invalid.code, 2);
});
