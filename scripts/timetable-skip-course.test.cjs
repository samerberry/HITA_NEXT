const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const home = fs.readFileSync(path.join(root, 'pages/Home.ets'), 'utf8').replace(/\r\n/g, '\n');
const slice = (source, start, end) => {
  const from = source.indexOf(start);
  const to = source.indexOf(end, from);
  assert.ok(from >= 0 && to > from, start);
  return source.slice(from, to);
};
const compile = source => ts.transpileModule(source, {
  compilerOptions: { target: ts.ScriptTarget.ES2020 }
}).outputText;
const deferred = () => {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
};
const flush = async () => { for (let i = 0; i < 12; i++) await Promise.resolve(); };

function harness() {
  const course = { id: 'lesson', type: 'CLASS', name: '高等数学', timetableId: 'table' };
  const nextWeek = { ...course, id: 'next-week' };
  const exam = { ...course, id: 'exam', type: 'EXAM' };
  const state = {
    dialogs: [], toasts: [], writes: [], effects: [], syncs: [], refreshes: [],
    answer: async () => ({ index: 1 }), write: async () => {}, animate: async () => {}
  };
  const context = {
    getHostContext: () => ({}),
    getPromptAction: () => ({
      showDialog: async options => { state.dialogs.push(options); return state.answer(); },
      showToast: options => state.toasts.push(options.message)
    })
  };
  const binding = slice(home, '.bindSheet($$this.activeSheetVisible,', '\n  @Builder\n  compatibleDock()');
  const disappear = binding.match(/onDisappear: \(\) => \{([\s\S]*?)\n      \}/)[1];
  const panCancel = home.match(/\.onActionCancel\(\(\) => \{([\s\S]*?)\n            \}\)/)[1];
  const code = `class Home {
    pageVisible = true; currentTab = 1; timetableWeek = 6;
    currentTimetable = { id: 'table' };
    skippingCourse = false; courseSkipAnimating = false;
    courseSheetOpen = true; activeSheetVisible = true; courseColorEditing = false;
    sheetRequestGeneration = 0; summaryRequestGeneration = 0;
    classReminderEnabled = true; courseSheetDismissTimer = -1;
    timetableAnimating = false; timetableDragOffset = 0; timetableAnimationTimer = -1;
    timetableCardSurfaces = [{ key: 'card', eventIds: ['lesson'], left: 10, top: 24, width: 40, height: 90 }];
    timetableEvents = [course, nextWeek, exam]; todayItems = [course, exam]; selectedCourse = course;
    getUIContext() { return context; }
    drawTimetableNow() { this.draws = (this.draws || 0) + 1; }
    updateTodayHighlights() { this.highlights = (this.highlights || 0) + 1; }
    async refreshSummaries(preserve) { state.refreshes.push(preserve); }
    canOpenSheet() { return !this.activeSheetVisible && !this.skippingCourse; }
    disappear() { ${disappear} }
    cancelWeekPan() { ${panCancel} }
    ${slice(home, '  private resetTimetableAnimationState()', '  private animateTimetableWeek(')}
    ${slice(home, '  private openCourseAt(', '  private async saveCourseColor(')}
    ${slice(home, '  private closeActiveSheet()', '  private requestCalendarExport()')}
  }`;
  const rdb = { getInstance: () => ({
    deleteClassOccurrences: async (ids, table) => {
      state.writes.push([ids, table]);
      await state.write();
    }
  }) };
  const reminders = { sync: async (_ctx, events) => state.syncs.push(events.map(event => event.id)) };
  const page = new Function('course', 'nextWeek', 'exam', 'context', 'state', 'RdbHelper',
    'EasEventType', 'ClassReminderScheduler', '$r', 'TAB_TIMETABLE', 'TIMETABLE_GRID_TOP_PADDING',
    'TIMETABLE_SLIDE_MS', 'NextClassWidgetService',
    compile(code) + '; return new Home();')(
    course, nextWeek, exam, context, state, rdb, { CLASS: 'CLASS', EXAM: 'EXAM' },
    reminders, value => value, 1, 24, 220, { scheduleRefresh() {} });
  page.courseDeleteEffects = { play: async ids => {
    assert.equal(page.courseSheetOpen, false, 'particles must wait for actual sheet dismissal');
    assert.equal(state.writes.length, 1, 'persist before animating');
    assert.ok(!page.timetableEvents.some(item => item.id === course.id));
    state.effects.push(ids);
    await state.animate();
  } };
  return { page, state, course, nextWeek, exam };
}

test('cancel and outside/back dismissal leave the class intact and produce no error toast', async () => {
  for (const reject of [false, true]) {
    const { page, state, course } = harness();
    state.answer = async () => { if (reject) throw Error('cancel'); return { index: 0 }; };
    await page.confirmSkipCourse(course);
    assert.deepEqual(state.writes, []);
    assert.deepEqual(state.effects, []);
    assert.deepEqual(state.toasts, []);
    assert.equal(page.timetableEvents[0], course);
    assert.equal(page.activeSheetVisible, true);
    assert.equal(page.skippingCourse, false);
  }
});

test('skip waits for sheet dismissal and dissolve completion, then toasts and updates reminders', async () => {
  const { page, state, course } = harness();
  const animation = deferred();
  state.animate = () => animation.promise;
  const pending = page.confirmSkipCourse(course);
  await flush();
  assert.deepEqual(state.dialogs[0].buttons.map(item => item.text), ['我去上课', '我意已决']);
  assert.equal(state.dialogs[0].title, '确定要翘掉这节课吗？');
  assert.deepEqual(state.writes, [[['lesson'], 'table']]);
  assert.equal(page.activeSheetVisible, false);
  assert.deepEqual(state.effects, []);
  assert.deepEqual(page.timetableEvents.map(item => item.id), ['next-week', 'exam']);
  assert.deepEqual(page.todayItems.map(item => item.id), ['exam']);
  page.disappear();
  await flush();
  assert.deepEqual(state.effects, [['card']]);
  assert.deepEqual(state.toasts, []);
  animation.resolve();
  await pending;
  assert.deepEqual(state.toasts, ['这节高等数学如奶油般化开了。']);
  assert.deepEqual(state.syncs, [['next-week', 'exam']]);
  assert.deepEqual(state.refreshes, [true]);
  assert.equal(page.timetableWeek, 6);
  assert.equal(page.skippingCourse, false);
  assert.equal(page.courseSkipAnimating, false);
});

test('a failed write keeps the sheet, card and lesson and allows retry', async () => {
  const { page, state, course } = harness();
  state.write = async () => { throw Error('disk full'); };
  await page.confirmSkipCourse(course);
  assert.equal(page.timetableEvents[0], course);
  assert.equal(page.todayItems[0], course);
  assert.equal(page.activeSheetVisible, true);
  assert.equal(page.skippingCourse, false);
  assert.deepEqual(state.effects, []);
  assert.deepEqual(state.syncs, []);
  assert.deepEqual(state.toasts, ['未能翘掉这节课，请重试']);
});

test('exams, other tabs and stale details cannot invoke skipping', async () => {
  for (const change of [
    ({ page, exam }) => { page.selectedCourse = exam; },
    ({ page }) => { page.currentTab = 0; },
    ({ page }) => { page.courseSheetOpen = false; },
    ({ page }) => { page.activeSheetVisible = false; },
    ({ page }) => { page.pageVisible = false; }
  ]) {
    const h = harness();
    change(h);
    await h.page.confirmSkipCourse(h.page.selectedCourse);
    assert.deepEqual(h.state.dialogs, []);
    assert.deepEqual(h.state.writes, []);
  }
});

test('duplicate taps produce one dialog, and a late confirmation after leaving does not delete', async () => {
  const { page, state, course } = harness();
  const answer = deferred();
  state.answer = () => answer.promise;
  const pending = page.confirmSkipCourse(course);
  await page.confirmSkipCourse(course);
  assert.equal(state.dialogs.length, 1);
  page.closeActiveSheet();
  answer.resolve({ index: 1 });
  await pending;
  assert.deepEqual(state.writes, []);
  assert.equal(page.skippingCourse, false);
});

test('leaving during a successful write persists the deletion without reopening a sheet or animating', async () => {
  const { page, state, course } = harness();
  const write = deferred();
  state.write = () => write.promise;
  const pending = page.confirmSkipCourse(course);
  await flush();
  page.pageVisible = false;
  page.closeActiveSheet();
  write.resolve();
  await pending;
  assert.deepEqual(state.effects, []);
  assert.deepEqual(state.toasts, []);
  assert.deepEqual(state.syncs, [['next-week', 'exam']]);
  assert.equal(page.activeSheetVisible, false);
});

test('side-by-side overlapping cards select by actual horizontal bounds, and gaps do nothing', () => {
  const { page, course, exam } = harness();
  page.activeSheetVisible = false;
  page.timetableCardSurfaces.push({ key: 'exam-card', eventIds: ['exam'],
    left: 55, top: 24, width: 40, height: 90 });
  page.openCourseAt(30, 50);
  assert.equal(page.selectedCourse, course);
  page.activeSheetVisible = false;
  page.openCourseAt(75, 50);
  assert.equal(page.selectedCourse, exam);
  page.activeSheetVisible = false;
  page.openCourseAt(52, 50);
  assert.equal(page.activeSheetVisible, false);
});

test('material clicks open courses and exams by identity without depending on scrolled or transformed coordinates', () => {
  const { page, course, exam } = harness();
  page.timetableCardSurfaces.push({ key: 'exam-card', eventIds: ['exam'],
    left: 55, top: 900, width: 40, height: 90 });
  for (const [key, expected] of [['card', course], ['exam-card', exam]]) {
    page.activeSheetVisible = false;
    page.openCourseCard(key);
    assert.equal(page.activeSheetVisible, true);
    assert.equal(page.selectedCourse, expected);
  }
});

test('bubbling a material click into the grid does not replace or reopen the active detail sheet', () => {
  const { page, course, exam } = harness();
  page.activeSheetVisible = false;
  page.timetableCardSurfaces.push({ key: 'exam-card', eventIds: ['exam'],
    left: 55, top: 24, width: 40, height: 90 });
  page.openCourseCard('card');
  page.openCourseAt(75, 50);
  page.openCourseCard('exam-card');
  assert.equal(page.selectedCourse, course);
  assert.notEqual(page.selectedCourse, exam);
  assert.equal(page.activeSheetVisible, true);
});

test('stale cards and clicks during a week change or dissolve cannot open details', () => {
  const { page } = harness();
  page.activeSheetVisible = false;
  page.openCourseCard('removed-card');
  assert.equal(page.activeSheetVisible, false);
  page.timetableAnimating = true;
  page.openCourseAt(30, 50);
  page.openCourseCard('card');
  assert.equal(page.activeSheetVisible, false);
  page.timetableAnimating = false;
  page.skippingCourse = true;
  page.openCourseCard('card');
  assert.equal(page.activeSheetVisible, false);
  page.skippingCourse = false;
  page.currentTimetable = { id: 'another-table' };
  page.openCourseCard('card');
  assert.equal(page.activeSheetVisible, false);
});

test('cancelling an unstarted pan never locks out a light tap, regardless of native callback order', () => {
  for (const cancelFirst of [true, false]) {
    for (const material of [true, false]) {
      const { page, course } = harness();
      page.activeSheetVisible = false;
      if (cancelFirst) page.cancelWeekPan();
      if (material) page.openCourseCard('card');
      else page.openCourseAt(30, 50);
      if (!cancelFirst) page.cancelWeekPan();
      assert.equal(page.timetableAnimating, false);
      assert.equal(page.timetableAnimationTimer, -1, 'a tap must not schedule a 240 ms animation lock');
      assert.equal(page.activeSheetVisible, true);
      assert.equal(page.selectedCourse, course);
    }
  }
});

test('skip UI exists only in timetable class details and uses the red material host', () => {
  const detail = fs.readFileSync(path.join(root, 'feature/timetable/views/CourseDetailContent.ets'), 'utf8');
  assert.match(home, /CourseDetailContent\(\{/);
  assert.match(detail, /deleteLabel: string = '翘课'/);
  assert.match(detail, /Button\('编辑'[\s\S]*Button\(this\.deleteLabel/);
  assert.match(detail, /if \(this\.event\.type === EasEventType\.CLASS\)[\s\S]*Button\(this\.deleteLabel/);
  assert.match(detail, /ImmersiveHeader\(\{ barHeight: 56/);
  assert.match(detail, /CompatibleMaterialModifier\(\$r\('app.color.hita_error_fill'\), true/);
  assert.match(detail, /\$r\('app.color.hita_error_fill'\), false\)/);
  assert.match(detail, /Button\(this\.deleteLabel[\s\S]*?\.height\(HitaDesign.buttonHeight\)[\s\S]*?\.fontSize\(HitaDesign.body\)/);
  assert.doesNotMatch(detail, /\.width\(132\)|\.height\(52\)/);
  assert.match(detail, /\.justifyContent\(FlexAlign\.End\)/);
  for (const file of ['TimetableDetailPage.ets', 'ExamPage.ets']) {
    assert.doesNotMatch(fs.readFileSync(path.join(root, 'pages', file), 'utf8'), /Button\('翘课'/);
  }
});

test('database deletion is scoped to explicit occurrence IDs, timetable and CLASS type', async () => {
  const source = fs.readFileSync(path.join(root, 'common/db/RdbHelper.ets'), 'utf8');
  const method = slice(source, '  async deleteClassOccurrences(', '  /** 删除某科目');
  class Predicate {
    constructor() { this.filters = []; }
    equalTo(key, value) { this.filters.push(row => row[key] === value); return this; }
    in(key, values) { this.filters.push(row => values.includes(row[key])); return this; }
  }
  let widgetRefreshes = 0;
  const db = new Function('relationalStore', 'EasEventType', 'ScheduleChangeSignal',
    compile(`class Db { ${method} };`) + '; return new Db();')(
    { RdbPredicates: Predicate }, { CLASS: 'CLASS' }, { notify: () => widgetRefreshes++ });
  let rows = [
    { id: 'one', timetableId: 'a', type: 'CLASS' },
    { id: 'co-teacher', timetableId: 'a', type: 'CLASS' },
    { id: 'next-week', timetableId: 'a', type: 'CLASS' },
    { id: 'exam', timetableId: 'a', type: 'EXAM' },
    { id: 'one', timetableId: 'b', type: 'CLASS' }
  ];
  db.s = () => ({ delete: async pred => {
    const before = rows.length;
    rows = rows.filter(row => !pred.filters.every(filter => filter(row)));
    return before - rows.length;
  } });
  await db.deleteClassOccurrences(['one', 'co-teacher', 'exam'], 'a');
  assert.equal(widgetRefreshes, 1);
  assert.deepEqual(rows.map(row => row.id), ['next-week', 'exam', 'one']);
  await assert.rejects(db.deleteClassOccurrences([], 'a'), /identity/);
  await assert.rejects(db.deleteClassOccurrences(['one'], ''), /identity/);
  await assert.rejects(db.deleteClassOccurrences(['missing'], 'a'), /no longer exists/);
  db.s = () => ({ delete: async () => { throw Error('disk full'); } });
  await assert.rejects(db.deleteClassOccurrences(['one'], 'b'), /disk full/);
  assert.equal(widgetRefreshes, 1, 'failed deletes must not refresh cards');
});

function refreshHarness() {
  const table = { id: 'table', getWeekNumber: () => 3 };
  const state = { events: async () => [], redraws: 0 };
  const rdb = {
    init: async () => {},
    getTimetables: async () => [table],
    getTimetableById: async () => table,
    getEventsOfTimetable: () => state.events(),
    getSubjectsOfTimetable: async () => []
  };
  const code = `class Home {
    summaryRequestGeneration = 0; skippingCourse = false;
    currentTimetable = table; timetableWeek = 6; timetableEvents = []; nowTick = Date.now();
    getUIContext() { return { getHostContext: () => ({}) }; }
    updateTodayHighlights() {}
    drawTimetableNow() { state.redraws++; }
    static defaultCanvasColor() { return 1; }
    ${slice(home, '  async refreshSummaries(', '  private classReminderSubtitle()')}
  }`;
  const page = new Function('table', 'state', 'RdbHelper', 'EasSessionStore', 'TimetableResolver',
    'TimetableSelectionStore', 'EasEventType', 'DAY_MS', 'NextClassWidgetService', 'CalendarSyncStore',
    compile(code) + '; return new Home();')(
    table, state, { getInstance: () => rdb }, { getInstance: () => ({ loadPreferred: async () => undefined }) },
    { getRecent: async () => table, getReal: async () => table },
    { getInstance: () => ({ load: async () => 'table' }) }, { EXAM: 'EXAM' }, 86400000, { scheduleRefresh() {} },
    { getInstance: () => ({ enabled: async () => false }) });
  return { page, state };
}

test('a database reload after skipping preserves the viewed week instead of jumping to the current week', async () => {
  const { page } = refreshHarness();
  await page.refreshSummaries(true);
  assert.equal(page.timetableWeek, 6);
  await page.refreshSummaries();
  assert.equal(page.timetableWeek, 3);
});

test('an in-flight refresh cannot resurrect a skipped class or interrupt its animation', async () => {
  const { page, state } = refreshHarness();
  const read = deferred();
  state.events = () => read.promise;
  const pending = page.refreshSummaries();
  await flush();
  page.skippingCourse = true;
  page.summaryRequestGeneration++;
  read.resolve([{ id: 'deleted', subjectId: 'subject', from: Date.now(), type: 'CLASS' }]);
  await pending;
  assert.deepEqual(page.timetableEvents, []);
  assert.equal(page.timetableWeek, 6);
  assert.equal(state.redraws, 0);
  page.skippingCourse = false;
  state.events = async () => [];
  await page.refreshSummaries(true);
  assert.deepEqual(page.timetableEvents, []);
  assert.equal(state.redraws, 1);
});
