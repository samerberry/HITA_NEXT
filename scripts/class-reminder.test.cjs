const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');
const values = new Map();
const published = [];
const prefs = { get: async (key, fallback) => values.has(key) ? values.get(key) : fallback,
  put: async (key, value) => values.set(key, value), flush: async () => {} };
const notifications = { SlotType: { SOCIAL_COMMUNICATION: 1 }, ContentType: { NOTIFICATION_CONTENT_BASIC_TEXT: 0 },
  addSlot: async () => {}, publish: async request => published.push(request) };
const cache = new Map();
const agents = [];
const root = path.resolve(__dirname, '../entry/src/main/ets');
global.$r = name => name;
function load(file) {
  file = path.resolve(root, file);
  if (cache.has(file)) return cache.get(file).exports;
  const mod = { exports: {} }; cache.set(file, mod);
  const req = name => {
    if (name === '@kit.ArkData') return { preferences: { getPreferences: async () => prefs } };
    if (name === '@kit.NotificationKit') return { notificationManager: notifications };
    if (name === '@kit.AbilityKit') return { wantAgent: {
      OperationType: { START_ABILITY: 1 }, WantAgentFlags: { UPDATE_PRESENT_FLAG: 1 },
      getWantAgent: async options => { agents.push(options); return options; }
    } };
    if (name === '@kit.PerformanceAnalysisKit') return { hilog: { info() {}, warn() {}, error() {} } };
    if (name.startsWith('@kit.')) return {};
    return load(path.resolve(path.dirname(file), name + '.ets'));
  };
  const js = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  new Function('require', 'module', 'exports', js)(req, mod, mod.exports);
  return mod.exports;
}
const { ClassReminderStore } = load('feature/timetable/data/ClassReminderStore.ets');
const { ClassReminderScheduler: scheduler } = load('feature/timetable/data/ClassReminderScheduler.ets');
const { EasEventItem, EasEventType } = load('common/model/timetable/TimetableModels.ets');
const store = ClassReminderStore.getInstance();
test('existing settings default to 15; custom values persist and reject invalid input', async () => {
  values.clear(); await store.init({});
  assert.equal(await store.loadLeadMinutes(), 15);
  for (const value of [1, 37, 120]) {
    await store.saveLeadMinutes(value); assert.equal(await store.loadLeadMinutes(), value);
  }
  const reopened = new ClassReminderStore(); await reopened.init({});
  assert.equal(await reopened.loadLeadMinutes(), 120);
  for (const value of [0, -1, 121, NaN, 2.5]) await assert.rejects(store.saveLeadMinutes(value));
  assert.equal(await store.loadLeadMinutes(), 120);
  values.set('class_reminder_lead_minutes', 'bad'); assert.equal(await store.loadLeadMinutes(), 15);
});
test('custom time changes notification boundary and schedule; disabling and repeated edits do not duplicate', async () => {
  values.clear(); published.length = 0; await store.init({}); await store.saveEnabled(true);
  const event = Object.assign(new EasEventItem(), { id: 'lesson', type: EasEventType.CLASS,
    name: '测试课程', place: '301', from: Date.now() + 30 * 60000, to: Date.now() + 90 * 60000 });
  await store.saveLeadMinutes(15);
  assert.equal(await scheduler.dispatchDue({}, [event]), 0);
  await scheduler.sync({}, [event]); const before = await store.loadSignature();
  await store.saveLeadMinutes(45);
  await scheduler.sync({}, [event]);
  assert.notEqual(await store.loadSignature(), before);
  assert.equal(published.length, 1);
  assert.match(published[0].content.normal.text, /30分钟后上课/);
  await store.saveLeadMinutes(60); await scheduler.sync({}, [event]);
  assert.equal(published.length, 1);
  await store.saveEnabled(false); await scheduler.cancelAll({});
  assert.equal(await scheduler.dispatchDue({}, [event]), 0);
  assert.equal(await store.loadLeadMinutes(), 60);
});

test('exam switch and lead time work independently and notifications link to the exact occurrence', async () => {
  values.clear(); published.length = 0; agents.length = 0;
  await store.init({});
  assert.equal(await store.loadExamEnabled(), false);
  assert.equal(await store.loadExamLeadMinutes(), 60);
  await store.saveExamEnabled(true);
  const exam = Object.assign(new EasEventItem(), { id: 'exam', type: EasEventType.EXAM,
    timetableId: 'term', name: 'Exam', place: '301', from: Date.now() + 45 * 60000, to: Date.now() + 90 * 60000 });
  const course = Object.assign(new EasEventItem(), { ...exam, id: 'course', type: EasEventType.CLASS });
  const context = { abilityInfo: { bundleName: 'hita.next', name: 'EntryAbility' } };
  await Promise.all([scheduler.dispatchDue(context, [exam, course]), scheduler.dispatchDue(context, [exam, course])]);
  assert.equal(published.length, 1);
  assert.match(published[0].content.normal.text, /分钟后考试/);
  assert.deepEqual(agents[0].wants[0].parameters, { hitaReminderEventId: 'exam', hitaReminderTimetableId: 'term' });
  await store.saveExamLeadMinutes(120);
  await scheduler.sync(context, [exam, course], true);
  assert.equal(published.length, 1, 'force sync and changed lead time must retain notification history');
  await store.saveExamEnabled(false);
  assert.equal(await scheduler.dispatchDue(context, [exam]), 0);
});

test('calendar coverage suppresses only successfully synced alarms; changed times use app fallback', async () => {
  values.clear(); published.length = 0;
  await store.init({}); await store.saveEnabled(true);
  const { CalendarSyncStore } = load('feature/timetable/data/CalendarSyncStore.ets');
  const calendar = CalendarSyncStore.getInstance(); await calendar.init({});
  await calendar.setEnabled('term', true);
  const event = Object.assign(new EasEventItem(), { id: 'lesson', type: EasEventType.CLASS,
    timetableId: 'term', from: Date.now() + 5 * 60000, to: Date.now() + 60 * 60000 });
  await calendar.setCoverage('term', [CalendarSyncStore.coverageKey(event.id, event.from, 15)]);
  assert.equal(await scheduler.dispatchDue({}, [event]), 0);
  event.from += 60000;
  assert.equal(await scheduler.dispatchDue({}, [event]), 1);
  assert.equal(published.length, 1);
});

test('upgrading preserves notification history from previous releases', async () => {
  values.clear(); published.length = 0;
  await store.init({}); await store.saveEnabled(true);
  const event = Object.assign(new EasEventItem(), { id: 'old', type: EasEventType.CLASS,
    from: Date.now() + 5 * 60000, to: Date.now() + 60 * 60000 });
  await store.markNotified(event.id + ':' + event.from);
  assert.equal(await scheduler.dispatchDue({}, [event]), 0);
});
