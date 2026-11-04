const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');
const root = path.resolve(__dirname, '../entry/src/main');
function load(file, overrides = {}, cache = new Map()) {
  file = path.resolve(root, 'ets', file);
  if (cache.has(file)) return cache.get(file).exports;
  const module = { exports: {} };
  cache.set(file, module);
  const code = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  new Function('require', 'module', 'exports', code)(name => {
    if (overrides[name]) return overrides[name];
    if (name === '@kit.PerformanceAnalysisKit') return { hilog: { warn() {} } };
    if (name.startsWith('@kit.')) return {};
    return load(path.resolve(path.dirname(file), name + '.ets'), overrides, cache);
  }, module, module.exports);
  return module.exports;
}
const { NextClassModel } = load('feature/widget/NextClassModel.ets');
const now = new Date(2026, 9, 16, 8, 0).getTime();
const minute = 60000;
const course = (id, offset, overrides = {}) => ({
  id, type: 'CLASS', name: '高等数学', place: '正心楼 101', teacher: '王老师',
  from: now + offset * minute, to: now + (offset + 45) * minute, ...overrides
});
function view(events, at = now, exists = true) {
  const data = NextClassModel.snapshot(events, exists, now);
  return NextClassModel.view(data.scheduleJson, data.hasTimetable, data.dataState, at);
}
test('prefers an ongoing class over the next class and excludes exams and invalid events', () => {
  const result = view([course('late', 90), course('exam', 1, { type: 'EXAM' }),
    course('started', -10, { name: '当前课程', teacher: '李老师', place: '博学楼 101' }),
    course('negative', 2, { to: now }), course('bad', NaN),
    course('next', 15, { name: '大学物理', teacher: '陈老师', place: '格物楼 202' })]);
  assert.equal(result.title, '当前课程');
  assert.equal(result.isOngoing, true);
  assert.equal(result.countdown, '35分钟');
  assert.equal(result.countdownUnit, '后下课');
  assert.ok(Math.abs(result.progressPercent - (10 / 45 * 100)) < 0.001);
  assert.equal(result.place, '博学楼 101');
  assert.equal(result.teacher, '李老师');
  assert.equal(result.timeLabel, '今天 07:50–08:35');
});
test('cached payload shows ongoing course progress and advances when the class ends', () => {
  const events = [course('one', -30, { place: '正心楼 101', teacher: '王老师' }),
    course('two', 30, { name: '英语', place: '格物楼 202', teacher: '陈老师' })];
  const current = view(events);
  assert.equal(current.title, '高等数学');
  assert.equal(current.isOngoing, true);
  assert.equal(current.countdown, '15分钟');
  assert.equal(current.countdownUnit, '后下课');
  assert.ok(Math.abs(current.progressPercent - (30 / 45 * 100)) < 0.001);
  assert.equal(current.place, '正心楼 101');
  assert.equal(current.teacher, '王老师');
  const next = view(events, now + 15 * minute);
  assert.equal(next.title, '英语');
  assert.equal(next.isOngoing, false);
  assert.equal(next.countdown, '15分钟');
  assert.equal(next.countdownUnit, '后上课');
  assert.equal(next.place, '格物楼 202');
  assert.equal(next.teacher, '陈老师');
  const started = view(events, now + 30 * minute);
  assert.equal(started.title, '英语');
  assert.equal(started.isOngoing, true);
  assert.equal(started.countdown, '45分钟');
  assert.equal(started.countdownUnit, '后下课');
  assert.equal(started.progressPercent, 0);
  assert.equal(started.place, '格物楼 202');
  assert.equal(started.teacher, '陈老师');
  const lastMoment = view(events, now + 15 * minute - 1);
  assert.equal(lastMoment.title, '高等数学');
  assert.equal(lastMoment.place, '正心楼 101');
  assert.equal(lastMoment.teacher, '王老师');
  const liveTick = view(events, now + 30 * minute + 1000);
  assert.ok(liveTick.progressPercent > started.progressPercent);
  assert.equal(liveTick.countdown, '45分钟');
});
test('rounds up partial minutes and displays hours, days and cross-day start times', () => {
  assert.equal(view([course('one', 0.1)]).countdown, '1分钟');
  assert.equal(view([course('hour', 61)]).countdown, '1小时1分钟');
  assert.equal(view([course('tomorrow', 1440)]).title, '暂无待上课程');
  assert.equal(view([course('later', 2880 + 60)]).title, '暂无待上课程');
});

test('only displays the earliest upcoming class from the current calendar day', () => {
  const result = view([course('tomorrow', 1440), course('today', 90)]);
  assert.equal(result.title, '高等数学');
  assert.equal(result.countdown, '1小时30分钟');
});
test('uses the same latest-starting ongoing class when course times overlap', () => {
  const result = view([
    course('earlier', -30, { name: '前一节', place: '旧地点', teacher: '旧教师' }),
    course('latest', -10, { name: '正在上的课', place: '新地点', teacher: '新教师' }),
    course('next', 10, { name: '下一节课', place: '下一地点', teacher: '下一教师' })
  ]);
  assert.equal(result.title, '正在上的课');
  assert.equal(result.place, '新地点');
  assert.equal(result.teacher, '新教师');
  assert.equal(result.isOngoing, true);
});
test('represents no timetable, no upcoming classes, loading and read failures separately', () => {
  assert.equal(view([], now, false).title, '还没有课表');
  assert.equal(view([]).title, '暂无待上课程');
  assert.equal(NextClassModel.view('[]', false, 'loading', now).title, '正在读取课表');
  assert.equal(NextClassModel.view('[]', false, 'error', now).title, '课表暂不可用');
  assert.equal(NextClassModel.view('bad json', true, 'ready', now).title, '课表暂不可用');
  assert.equal(NextClassModel.view('{}', true, 'ready', now).title, '课表暂不可用');
});
test('uses fallbacks for missing fields and never exposes credentials in its bounded payload', () => {
  const result = view([course('one', 10, { name: ' NULL ', place: ' ', teacher: '' })]);
  assert.equal(result.title, '未命名课程');
  assert.equal(result.place, '地点待定');
  assert.equal(result.teacher, '教师待定');
  const events = Array.from({ length: 90 }, (_, i) => course(String(i), i + 1, { cookie: 'secret' }));
  const snapshot = NextClassModel.snapshot(events, true, now);
  assert.equal(JSON.parse(snapshot.scheduleJson).length, 64);
  assert.ok(!snapshot.scheduleJson.includes('cookie'));
  assert.ok(!snapshot.scheduleJson.includes('secret'));
  assert.equal(NextClassModel.snapshot(events, false, now).scheduleJson, '[]');
});
test('only copies the selected timetable event fields into the service-card payload', () => {
  const selected = course('selected-course', 10, {
    timetableId: 'selected', place: '课表地点 A101', teacher: '课表教师'
  });
  const other = course('other-course', 12, {
    timetableId: 'other', place: '其他地点 B202', teacher: '其他教师'
  });
  const payload = JSON.parse(NextClassModel.snapshot([selected, other], true, now, 'selected').scheduleJson);
  assert.deepEqual(payload.map(item => item.id), ['selected-course']);
  const result = NextClassModel.view(JSON.stringify(payload), true, 'ready', now);
  assert.equal(result.place, '课表地点 A101');
  assert.equal(result.teacher, '课表教师');
  assert.equal(result.timeLabel, '今天 08:10–08:55');
});
test('reads the chosen timetable, falls back when deleted, and never requests academic login', async () => {
  let selected = 'chosen';
  let exists = true;
  const readIds = [];
  const { NextClassWidgetService: service } = load('feature/widget/NextClassWidgetService.ets', {
    '../../common/db/RdbHelper': { RdbHelper: { getInstance: () => ({
      init: async () => {},
      getTimetableById: async id => exists ? { id } : undefined,
      getEventsOfTimetable: async id => {
        readIds.push(id);
        const liveNow = Date.now();
        return [
          course('selected-course', 10, {
            timetableId: id, place: '当前课表地点', teacher: '当前课表教师',
            from: liveNow + 10 * minute, to: liveNow + 55 * minute
          }),
          course('other-course', 12, {
            timetableId: 'other', place: '错课表地点', teacher: '错课表教师',
            from: liveNow + 12 * minute, to: liveNow + 57 * minute
          })
        ];
      }
    }) } },
    '../timetable/data/TimetableSelectionStore': { TimetableSelectionStore: {
      getInstance: () => ({ init: async () => {}, load: async () => 'stale-cache' }),
      loadLatest: async () => selected
    } },
    '../timetable/data/TimetableResolver': { TimetableResolver: { getForDisplay: async () => ({ id: 'fallback' }) } }
  });
  const chosenSnapshot = await service.load({}, true);
  assert.equal(chosenSnapshot.dataState, 'ready');
  const chosenView = NextClassModel.view(chosenSnapshot.scheduleJson, true, 'ready', Date.now());
  assert.equal(chosenView.place, '当前课表地点');
  assert.equal(chosenView.teacher, '当前课表教师');
  selected = 'switched';
  await service.load({}, true);
  exists = false;
  await service.load({}, true);
  assert.deepEqual(readIds, ['chosen', 'switched', 'fallback']);
  const source = fs.readFileSync(path.join(root, 'ets/feature/widget/NextClassWidgetService.ets'), 'utf8');
  assert.doesNotMatch(source, /EasApiClient|EasSessionStore|fetch/);
});
test('card-process refreshes bypass the stale per-process selection cache', async () => {
  const { NextClassWidgetService: service } = load('feature/widget/NextClassWidgetService.ets', {
    '@kit.FormKit': { formBindingData: { createFormBindingData: value => value }, formProvider: {
      updateForm: async () => {}
    } }
  });
  const calls = [];
  service.load = async (_context, fromCardProcess) => { calls.push(fromCardProcess); return { scheduleJson: '[]' }; };
  await service.refreshForm({}, 'card');
  assert.deepEqual(calls, [true]);
  // Evicting the shared preferences cache let detached instances flush the old selection back to disk,
  // so the card reads a mirror file that every selection write keeps current.
  const files = new Map();
  const fileIo = {
    OpenMode: { CREATE: 1, WRITE_ONLY: 2, TRUNC: 4 },
    accessSync: p => files.has(p),
    readTextSync: p => files.get(p),
    openSync: p => ({ fd: p }),
    writeSync: (fd, text) => files.set(fd, text),
    closeSync() {},
    renameSync: (from, to) => { files.set(to, files.get(from)); files.delete(from); }
  };
  const data = new Map([['active_timetable_id', 'old']]);
  const store = {
    get: async (key, fallback) => data.has(key) ? data.get(key) : fallback,
    put: async (key, value) => data.set(key, value),
    delete: async key => data.delete(key),
    flush: async () => {}
  };
  const { TimetableSelectionStore } = load('feature/timetable/data/TimetableSelectionStore.ets', {
    '@kit.CoreFileKit': { fileIo },
    '@kit.ArkData': { preferences: {
      removePreferencesFromCacheSync: () => assert.fail('the shared preferences cache must never be evicted'),
      getPreferences: async () => store
    } }
  });
  const context = { getApplicationContext: () => ({ filesDir: '/app' }) };
  assert.equal(await TimetableSelectionStore.loadLatest(context), '', 'no mirror yet');
  const selection = new TimetableSelectionStore();
  await selection.init(context);
  assert.equal(await TimetableSelectionStore.loadLatest(context), 'old', 'init seeds the mirror from preferences');
  await selection.save('latest');
  assert.equal(await TimetableSelectionStore.loadLatest(context), 'latest');
  assert.ok(!files.has('/app/active_timetable_id.txt.tmp'), 'writes go through a renamed temp file');
  await selection.clear();
  assert.equal(await TimetableSelectionStore.loadLatest(context), '');
});
test('refreshes each published card and tolerates a card removed during refresh', async () => {
  const published = [];
  const { NextClassWidgetService: service } = load('feature/widget/NextClassWidgetService.ets', {
    '@kit.FormKit': {
      formBindingData: { createFormBindingData: value => value },
      formProvider: {
        getPublishedRunningFormInfos: async () => [
          { formId: '1', formName: 'NextClassCard', moduleName: 'entry' },
          { formId: '2', formName: 'NextClassCard', moduleName: 'entry' },
          { formId: '3', formName: 'AnotherCard', moduleName: 'entry' }
        ],
        updateForm: async (id, data) => { published.push([id, data.dataState]); if (id === '1') throw Error('removed'); }
      }
    }
  });
  service.context = {};
  service.load = async () => ({ scheduleJson: '[]', dataState: 'ready', hasTimetable: false });
  await service.refreshAll();
  assert.deepEqual(published, [['1', 'ready'], ['2', 'ready']]);
});
test('connects saved timetable changes to the card refresh pipeline', () => {
  const timers = [];
  const originalSetTimeout = global.setTimeout;
  const originalClearTimeout = global.clearTimeout;
  global.setTimeout = callback => { timers.push(callback); return timers.length; };
  global.clearTimeout = () => {};
  try {
    const cache = new Map();
    const { NextClassWidgetService: service } = load('feature/widget/NextClassWidgetService.ets', {}, cache);
    const { ScheduleChangeSignal } = load('common/util/ScheduleChangeSignal.ets', {}, cache);
    let refreshes = 0;
    service.refreshAll = () => { refreshes++; return Promise.resolve(); };
    service.attach({ getApplicationContext: () => ({}) });
    assert.equal(timers.length, 1, 'attach schedules an initial card refresh');
    ScheduleChangeSignal.notify();
    assert.equal(timers.length, 2, 'a committed timetable change reschedules publication');
    timers[1]();
    assert.equal(refreshes, 1);
  } finally {
    global.setTimeout = originalSetTimeout;
    global.clearTimeout = originalClearTimeout;
  }
});
test('publishes edited teacher and place fields so the card follows the saved schedule', async () => {
  const published = [];
  const { NextClassWidgetService: service } = load('feature/widget/NextClassWidgetService.ets', {
    '@kit.FormKit': {
      formBindingData: { createFormBindingData: value => value },
      formProvider: {
        getPublishedRunningFormInfos: async () => [
          { formId: 'card', formName: 'NextClassCard', moduleName: 'entry' }
        ],
        updateForm: async (_id, data) => published.push(data)
      }
    }
  });
  service.context = {};
  service.backgroundFiles = () => undefined;
  let currentEvents = [course('active', -10, { place: '创建时地点', teacher: '创建时教师' })];
  service.load = async () => NextClassModel.snapshot(currentEvents, true, now);
  await service.refreshAll();
  currentEvents = [course('active', -10, { place: '编辑后地点', teacher: '编辑后教师' })];
  await service.refreshAll();

  assert.equal(published.length, 2);
  const latest = NextClassModel.view(published[1].scheduleJson, true, 'ready', now);
  assert.equal(latest.place, '编辑后地点');
  assert.equal(latest.teacher, '编辑后教师');
});
test('publishes the latest schedule when edits race a slow database read', async () => {
  const published = [];
  const { NextClassWidgetService: service } = load('feature/widget/NextClassWidgetService.ets', {
    '@kit.FormKit': { formBindingData: { createFormBindingData: value => value }, formProvider: {
      getPublishedRunningFormInfos: async () => [{ formId: '1', formName: 'NextClassCard', moduleName: 'entry' }],
      updateForm: async (_id, data) => published.push(data.scheduleJson)
    } }
  });
  service.context = {};
  let reads = 0;
  service.load = async () => {
    if (++reads === 1) { service.revision++; return { scheduleJson: 'old' }; }
    return { scheduleJson: 'new' };
  };
  await service.refreshAll();
  assert.deepEqual(published, ['new']);
});
test('registers both sizes, second-level timer updates and periodic provider refresh', () => {
  const config = JSON.parse(fs.readFileSync(path.join(root, 'resources/base/profile/next_class_form_config.json'))).forms[0];
  assert.deepEqual(config.supportDimensions, ['2*2', '2*4']);
  assert.equal(config.isDynamic, true);
  assert.equal(config.updateEnabled, true);
  assert.equal(config.updateDuration, 1);
  const module = JSON.parse(fs.readFileSync(path.join(root, 'module.json5')));
  assert.equal(module.module.extensionAbilities.find(item => item.name === 'NextClassFormAbility').type, 'form');
  const ui = fs.readFileSync(path.join(root, 'ets/widget/pages/NextClassCard.ets'), 'utf8');
  assert.ok(ui.includes('TextTimer({ isCountDown: false, controller: this.ticker })'));
  assert.match(ui, /private ticker: TextTimerController = new TextTimerController\(\)/);
  assert.match(ui, /\.onAppear\(\(\): void => this\.startTicker\(\)\)/);
  assert.match(ui, /this\.ticker\.start\(\)/);
  assert.match(ui, /\.format\('ss'\)/);
  assert.match(ui, /\.onTimer\(\(_utc: number, elapsedTime: number\): void => this\.onTick\(elapsedTime\)\)/);
  assert.match(ui, /private onTick\(elapsedTime: number\): void \{\s*this\.refreshDisplay\(\)/);
  assert.doesNotMatch(ui, /\.width\(1\)\s*\.height\(1\)/);
  assert.match(ui, /\.fontColor\('#01000001'\)/);
  assert.doesNotMatch(ui, /\.opacity\(0\)/);
  assert.doesNotMatch(ui, /TextClock\(|onDateChange/);
  assert.ok(ui.includes('@Entry(storage)'));
  assert.match(ui, /@State place: string/);
  assert.match(ui, /@State teacher: string/);
  assert.match(ui, /@State progressPercent: number/);
  assert.match(ui, /this\.place = nextView\.place/);
  assert.match(ui, /this\.teacher = nextView\.teacher/);
  assert.match(ui, /this\.progressPercent = nextView\.progressPercent/);
  assert.match(ui, /Text\(Math\.floor\(this\.progressPercent\)\.toString\(\) \+ '%'\)/);
  assert.match(ui, /Marquee\(\{ src: this\.timeLabel, start: true,/);
  assert.match(ui, /Marquee\(\{ src: this\.title, start: true,/);
  assert.match(ui, /Marquee\(\{ src: this\.countdown, start: true,/);
  assert.match(ui, /Marquee\(\{ src: this\.countdownUnit, start: true,/);
  assert.doesNotMatch(ui, /TextOverflow\.Ellipsis/);
  assert.match(ui, /this\.title = nextView\.title;\s*this\.timeLabel = nextView\.timeLabel;\s*this\.place = nextView\.place;\s*this\.teacher = nextView\.teacher;/);
  // Builder string parameters are by value; the metadata rows must read state directly.
  assert.match(ui, /metadataRow\(icon: Resource, isTeacher: boolean, compact: boolean\)/);
  assert.match(ui, /Marquee\(\{ src: isTeacher \? this\.teacher : this\.place, start: true,/);
  assert.doesNotMatch(ui, /metadataRow\([^)]*this\.(place|teacher)/);
  assert.doesNotMatch(ui, /this\.view\.(title|timeLabel)/);
  assert.match(ui, /Progress\(\{ value: this\.progressPercent, total: 100, type: ProgressType\.Ring \}\)/);
  assert.match(ui, /\.width\(compact \? 44 : 52\)/);
  assert.match(ui, /\.height\(compact \? 44 : 52\)/);
  assert.match(ui, /\.color\('#2365B2'\)/);
  assert.match(ui, /Stack\(\{ alignContent: Alignment\.Center \}\)/);
  assert.doesNotMatch(ui, /this\.view\.(place|teacher)/);
  assert.doesNotMatch(ui, /setInterval|setTimeout/);
  const home = fs.readFileSync(path.join(root, 'ets/pages/Home.ets'), 'utf8');
  assert.match(home, /CurrentClassSelection\.find\(courses, now\)/);
  assert.match(home, /setInterval\([\s\S]*?\}, 1000\)/);
  assert.match(home, /NextClassWidgetService\.scheduleRefresh\(\)/);
});

test('passes each requested widget size to initial storage without resetting it on schedule updates', () => {
  const refreshed = [];
  const { default: Ability } = load('widget/NextClassFormAbility.ets', {
    '@kit.FormKit': {
      FormExtensionAbility: class {},
      formBindingData: { createFormBindingData: value => value },
      formInfo: { FormParam: { IDENTITY_KEY: 'id', DIMENSION_KEY: 'dimension' } }
    },
    '../feature/widget/NextClassWidgetService': {
      NextClassWidgetService: { refreshForm: async (_context, id) => refreshed.push(id) }
    }
  });
  const ability = new Ability();
  assert.equal(ability.onAddForm({ parameters: { id: 'compact', dimension: 2 } }).formDimension, 2);
  assert.equal(ability.onAddForm({ parameters: { id: 'wide', dimension: 3 } }).formDimension, 3);
  assert.deepEqual(refreshed, ['compact', 'wide']);
  assert.equal(Object.hasOwn(NextClassModel.snapshot([], false, now), 'formDimension'), false);
});

test('a provider update retries when the selected timetable changes during its read', async () => {
  const published = [];
  const { NextClassWidgetService: service } = load('feature/widget/NextClassWidgetService.ets', {
    '@kit.FormKit': { formBindingData: { createFormBindingData: value => value }, formProvider: {
      updateForm: async (id, data) => published.push([id, data.scheduleJson])
    } }
  });
  let reads = 0;
  service.load = async () => {
    if (++reads === 1) { service.revision++; return { scheduleJson: 'old' }; }
    return { scheduleJson: 'new' };
  };
  await service.refreshForm({}, 'wide');
  assert.deepEqual(published, [['wide', 'new']]);
});
