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

function tapLocalDataLoginIcon(page, count = 7) {
  for (let tap = 0; tap < count; tap++) page.onLocalDataLoginIconTap();
}

function harness() {
  const state = {
    lastReads: 0, reads: 0, toasts: [], topPage: 'AssistantPage', webCleared: 0, refreshes: 0,
    keyboardModes: [],
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
    setKeyboardAvoidMode(mode) { state.keyboardModes.push(mode); },
    refreshSummaries() { state.refreshes++; },
    getPromptAction: () => ({ showToast: item => state.toasts.push(item.message) }),
    getRouter: () => ({ getState: () => ({ name: state.topPage }) })
  };
  const binding = slice('.bindSheet($$this.activeSheetVisible,', '\n  @Builder\n  compatibleDock()');
  const sheetLayout = binding.slice(binding.indexOf('height:'), binding.indexOf('dragBar:'));
  const callback = name => {
    const match = binding.match(new RegExp(`${name}: \\(\\) => \\{([\\s\\S]*?)\\n      \\}`));
    assert.ok(match, name);
    return match[1];
  };
  const animation = home.match(/\.onAnimationStart\([^\n]+=> \{([\s\S]*?)\n    \}\)/);
  assert.ok(animation);
  const showPage = slice('  async onPageShow(): Promise<void> {', '    this.widgetBackgroundSet =');
  const code = `
    class Home {
      pageVisible = true;
      currentTab = 2;
      selectedNav = 2;
      tabTransitionRunning = false;
      activeSheetVisible = false;
      sessionSheetOpen = false;
      sessionDemoVisible = false;
      localDataLoginTaps = 0;
      campusWebsiteNoticeOpen = false;
      sessionWebVisible = false;
      courseSheetOpen = false;
      calendarExportSheetOpen = false;
      sessionSheetLoading = false;
      sheetRequestGeneration = 0;
      sessionSheetCampus = 'WEIHAI';
      sessionSheetStudentType = '1';
      sessionStudentTypeManuallySelected = false;
      sessionSheetInfo;
      sessionSheetStatus = Status.UNKNOWN;
      sessionInfo;
      selectedCourse;
      calendarExportTimetable;
      courseDeleteEffects = { resume() {}, pause() {} };
      finishCourseSheetDismissal() {}
      resetDockInteraction() {}
      dockHandObserver = { stop() {} };
      startDockHandedness() {}
      getUIContext() { return context; }
      stopTimetableMarquee() {}
      startTimetableMarquee() {}
      stopClock() {}
      startClock() {}
      async refreshSummaries() { context.refreshSummaries(); }
      onPageShow() { ${showPage.slice(showPage.indexOf('{') + 1)} }
      sheetLayout() { return { ${sheetLayout} }; }
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
    'TAB_TIMETABLE', 'EasSessionStatus', 'EasDataProvider', 'EasApiClient', 'Status', 'EasWebLoginState',
    'SheetSize', 'ScrollSizeMode', 'SheetKeyboardAvoidMode', 'HitaDesign', 'EasStudentType',
    compiled + '; return new Home();')(
    context, { getInstance: () => store },
    { WEIHAI: 'WEIHAI', BENBU: 'BENBU', SHENZHEN: 'SHENZHEN' }, { OFFSET: 'offset', NONE: 'none' }, 1,
    Status, class {
      async checkSessionStatus(session) { state.checks.push(session); return state.verify(session); }
    }, class {}, Status, { clear: async () => { state.webCleared++; } },
    { FIT_CONTENT: 'fit', MEDIUM: 'medium', LARGE: 'large' }, { CONTINUOUS: 'continuous' },
    { TRANSLATE_AND_SCROLL: 'translate-and-scroll', NONE: 'none' }, { spaceLg: 24 }, { GRAD: 'GRAD' });
  return { page, state };
}

test('campus account panel restores the saved student type only for Weihai and Benbu', async () => {
  const { page, state } = harness();
  state.load = async campus => ({ campus, stutype: 'GRAD' });
  await page.openSessionSheet();
  assert.equal(page.sessionSheetCampus, 'WEIHAI');
  assert.equal(page.sessionSheetStudentType, '2');
  await page.selectSessionCampus('BENBU');
  assert.equal(page.sessionSheetStudentType, '2');
  await page.selectSessionCampus('SHENZHEN');
  assert.equal(page.sessionSheetStudentType, '1');
  const panel = slice('  sessionSheet()', '  sessionCampusSelector(');
  assert.match(panel, /if \(this\.sessionSheetCampus !== 'SHENZHEN'\) \{\s*Column\(\) \{\s*CourseModeSegment\(\{\s*labels: \['本科', '研究生'\],\s*selectedIndex: this\.sessionSheetStudentType === '2' \? 1 : 0,\s*onSelect: \(index: number\) => this\.selectSessionStudentType\(index\)/);
});

test('a manual student type selection survives a pending campus account load', async () => {
  const { page, state } = harness();
  await page.openSessionSheet();
  const pending = deferred();
  state.load = campus => campus === 'BENBU' ? pending.promise : Promise.resolve({ campus, stutype: 'GRAD' });
  const selecting = page.selectSessionCampus('BENBU');
  assert.equal(page.sessionSheetLoading, true);
  page.selectSessionStudentType(1);
  assert.equal(page.sessionSheetStudentType, '2');
  page.selectSessionStudentType(0);
  assert.equal(page.sessionSheetStudentType, '1');
  pending.resolve({ campus: 'BENBU', stutype: 'GRAD' });
  await selecting;
  assert.equal(page.sessionSheetStudentType, '1');
  await page.selectSessionCampus('WEIHAI');
  assert.equal(page.sessionSheetStudentType, '2');
});

test('native dismissal synchronizes visibility immediately and has no default session-sheet fallback', () => {
  assert.match(home, /\.bindSheet\(\$\$this\.activeSheetVisible,/);
  const active = slice('  activeSheet()', '  calendarExportConfirmationSheet(');
  assert.match(active, /else if \(this\.sessionSheetOpen\) \{\s*this\.sessionSheet\(\)/);
  assert.doesNotMatch(active, /else \{\s*this\.sessionSheet\(\)/);
  assert.match(slice('  aboutToDisappear()', '  private startClock()'), /this\.closeActiveSheet\(\)/);
  assert.match(slice('  private openCourseAt(', '  private eventDetailEndTime('), /!this\.canOpenSheet\(\)/);
});

test('closing any sheet cannot flash it on a tab change, while its exit content stays stable', () => {
  for (const kind of ['session', 'course', 'calendarExport']) {
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
    for (const flag of ['session', 'course', 'calendarExport']) {
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
  assert.equal(page.sessionWebVisible, true);
  assert.equal(page.sessionSheetOpen, true);
  assert.equal(page.activeSheetVisible, true);
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
  assert.equal(page.sessionWebVisible, false);
  page.didDisappear();
  pending.resolve({ campus: 'BENBU', name: 'Late' });
  await selecting;
  assert.equal(page.sessionSheetInfo, undefined);
});

test('going to the background keeps an open sheet, while a pushed page still closes it', async () => {
  const { page, state } = harness();
  await page.openSessionSheet();
  state.topPage = 'Home';
  page.onPageHide();
  assert.equal(page.activeSheetVisible, true, 'reading an SMS code must not end the login');
  state.topPage = 'AssistantPage';
  page.onPageHide();
  assert.equal(page.activeSheetVisible, false);
});

test('logging out also signs the web views out', async () => {
  const { page, state } = harness();
  await page.openSessionSheet();
  await page.logoutSession();
  assert.equal(state.webCleared, 1);
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
  await page.selectSessionCampus('BENBU');
  assert.equal(page.sessionSheetInfo.campus, 'BENBU');
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
  assert.equal(page.sessionWebVisible, false);
  page.beginSessionLogin();
  assert.equal(page.sessionWebVisible, true);
  page.willDisappear(); page.didDisappear();
  state.load = async campus => ({ campus, loginExpired: false });
  await page.openSessionSheet();
  assert.equal(page.sessionSheetStatus, Status.SAVED);
  assert.equal(page.sessionWebVisible, false);
  assert.equal(state.checks.length, 0);
  assert.doesNotMatch(home, /checkSessionStatus\(|verifySessionSheet\(/);
});

test('campus notice is reachable before selecting a campus and normal login opens the genuine Web', () => {
  const account = slice('  sessionSheet()', '  sessionCampusSelector(');
  assert.match(account, /if \(this\.sessionWebVisible\) \{\s*EasLoginPage\(/);
  assert.match(account, /active: this\.activeSheetVisible && this\.sessionSheetOpen/);
  assert.match(account, /label: '网页登录'[\s\S]*this\.beginSessionLogin\(\)/);
  assert.match(account, /title: '说明'[\s\S]*showCampusWebsiteNotice\(\)[\s\S]*Text\('认证校区'\)/);
  assert.match(home, /title: '校方网页访问说明'/);
  assert.match(account, /if \(this\.sessionDemoVisible\) \{\s*EasLocalDataConfirmation\([\s\S]*onConfirmed:[^\n]*this\.onSessionLoggedIn/);
  assert.match(account, /SymbolGlyph\(\$r\('sys\.symbol\.lock_shield'\)\)[^}]*\}\s*[^{}]*\.onClick\(\(\) => this\.onLocalDataLoginIconTap\(\)\);\s*Column\(\) \{\s*Text\('登录教务系统'\)/);
  assert.doesNotMatch(account, /label: '使用本地数据'/);
  assert.match(account, /Text\(this\.sessionSheetInfo\.demoMode \? '本地数据'/);
  assert.match(home, /this\.sessionInfo\.demoMode \? '本地数据'/);
});

test('the account panel stays compact and does not change Home keyboard avoidance', async () => {
  for (const dismiss of [page => page.closeActiveSheet(), page => page.willDisappear()]) {
    const { page, state } = harness();
    state.load = async () => undefined;
    page.onPageShow();
    assert.equal(state.keyboardModes.at(-1), 'none');
    await page.openSessionSheet();
    assert.equal(state.keyboardModes.at(-1), 'none');
    assert.equal(page.sheetLayout().keyboardAvoidMode, 'none');
    assert.equal(page.sheetLayout().height, 'fit');
    dismiss(page);
    assert.equal(state.keyboardModes.at(-1), 'none', 'do not reintroduce automatic avoidance during exit');
    page.didDisappear();
    assert.equal(state.keyboardModes.at(-1), 'none', 'restore the unchanged Home/dock policy');
  }
});

test('returning from the background retains account-sheet keyboard avoidance', async () => {
  const { page, state } = harness();
  state.topPage = 'Home';
  await page.openSessionSheet();
  page.onPageHide();
  assert.equal(page.sessionSheetOpen, true);
  assert.equal(page.activeSheetVisible, true);
  page.onPageShow();
  assert.equal(state.keyboardModes.at(-1), 'none', 'the compact account panel retains Home avoidance');
  page.beginSessionLogin();
  page.onPageHide();
  page.onPageShow();
  assert.equal(state.keyboardModes.at(-1), 'offset', 'the real web stage keeps the same avoidance scope');
});

test('local data confirmation uses the compact sheet and Home keyboard policy', async () => {
  const { page, state } = harness();
  state.load = async () => undefined;
  await page.openSessionSheet();
  tapLocalDataLoginIcon(page);
  assert.equal(page.sessionDemoVisible, true);
  assert.equal(page.sheetLayout().height, 'fit');
  assert.equal(page.sheetLayout().keyboardAvoidMode, 'none');
  assert.equal(state.keyboardModes.at(-1), 'none');
});

test('the shield counts taps within a sheet and works from every campus', async () => {
  const { page, state } = harness();
  state.load = async () => undefined;
  await page.openSessionSheet();
  tapLocalDataLoginIcon(page, 6);
  assert.equal(page.sessionDemoVisible, false);
  await page.selectSessionCampus('SHENZHEN');
  tapLocalDataLoginIcon(page, 6);
  assert.equal(page.sessionDemoVisible, false, 'switching campus resets the previous taps');
  page.willDisappear();
  page.didDisappear();
  for (const campus of ['SHENZHEN', 'WEIHAI', 'BENBU']) {
    state.loadLast = async () => campus;
    await page.openSessionSheet();
    tapLocalDataLoginIcon(page, 6);
    assert.equal(page.sessionDemoVisible, false);
    page.onLocalDataLoginIconTap();
    assert.equal(page.sessionDemoVisible, true);
    assert.equal(page.sessionSheetCampus, campus);
    assert.equal(page.sessionWebVisible, false);
    page.beginSessionLogin();
    assert.equal(page.sessionWebVisible, false, 'local confirmation stays in the account panel');
    page.willDisappear();
    page.didDisappear();
  }
});

test('local data confirmation stays mounted during dismissal and resets after exit', async () => {
  for (const dismiss of [page => page.closeActiveSheet(), page => {
    page.activeSheetVisible = false; // Native $$ binding updates before onWillDisappear.
    page.willDisappear();
  }]) {
    const { page, state } = harness();
    state.load = async () => undefined;
    await page.openSessionSheet();
    await page.selectSessionCampus('SHENZHEN');
    tapLocalDataLoginIcon(page);
    dismiss(page);
    assert.equal(page.activeSheetVisible && page.sessionSheetOpen, false, 'disable confirmation during exit');
    assert.equal(page.sessionDemoVisible, true, 'keep the confirmation panel during exit');
    page.didDisappear();
    await page.openSessionSheet();
    assert.equal(page.sessionDemoVisible, false);
  }
});

test('a late sheet dismissal cannot change the keyboard mode of a new routed page', async () => {
  const { page, state } = harness();
  await page.openSessionSheet();
  page.onPageHide();
  assert.equal(page.activeSheetVisible, false);
  assert.equal(state.keyboardModes.at(-1), 'offset');
  const calls = state.keyboardModes.length;
  page.didDisappear();
  assert.equal(state.keyboardModes.length, calls, 'hidden Home must not write the next page keyboard policy');
  page.onPageShow();
  assert.equal(state.keyboardModes.at(-1), 'none');
});

test('failed and cancelled account-sheet opens do not change keyboard policy', async () => {
  const { page, state } = harness();
  page.onPageShow();
  const calls = state.keyboardModes.length;
  state.load = async () => { throw Error('Unavailable'); };
  await page.openSessionSheet();
  assert.equal(state.keyboardModes.length, calls);
  const pending = deferred();
  state.load = () => pending.promise;
  const opening = page.openSessionSheet();
  await flush();
  page.selectTab(1);
  pending.resolve(undefined);
  await opening;
  assert.equal(state.keyboardModes.length, calls);
});

test('a single login click opens the selected campus Web and keeps its height through exit', async () => {
  const { page, state } = harness();
  state.load = async () => undefined;
  page.beginSessionLogin();
  assert.equal(page.sessionWebVisible, false);
  await page.openSessionSheet();
  await page.selectSessionCampus('BENBU');
  assert.equal(page.sessionSheetCampus, 'BENBU');
  assert.equal(page.sheetLayout().height, 'fit');
  assert.equal(page.sheetLayout().detents, undefined);
  page.beginSessionLogin();
  assert.equal(page.sessionWebVisible, true);
  assert.equal(page.sessionDemoVisible, false);
  assert.equal(page.sheetLayout().height, 'large');
  assert.deepEqual(page.sheetLayout().detents, ['large', 'medium']);
  assert.equal(page.sheetLayout().scrollSizeMode, 'continuous');
  assert.equal(page.sheetLayout().keyboardAvoidMode, 'translate-and-scroll');
  page.willDisappear();
  assert.equal(page.sessionWebVisible, true);
  assert.equal(page.sheetLayout().height, 'large');
  page.didDisappear();
  assert.equal(page.sessionWebVisible, false);
  await page.openSessionSheet();
  assert.equal(page.sheetLayout().height, 'fit');
});

test('requesting relogin changes the existing sheet without network work and retains its mode until exit', async () => {
  const { page, state } = harness();
  await page.openSessionSheet();
  const previous = page.sessionSheetInfo;
  const reads = state.reads;
  const generation = page.sheetRequestGeneration;
  page.beginSessionLogin();
  assert.equal(page.sessionWebVisible, true);
  assert.equal(page.sessionSheetInfo, previous);
  assert.equal(page.sessionSheetOpen, true);
  assert.equal(page.activeSheetVisible, true);
  assert.equal(page.sheetRequestGeneration, generation + 1);
  assert.equal(state.reads, reads);
  assert.equal(state.checks.length, 0);
  assert.equal(state.webCleared, 0);
  page.willDisappear();
  assert.equal(page.sessionWebVisible, true);
  assert.equal(page.sessionSheetOpen, true);
  assert.equal(page.activeSheetVisible, false);
  page.didDisappear();
  assert.equal(page.sessionWebVisible, false);
  assert.equal(page.sessionSheetOpen, false);
});

test('tapping the selected campus preserves the current input instance and outstanding local read', async () => {
  const { page, state } = harness();
  state.load = async () => undefined;
  await page.openSessionSheet();
  let generation = page.sheetRequestGeneration;
  let reads = state.reads;
  await page.selectSessionCampus('WEIHAI');
  assert.equal(page.sheetRequestGeneration, generation);
  assert.equal(page.sessionWebVisible, false);
  assert.equal(state.reads, reads);
  const pending = deferred();
  state.load = () => pending.promise;
  const selecting = page.selectSessionCampus('BENBU');
  generation = page.sheetRequestGeneration;
  reads = state.reads;
  await page.selectSessionCampus('BENBU');
  assert.equal(page.sheetRequestGeneration, generation);
  assert.equal(page.sessionSheetLoading, true);
  assert.equal(state.reads, reads);
  pending.resolve(undefined);
  await selecting;
  assert.equal(page.sessionWebVisible, false);
  assert.equal(page.sessionSheetLoading, false);
});

test('campus changes hide the previous form until the current local read completes', async () => {
  const { page, state } = harness();
  state.load = async () => undefined;
  await page.openSessionSheet();
  const old = deferred();
  const fresh = deferred();
  state.load = () => old.promise;
  const first = page.selectSessionCampus('BENBU');
  assert.equal(page.sessionSheetLoading, true);
  assert.equal(page.sessionWebVisible, false);
  state.load = () => fresh.promise;
  const second = page.selectSessionCampus('SHENZHEN');
  old.resolve(undefined);
  await first;
  assert.equal(page.sessionSheetCampus, 'SHENZHEN');
  assert.equal(page.sessionSheetLoading, true);
  assert.equal(page.sessionWebVisible, false);
  fresh.resolve(undefined);
  await second;
  assert.equal(page.sessionSheetLoading, false);
  assert.equal(page.sessionWebVisible, false);
  assert.equal(page.activeSheetVisible, true);
  assert.equal(state.webCleared, 0);
  assert.equal(state.checks.length, 0);
});

test('closing during a campus read preserves loading height and ignores the late result on reopen', async () => {
  const { page, state } = harness();
  await page.openSessionSheet();
  const old = deferred();
  state.load = () => old.promise;
  const selecting = page.selectSessionCampus('BENBU');
  page.willDisappear();
  assert.equal(page.sessionSheetLoading, true);
  assert.equal(page.sessionWebVisible, false);
  assert.equal(page.activeSheetVisible, false);
  page.didDisappear();
  assert.equal(page.sessionSheetLoading, false);
  state.load = async () => undefined;
  await page.openSessionSheet();
  old.resolve({ campus: 'BENBU', name: 'Old result' });
  await selecting;
  assert.equal(page.sessionSheetCampus, 'WEIHAI');
  assert.equal(page.sessionSheetInfo, undefined);
  assert.equal(page.sessionWebVisible, false);
  assert.equal(page.activeSheetVisible, true);
  assert.equal(page.sessionSheetLoading, false);
});

test('only a verified result for the visible selected campus closes the account sheet', async () => {
  const { page, state } = harness();
  state.load = async () => undefined;
  await page.openSessionSheet();
  await page.selectSessionCampus('BENBU');
  page.beginSessionLogin();
  page.onSessionLoggedIn('WEIHAI', { campus: 'WEIHAI' });
  page.onSessionLoggedIn('BENBU', { campus: 'WEIHAI' });
  assert.equal(page.activeSheetVisible, true);
  assert.equal(state.refreshes, 0);
  page.onSessionLoggedIn('BENBU', { campus: 'BENBU' });
  assert.equal(page.activeSheetVisible, false);
  assert.equal(state.refreshes, 1);
  page.onSessionLoggedIn('BENBU', { campus: 'BENBU' });
  assert.equal(state.refreshes, 1);
});

test('successful demo login closes the account sheet and imports its local timetable once', () => {
  const { page } = harness();
  page.sessionSheetCampus = 'WEIHAI';
  page.sessionDemoVisible = true;
  page.sessionSheetOpen = true;
  page.activeSheetVisible = true;
  let imports = 0;
  page.importTimetable = async () => { imports++; };
  page.onSessionLoggedIn('WEIHAI', { campus: 'WEIHAI', demoMode: true });
  assert.equal(page.activeSheetVisible, false);
  assert.equal(imports, 1);
  page.onSessionLoggedIn('WEIHAI', { campus: 'WEIHAI', demoMode: true });
  assert.equal(imports, 1);
});
