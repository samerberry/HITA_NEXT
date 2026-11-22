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

test('a saved all-day reminder stays readable after a time-zone change; only saving enforces the deadline rule', () => {
  const late = task({ id: 'late', dueAt: new Date(2026, 9, 27, 8).getTime(), allDay: true });
  late.remindAt = rules.deadline(late) + 3600000;
  assert.equal(rules.storedValidation(late), '');
  assert.equal(rules.validation(late), '提醒时间不能晚于截止时间');
});

test('Today previews one visible pending task by effective deadline, then creation and insertion order', () => {
  const timed = task({ id: 'early', dueAt: now, createdAt: 1 });
  const newer = task({ id: 'newer', dueAt: now, createdAt: 2 });
  const allDay = task({ allDay: true, dueAt: rules.dayStart(now) });
  const undated = task({ dueAt: 0, createdAt: 0 });
  const hidden = task({ dueAt: now - 1, showInToday: false });
  const order = [undated, allDay, newer, hidden, timed];
  assert.equal(rules.firstForToday(order), timed);
  assert.equal(rules.firstForToday([timed, { ...timed, id: 'same-ms' }]), timed);
  assert.equal(rules.firstForToday([undated, allDay]), allDay);
  assert.equal(rules.firstForToday([hidden, undated]), undated);
  assert.equal(rules.firstForToday([hidden]), undefined);
  assert.equal(rules.firstForToday([]), undefined);
});

test('the task list offers only homework and review tabs and opens on homework', () => {
  const panel = fs.readFileSync(path.join(root, 'feature/learning/LearningTasksPanel.ets'), 'utf8');
  assert.match(panel, /if \(this\.filterKind\.length === 0 && this\.subjectId\.length === 0 && this\.examId\.length === 0\) \{\s*Row\(\) \{\s*CourseModeSegment\(\{\s*labels: \['作业', '复习'\], selectedIndex: this\.selectedKind === LearningTaskKind\.REVIEW \? 1 : 0/);
  assert.match(panel, /@State selectedKind: string = LearningTaskKind\.HOMEWORK;/);
  assert.match(panel, /if \(this\.filterKind\.length > 0\) this\.selectedKind = this\.filterKind;/);
  assert.match(panel, /if \(this\.filterKind\.length === 0\) this\.selectedKind = task\.kind;/);
});

// Run the panel's real state changes with independently controlled storage and visual feedback.
function panelHarness(row, write = async () => {}, others = []) {
  const source = fs.readFileSync(path.join(root, 'feature/learning/LearningTasksPanel.ets'), 'utf8');
  const methods = source.slice(source.indexOf('  private async load('), source.indexOf('  private remove('));
  const script = ts.transpileModule('class Panel {\n' + methods + '\n}; return new Panel();', {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  let finishCheck, writes = 0, cancelled = 0, stored = row;
  const db = {
    setLearningTaskCompleted: async (id, done) => {
      assert.equal(id, row.id);
      writes++;
      await write();
      stored = { ...row, completedAt: done ? now : 0 };
    },
    init: async () => {}, getLearningContext: async () => ({}), getLearningTasks: async () => [stored, ...others]
  };
  const panel = new Function('RdbHelper', 'LearningTaskReminders', 'setTimeout', 'Curve',
    'CHECK_DURATION', 'REGROUP_DURATION', 'LearningTaskRules', '$r', script)({ getInstance: () => db },
    { cancel: async () => { cancelled++; } }, callback => { finishCheck = callback; }, {}, 120, 250, rules, s => s);
  Object.assign(panel, { tasks: [row, ...others], active: true, generation: 0, previewTaskId: '', initialTaskId: '',
    requestedTaskId: '', filterKind: '', onRequestHandled() { this.initialTaskId = ''; },
    onBusyChanged() {}, getUIContext: () => ({ animateTo: (_, change) => change(), getHostContext: () => ({}) }) });
  return { panel, finish: () => finishCheck(), writes: () => writes, cancelled: () => cancelled };
}

test('complete and restore preview just the tapped row and regroup once after feedback and persistence', async () => {
  for (const completedAt of [0, now]) {
    const row = task({ id: 'target', completedAt });
    const h = panelHarness(row);
    const pending = h.panel.toggle(row);
    assert.equal(h.panel.showsCheck(row), completedAt === 0);
    assert.equal(h.panel.showsCheck(task({ id: 'other', completedAt })), completedAt > 0);
    assert.equal(h.panel.tasks[0], row);
    await h.panel.toggle(row);
    assert.equal(h.writes(), 1);
    h.finish();
    await pending;
    assert.equal(h.panel.tasks[0].completedAt > 0, completedAt === 0);
    assert.equal(h.panel.previewTaskId, '');
    assert.equal(h.panel.busy, false);
    assert.equal(h.cancelled(), completedAt === 0 ? 1 : 0);
  }
});

test('a failed completion or restore undoes its visual preview and leaves the row available to retry', async () => {
  for (const completedAt of [0, now]) {
    const row = task({ id: 'target', completedAt });
    const h = panelHarness(row, async () => { throw Error('write failed'); });
    await h.panel.toggle(row);
    assert.equal(h.panel.tasks[0], row);
    assert.equal(h.panel.showsCheck(row), completedAt > 0);
    assert.equal(h.panel.previewTaskId, '');
    assert.equal(h.panel.busy, false);
    assert.ok(h.panel.error.includes('重试'));
    assert.equal(h.cancelled(), 0);
  }
});

test('desktop taps edit the requested ID on launch, when switching tasks, and after returning to the list', async () => {
  const first = task({ id: 'a', kind: 'HOMEWORK' }), next = task({ id: 'b', kind: 'REVIEW' });
  const { panel } = panelHarness(first, undefined, [next]);
  const request = async target => {
    panel.initialTaskId = target.id;
    panel.onTaskRequestChanged();
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(panel.initialTaskId, '');
    assert.equal(panel.draft.id, target.id);
    assert.equal(panel.selectedKind, target.kind);
    assert.equal(panel.editing, true);
    assert.equal(panel.isNew, false);
  };
  await request(first);
  await request(next);
  const draft = panel.draft;
  panel.draftDirty = true;
  await request(next);
  assert.equal(panel.draft, draft, 'opening the same task preserves the current draft');
  panel.editing = false;
  await request(next);
});

test('a desktop switch keeps unsaved edits until confirmed and honours the latest tap', async () => {
  const a = task({ id: 'a' }), b = task({ id: 'b' }), c = task({ id: 'c' });
  const { panel } = panelHarness(a, undefined, [b, c]);
  Object.assign(panel, { draft: a, editing: true, draftDirty: true, requestedTaskId: b.id });
  let decide;
  panel.getUIContext = () => ({ getPromptAction: () => ({ showDialog: () => new Promise(done => { decide = done; }) }) });
  let decision = panel.openRequestedTask();
  decide({ index: 0 }); await decision;
  assert.equal(panel.draft, a);
  assert.equal(panel.draftDirty, true);
  panel.requestedTaskId = b.id;
  decision = panel.openRequestedTask();
  panel.requestedTaskId = c.id;
  decide({ index: 1 }); await decision;
  assert.equal(panel.draft.id, c.id);
  assert.equal(panel.draftDirty, false);
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
