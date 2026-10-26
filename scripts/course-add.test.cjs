const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
global.$r = x => x;
global.DialogAlignment = { Bottom: 'bottom' };

function load(relative, overrides = {}, cache = new Map()) {
  const file = path.resolve(root, relative);
  if (cache.has(file)) return cache.get(file).exports;
  let source = fs.readFileSync(file, 'utf8');
  if (file.endsWith('AddEventPage.ets')) {
    source = source.slice(0, source.indexOf('\n  build()')) + '\n}\n';
    source = source.replace(/^@Component\r?\n/gm, '')
      .replace(/@(State|Prop|StorageProp)(\([^)]*\))?\s+/g, '')
      .replace('export struct EventEditorForm', 'export class EventEditorForm');
  }
  const mod = { exports: {} };
  cache.set(file, mod);
  const compiled = ts.transpileModule(source, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020
  } }).outputText;
  new Function('require', 'module', 'exports', compiled)(name => {
    if (name.endsWith('/RdbHelper') && overrides.db) return { RdbHelper: { getInstance: () => overrides.db } };
    if (name.endsWith('/CourseTimePickerDialog')) return { CourseTimePickerDialog: options => options };
    if (name.endsWith('/CourseTextPickerDialog')) return { CourseTextPickerDialog: options => options };
    if (name.endsWith('/CompatibleSheetMaterial')) return { CompatibleSheetMaterial: {
      isEnabled: () => false, cardColor: fallback => fallback
    } };
    if (name.endsWith('/CompatiblePickerMaterial')) return { CompatiblePickerMaterial: {
      isEnabled: () => overrides.pickerEnabled === true, textOptions: options => options,
      dialogMaterial: () => overrides.pickerEnabled ? 'controlled-material' : undefined
    } };
    if (name === '@kit.PerformanceAnalysisKit') return { hilog: { error() {} } };
    if (name === '@kit.ArkData') return { relationalStore: { RdbPredicates: class {
      constructor(table) { this.table = table; this.filters = []; }
      equalTo(key, value) { this.filters.push([key, value]); return this; }
    } } };
    if (name.startsWith('@kit.')) return {};
    return load(path.resolve(path.dirname(file), name + '.ets'), overrides, cache);
  }, mod, mod.exports);
  return mod.exports;
}

const { EasTimetable, EasTermSubject, EasEventItem, EasEventType } = load('common/model/timetable/TimetableModels.ets');
const { CourseDateSelection: dates } = load('feature/timetable/CourseDateSelection.ets');
const { RdbHelper } = load('common/db/RdbHelper.ets');
function timetable() {
  return Object.assign(new EasTimetable(), {
    id: 'target', startTime: new Date(2026, 7, 31).getTime(),
    endTime: new Date(2027, 0, 18).getTime() - 1
  });
}

test('weekly selection expands unique weeks x weekdays in date order, across year boundaries', () => {
  const tt = timetable();
  const selected = dates.weeklyDates(tt, [20, 1, 1], [7, 1, 7]);
  assert.equal(dates.weekCount(tt), 20);
  assert.deepEqual(selected.map(x => {
    const d = new Date(x); return [d.getFullYear(), d.getMonth() + 1, d.getDate(), d.getDay()];
  }), [[2026, 8, 31, 1], [2026, 9, 6, 0], [2027, 1, 11, 1], [2027, 1, 17, 0]]);
});

test('cleared weeks/days and invalid/out-of-term choices cannot silently add courses', () => {
  for (const [weeks, days] of [[[], [1]], [[1], []], [[0], [1]], [[21], [1]], [[1], [8]], [[1.5], [1]]]) {
    assert.throws(() => dates.weeklyDates(timetable(), weeks, days));
  }
  const short = timetable(); short.endTime = short.startTime + 86400000;
  assert.equal(dates.weeklyDates(short, [1], [7])[0], short.startTime + 6 * 86400000);
});

test('selection updates are idempotent and can deselect or retain disjoint weeks', () => {
  assert.deepEqual(dates.toggle([1, 3, 5], 3, true), [1, 3, 5]);
  assert.deepEqual(dates.toggle([1, 3, 5], 3, false), [1, 5]);
  assert.deepEqual(dates.toggle([1, 5], 2, true), [1, 2, 5]);
});

function transactionDb(failAt = -1) {
  const db = new RdbHelper();
  const rows = { subject: [], events: [], timetable: [{ id: 'target', startTime: 1, endTime: 10000 }] };
  const calls = [];
  db.store = { createTransaction: async () => {
    const pending = structuredClone(rows);
    return {
      query: async pred => {
        const row = pending[pred.table].find(row => pred.filters.every(([k,v]) => row[k] === v));
        return { goToFirstRow: () => !!row, getColumnIndex: key => key, getLong: key => row[key], close() {} };
      },
      update: async (value, pred) => {
        if (failAt === 'update') throw Error('update failed');
        const row = pending[pred.table].find(row => pred.filters.every(([k,v]) => row[k] === v));
        if (!row) return 0;
        Object.assign(row, value); return 1;
      },
      insert: async (table, value) => {
        if (table === 'events' && pending.events.length === failAt) throw Error('disk full');
        pending[table].push({ ...value });
      },
      commit: async () => { Object.assign(rows, pending); calls.push('commit'); },
      rollback: async () => calls.push('rollback')
    };
  } };
  return { db, rows, calls };
}
function batch() {
  const subject = Object.assign(new EasTermSubject(), { id: 'shared', timetableId: 'target', color: 0xffaabbcc });
  const events = [1, 2, 3].map(day => Object.assign(new EasEventItem(), {
    subjectId: subject.id, timetableId: subject.timetableId, type: EasEventType.CLASS, from: day * 1000, to: day * 1000 + 500
  }));
  return { subject, events };
}

test('batch writes one subject and every occurrence in one commit', async () => {
  const { db, rows, calls } = transactionDb();
  const { subject, events } = batch();
  await db.saveCourseOccurrences(subject, events, true);
  assert.equal(rows.subject.length, 1);
  assert.equal(rows.subject[0].color, subject.color);
  assert.equal(rows.events.length, 3);
  assert.equal(new Set(rows.events.map(e => e.id)).size, 3);
  assert.deepEqual(calls, ['commit']);
});

test('failed second occurrence rolls back the entire addition and can be retried', async () => {
  const { db, rows, calls } = transactionDb(1);
  const { subject, events } = batch();
  await assert.rejects(db.saveCourseOccurrences(subject, events, true));
  assert.deepEqual(rows, { subject: [], events: [], timetable: [{ id: 'target', startTime: 1, endTime: 10000 }] });
  assert.deepEqual(calls, ['rollback']);
});

test('adding occurrences to an existing course never overwrites its color or metadata', async () => {
  const { db, rows } = transactionDb();
  const { subject, events } = batch();
  rows.subject.push({ id: subject.id, color: 123, credit: 5 });
  await db.saveCourseOccurrences(subject, events, false);
  assert.deepEqual(rows.subject, [{ id: subject.id, color: 123, credit: 5 }]);
});

function formSetup(overrides = {}) {
  const tt = timetable();
  const commits = [], saved = [];
  const subject = Object.assign(new EasTermSubject(), { id: 'existing', name: '数学', timetableId: tt.id, color: 123 });
  const db = {
    init: async () => {}, getTimetableById: async id => id === tt.id ? tt : undefined,
    getSubjectsOfTimetable: async () => [subject],
    saveCourseOccurrences: async (...args) => commits.push(args)
  };
  const { EventEditorForm } = load('pages/AddEventPage.ets', { ...overrides, db });
  const form = new EventEditorForm();
  form.getUIContext = () => ({ getHostContext: () => ({}), getPromptAction: () => ({ showToast() {} }) });
  Object.assign(form, { courseTimetable: tt, weekChoices: dates.numbers(20), typeIdx: 1, timetableId: tt.id, name: '数学', hour: 8, minute: 15, endHour: 9,
    endMinute: 5, selectedWeeks: [1, 3], selectedWeekdays: [1, 3], dateMode: 1, sheetMode: true,
    loading: false, editorActive: true, onSaved: (event, events) => saved.push(events) });
  return { form, tt, db, commits, saved };
}

test('shared form saves all combinations into the explicit timetable and reports all events', async () => {
  const { form, commits, saved } = formSetup();
  await form.save();
  assert.equal(commits.length, 1);
  const [subject, events, newSubject] = commits[0];
  assert.equal(subject.id, 'existing');
  assert.equal(newSubject, false);
  assert.equal(events.length, 4);
  assert.ok(events.every(e => e.timetableId === 'target' && e.subjectId === 'existing' && e.color === 123));
  assert.ok(events.every(e => new Date(e.from).getHours() === 8 && new Date(e.from).getMinutes() === 15));
  assert.equal(saved[0].length, 4);
  await form.save();
  assert.equal(commits.length, 1, 'double tap must not create a duplicate batch');
});

test('clearing the selection stays cleared during save, with no database write', async () => {
  for (const key of ['selectedWeeks', 'selectedWeekdays']) {
    const { form, commits } = formSetup();
    form[key] = [];
    await form.save();
    assert.equal(commits.length, 0);
    assert.equal(form.saved, false);
    assert.match(form.hint, /至少选择/);
  }
});

test('single-date mode ignores weekly choices and uses the selected calendar day', async () => {
  const { form, commits } = formSetup();
  form.dateMode = 0;
  form.dayOffset = 10;
  await form.save();
  const events = commits[0][1];
  assert.equal(events.length, 1);
  const day = new Date(events[0].from); day.setHours(0, 0, 0, 0);
  assert.equal(day.getTime(), form.todayBase + 10 * 86400000);
});

test('a deleted target timetable does not silently redirect the addition elsewhere', async () => {
  const { form, db, commits } = formSetup();
  db.getTimetableById = async () => undefined;
  await form.save();
  assert.equal(commits.length, 0);
  assert.equal(form.saved, false);
});

test('failed saves keep the form retryable and dismissed forms do not notify old parents', async () => {
  const { form, db, saved } = formSetup();
  db.saveCourseOccurrences = async () => { throw Error('failure'); };
  await form.save();
  assert.equal(form.saved, false);
  assert.equal(form.saving, false);
  assert.equal(saved.length, 0);
  db.saveCourseOccurrences = async () => { form.aboutToDisappear(); };
  await form.save();
  assert.equal(saved.length, 0);
});

test('period mode reads the selected timetable structure and persists course numbers', async () => {
  const { form, tt, commits } = formSetup();
  tt.scheduleStructure = EasTimetable.getWeihaiTimeStructure();
  Object.assign(form, { timeMode: 1, fromPeriod: 3, toPeriod: 4 });
  assert.equal(form.canSave(), true);
  await form.save();
  for (const event of commits[0][1]) {
    assert.equal(new Date(event.from).getHours(), 10);
    assert.equal(new Date(event.from).getMinutes(), 5);
    assert.equal(new Date(event.to).getHours(), 11);
    assert.equal(new Date(event.to).getMinutes(), 50);
    assert.equal(event.fromNumber, 3);
    assert.equal(event.lastNumber, 4);
  }
});

test('save remains disabled for missing name, weeks, weekdays, invalid periods or reversed times', () => {
  for (const patch of [{ name: ' ' }, { selectedWeeks: [] }, { selectedWeekdays: [] },
    { timeMode: 1, fromPeriod: 0, toPeriod: 0 }, { timeMode: 1, fromPeriod: 4, toPeriod: 3 },
    { timeMode: 1, fromPeriod: 1, toPeriod: 99 }, { endHour: 7 }, { loading: true }, { saving: true }]) {
    const { form } = formSetup(); Object.assign(form, patch);
    assert.equal(form.canSave(), false, JSON.stringify(patch));
  }
  const { form } = formSetup(); assert.equal(form.canSave(), true);
});

test('existing course copies blank fields too and retains explicitly selected identity among duplicate names', async () => {
  const { form, db, commits } = formSetup();
  const selected = Object.assign(new EasEventItem(), { subjectId: 'second', name: '数学', place: '', teacher: 'B' });
  form.place = 'old classroom'; form.teacher = 'old teacher';
  form.selectExistingCourse(selected);
  assert.equal(form.place, ''); assert.equal(form.teacher, 'B');
  db.getSubjectsOfTimetable = async () => [
    Object.assign(new EasTermSubject(), { id: 'first', name: '数学', timetableId: 'target', color: 111 }),
    Object.assign(new EasTermSubject(), { id: 'second', name: '数学', timetableId: 'target', color: 222 })
  ];
  await form.save();
  assert.equal(commits[0][0].id, 'second'); assert.equal(commits[0][2], false);
  assert.ok(commits[0][1].every(e => e.subjectId === 'second' && e.color === 222 && e.teacher === 'B'));
});

test('deleted selected course does not silently attach to another course with the same name', async () => {
  const { form, commits } = formSetup(); form.selectedSubjectId = 'deleted';
  await form.save(); assert.equal(commits.length, 0); assert.match(form.hint, /已不存在/);
});

test('extended teaching weeks survive save-time target reload', async () => {
  const { form, commits } = formSetup();
  form.weekChoices = dates.numbers(25); form.selectedWeeks = [21, 25];
  assert.equal(form.canSave(), true); assert.match(form.extensionHint(), /延长/);
  await form.save(); assert.equal(commits[0][1].length, 4);
  assert.equal(form.weekChoices.length, 25);
});

test('single-date courses before the term are blocked without shifting the term start', async () => {
  const { form, tt, commits } = formSetup();
  form.dateMode = 0; form.todayBase = tt.startTime; form.dayOffset = -1;
  assert.equal(form.canSave(), false); await form.save();
  assert.equal(commits.length, 0); assert.match(form.hint, /早于开学/);
});

test('term extension and courses commit together, with the end rounded to Sunday', async () => {
  const { db, rows } = transactionDb(); const { subject, events } = batch();
  const tt = timetable(); rows.timetable[0] = { id: 'target', startTime: tt.startTime, endTime: tt.endTime };
  events.forEach((e,i) => { e.from = new Date(2027, 1, 1+i, 8).getTime(); e.to = e.from + 3600000; });
  await db.saveCourseOccurrences(subject, events, true);
  assert.equal(rows.timetable[0].endTime, new Date(2027, 1, 7, 23, 59, 59, 999).getTime());
  assert.equal(rows.timetable[0].startTime, tt.startTime);
  assert.equal(rows.events.length, 3);
});

test('failed term extension rolls back inserted courses and subject', async () => {
  const { db, rows, calls } = transactionDb('update'); const { subject, events } = batch();
  events[0].to = 100000;
  await assert.rejects(db.saveCourseOccurrences(subject, events, true));
  assert.equal(rows.events.length, 0); assert.equal(rows.subject.length, 0);
  assert.equal(rows.timetable[0].endTime, 10000); assert.deepEqual(calls, ['rollback']);
});

test('a concurrently deleted timetable aborts the whole batch', async () => {
  const { db, rows } = transactionDb(); const { subject, events } = batch(); rows.timetable = [];
  await assert.rejects(db.saveCourseOccurrences(subject, events, true));
  assert.equal(rows.events.length, 0); assert.equal(rows.subject.length, 0);
});

test('editing a period-created course by clock clears stale period numbers but date-only edits retain them', async () => {
  for (const changed of [false, true]) {
    const { form, db } = formSetup();
    const event = Object.assign(new EasEventItem(), { id: 'edit', type: EasEventType.CLASS, timetableId: 'target',
      from: new Date(2026, 9, 12, 8, 15).getTime(), to: new Date(2026, 9, 12, 9, 5).getTime(),
      fromNumber: 1, lastNumber: 2 });
    form.editId = event.id;
    if (changed) form.minute = 20;
    db.getEventById = async () => event;
    let stored;
    form.originalCourse = event; form.relatedCourses = [event];
    db.replaceCourseOccurrences = async (_before, after) => { stored = after[0]; };
    let dialog = 0;
    form.getUIContext = () => ({ getPromptAction: () => ({
      showDialog: async () => ({ index: dialog++ === 0 ? 1 : 0 }), showToast() {}
    }) });
    await form.save();
    assert.equal(stored.fromNumber, changed ? 0 : 1);
    assert.equal(stored.lastNumber, changed ? 0 : 2);
  }
});
test('legacy imported ranges follow actual events without truncating later manual events', () => {
  const tt = timetable(); tt.code = 'SHENZHEN:term'; tt.endTime = tt.startTime + 25 * 7 * 86400000;
  const event = week => Object.assign(new EasEventItem(), { timetableId: tt.id,
    from: tt.startTime + (week - 1) * 7 * 86400000 + 8 * 3600000,
    to: tt.startTime + (week - 1) * 7 * 86400000 + 9 * 3600000 });
  assert.equal(dates.repairedImportedEnd(tt, [event(17)]), tt.startTime + 17 * 7 * 86400000 - 1);
  assert.equal(dates.repairedImportedEnd(tt, [event(17), event(21)]), tt.startTime + 21 * 7 * 86400000 - 1);
  assert.equal(dates.repairedImportedEnd(tt, []), tt.endTime);
  const invalid = event(17); invalid.to = NaN;
  assert.equal(dates.repairedImportedEnd(tt, [invalid]), tt.endTime);
  invalid.to = event(17).to; invalid.timetableId = 'other';
  assert.equal(dates.repairedImportedEnd(tt, [invalid]), tt.endTime);
  tt.code = ''; assert.equal(dates.repairedImportedEnd(tt, [event(17)]), tt.endTime);
  tt.code = 'SHENZHEN:term'; tt.endTime--;
  assert.equal(dates.repairedImportedEnd(tt, [event(17)]), tt.endTime);
});

test('legacy range migration changes only the matching timetable end', async () => {
  const db = new RdbHelper(); const tt = timetable(); tt.code = 'SHENZHEN:term';
  tt.endTime = tt.startTime + 25 * 7 * 86400000;
  const oldEnd = tt.endTime; const updates = [];
  db.getTimetables = async () => [tt, timetable()];
  db.getEventsOfTimetable = async id => [Object.assign(new EasEventItem(), {
    timetableId: id, from: tt.startTime + 16 * 7 * 86400000, to: tt.startTime + 16 * 7 * 86400000 + 3600000
  })];
  db.upd = async (values, pred) => updates.push([values, pred.filters]);
  await db.repairLegacyImportedWeeks();
  assert.deepEqual(updates, [[{ endTime: tt.startTime + 17 * 7 * 86400000 - 1 }, [['id', tt.id], ['endTime', oldEnd]]]]);
});

test('course clock dialog omits the native calendar title, commits only valid times and closes on dismissal', () => {
  const original = global.CustomDialogController;
  const originalColor = global.Color;
  global.Color = { Transparent: 'transparent' };
  const dialogs = [];
  global.CustomDialogController = class {
    constructor(options) { this.options = options; this.opened = false; this.closed = false; dialogs.push(this); }
    open() { this.opened = true; }
    close() { this.closed = true; }
  };
  try {
    const { form } = formSetup();
    form.pickStartTime();
    assert.equal(dialogs.length, 1);
    const first = dialogs[0];
    assert.equal(first.opened, true);
    assert.equal(first.options.builder.title, '开始时间');
    assert.equal(first.options.builder.initialHour, 8);
    assert.equal(first.options.builder.initialMinute, 15);
    assert.equal(first.options.builder.onAccept(9, 10), false, 'a reversed interval stays in the picker');
    assert.equal(form.hour, 8);
    assert.equal(first.options.builder.onAccept(7, 45), true);
    assert.equal(form.hour, 7);
    assert.equal(form.minute, 45);
    form.pickEndTime();
    assert.equal(first.closed, true, 'opening another picker closes the previous one');
    const second = dialogs[1];
    assert.equal(second.options.builder.title, '结束时间');
    assert.equal(second.options.builder.onAccept(7, 30), false);
    assert.equal(second.options.builder.onAccept(10, 0), true);
    assert.equal(form.endHour, 10);
    form.aboutToDisappear();
    assert.equal(second.closed, true);
    assert.equal(second.options.builder.onAccept(11, 0), false, 'late accepts cannot update a dismissed editor');
    assert.equal(form.endHour, 10);
    const clock = fs.readFileSync(path.join(root, 'feature/timetable/views/CourseTimePickerDialog.ets'), 'utf8');
    assert.match(clock, /TimePicker\(\{ selected:/);
    assert.doesNotMatch(clock, /DatePicker\(|showTimePickerDialog|dateText|星期六|2000年/);
  } finally {
    if (original === undefined) delete global.CustomDialogController;
    else global.CustomDialogController = original;
    if (originalColor === undefined) delete global.Color;
    else global.Color = originalColor;
  }
});

test('existing-course and period pickers preserve selection and discard late course accepts', async () => {
  const { form, db } = formSetup();
  const picked = [];
  form.getUIContext = () => ({ showTextPickerDialog: options => picked.push(options) });
  db.getEventsOfTimetable = async () => [
    Object.assign(new EasEventItem(), { type: EasEventType.CLASS, subjectId: 'existing',
      name: '数学', place: 'T3101', teacher: 'A' })
  ];
  await form.chooseExistingCourse();
  assert.equal(picked.length, 1);
  assert.deepEqual(picked[0].range, ['数学 · T3101 · A']);
  assert.equal(picked[0].canLoop, false);
  picked[0].onAccept({ index: 0 });
  assert.equal(form.selectedSubjectId, 'existing');
  assert.equal(form.place, 'T3101');
  form.name = 'unchanged';
  form.aboutToDisappear();
  picked[0].onAccept({ index: 0 });
  assert.equal(form.name, 'unchanged');
});

test('the API 26 wheel retains callbacks and closes its previous dialog and dismissed editor', () => {
  const original = global.CustomDialogController, originalColor = global.Color;
  global.Color = { Transparent: 'transparent' };
  const dialogs = [];
  global.CustomDialogController = class {
    constructor(options) { this.options = options; dialogs.push(this); }
    open() { this.opened = true; }
    close() { this.closed = true; }
  };
  try {
    const { form } = formSetup({ pickerEnabled: true });
    form.getUIContext = () => ({ showTextPickerDialog() { assert.fail('API 26 uses the controlled wheel'); } });
    const accepted = [], cancelled = [];
    const options = { range: ['A', 'B'], selected: 1, canLoop: false,
      onAccept: result => accepted.push(result), onCancel: () => cancelled.push('cancel') };
    form.showCourseTextPicker(options);
    assert.equal(dialogs[0].options.builder.options, options);
    assert.equal(dialogs[0].options.backgroundColor, 'transparent');
    assert.equal(dialogs[0].options.systemMaterial, 'controlled-material');
    assert.equal(dialogs[0].opened, true);
    dialogs[0].options.builder.options.onAccept({ index: 1, value: 'B' });
    assert.deepEqual(accepted, [{ index: 1, value: 'B' }]);
    dialogs[0].options.cancel();
    assert.deepEqual(cancelled, ['cancel']);
    form.showCourseTextPicker(options);
    assert.equal(dialogs[0].closed, true);
    form.aboutToDisappear();
    assert.equal(dialogs[1].closed, true);
    assert.equal(form.coursePicker, undefined);
  } finally {
    if (original === undefined) delete global.CustomDialogController;
    else global.CustomDialogController = original;
    if (originalColor === undefined) delete global.Color;
    else global.Color = originalColor;
  }
});
for (const sheetMode of [false, true]) {
  test(`repeated close requests close ${sheetMode ? 'sheet' : 'page'} once while the editor is leaving`, () => {
    const { form } = formSetup();
    let closed = 0;
    let routed = 0;
    form.sheetMode = sheetMode;
    form.choosingWeeks = true;
    form.onCancel = () => closed++;
    form.getUIContext = () => ({ getRouter: () => ({ back: () => routed++ }) });
    form.leaveEditor();
    form.leaveEditor();
    assert.equal(closed, sheetMode ? 1 : 0);
    assert.equal(routed, sheetMode ? 0 : 1);
    assert.equal(form.choosingWeeks, false);
    form.aboutToDisappear();
    form.leaveEditor();
    assert.equal(closed + routed, 1);
  });
}
