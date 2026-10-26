const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const home = fs.readFileSync(path.resolve(__dirname, '../entry/src/main/ets/pages/Home.ets'), 'utf8')
  .replace(/\r\n/g, '\n');
function slice(start, end) {
  const from = home.indexOf(start);
  const to = home.indexOf(end, from);
  assert.ok(from >= 0 && to > from, start);
  return home.slice(from, to);
}
function deferred() {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return { promise, resolve };
}
const flush = async () => { for (let i = 0; i < 10; i++) await Promise.resolve(); };
const Status = { SAVED: 'saved', CHECKING: 'checking', CONNECTED: 'connected', EXPIRED: 'expired', UNKNOWN: 'unknown' };

function harness() {
  const state = {
    lastReads: 0, reads: 0, toasts: [],
    loadLast: async () => 'WEIHAI',
    load: async campus => ({ campus, name: 'Current session' }),
    clear: async () => {},
    checks: [],
    verify: async () => Status.CONNECTED
  };
  const store = {
    async loadLastCampus() { state.lastReads++; return state.loadLast(); },
    async load(campus) { state.reads++; return state.load(campus); },
    async clear(campus) { return state.clear(campus); }
  };
  const context = {
    setKeyboardAvoidMode() {},
    getPromptAction: () => ({ showToast: item => state.toasts.push(item.message) })
  };
  const binding = slice('.bindSheet($$this.activeSheetVisible,', '\n  @Builder\n  compatibleDock()');
  const callback = name => {
    const match = binding.match(new RegExp(`${name}: \\(\\) => \\{([\\s\\S]*?)\\n      \\}`));
    assert.ok(match, name);
    return match[1];
  };
  const animation = home.match(/\.onAnimationStart\([^\n]+=> \{([\s\S]*?)\n    \}\)/);
  assert.ok(animation);
  const code = `
    class Home {
      pageVisible = true;
      currentTab = 2;
      selectedNav = 2;
      tabTransitionRunning = false;
      activeSheetVisible = false;
      sessionSheetOpen = false;
      loginSheetOpen = false;
      courseSheetOpen = false;
      calendarExportSheetOpen = false;
      sessionSheetLoading = false;
      sheetRequestGeneration = 0;
      sessionSheetCampus = 'WEIHAI';
      sessionSheetInfo;
      sessionSheetStatus = Status.UNKNOWN;
      sessionInfo;
      selectedCourse;
      calendarExportTimetable;
      courseDeleteEffects = { resume() {}, pause() {} };
      finishCourseSheetDismissal() {}
      resetDockInteraction() {}
      dockHandObserver = { stop() {} };
      getUIContext() { return context; }
      stopTimetableMarquee() {}
      startTimetableMarquee() {}
      stopClock() {}
      startClock() {}
      async refreshSummaries() {}
      willDisappear() { ${callback('onWillDisappear')} }
      didDisappear() { ${callback('onDisappear')} }
      startTabAnimation(index, targetIndex) { ${animation[1]} }
      ${slice('  onPageHide()', '  private onAppearanceChanged()')}
      ${slice('  private selectTab(', '  private dockPageInset()')}
      ${slice('  private canOpenSheet()', '  private requestCalendarExport()')}
      ${slice('  private static campusName(', '  build()')}
    }
  `;
  const compiled = ts.transpileModule(code, {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const page = new Function('context', 'EasSessionStore', 'EasCampus', 'KeyboardAvoidMode',
    'TAB_TIMETABLE', 'EasSessionStatus', 'EasDataProvider', 'EasApiClient', 'Status',
    compiled + '; return new Home();')(
    context, { getInstance: () => store },
    { WEIHAI: 'WEIHAI', BENBU: 'BENBU', SHENZHEN: 'SHENZHEN' }, { OFFSET: 0 }, 1,
    Status, class {
      async checkSessionStatus(session) { state.checks.push(session); return state.verify(session); }
    }, class {}, Status);
  return { page, state };
}

test('native dismissal synchronizes visibility immediately and has no default session-sheet fallback', () => {
  assert.match(home, /\.bindSheet\(\$\$this\.activeSheetVisible,/);
  const active = slice('  activeSheet()', '  calendarExportConfirmationSheet(');
  assert.match(active, /else if \(this\.sessionSheetOpen\) \{\s*this\.sessionSheet\(\)/);
  assert.doesNotMatch(active, /else \{\s*this\.sessionSheet\(\)/);
  assert.match(slice('  aboutToDisappear()', '  private startClock()'), /this\.closeActiveSheet\(\)/);
  assert.match(slice('  private openCourseAt(', '  private eventDetailEndTime('), /!this\.canOpenSheet\(\)/);
});

test('closing any sheet cannot flash it on a tab change, while its exit content stays stable', () => {
  for (const kind of ['session', 'login', 'course', 'calendarExport']) {
    const { page } = harness();
    page[`${kind}SheetOpen`] = true;
    page.activeSheetVisible = true;
    const course = { id: 'course' };
    const timetable = { id: 'timetable' };
    page.selectedCourse = course;
    page.calendarExportTimetable = timetable;
    page.willDisappear();
    assert.equal(page.activeSheetVisible, false);
    assert.equal(page[`${kind}SheetOpen`], true);
    assert.equal(page.selectedCourse, course);
    assert.equal(page.canOpenSheet(), false, 'do not reopen while the old sheet is closing');
    page.selectTab(1);
    assert.equal(page.activeSheetVisible, false);
    page.didDisappear();
    for (const flag of ['session', 'login', 'course', 'calendarExport']) {
      assert.equal(page[`${flag}SheetOpen`], false);
    }
    assert.equal(page.selectedCourse, undefined);
    assert.equal(page.calendarExportTimetable, undefined);
    page.selectTab(2);
    page.selectTab(1);
    assert.equal(page.activeSheetVisible, false);
    assert.equal(page.canOpenSheet(), true, 'a fresh user action can open a new sheet');
  }
});

test('switching away and back invalidates a pending last-campus read instead of reopening More', async () => {
  const { page, state } = harness();
  const pending = deferred();
  state.loadLast = () => pending.promise;
  const opening = page.openSessionSheet();
  page.selectTab(1);
  page.selectTab(2);
  pending.resolve('BENBU');
  await opening;
  assert.equal(page.activeSheetVisible, false);
  assert.equal(page.sessionSheetOpen, false);
  assert.equal(state.reads, 0);
  state.loadLast = async () => 'WEIHAI';
  await page.openSessionSheet();
  assert.equal(page.sessionSheetOpen, true);
});

test('late session data cannot present a popup after tab animation or route hiding', async () => {
  for (const leave of [page => page.startTabAnimation(2, 1), page => page.onPageHide()]) {
    const { page, state } = harness();
    const pending = deferred();
    state.load = () => pending.promise;
    const opening = page.openSessionSheet();
    await flush();
    assert.equal(state.reads, 1);
    leave(page);
    pending.resolve({ campus: 'WEIHAI', name: 'Late' });
    await opening;
    assert.equal(page.activeSheetVisible, false);
    assert.equal(page.sessionSheetInfo, undefined);
    assert.equal(page.sessionSheetLoading, false);
  }
});

test('rapid taps use one request, and a stale request cannot unlock or overwrite a later one', async () => {
  const { page, state } = harness();
  const old = deferred();
  const fresh = deferred();
  state.load = () => old.promise;
  const first = page.openSessionSheet();
  await flush();
  await page.openSessionSheet();
  assert.equal(state.lastReads, 1);
  page.selectTab(1);
  page.selectTab(2);
  state.load = () => fresh.promise;
  const second = page.openSessionSheet();
  await flush();
  old.resolve({ campus: 'BENBU', name: 'Old' });
  await first;
  assert.equal(page.activeSheetVisible, false);
  assert.equal(page.sessionSheetLoading, true);
  fresh.resolve({ campus: 'WEIHAI', name: 'New' });
  await second;
  assert.equal(page.sessionSheetInfo.name, 'New');
  assert.equal(page.sessionSheetLoading, false);
  assert.equal(page.activeSheetVisible, true);
});

test('session read failure stays closed and the next attempt remains usable', async () => {
  const { page, state } = harness();
  state.load = async () => { throw Error('Unavailable'); };
  await page.openSessionSheet();
  assert.equal(page.activeSheetVisible, false);
  assert.equal(page.sessionSheetLoading, false);
  assert.equal(state.toasts.length, 1);
  state.load = async () => undefined;
  await page.openSessionSheet();
  assert.equal(page.activeSheetVisible, true);
  page.beginSessionLogin();
  assert.equal(page.loginSheetOpen, true);
  assert.equal(page.sessionSheetOpen, false);
});

test('late campus selection and login clicks cannot update or reopen a dismissed session sheet', async () => {
  const { page, state } = harness();
  await page.openSessionSheet();
  const pending = deferred();
  state.load = () => pending.promise;
  const selecting = page.selectSessionCampus('BENBU');
  page.willDisappear();
  page.beginSessionLogin();
  assert.equal(page.activeSheetVisible, false);
  assert.equal(page.loginSheetOpen, false);
  page.didDisappear();
  pending.resolve({ campus: 'BENBU', name: 'Late' });
  await selecting;
  assert.equal(page.sessionSheetInfo, undefined);
});

test('a late logout does not close a newly opened course detail', async () => {
  const { page, state } = harness();
  await page.openSessionSheet();
  const pending = deferred();
  state.clear = () => pending.promise;
  const logout = page.logoutSession();
  page.willDisappear();
  page.didDisappear();
  page.selectTab(1);
  page.courseSheetOpen = true;
  page.selectedCourse = { id: 'current-course' };
  page.activeSheetVisible = true;
  pending.resolve();
  await logout;
  assert.equal(page.activeSheetVisible, true);
  assert.equal(page.courseSheetOpen, true);
});

test('switching campus ignores out-of-order results and recovers from a failed read', async () => {
  const { page, state } = harness();
  await page.openSessionSheet();
  const old = deferred();
  state.load = () => old.promise;
  const selecting = page.selectSessionCampus('BENBU');
  state.load = async () => { throw Error('Read failed'); };
  await page.selectSessionCampus('SHENZHEN');
  old.resolve({ campus: 'BENBU' });
  await selecting;
  assert.equal(page.sessionSheetCampus, 'SHENZHEN');
  assert.equal(page.sessionSheetInfo, undefined);
  assert.equal(page.activeSheetVisible, true);
  assert.equal(state.toasts.length, 1);
  state.load = async campus => ({ campus });
  await page.selectSessionCampus('SHENZHEN');
  assert.equal(page.sessionSheetInfo.campus, 'SHENZHEN');
});


test('display settings keep their close guard until dismissal finishes', () => {
  const { page } = harness();
  page.timetableDisplayOpen = true;
  page.activeSheetVisible = true;
  page.willDisappear();
  assert.equal(page.canOpenSheet(), false);
  assert.equal(page.timetableDisplayOpen, true);
  page.didDisappear();
  assert.equal(page.timetableDisplayOpen, false);
  assert.equal(page.canOpenSheet(), true);
});

test('opening and reopening account sheet reads saved expiry without network probes or clearing data', async () => {
  const { page, state } = harness();
  let clears = 0;
  state.clear = async () => { clears++; };
  state.verify = () => { assert.fail('account sheet must not probe'); };
  state.load = async campus => ({ campus, name: 'Current session', loginExpired: true });
  await page.openSessionSheet();
  assert.equal(page.activeSheetVisible, true);
  assert.equal(page.sessionSheetStatus, Status.EXPIRED);
  assert.equal(page.sessionSheetInfo.name, 'Current session');
  page.willDisappear(); page.didDisappear();
  await page.openSessionSheet();
  assert.equal(page.sessionSheetStatus, Status.EXPIRED);
  assert.equal(clears, 0);
  assert.equal(state.checks.length, 0);
});

test('account sheet displays independent saved campus states and ignores late reads', async () => {
  const { page, state } = harness();
  await page.openSessionSheet();
  assert.equal(page.sessionSheetStatus, Status.SAVED);
  const old = deferred();
  state.load = () => old.promise;
  const pending = page.selectSessionCampus('BENBU');
  state.load = async campus => ({ campus, loginExpired: false });
  await page.selectSessionCampus('SHENZHEN');
  old.resolve({ campus: 'BENBU', loginExpired: true }); await pending;
  assert.equal(page.sessionSheetCampus, 'SHENZHEN');
  assert.equal(page.sessionSheetStatus, Status.SAVED);
  assert.equal(state.checks.length, 0);
});

test('missing session and completed relogin use local state without automatic validation', async () => {
  const { page, state } = harness();
  state.load = async () => undefined;
  await page.openSessionSheet();
  assert.equal(page.sessionSheetInfo, undefined);
  page.willDisappear(); page.didDisappear();
  state.load = async campus => ({ campus, loginExpired: false });
  await page.openSessionSheet();
  assert.equal(page.sessionSheetStatus, Status.SAVED);
  assert.equal(state.checks.length, 0);
  assert.doesNotMatch(home, /checkSessionStatus\(|verifySessionSheet\(/);
});
