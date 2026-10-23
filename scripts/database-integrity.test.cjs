const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');
const { DatabaseSync } = require('node:sqlite');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const compile = source => ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText;

class Predicates {
  constructor(table) { this.table = table; this.filters = []; this.values = []; this.order = ''; this.limit = ''; }
  equalTo(key, value) { this.filters.push(`${key} = ?`); this.values.push(value); return this; }
  in(key, values) {
    this.filters.push(`${key} IN (${values.map(() => '?').join(',')})`);
    this.values.push(...values); return this;
  }
  orderByDesc(key) { this.order = ` ORDER BY ${key} DESC`; return this; }
  orderByAsc(key) { this.order = ` ORDER BY ${key} ASC`; return this; }
  limitAs(value) { this.limit = ` LIMIT ${value}`; return this; }
  where() { return this.filters.length ? ' WHERE ' + this.filters.join(' AND ') : ''; }
}

function load(file, overrides = {}, cache = new Map()) {
  file = path.resolve(root, file);
  if (cache.has(file)) return cache.get(file).exports;
  const mod = { exports: {} };
  cache.set(file, mod);
  new Function('require', 'module', 'exports', compile(fs.readFileSync(file, 'utf8')))(name => {
    if (overrides[name]) return overrides[name];
    if (name === '@kit.ArkData') return { relationalStore: { RdbPredicates: Predicates } };
    if (name === '@kit.PerformanceAnalysisKit') return { hilog: { info() {}, warn() {}, error() {} } };
    if (name.startsWith('@kit.')) return {};
    assert.ok(name.startsWith('.'), name);
    return load(path.resolve(path.dirname(file), name + '.ets'), overrides, cache);
  }, mod, mod.exports);
  return mod.exports;
}

const { RdbHelper } = load('common/db/RdbHelper.ets');
const { EasTimetable, EasTimePeriodInDay, EasTermSubject, EasEventItem, EasEventType, EasImportBaseEntry } =
  load('common/model/timetable/TimetableModels.ets');
const { EasTimetableImporter } = load('feature/eas/EasTimetableImporter.ets');
const { EasSession, EasCampus } = load('feature/eas/EasSession.ets');
const { EasCourseItem, EasTermItem } = load('feature/eas/model/EasModels.ets');
const day = 86400000;
const start = new Date(2026, 7, 31).getTime();
const legacyBenbuTimes = [
  [8, 0, 8, 50], [8, 55, 9, 45], [10, 5, 10, 55], [11, 0, 11, 50],
  [13, 30, 14, 20], [14, 25, 15, 15], [15, 25, 16, 15], [16, 20, 17, 10],
  [17, 20, 18, 10], [18, 30, 19, 20], [19, 30, 20, 20], [20, 30, 21, 20]
];
// Android CampusDefaultSchedule.BENBU_UNDERGRADUATE, checked on 2026-10-14.
const benbuTimes = [
  [8, 0, 8, 50], [8, 55, 9, 45], [10, 0, 10, 50], [10, 55, 11, 45],
  [13, 45, 14, 35], [14, 40, 15, 30], [15, 45, 16, 35], [16, 40, 17, 30],
  [18, 30, 19, 20], [19, 25, 20, 15], [20, 30, 21, 20], [21, 25, 22, 15]
];
const periods = rows => rows.map(row => EasTimePeriodInDay.ofHour(...row));
const periodRows = rows => rows.map(p => [p.from.hour, p.from.minute, p.to.hour, p.to.minute]);

function rowsResult(rows) {
  let index = -1;
  return {
    goToFirstRow: () => { index = 0; return rows.length > 0; },
    goToNextRow: () => ++index < rows.length,
    getColumnIndex: name => name,
    getLong: name => Number(rows[index][name]),
    getDouble: name => Number(rows[index][name]),
    getString: name => String(rows[index][name] ?? ''),
    close() {}
  };
}

function database() {
  const sql = new DatabaseSync(':memory:');
  const source = read('common/db/RdbHelper.ets');
  const schemas = source.slice(source.indexOf('const CREATE_TIMETABLE:'), source.indexOf('export class RdbHelper'));
  for (const schema of new Function(compile(schemas +
    '\nreturn [CREATE_TIMETABLE, CREATE_SUBJECT, CREATE_EVENTS, CREATE_IMPORT_BASE];'))()) {
    sql.exec(schema);
  }
  const ops = {
    insert: async (table, values) => {
      const keys = Object.keys(values);
      return Number(sql.prepare(`INSERT INTO ${table} (${keys.join(',')}) VALUES (${keys.map(() => '?').join(',')})`)
        .run(...keys.map(key => values[key])).lastInsertRowid);
    },
    update: async (values, pred) => {
      const keys = Object.keys(values);
      return sql.prepare(`UPDATE ${pred.table} SET ${keys.map(key => `${key}=?`).join(',')}${pred.where()}`)
        .run(...keys.map(key => values[key]), ...pred.values).changes;
    },
    delete: async pred => sql.prepare(`DELETE FROM ${pred.table}${pred.where()}`).run(...pred.values).changes,
    query: async (pred, columns = ['*']) => rowsResult(sql.prepare(
      `SELECT ${columns.join(',')} FROM ${pred.table}${pred.where()}${pred.order}${pred.limit}`).all(...pred.values)),
    execute: async (text, values = []) => sql.prepare(text).run(...values).changes
  };
  let failCommit = false;
  const db = new RdbHelper();
  db.store = { ...ops, createTransaction: async () => {
    sql.exec('BEGIN IMMEDIATE');
    return {
      ...ops,
      commit: async () => { if (failCommit) throw Error('commit failed'); sql.exec('COMMIT'); },
      rollback: async () => sql.exec('ROLLBACK')
    };
  } };
  const snapshot = () => ['timetable', 'subject', 'events'].map(table =>
    sql.prepare(`SELECT rowid, * FROM ${table} ORDER BY id`).all());
  return { db, sql, ops, snapshot, rejectCommit: () => { failCommit = true; } };
}

function table(id = 'a') {
  return Object.assign(new EasTimetable(), {
    id, code: id === 'a' ? 'BENBU:2026-20271' : 'LOCAL:' + id,
    name: 'Term ' + id, startTime: start, endTime: start + 21 * day - 1
  });
}
function subject(id = 'math', timetableId = 'a') {
  return Object.assign(new EasTermSubject(), { id, timetableId, name: 'Math', color: 0xff446688, credit: 3 });
}
function event(id, type = EasEventType.CLASS, timetableId = 'a', offset = 0) {
  return Object.assign(new EasEventItem(), {
    id, type, timetableId, subjectId: 'math', name: id, place: 'A101',
    from: start + offset + 8 * 3600000, to: start + offset + 10 * 3600000,
    fromNumber: 1, lastNumber: 2, color: type === EasEventType.EXAM ? 0xffee1111 : 0
  });
}
async function seed(db) {
  await db.saveTimetable(table());
  await db.saveTimetable(table('b'));
  await db.saveSubject(subject());
  await db.saveSubject(subject('other-subject', 'b'));
  for (const item of [
    event('old-one'), event('old-two', EasEventType.CLASS, 'a', day),
    event('exam', EasEventType.EXAM, 'a', 28 * day),
    event('memo', EasEventType.OTHER), event('other-table', EasEventType.CLASS, 'b')
  ]) await db.saveEvent(item);
}

test('failed single-row edits preserve timetable, subject and event identities and contents', async () => {
  for (const [tableName, item, save] of [
    ['timetable', table(), 'saveTimetable'],
    ['subject', subject(), 'saveSubject'],
    ['events', event('old-one'), 'saveEvent']
  ]) {
    const fixture = database();
    try {
      await seed(fixture.db);
      const before = fixture.snapshot();
      item.name = 'Changed';
      fixture.sql.exec(`CREATE TRIGGER fail_write BEFORE UPDATE ON ${tableName} BEGIN SELECT RAISE(ABORT, 'disk full'); END`);
      await assert.rejects(fixture.db[save](item), /disk full/);
      assert.deepEqual(fixture.snapshot(), before);
      fixture.sql.exec('DROP TRIGGER fail_write');
      await fixture.db[save](item);
      const saved = fixture.sql.prepare(`SELECT rowid, name FROM ${tableName} WHERE id=?`).get(item.id);
      assert.equal(saved.name, 'Changed');
      assert.equal(saved.rowid, before[['timetable', 'subject', 'events'].indexOf(tableName)].find(row => row.id === item.id).rowid);
    } finally { fixture.sql.close(); }
  }
});

test('batch timetable deletion rolls back every table on a midway failure', async () => {
  const f = database();
  try {
    await seed(f.db);
    const before = f.snapshot();
    f.sql.exec("CREATE TRIGGER fail_delete BEFORE DELETE ON subject BEGIN SELECT RAISE(ABORT, 'disk full'); END");
    await assert.rejects(f.db.deleteTimetablesCascade(['a']), /disk full/);
    assert.deepEqual(f.snapshot(), before);
    f.sql.exec('DROP TRIGGER fail_delete');
    await f.db.deleteTimetablesCascade(['a']);
    assert.deepEqual(f.snapshot(), before.map(rows => rows.filter(row =>
      (row.timetableId ?? row.id) !== 'a')));
    await f.db.deleteTimetablesCascade([]);
    assert.equal(f.sql.prepare('SELECT count(*) AS n FROM timetable').get().n, 1);
  } finally { f.sql.close(); }
});

test('re-import rolls back failed writes, then replaces courses without deleting exams or other tables', async () => {
  const f = database();
  try {
    await seed(f.db);
    const before = f.snapshot();
    const incoming = [event('new-one'), event('new-two', EasEventType.CLASS, 'a', 2 * day)];
    const edited = Object.assign(subject(), { credit: 4 });
    f.sql.exec("CREATE TRIGGER fail_import BEFORE INSERT ON events WHEN NEW.id = 'new-two' BEGIN SELECT RAISE(ABORT, 'disk full'); END");
    await assert.rejects(f.db.saveImportedTimetable(table(), [edited], incoming, true), /disk full/);
    assert.deepEqual(f.snapshot(), before);
    f.sql.exec('DROP TRIGGER fail_import');
    const imported = table();
    await f.db.saveImportedTimetable(imported, [edited], incoming, true);
    const after = f.snapshot();
    assert.deepEqual(after[2].filter(row => ['exam', 'memo', 'other-table'].includes(row.id)),
      before[2].filter(row => ['exam', 'memo', 'other-table'].includes(row.id)));
    assert.deepEqual(after[2].filter(row => row.timetableId === 'a' && row.type === 'CLASS').map(row => row.id),
      ['new-one', 'new-two']);
    assert.equal(after[1].find(row => row.id === 'math').color, subject().color);
    assert.equal(after[1].find(row => row.id === 'math').credit, 4);
    assert.equal(imported.endTime, start + 35 * day - 1, 'retained later exams remain inside the term');
    assert.equal(after[0].find(row => row.id === 'a').endTime, imported.endTime);
  } finally { f.sql.close(); }
});

test('new imports cannot leave partial records, overwrite another term, or report success after commit failure', async () => {
  const f = database();
  try {
    await seed(f.db);
    const before = f.snapshot();
    f.sql.exec("CREATE TRIGGER fail_import BEFORE INSERT ON events BEGIN SELECT RAISE(ABORT, 'disk full'); END");
    await assert.rejects(f.db.saveImportedTimetable(table('new'), [subject('new-subject', 'new')],
      [event('new-event', EasEventType.CLASS, 'new')], false), /disk full/);
    assert.deepEqual(f.snapshot(), before);
    f.sql.exec('DROP TRIGGER fail_import');
    await assert.rejects(f.db.saveImportedTimetable(table(), [subject()], [event('bad', EasEventType.CLASS, 'b')], true),
      /Invalid timetable/);
    await assert.rejects(f.db.saveImportedTimetable(table('missing'), [], [event('new', EasEventType.EXAM, 'missing')], true),
      /Invalid timetable/);
    await assert.rejects(f.db.saveImportedTimetable(table('missing'), [subject('m', 'missing')],
      [event('new', EasEventType.CLASS, 'missing')], true), /no longer exists/);
    assert.deepEqual(f.snapshot(), before);
    f.rejectCommit();
    await assert.rejects(f.db.saveImportedTimetable(table(), [subject()], [event('new')], true), /commit failed/);
    assert.deepEqual(f.snapshot(), before);
  } finally { f.sql.close(); }
});

const baseRows = sql => sql.prepare('SELECT timetableId, name, fromTime, toTime, signature FROM import_base ' +
  'ORDER BY timetableId, fromTime, name').all().map(row => ({ ...row }));
const entry = (item, signature = 'sig') => new EasImportBaseEntry(item.name, item.from, item.to, signature);

test('merge updates write only the listed classes and roll back as a whole', async () => {
  const f = database();
  try {
    await seed(f.db);
    await f.db.saveImportBase('a', [entry(event('old-one')), entry(event('old-two', EasEventType.CLASS, 'a', day))]);
    await f.db.saveImportBase('b', [entry(event('other-table', EasEventType.CLASS, 'b'))]);
    const before = f.snapshot();
    const baseBefore = baseRows(f.sql);
    const inserted = Object.assign(event('new-one', EasEventType.CLASS, 'a', 30 * day), { subjectId: 'chem' });
    const updated = Object.assign(event('old-one'), { place: 'B202', teacher: 'New teacher' });
    const removed = event('old-two', EasEventType.CLASS, 'a', day);
    const nextBase = [entry(updated, 'next'), entry(inserted, 'next')];
    const apply = () => f.db.applyTimetableMerge('a', [Object.assign(subject('chem'), { name: 'Chemistry' })],
      [inserted], [updated], [removed], nextBase);
    f.sql.exec("CREATE TRIGGER fail_base BEFORE INSERT ON import_base WHEN NEW.signature = 'next' " +
      "BEGIN SELECT RAISE(ABORT, 'disk full'); END");
    await assert.rejects(apply(), /disk full/);
    assert.deepEqual(f.snapshot(), before);
    assert.deepEqual(baseRows(f.sql), baseBefore);
    f.sql.exec('DROP TRIGGER fail_base');
    await apply();
    const after = f.snapshot();
    const rowOf = id => after[2].find(row => row.id === id);
    assert.equal(rowOf('old-one').place, 'B202');
    assert.equal(rowOf('old-one').rowid, before[2].find(row => row.id === 'old-one').rowid, 'updated in place');
    assert.equal(rowOf('old-two'), undefined);
    assert.ok(rowOf('new-one'));
    for (const id of ['exam', 'memo', 'other-table']) {
      assert.deepEqual(rowOf(id), before[2].find(row => row.id === id));
    }
    assert.deepEqual(after[1].map(row => row.id), ['chem', 'math', 'other-subject']);
    assert.equal(after[1].find(row => row.id === 'math').color, subject().color, 'existing subjects keep user settings');
    assert.equal(after[0].find(row => row.id === 'a').endTime, start + 35 * day - 1, 'a later class extends the term');
    assert.deepEqual(baseRows(f.sql).filter(row => row.timetableId === 'a').map(row => row.signature), ['next', 'next']);
    assert.deepEqual(baseRows(f.sql).filter(row => row.timetableId === 'b'), baseBefore.filter(row => row.timetableId === 'b'));
    await assert.rejects(f.db.applyTimetableMerge('a', [], [event('exam-like', EasEventType.EXAM)], [], [], []),
      /Invalid timetable merge/);
    await assert.rejects(f.db.applyTimetableMerge('missing', [], [], [], [], []), /no longer exists/);
  } finally { f.sql.close(); }
});

test('imports record the school base, and deleting or shifting a term keeps its base in step', async () => {
  const f = database();
  try {
    await seed(f.db);
    const incoming = [event('new-one'), event('new-two', EasEventType.CLASS, 'a', 7 * day)];
    await f.db.saveImportedTimetable(table(), [subject()], incoming, true, incoming.map(item => entry(item)));
    await f.db.saveImportBase('b', [entry(event('other-table', EasEventType.CLASS, 'b'))]);
    assert.deepEqual((await f.db.getImportBase('a')).map(item => item.name), ['new-one', 'new-two']);

    // A one-week shift moves every row onto the old slot of the next one; no row may collide midway.
    const old = table();
    const term = f.sql.prepare("SELECT startTime, endTime FROM timetable WHERE id='a'").get();
    await f.db.shiftTimetableStart('a', term.startTime, term.endTime, EasTimetable.mondayMsOf(old.startTime) + 7 * day);
    const shifted = await f.db.getImportBase('a');
    assert.deepEqual(shifted.map(item => item.from), incoming.map(item => item.from + 7 * day));
    const events = f.snapshot()[2].filter(row => row.id.startsWith('new-'));
    assert.deepEqual(events.map(row => row.fromTime), shifted.map(item => item.from), 'base and classes stay aligned');

    await f.db.deleteTimetablesCascade(['a']);
    assert.deepEqual(await f.db.getImportBase('a'), []);
    assert.equal((await f.db.getImportBase('b')).length, 1);
  } finally { f.sql.close(); }
});

test('start date changes roll back partial shifts and reject stale editor dates', async () => {
  const f = database();
  try {
    await seed(f.db);
    const before = f.snapshot();
    const old = table();
    const next = start + 7 * day;
    f.sql.exec("CREATE TRIGGER fail_shift BEFORE UPDATE ON events WHEN OLD.id='old-two' BEGIN SELECT RAISE(ABORT, 'disk full'); END");
    await assert.rejects(f.db.shiftTimetableStart('a', old.startTime, old.endTime, next), /disk full/);
    assert.deepEqual(f.snapshot(), before);
    f.sql.exec('DROP TRIGGER fail_shift');
    await f.db.shiftTimetableStart('a', old.startTime, old.endTime, next);
    const shifted = f.snapshot();
    assert.equal(shifted[0].find(row => row.id === 'a').startTime, next);
    for (const row of shifted[2]) {
      const original = before[2].find(item => item.id === row.id);
      assert.deepEqual({ ...row }, { ...original,
        fromTime: original.fromTime + (row.timetableId === 'a' ? 7 * day : 0),
        toTime: original.toTime + (row.timetableId === 'a' ? 7 * day : 0) });
    }
    await assert.rejects(f.db.shiftTimetableStart('a', old.startTime, old.endTime, next + 7 * day), /reload/);
    assert.deepEqual(f.snapshot(), shifted);
  } finally { f.sql.close(); }
});

test('invalid academic courses leave existing data intact and duplicate teaching rows merge before committing', async () => {
  const f = database();
  try {
    await seed(f.db);
    const session = Object.assign(new EasSession(), { campus: EasCampus.BENBU });
    const term = Object.assign(new EasTermItem(), { yearCode: '2026-2027', termCode: '1', yearName: '2026-2027', termName: 'Autumn' });
    const course = () => Object.assign(new EasCourseItem(), {
      name: 'Math', dayOfWeek: 1, beginSection: 1, sectionCount: 2, weekNumbers: [1, 2], teacher: 'Teacher A', classroom: 'A101'
    });
    const before = f.snapshot();
    for (const override of [{ dayOfWeek: 8 }, { beginSection: 99 }, { weekNumbers: [] }]) {
      await assert.rejects(EasTimetableImporter.saveCourses(f.db, session, term, [Object.assign(course(), override)],
        EasTimetableImporter.scheduleStructure(EasCampus.BENBU), start));
      assert.deepEqual(f.snapshot(), before);
    }
    await EasTimetableImporter.saveCourses(f.db, session, term,
      [course(), Object.assign(course(), { teacher: 'Teacher B', classroom: 'A102' })],
      EasTimetableImporter.scheduleStructure(EasCampus.BENBU), start);
    const lessons = f.sql.prepare("SELECT * FROM events WHERE timetableId='a' AND type='CLASS'").all();
    assert.equal(lessons.length, 2);
    assert.ok(lessons.every(row => row.teacher === 'Teacher A/Teacher B' && row.place === 'A101/A102'));
    assert.equal(f.sql.prepare("SELECT count(*) AS n FROM events WHERE id='exam'").get().n, 1);
  } finally { f.sql.close(); }
});

test('ICS imports publish all records before changing the active timetable', async () => {
  for (const fail of [true, false]) {
    const f = database();
    try {
      await seed(f.db);
      const before = f.snapshot();
      const selected = [];
      const { TimetableIcsImporter } = load('feature/timetable/data/TimetableIcsImporter.ets', {
        '../../../common/db/RdbHelper': { RdbHelper: { getInstance: () => f.db } },
        './TimetableSelectionStore': { TimetableSelectionStore: {
          getInstance: () => ({ init: async () => {}, save: async id => selected.push(id) })
        } }
      });
      if (fail) f.sql.exec("CREATE TRIGGER fail_ics BEFORE INSERT ON events WHEN NEW.name='Second' BEGIN SELECT RAISE(ABORT, 'disk full'); END");
      const ics = ['BEGIN:VCALENDAR', 'VERSION:2.0',
        'BEGIN:VEVENT', 'UID:first', 'DTSTART:20260831T080000', 'DTEND:20260831T090000', 'SUMMARY:First', 'END:VEVENT',
        'BEGIN:VEVENT', 'UID:second', 'DTSTART:20260901T080000', 'DTEND:20260901T090000', 'SUMMARY:Second', 'END:VEVENT',
        'END:VCALENDAR'].join('\r\n');
      if (fail) {
        await assert.rejects(TimetableIcsImporter.importText({}, ics, 'Imported'), /disk full/);
        assert.deepEqual(f.snapshot(), before);
        assert.deepEqual(selected, []);
      } else {
        const result = await TimetableIcsImporter.importText({}, ics, 'Imported');
        assert.equal(result.success, true);
        assert.deepEqual(selected, [result.timetableId]);
        assert.equal(f.sql.prepare('SELECT count(*) AS n FROM events WHERE timetableId=?').get(result.timetableId).n, 2);
      }
    } finally { f.sql.close(); }
  }
});

test('Benbu imports convert every section to the undergraduate bell schedule, independently of other campuses', async () => {
  assert.deepEqual(periodRows(EasTimetableImporter.scheduleStructure(EasCampus.BENBU)), benbuTimes);
  assert.deepEqual(periodRows(EasTimetableImporter.scheduleStructure(EasCampus.SHENZHEN)),
    periodRows(EasTimetable.getDefaultTimeStructure()));
  assert.deepEqual(periodRows(EasTimetableImporter.scheduleStructure(EasCampus.WEIHAI)),
    periodRows(EasTimetable.getWeihaiTimeStructure()));
  const modified = EasTimetableImporter.scheduleStructure(EasCampus.BENBU);
  modified[4].from.minute = 0;
  assert.equal(EasTimetableImporter.scheduleStructure(EasCampus.BENBU)[4].from.minute, 45);
  const f = database();
  try {
    const session = Object.assign(new EasSession(), { campus: EasCampus.BENBU });
    const term = Object.assign(new EasTermItem(), { yearCode: '2026-2027', termCode: '1' });
    const courses = benbuTimes.map((_, i) => Object.assign(new EasCourseItem(), {
      name: `Course ${i + 1}`, dayOfWeek: 3, beginSection: i + 1, sectionCount: 1, weekNumbers: [1, 2]
    }));
    await EasTimetableImporter.saveCourses(f.db, session, term, courses,
      EasTimetableImporter.scheduleStructure(EasCampus.BENBU), start);
    const lessons = f.sql.prepare('SELECT * FROM events').all();
    assert.equal(lessons.length, 24);
    for (const lesson of lessons) {
      const time = benbuTimes[lesson.fromNumber - 1];
      const date = new Date(lesson.fromTime);
      assert.equal(date.getDay(), 3);
      assert.deepEqual([date.getHours(), date.getMinutes()], time.slice(0, 2));
      const end = new Date(lesson.toTime);
      assert.deepEqual([end.getHours(), end.getMinutes()], time.slice(2));
    }
  } finally { f.sql.close(); }
});

async function seedLegacyBenbu(db) {
  const timetable = table();
  timetable.scheduleStructure = periods(legacyBenbuTimes);
  await db.saveTimetable(timetable);
  await db.saveSubject(subject());
  for (let i = 0; i < 12; i += 2) {
    const times = timetable.getTimestamps(2, 3, i + 1, i + 2);
    await db.saveEvent(Object.assign(event(`legacy-${i}`), {
      from: times[0], to: times[1], fromNumber: i + 1, lastNumber: i + 2
    }));
  }
  const fifth = timetable.getTimestamps(1, 1, 5, 6);
  await db.saveEvent(Object.assign(event('edited'), {
    from: fifth[0] + 60000, to: fifth[1], fromNumber: 5, lastNumber: 6
  }));
  for (const [id, type] of [['exam', EasEventType.EXAM], ['memo', EasEventType.OTHER]]) {
    await db.saveEvent(Object.assign(event(id, type), {
      from: fifth[0], to: fifth[1], fromNumber: 5, lastNumber: 6
    }));
  }
  await db.saveEvent(Object.assign(event('invalid-section'), { fromNumber: 99, lastNumber: 100 }));
  await db.saveEvent(Object.assign(event('no-section'), { fromNumber: 0, lastNumber: 0 }));
}

test('saved Benbu courses are repaired once while preserving dates, identity, edits and non-course events', async () => {
  const f = database();
  try {
    await seedLegacyBenbu(f.db);
    const before = f.snapshot();
    await f.db.repairLegacyBenbuTimetables();
    const after = f.snapshot();
    const saved = await f.db.getTimetableById('a');
    assert.deepEqual(periodRows(saved.scheduleStructure), benbuTimes);
    assert.deepEqual(after[0].map(row => ({ ...row })), before[0].map(row => ({
      ...row, scheduleStructure: EasTimetable.encodeStructure(periods(benbuTimes))
    })));
    assert.deepEqual(after[1], before[1]);
    for (const row of after[2]) {
      const original = before[2].find(item => item.id === row.id);
      if (!row.id.startsWith('legacy-')) {
        assert.deepEqual(row, original);
        continue;
      }
      const expected = saved.getTimestamps(2, 3, row.fromNumber, row.lastNumber);
      assert.deepEqual({ ...row }, { ...original, fromTime: expected[0], toTime: expected[1] });
    }
    await f.db.repairLegacyBenbuTimetables();
    assert.deepEqual(f.snapshot(), after);
    const source = read('common/db/RdbHelper.ets');
    assert.match(source.slice(source.indexOf('private async openStore('),
      source.indexOf('private async ensureEventColorColumn(')), /await this\.repairLegacyBenbuTimetables\(\)/);
  } finally { f.sql.close(); }
});

test('Benbu repair does not touch other campuses, local timetables or any customized schedule', async () => {
  const f = database();
  try {
    const variants = [
      ['weihai', 'WEIHAI:2026-20271', periods(legacyBenbuTimes)],
      ['shenzhen', 'SHENZHEN:2026-20271', periods(legacyBenbuTimes)],
      ['local', '', periods(legacyBenbuTimes)],
      ['correct', 'BENBU:2025-20261', periods(benbuTimes)],
      ['custom', 'BENBU:2025-20262', periods(legacyBenbuTimes)]
    ];
    variants[4][2][9].from.minute = 35;
    for (const [id, code, scheduleStructure] of variants) {
      await f.db.saveTimetable(Object.assign(table(id), { code, scheduleStructure }));
      await f.db.saveEvent(event(id, EasEventType.CLASS, id));
    }
    const before = f.snapshot();
    await f.db.repairLegacyBenbuTimetables();
    assert.deepEqual(f.snapshot(), before);
  } finally { f.sql.close(); }
});

test('Benbu repair rolls back every timestamp and the schedule if a write or commit fails', async () => {
  for (const failCommit of [false, true]) {
    const f = database();
    try {
      await seedLegacyBenbu(f.db);
      const before = f.snapshot();
      if (failCommit) f.rejectCommit();
      else f.sql.exec("CREATE TRIGGER fail_repair BEFORE UPDATE ON events WHEN OLD.id='legacy-4' BEGIN SELECT RAISE(ABORT, 'disk full'); END");
      await assert.rejects(f.db.repairLegacyBenbuTimetables(), failCommit ? /commit failed/ : /disk full/);
      assert.deepEqual(f.snapshot(), before);
      if (!failCommit) {
        f.sql.exec('DROP TRIGGER fail_repair');
        await f.db.repairLegacyBenbuTimetables();
        assert.deepEqual(periodRows((await f.db.getTimetableById('a')).scheduleStructure), benbuTimes);
      }
    } finally { f.sql.close(); }
  }
});
