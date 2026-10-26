const assert = require('node:assert/strict');
const test = require('node:test');

const { harness } = require('./helpers/calendar-sync-harness.cjs');

test('exports exact occurrences, including nonconsecutive weeks, exams, locations and teacher', async () => {
  const h = harness();
  h.state.events = [h.course(), h.course({ from: Date.parse('2026-10-19T18:45:00+08:00'),
    to: Date.parse('2026-10-19T20:30:00+08:00') }), h.course({ type: 'EXAM', name: '数学考试' }),
    h.course({ type: 'OTHER', name: '研讨会' }), h.course({ type: 'TAG' }),
    h.course({ timetableId: 'another' })];
  const result = await h.run();
  assert.equal(result.success, true);
  assert.equal(result.total, 4);
  const rows = h.state.calendars[0].rows;
  assert.equal(rows[0].startTime, Date.parse('2026-10-05T00:30:00Z'));
  assert.equal(rows[0].endTime, Date.parse('2026-10-05T02:15:00Z'));
  assert.equal(rows[0].timeZone, 'Asia/Shanghai');
  assert.equal(rows[0].isAllDay, false);
  assert.equal(rows[0].location.location, 'A101');
  assert.equal(rows[0].description, '课表：2026 秋季\n教师：张老师\n节次：第 1-2 节');
  assert.equal(rows[1].startTime, Date.parse('2026-10-19T10:45:00Z'));
  assert.equal(rows[1].recurrenceRule, undefined);
  assert.equal(h.state.calendars[0].getAccount().displayName, 'HITA · 2026 秋季');
});

test('native calendar query accepts omitted filters and returns identifiers for duplicate detection', async () => {
  const h = harness();
  h.state.events = [h.course()];
  assert.equal((await h.run()).success, true);
  const calendar = h.state.calendars[0];
  const firstId = calendar.rows[0].id;
  await assert.rejects(calendar.getEvents(undefined, ['id', 'identifier']), { code: 401 });
  assert.equal((await h.run()).success, true);
  assert.deepEqual(h.state.queryArgs, [[], [undefined, ['id', 'identifier']], []]);
  assert.equal(calendar.rows.length, 1);
  assert.equal(calendar.rows[0].id, firstId);
});

test('repeated exports and regenerated local IDs reuse the same calendar events', async () => {
  const h = harness();
  h.state.events = [h.course(), h.course()];
  assert.equal((await h.run()).total, 1);
  const id = h.state.calendars[0].rows[0].id;
  h.state.events = [h.course({ teacher: '李老师', place: 'B202' })];
  assert.equal((await h.run()).success, true);
  assert.equal(h.state.calendars.length, 1);
  assert.equal(h.state.calendars[0].rows.length, 1);
  assert.equal(h.state.calendars[0].rows[0].id, id);
  assert.equal(h.state.calendars[0].rows[0].location.location, 'B202');
  assert.match(h.state.calendars[0].rows[0].description, /李老师/);
});

test('changed dates replace stale exports while preserving user events and other timetables', async () => {
  const h = harness();
  h.state.events = [h.course()];
  await h.run();
  const calendar = h.state.calendars[0];
  const oldId = calendar.rows[0].id;
  calendar.rows.push({ id: 999, title: 'Personal' });
  const unrelated = h.makeCalendar({ name: 'personal', type: 'local' });
  unrelated.rows.push({ id: 1000, title: 'Appointment' });
  h.state.calendars.push(unrelated);
  const shifted = h.course({ from: h.course().from + 86400000, to: h.course().to + 86400000 });
  h.state.events = [shifted];
  assert.equal((await h.run()).success, true);
  assert.equal(calendar.rows.some(row => row.id === oldId), false);
  assert.equal(calendar.rows.some(row => row.id === 999), true);
  assert.deepEqual(unrelated.rows, [{ id: 1000, title: 'Appointment' }]);
  const second = { ...h.timetable, id: 'term-b' };
  h.state.timetables.set(second.id, second);
  h.state.events.push(h.course({ timetableId: second.id }));
  await h.run(second);
  assert.equal(h.state.calendars.length, 3);
  assert.equal(calendar.rows.length, 2);
});

test('permission denial, empty and deleted timetables do not access or mutate calendars', async () => {
  const h = harness();
  assert.equal((await h.exporter.exportTimetable({}, undefined)).success, false);
  assert.match((await h.run()).message, /没有可导出/);
  assert.equal(h.state.permissionCalls, 0);
  h.state.events = [h.course()];
  for (const permissions of [[0, -1], [-1, 0], [-1, -1], []]) {
    h.state.permissions = permissions;
    assert.match((await h.run()).message, /日历权限/);
  }
  assert.equal(h.state.calendarCalls, 0);
  h.state.timetables.clear();
  assert.match((await h.run()).message, /已删除/);
});

test('invalid event times fail before requesting permissions or exporting partial data', async () => {
  for (const overrides of [{ from: NaN }, { to: Infinity }, { from: 0 },
    { from: 10, to: 10 }, { from: 20, to: 10 }, { from: 1e20, to: 2e20 }]) {
    const h = harness();
    h.state.events = [h.course(), h.course(overrides)];
    assert.match((await h.run()).message, /无效的课程时间/);
    assert.equal(h.state.permissionCalls, 0);
    assert.equal(h.state.calendars.length, 0);
  }
});

test('partial failure can be retried without duplicates and does not prune previous exports', async () => {
  const h = harness();
  h.state.events = [h.course({ name: 'Old course' })];
  await h.run();
  h.state.events = [h.course(), h.course({ name: 'Physics' })];
  h.state.failAt = 3;
  const failed = await h.run();
  assert.equal(failed.success, false);
  assert.match(failed.message, /1\/2/);
  assert.equal(h.state.calendars[0].rows.length, 2);
  h.state.failAt = 0;
  assert.equal((await h.run()).success, true);
  assert.deepEqual(h.state.calendars[0].rows.map(row => row.title), ['高等数学', 'Physics']);
});

test('a committed write with a lost response is discovered on retry', async () => {
  const h = harness();
  h.state.events = [h.course()];
  h.state.failAfterInsert = true;
  assert.equal((await h.run()).success, false);
  assert.equal((await h.run()).success, true);
  assert.equal(h.state.calendars[0].rows.length, 1);
});

test('failed reads do not cause duplicate inserts; failed calendar creation is not success', async () => {
  const h = harness();
  h.state.events = [h.course()];
  h.state.failCreate = true;
  assert.equal((await h.run()).success, false);
  h.state.failCreate = false;
  await h.run();
  h.state.failRead = true;
  assert.equal((await h.run()).success, false);
  assert.equal(h.state.calendars[0].rows.length, 1);
});

test('failed stale-event deletion reports incomplete export and recovers on retry', async () => {
  const h = harness();
  h.state.events = [h.course()];
  await h.run();
  h.state.events = [h.course({ name: 'New course' })];
  h.state.failDelete = true;
  assert.equal((await h.run()).success, false);
  h.state.failDelete = false;
  assert.equal((await h.run()).success, true);
  assert.deepEqual(h.state.calendars[0].rows.map(row => row.title), ['New course']);
});

test('simultaneous exports share a lock that is released after completion', async () => {
  const h = harness();
  h.state.events = [h.course()];
  let release;
  h.state.permissionGate = new Promise(resolve => { release = resolve; });
  const first = h.run();
  assert.match((await h.run()).message, /正在导出/);
  release();
  assert.equal((await first).success, true);
  assert.equal((await h.run()).success, true);
  assert.equal(h.state.calendars[0].rows.length, 1);
});
