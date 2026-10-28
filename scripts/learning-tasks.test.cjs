const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');

function load(file, overrides = {}, cache = new Map()) {
  file = path.resolve(root, file);
  if (cache.has(file)) return cache.get(file).exports;
  const mod = { exports: {} }; cache.set(file, mod);
  const compiled = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  new Function('require', 'module', 'exports', compiled)(name => {
    if (overrides[name]) return overrides[name];
    if (name.startsWith('@kit.')) return {};
    return load(path.resolve(path.dirname(file), name + '.ets'), overrides, cache);
  }, mod, mod.exports);
  return mod.exports;
}
const { LearningTask, LearningContext, LearningTaskRules: rules } = load('common/model/learning/LearningTask.ets');
const now = new Date(2026, 9, 27, 14, 0).getTime();
const task = values => Object.assign(new LearningTask(), { title: 'Exercises', timetableId: 'term', subjectId: 'math', courseName: 'Math' }, values);

test('the task list offers only homework and review tabs and opens on homework', () => {
  const panel = fs.readFileSync(path.join(root, 'feature/learning/LearningTasksPanel.ets'), 'utf8');
  assert.doesNotMatch(panel, /kindTab\('全部'|embedded/);
  assert.match(panel, /this\.kindTab\('作业', LearningTaskKind\.HOMEWORK\)\s*this\.kindTab\('复习', LearningTaskKind\.REVIEW\)/);
  assert.match(panel, /@State selectedKind: string = LearningTaskKind\.HOMEWORK;/);
  assert.match(panel, /if \(this\.filterKind\.length > 0\) this\.selectedKind = this\.filterKind;/);
  assert.match(panel, /if \(this\.filterKind\.length === 0\) this\.selectedKind = task\.kind;/);
});

test('all-day deadlines remain pending until local midnight; timed tasks become overdue, completion wins', () => {
  const date = new Date(2026, 9, 27).getTime();
  const allDay = task({ dueAt: date, allDay: true });
  assert.equal(rules.group(allDay, now), 1);
  assert.equal(rules.group(allDay, new Date(2026, 9, 28).getTime()), 0);
  assert.equal(rules.group(task({ dueAt: now - 1 }), now), 0);
  assert.equal(rules.group(task({ dueAt: now + 3600000 }), now), 1);
  assert.equal(rules.group(task({ dueAt: now + 86400000 }), now), 2);
  assert.equal(rules.group(task({ dueAt: 0 }), now), 3);
  assert.equal(rules.group(task({ dueAt: now - 1, completedAt: now }), now), 4);
  const input = [task({ id: 'done', completedAt: now }), task({ id: 'none' }), task({ id: 'late', dueAt: now - 1 }), allDay];
  assert.deepEqual(rules.sort(input, now).map(t => t.id), ['late', allDay.id, 'none', 'done']);
  assert.equal(input[0].id, 'done', 'sorting must not mutate stored projections');
});

test('course identity survives rename and unambiguous reimport without crossing terms or choosing ambiguous courses', () => {
  const data = new LearningContext();
  data.subjects = [{ id: 'new', timetableId: 'term', name: 'Renamed', code: 'M01' },
    { id: 'foreign', timetableId: 'other', name: 'Math', code: 'M01' }];
  assert.equal(rules.subject(task({ courseCode: 'M01' }), data).id, 'new');
  assert.equal(rules.subject(task({ subjectId: 'new', courseCode: 'old' }), data).name, 'Renamed');
  data.subjects.push({ id: 'ambiguous', timetableId: 'term', name: 'Other class', code: 'M01' });
  assert.equal(rules.subject(task({ courseCode: 'M01' }), data), undefined);
  assert.equal(rules.subject(task({ timetableId: 'deleted', courseCode: 'M01' }), data), undefined);
  data.subjects = [{ id: 'single', timetableId: 'term', name: 'Math', code: '' }];
  assert.equal(rules.subject(task({ courseCode: '' }), data).id, 'single');
});

test('next-class deadlines use the next future occurrence of the exact subject and timetable', () => {
  const subject = { id: 'math', timetableId: 'term' };
  const events = [
    { id: 'past', subjectId: 'math', timetableId: 'term', type: 'CLASS', from: now - 1000 },
    { id: 'foreign', subjectId: 'math', timetableId: 'other', type: 'CLASS', from: now + 1 },
    { id: 'exam', subjectId: 'math', timetableId: 'term', type: 'EXAM', from: now + 2 },
    { id: 'later', subjectId: 'math', timetableId: 'term', type: 'CLASS', from: now + 4000 },
    { id: 'next', subjectId: 'math', timetableId: 'term', type: 'CLASS', from: now + 3000 }
  ];
  assert.equal(rules.nextClass(subject, events, now).id, 'next');
  assert.equal(rules.nextClass(subject, events, now + 5000), undefined);
});

test('exam rescheduling preserves lead times and completion; other exams and terms never move', () => {
  const original = task({ kind: 'REVIEW', examId: 'exam', examAt: now, dueAt: now - 86400000,
    remindAt: now - 86400000 - 3600000, notifiedAt: now - 86400000 - 3600000 });
  const moved = rules.shifted(original, { id: 'exam', timetableId: 'term', name: 'Exam', from: now + 2 * 86400000 });
  assert.equal(moved.dueAt, original.dueAt + 2 * 86400000);
  assert.equal(moved.remindAt, original.remindAt + 2 * 86400000);
  assert.equal(moved.notifiedAt, 0);
  assert.equal(original.examAt, now);
  for (const change of [{ completedAt: now }, { timetableId: 'other' }, { examId: 'different' }, { examAt: 0 }]) {
    const t = task({ ...original, ...change });
    assert.deepEqual(rules.shifted(t, { id: 'exam', timetableId: 'term', from: now + 1000 }), { ...t });
  }
});

test('invalid task content, timestamps and reminders after a deadline are rejected', () => {
  assert.equal(rules.validation(task({})), '');
  for (const change of [{ title: ' ' }, { title: 'x'.repeat(121) }, { note: 'x'.repeat(4001) },
    { kind: 'UNKNOWN' }, { dueAt: -1 }, { remindAt: NaN }, { updatedAt: 0.5 }, { completedAt: '1' },
    { dueAt: now, remindAt: now + 1 }]) assert.notEqual(rules.validation(task(change)), '');
});

function reminderHarness() {
  const records = new Map(); const alerts = new Map(); let enabled = true; let fail = false;
  let duringAgent = () => {}; let duringPublish = () => {};
  const rdb = {
    getLearningTasks: async () => [...records.values()].map(t => ({ ...t })),
    markLearningTaskNotified: async (id, time) => {
      const t = records.get(id); if (t && !t.completedAt && t.remindAt === time) t.notifiedAt = time;
    }
  };
  const notificationManager = {
    SlotType: { SOCIAL_COMMUNICATION: 1 }, ContentType: { NOTIFICATION_CONTENT_BASIC_TEXT: 1 },
    isNotificationEnabled: async () => enabled,
    publish: async alert => { if (fail) { fail = false; throw Error('temporarily unavailable'); } alerts.set(alert.id, alert); duringPublish(); },
    cancel: async id => alerts.delete(id)
  };
  const { LearningTaskReminders: scheduler } = load('feature/learning/LearningTaskReminders.ets', {
    '../../common/db/RdbHelper': { RdbHelper: { getInstance: () => rdb } },
    '@kit.NotificationKit': { notificationManager },
    '@kit.AbilityKit': { wantAgent: { getWantAgent: async options => { duringAgent(); return options; },
      OperationType: { START_ABILITY: 1 }, WantAgentFlags: { UPDATE_PRESENT_FLAG: 1 } } }
  });
  return { scheduler, records, alerts, context: { abilityInfo: { bundleName: 'app', name: 'EntryAbility' } },
    setEnabled: value => { enabled = value; }, fail: () => { fail = true; },
    duringAgent: action => { duringAgent = action; }, duringPublish: action => { duringPublish = action; } };
}

test('task reminders fire once, retry publication failures and retain opt-in and expiry boundaries', async () => {
  const h = reminderHarness(); const time = Date.now();
  const pending = task({ id: 'pending', remindAt: time - 1000 }); h.records.set(pending.id, pending);
  h.records.set('old', task({ id: 'old', remindAt: time - 2 * 86400000 }));
  h.records.set('done', task({ id: 'done', remindAt: time - 1000, completedAt: time }));
  h.setEnabled(false); await h.scheduler.refresh(h.context); assert.equal(h.alerts.size, 0);
  h.setEnabled(true); h.fail(); await h.scheduler.refresh(h.context); assert.equal(pending.notifiedAt, 0);
  await h.scheduler.refresh(h.context);
  assert.equal(h.alerts.size, 1); assert.equal(pending.notifiedAt, pending.remindAt);
  await h.scheduler.refresh(h.context); assert.equal(h.alerts.size, 1);
  assert.equal([...h.alerts.values()][0].wantAgent.wants[0].parameters.hitaLearningTaskId, 'pending');
  pending.completedAt = time; await h.scheduler.refresh(h.context); assert.equal(h.alerts.size, 0);
  pending.completedAt = 0; await h.scheduler.refresh(h.context); assert.equal(h.alerts.size, 0, 'undo must not duplicate an already delivered reminder');
});

test('completion or deletion during notification setup/publication never leaves an alert behind', async () => {
  for (const phase of ['duringAgent', 'duringPublish']) {
    const h = reminderHarness(); const pending = task({ id: 'pending', remindAt: Date.now() - 1000 });
    h.records.set(pending.id, pending);
    h[phase](() => h.records.delete(pending.id));
    await h.scheduler.refresh(h.context);
    assert.equal(h.alerts.size, 0);
  }
});

test('reminder edits cancel the previous alert and schedule the new timestamp', async () => {
  const h = reminderHarness(); const pending = task({ id: 'pending', remindAt: Date.now() - 1000 });
  h.records.set(pending.id, pending);
  await h.scheduler.refresh(h.context); assert.equal(h.alerts.size, 1);
  pending.remindAt = Date.now() + 3600000;
  await h.scheduler.refresh(h.context); assert.equal(h.alerts.size, 0);
});
