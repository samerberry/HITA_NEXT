const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const cache = new Map();
const pageSource = fs.readFileSync(path.join(root, 'pages/TimetableDetailPage.ets'), 'utf8');

// ArkUI compiles inline builder arguments to getters retained with the keyed card.
// Read the actual binding expressions so this also detects a return to captured indices.
function retainedCourseBinding(host, row, index) {
  const body = pageSource.match(/this\.courseGroupCard\(\{([\s\S]*?)\}\)/)[1];
  const fields = ['subject', 'classCount', 'sessions'].map(key => {
    const expression = body.match(new RegExp(key + ': ([^,\r\n]+)'))[1];
    return `${key}: { get: () => ${expression} }`;
  });
  return new Function('row', 'index', `return Object.defineProperties({}, {${fields.join(',')}});`)
    .call(host, row, index);
}

class Predicates {
  constructor(table) {
    this.table = table;
    this.filters = [];
  }
  equalTo(column, value) {
    this.filters.push([column, value]);
    return this;
  }
}

function load(file) {
  file = path.resolve(root, file);
  if (cache.has(file)) return cache.get(file).exports;
  const mod = { exports: {} };
  cache.set(file, mod);
  const source = fs.readFileSync(file, 'utf8');
  const js = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  new Function('require', 'module', 'exports', js)(name => {
    if (name === '@kit.PerformanceAnalysisKit') return { hilog: { error() {} } };
    if (name === '@kit.ArkData') return { relationalStore: { RdbPredicates: Predicates } };
    if (name.startsWith('@kit.')) return {};
    return load(path.resolve(path.dirname(file), name + '.ets'));
  }, mod, mod.exports);
  return mod.exports;
}

const { RdbHelper } = load('common/db/RdbHelper.ets');

function database(options = {}) {
  const rows = {
    subject: [
      { id: 'course-a', timetableId: 'table-a' },
      { id: 'course-a', timetableId: 'table-b' },
      { id: 'course-b', timetableId: 'table-a' }
    ],
    events: [
      { id: 'one', subjectId: 'course-a', timetableId: 'table-a', type: 'CLASS' },
      { id: 'two', subjectId: 'course-a', timetableId: 'table-a', type: 'CLASS' },
      { id: 'exam', subjectId: 'course-a', timetableId: 'table-a', type: 'EXAM' },
      { id: 'other-table', subjectId: 'course-a', timetableId: 'table-b', type: 'CLASS' },
      { id: 'other-course', subjectId: 'course-b', timetableId: 'table-a', type: 'CLASS' }
    ]
  };
  const calls = [];
  const db = new RdbHelper();
  db.store = {
    createTransaction: async () => {
      const snapshot = structuredClone(rows);
      return {
        delete: async pred => {
          calls.push(['delete', pred.table, pred.filters]);
          if (options.failOn === pred.table) throw Error('disk full');
          const before = rows[pred.table].length;
          rows[pred.table] = rows[pred.table].filter(row =>
            !pred.filters.every(([column, value]) => row[column] === value));
          return before - rows[pred.table].length;
        },
        commit: async () => { calls.push(['commit']); },
        rollback: async () => {
          calls.push(['rollback']);
          rows.subject = snapshot.subject;
          rows.events = snapshot.events;
        }
      };
    }
  };
  return { db, rows, calls };
}

test('whole-course deletion removes only matching CLASS sessions and preserves linked exams', async () => {
  const { db, rows, calls } = database();
  await db.deleteCourseWithClasses('course-a', 'table-a');
  assert.deepEqual(rows.subject.map(row => row.timetableId + ':' + row.id),
    ['table-b:course-a', 'table-a:course-b']);
  assert.deepEqual(rows.events.map(row => row.id),
    ['exam', 'other-table', 'other-course']);
  assert.deepEqual(calls, [
    ['delete', 'subject', [['id', 'course-a'], ['timetableId', 'table-a']]],
    ['delete', 'events', [['subjectId', 'course-a'], ['timetableId', 'table-a'], ['type', 'CLASS']]],
    ['commit']
  ]);
});

test('failed deletion and missing course roll back without touching other rows', async () => {
  const failed = database({ failOn: 'events' });
  const before = structuredClone(failed.rows);
  await assert.rejects(failed.db.deleteCourseWithClasses('course-a', 'table-a'), /disk full/);
  assert.deepEqual(failed.rows, before);
  assert.deepEqual(failed.calls.at(-1), ['rollback']);

  const missing = database();
  await assert.rejects(missing.db.deleteCourseWithClasses('missing', 'table-a'), /no longer exists/);
  assert.deepEqual(missing.calls.map(call => call[0]), ['delete', 'rollback']);
  await assert.rejects(missing.db.deleteCourseWithClasses('', 'table-a'), /identity/);
});

async function confirmCourse(choice, fail = false, reminderFail = false, options = {}) {
  const source = pageSource;
  const method = source.slice(source.indexOf('  private currentSubjectRow('),
    source.indexOf('  /** 教务数据未提供考核方式')).replace('private confirmDeleteCourse', 'confirmDeleteCourse');
  const js = ts.transpileModule('class Host { ' + method + ' }; module.exports = Host;', {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const mod = { exports: {} };
  const calls = { deleted: [], particles: [], closed: 0, animated: 0, reminders: 0, dialogs: [], toasts: [], navigation: [] };
  const rdb = { getInstance: () => ({ deleteCourseWithClasses: async (...ids) => {
    calls.deleted.push(ids);
    if (fail) throw Error('disk full');
  } }) };
  new Function('RdbHelper', 'HitaColors', '$r', 'Curve', 'EasEventType', 'module', js)(
    rdb, { error: 'red' }, value => value, { EaseInOut: 'ease' }, { CLASS: 'CLASS' }, mod);
  const host = new mod.exports();
  host.pendingDeleteCourseId = '';
  host.detailScroller = { closeAllSwipeActions() { calls.closed++; } };
  host.subjectRows = options.rows || [
    { subject: { id: 'course-a', timetableId: 'table-a', name: '物理' }, classCount: 2, sessions: [] },
    { subject: { id: 'course-b', timetableId: 'table-a', name: '数学' }, classCount: 1, sessions: [] }
  ];
  const target = host.subjectRows[options.deleteIndex || 0];
  const bindings = host.subjectRows.map((row, index) => retainedCourseBinding(host, row, index));
  host.deleteEffects = { play: async ids => {
    assert.deepEqual(calls.deleted, [[target.subject.id, target.subject.timetableId]],
      'write must succeed before particles');
    calls.particles.push(ids);
    if (options.particles) await options.particles;
  } };
  host.eventRows = [
    { subjectId: 'course-a', timetableId: 'table-a', type: 'CLASS' },
    { subjectId: 'course-a', timetableId: 'table-a', type: 'EXAM' },
    { subjectId: 'course-a', timetableId: 'table-b', type: 'CLASS' },
    { subjectId: 'course-b', timetableId: 'table-a', type: 'CLASS' }
  ];
  host.expandedSubjectId = target.subject.id;
  host.resyncReminders = async () => {
    calls.reminders++;
    if (reminderFail) throw Error('notification unavailable');
  };
  host.getUIContext = () => ({
    animateTo: (_options, callback) => { calls.animated++; callback(); },
    getRouter: () => ({
      back: () => calls.navigation.push('back'),
      replaceUrl: () => calls.navigation.push('replaceUrl'),
      pushUrl: () => calls.navigation.push('pushUrl')
    }),
    getPromptAction: () => ({
      showDialog: async options => { calls.dialogs.push(options); return { index: choice }; },
      showToast: options => { calls.toasts.push(options.message); }
    })
  });
  host.confirmDeleteCourse(target);
  await new Promise(resolve => setImmediate(resolve));
  return { host, calls, bindings };
}

test('cancel and write failure leave the course visible; success removes only its class rows', async () => {
  const cancelled = await confirmCourse(0);
  assert.equal(cancelled.calls.closed, 1);
  assert.match(cancelled.calls.dialogs[0].message, /全部 2 次课/);
  assert.deepEqual(cancelled.calls.deleted, []);
  assert.deepEqual(cancelled.calls.particles, []);
  assert.equal(cancelled.host.pendingDeleteCourseId, '');
  assert.equal(cancelled.host.subjectRows.length, 2);

  const failed = await confirmCourse(1, true);
  assert.deepEqual(failed.calls.deleted, [['course-a', 'table-a']]);
  assert.equal(failed.host.subjectRows.length, 2);
  assert.equal(failed.calls.animated, 0);
  assert.deepEqual(failed.calls.particles, []);
  assert.deepEqual(failed.calls.toasts, ['删除失败，请重试']);

  const saved = await confirmCourse(1);
  assert.deepEqual(saved.host.subjectRows.map(row => row.subject.id), ['course-b']);
  assert.deepEqual(saved.host.eventRows.map(row => row.type), ['EXAM', 'CLASS', 'CLASS']);
  assert.equal(saved.host.expandedSubjectId, '');
  assert.equal(saved.calls.animated, 1);
  assert.deepEqual(saved.calls.particles, [['course-a']]);
  assert.equal(saved.host.pendingDeleteCourseId, '');
  assert.equal(saved.calls.reminders, 1);
  assert.deepEqual(saved.calls.toasts, ['课程及全部课时已删除']);

  const reminderFailed = await confirmCourse(1, false, true);
  assert.equal(reminderFailed.host.subjectRows.length, 1);
  assert.deepEqual(reminderFailed.calls.toasts, ['课程已删除，但提醒同步失败']);
});

for (const [position, count, deleteIndex] of [['first', 3, 0], ['middle', 3, 1], ['last', 3, 2], ['only', 1, 0]]) {
  test(`deleting the ${position} course keeps retained card bindings valid and stays on the detail page`, async () => {
    const rows = Array.from({ length: count }, (_, index) => ({
      subject: { id: 'course-' + index, timetableId: 'table-a', name: '课程' + index, type: 'COM_A' },
      classCount: index + 1, sessions: [{ id: 'session-' + index }]
    }));
    let finishParticles;
    const particles = new Promise(resolve => { finishParticles = resolve; });
    const { host, calls, bindings } = await confirmCourse(1, false, false, { rows, deleteIndex, particles });
    assert.equal(host.subjectRows, rows, 'keep rows alive until the particle animation finishes');
    assert.equal(host.pendingDeleteCourseId, rows[deleteIndex].subject.id);
    assert.equal(calls.animated, 0);
    assert.equal(calls.reminders, 0);
    host.confirmDeleteCourse(rows[deleteIndex]);
    assert.equal(calls.dialogs.length, 1, 'ignore repeated deletes while animating');
    finishParticles();
    await new Promise(resolve => setImmediate(resolve));
    const survivors = rows.filter((_, index) => index !== deleteIndex);
    assert.deepEqual(host.subjectRows, survivors);
    // Both surviving and exiting builders may be evaluated after the array shrinks.
    for (const [index, binding] of bindings.entries()) {
      assert.equal(binding.subject, rows[index].subject);
      assert.equal(binding.classCount, rows[index].classCount);
      assert.equal(binding.sessions, rows[index].sessions);
    }
    host.subjectRows = survivors.map(row => ({
      subject: { ...row.subject, type: 'COM_B' }, classCount: row.classCount + 1,
      sessions: [...row.sessions, { id: row.subject.id + '-new' }]
    })).reverse();
    for (const [index, binding] of bindings.entries()) {
      const expected = host.subjectRows.find(row => row.subject.id === rows[index].subject.id) || rows[index];
      assert.equal(binding.subject, expected.subject, 'retained cards must read live state by identity');
      assert.equal(binding.classCount, expected.classCount);
      assert.equal(binding.sessions, expected.sessions);
    }
    assert.equal(host.pendingDeleteCourseId, '');
    assert.equal(host.expandedSubjectId, '');
    assert.equal(calls.animated, 1);
    assert.equal(calls.reminders, 1);
    assert.deepEqual(calls.navigation, []);
    assert.deepEqual(calls.toasts, ['课程及全部课时已删除']);
  });
}

test('a departing course never binds to a same-id course from another timetable', async () => {
  const rows = ['table-a', 'table-b'].map(timetableId => ({
    subject: { id: 'course-a', timetableId, name: timetableId }, classCount: 1, sessions: []
  }));
  const { host, bindings } = await confirmCourse(1, false, false, { rows });
  assert.deepEqual(host.subjectRows, [rows[1]]);
  assert.equal(bindings[0].subject, rows[0].subject);
  assert.equal(bindings[1].subject, rows[1].subject);
});

test('detail page uses native left swipe, confirmation and animated expansion', () => {
  const source = fs.readFileSync(path.join(root, 'pages/TimetableDetailPage.ets'), 'utf8');
  const build = source.slice(source.indexOf('  build()'), source.indexOf('  private static dateText('));
  const toggle = source.slice(source.indexOf('  private toggleSubject('),
    source.indexOf('  private async saveSubjectCredit('));
  const deleteAction = source.slice(source.indexOf('  private courseDeleteAction('),
    source.indexOf('  private sessionRow('));
  assert.match(build, /List\(\{ scroller: this\.detailScroller \}\)/);
  assert.match(build, /ListItem\(\) \{\s*DeleteParticleCard\([\s\S]*?this\.courseGroupCard\(\{[\s\S]*?subject: this\.currentSubjectRow\(row\)\.subject,[\s\S]*?\.swipeAction\(\{\s*end:/);
  assert.match(build, /edgeEffect: SwipeEdgeEffect\.None/);
  assert.match(source, /deleteCourseWithClasses\(subjectId, timetableId\)/);
  assert.match(source, /if \(ret\.index !== 1\)/);
  assert.match(source, /event\.type !== EasEventType\.CLASS/);
  assert.doesNotMatch(source, /confirmDeleteEvent/);
  assert.match(toggle, /animateTo\(\{ duration: 300, curve: Curve\.EaseInOut \}/);
  assert.match(source, /\.transition\(TransitionEffect\.OPACITY\)/);
  assert.match(deleteAction, /SymbolGlyph\(\$r\('sys\.symbol\.trash'\)\)/);
  assert.doesNotMatch(deleteAction, /\.shadow\(/);
});
