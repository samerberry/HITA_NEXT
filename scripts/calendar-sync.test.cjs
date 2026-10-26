const assert = require('node:assert/strict');
const test = require('node:test');
const { harness } = require('./helpers/calendar-sync-harness.cjs');

async function setup(t) {
  const h = harness();
  const { ScheduleSyncService: service } = h.load('feature/timetable/data/ScheduleSyncService.ets');
  const { CalendarSyncStore, CalendarReminderOptions } = h.load('feature/timetable/data/CalendarSyncStore.ets');
  const { ClassReminderStore } = h.load('feature/timetable/data/ClassReminderStore.ets');
  const store = CalendarSyncStore.getInstance();
  const reminders = ClassReminderStore.getInstance();
  await store.init({});
  await reminders.init({});
  service.attach({});
  t.after(() => service.detach());
  return { ...h, service, store, reminders, options: new CalendarReminderOptions() };
}

test('only enrolled timetables sync; edits, cancellation and undo reconcile without duplicates', async t => {
  const h = await setup(t);
  h.state.events = [h.course({ id: 'a' })];
  await h.service.syncNow();
  assert.equal(h.state.calendars.length, 0);
  assert.equal((await h.service.enable({}, h.timetable)).success, true);
  const calendar = h.state.calendars[0];
  const originalId = calendar.rows[0].id;
  await h.service.syncNow();
  assert.equal(h.state.updates, 0, 'unchanged events must not be rewritten');
  h.state.events[0].place = 'B202';
  await h.service.syncNow();
  assert.equal(calendar.rows[0].id, originalId);
  assert.equal(calendar.rows[0].location.location, 'B202');
  assert.equal(h.state.updates, 1);
  h.state.events[0].from += 86400000;
  h.state.events[0].to += 86400000;
  await h.service.syncNow();
  assert.equal(calendar.rows.length, 1);
  assert.notEqual(calendar.rows[0].id, originalId);
  const saved = [...h.state.events];
  calendar.rows.push({ id: 999, title: 'Personal' });
  h.state.events = [];
  await h.service.syncNow();
  assert.deepEqual(calendar.rows, [{ id: 999, title: 'Personal' }]);
  h.state.events = saved;
  await h.service.syncNow();
  assert.equal(calendar.rows.length, 2);
  assert.ok(h.state.strictReads > 0);
});

test('course and exam alarms are independent; settings changes update existing calendar events', async t => {
  const h = await setup(t);
  await h.reminders.saveEnabled(true);
  await h.reminders.saveLeadMinutes(23);
  await h.reminders.saveExamEnabled(true);
  await h.reminders.saveExamLeadMinutes(75);
  h.state.events = [h.course({ id: 'a' }), h.course({ id: 'exam', name: 'Exam', type: 'EXAM' })];
  await h.service.enable({}, h.timetable);
  const calendar = h.state.calendars[0];
  const ids = calendar.rows.map(row => row.id);
  assert.deepEqual(calendar.rows.map(row => row.reminderTime), [[23], [75]]);
  await h.reminders.saveEnabled(false);
  await h.reminders.saveExamLeadMinutes(37);
  await h.service.syncNow();
  assert.deepEqual(calendar.rows.map(row => row.id), ids);
  assert.deepEqual(calendar.rows.map(row => row.reminderTime), [[], [37]]);
  await h.reminders.saveExamEnabled(false);
  await h.service.syncNow();
  assert.deepEqual(calendar.rows.map(row => row.reminderTime), [[], []]);
  assert.equal(h.state.permissionCalls, 1, 'automatic sync must not launch permission dialogs');
});

test('three consecutive lessons have one alarm, retain all calendar occurrences and do not mutate sources', async t => {
  const h = await setup(t);
  h.options.classes = true;
  const start = h.course().from;
  h.state.events = [0, 1, 2].map(index => h.course({ id: `lesson-${index}`, subjectId: 's',
    from: start + index * 70 * 60000, to: start + (index * 70 + 50) * 60000 }));
  const snapshot = JSON.stringify(h.state.events);
  const result = await h.exporter.exportTimetable({}, h.timetable, true, h.options, true);
  assert.equal(result.success, true);
  assert.deepEqual(h.state.calendars[0].rows.map(row => row.reminderTime), [[15], [], []]);
  assert.equal(result.coverage.length, 1);
  assert.equal(JSON.stringify(h.state.events), snapshot);
});

test('database failures never clear existing calendar events or unregister a timetable', async t => {
  const h = await setup(t);
  h.state.events = [h.course({ id: 'a' })];
  await h.service.enable({}, h.timetable);
  const rows = JSON.stringify(h.state.calendars[0].rows);
  for (const flag of ['failDb', 'failDbEvents']) {
    h.state[flag] = true;
    await h.service.syncNow().catch(() => {});
    assert.equal(JSON.stringify(h.state.calendars[0].rows), rows);
    assert.equal(await h.store.enabled(h.timetable.id), true);
    assert.match(h.statuses.get('hita_calendar_sync_status'), /未完成/);
    h.state[flag] = false;
  }
});

test('deleting a timetable and disabling sync remove only owned events; failed cleanup keeps enrollment', async t => {
  const h = await setup(t);
  h.state.events = [h.course({ id: 'a' })];
  await h.service.enable({}, h.timetable);
  const calendar = h.state.calendars[0];
  calendar.rows.push({ id: 999, title: 'Personal' });
  h.state.failDelete = true;
  await assert.rejects(h.service.disable({}, h.timetable.id));
  assert.equal(await h.store.enabled(h.timetable.id), true);
  h.state.failDelete = false;
  await h.service.disable({}, h.timetable.id);
  assert.equal(await h.store.enabled(h.timetable.id), false);
  assert.deepEqual(calendar.rows, [{ id: 999, title: 'Personal' }]);
  await h.service.enable({}, h.timetable);
  h.state.timetables.clear();
  await h.service.syncNow();
  assert.equal(await h.store.enabled(h.timetable.id), false);
  assert.deepEqual(calendar.rows, [{ id: 999, title: 'Personal' }]);
});

test('denied initial permissions roll back enrollment; partial writes remain enrolled and recover', async t => {
  const h = await setup(t);
  h.state.events = [h.course({ id: 'a' }), h.course({ id: 'b', name: 'Physics' })];
  h.state.permissions = [-1, -1];
  assert.equal((await h.service.enable({}, h.timetable)).success, false);
  assert.equal(await h.store.enabled(h.timetable.id), false);
  h.state.permissions = [0, 0];
  h.state.failAt = 2;
  assert.equal((await h.service.enable({}, h.timetable)).success, false);
  assert.equal(await h.store.enabled(h.timetable.id), true);
  h.state.failAt = 0;
  await h.service.syncNow();
  assert.equal(h.state.calendars[0].rows.length, 2);
});

test('coverage tracks only published times and lead values; disabled provider alarms restore app fallback', async t => {
  const h = await setup(t);
  await h.reminders.saveEnabled(true);
  const event = h.course({ id: 'a' });
  h.state.events = [event];
  await h.service.enable({}, h.timetable);
  assert.equal(await h.store.covers(event.timetableId, event.id, event.from, 15), true);
  assert.equal(await h.store.covers(event.timetableId, event.id, event.from + 60000, 15), false);
  assert.equal(await h.store.covers(event.timetableId, event.id, event.from, 30), false);
  h.state.calendars[0].config.enableReminder = false;
  await h.service.syncNow();
  assert.equal(await h.store.covers(event.timetableId, event.id, event.from, 15), false);
  assert.match(h.statuses.get('hita_calendar_sync_status'), /提醒已关闭/);
});

test('change signals preserve the existing widget listener and coalesce calendar sync', async t => {
  const h = await setup(t);
  h.state.events = [h.course({ id: 'a' })];
  await h.service.enable({}, h.timetable);
  const { ScheduleChangeSignal: signal } = h.load('common/util/ScheduleChangeSignal.ets');
  let widgetUpdates = 0;
  signal.listener = () => widgetUpdates++;
  h.state.events[0].place = 'C303';
  signal.notify(); signal.notify();
  await new Promise(resolve => setTimeout(resolve, 650));
  await h.service.syncNow();
  assert.equal(widgetUpdates, 2);
  assert.equal(h.state.calendars[0].rows[0].location.location, 'C303');
  assert.equal(h.state.calendars[0].rows.length, 1);
});

test('changes arriving during initial publication are serialized and coverage follows each published snapshot', async t => {
  const h = await setup(t);
  await h.reminders.saveEnabled(true);
  const event = h.course({ id: 'a' });
  const oldFrom = event.from;
  h.state.events = [event];
  let release;
  h.state.permissionGate = new Promise(resolve => { release = resolve; });
  const first = h.service.enable({}, h.timetable);
  while (h.state.permissionCalls === 0) await new Promise(resolve => setImmediate(resolve));
  event.from += 86400000; event.to += 86400000;
  const second = h.service.syncNow();
  release();
  const result = await first;
  const { CalendarSyncStore } = h.load('feature/timetable/data/CalendarSyncStore.ets');
  assert.deepEqual(result.coverage, [CalendarSyncStore.coverageKey(event.id, oldFrom, 15)]);
  await second;
  assert.equal(h.state.calendars[0].rows.length, 1);
  assert.equal(h.state.calendars[0].rows[0].startTime, event.from);
  assert.equal(await h.store.covers(event.timetableId, event.id, oldFrom, 15), false);
  assert.equal(await h.store.covers(event.timetableId, event.id, event.from, 15), true);
  h.service.detach(); h.service.attach({});
  await h.service.syncNow();
  assert.equal(h.state.calendars[0].rows.length, 1, 'reattaching reloads enrollment without duplicate events');
});
