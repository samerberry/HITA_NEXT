const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const home = fs.readFileSync(path.resolve(__dirname, '../entry/src/main/ets/pages/Home.ets'), 'utf8')
  .replace(/\r\n/g, '\n');
const slice = (start, end) => {
  const from = home.indexOf(start);
  const to = home.indexOf(end, from);
  assert.ok(from >= 0 && to > from, start);
  return home.slice(from, to);
};

function harness() {
  const state = { calls: [], disabled: [], enabled: true, toasts: [],
    run: async () => ({ success: true, message: 'Exported' }), cleanup: async () => { state.enabled = false; } };
  const context = {
    getHostContext: () => ({}),
    getPromptAction: () => ({ showToast: value => state.toasts.push(value.message) })
  };
  const exporter = {
    async enable(ctx, timetable) {
      state.calls.push(timetable);
      return state.run(ctx, timetable);
    },
    async disable(ctx, id) {
      state.disabled.push(id);
      await state.cleanup();
    }
  };
  const binding = slice('.bindSheet($$this.activeSheetVisible,', '\n  @Builder\n  compatibleDock()');
  const disappear = binding.match(/onDisappear: \(\) => \{([\s\S]*?)\n      \}/);
  assert.ok(disappear, 'exercise the real sheet cleanup callback');
  const code = `
    class Home {
      currentTimetable = { id: 'a', name: 'Term A' };
      calendarExportTimetable;
      calendarExporting = false;
      calendarSyncEnabled = true;
      calendarExportSyncEnabled = false;
      calendarExportSheetOpen = false;
      activeSheetVisible = false;
      pageVisible = true;
      tabTransitionRunning = false;
      sessionSheetOpen = false;
      loginSheetOpen = false;
      courseSheetOpen = false;
      sheetRequestGeneration = 0;
      getUIContext() { return context; }
      finishCourseSheetDismissal() {}
      dismissSheet() { ${disappear[1]} }
      ${slice('  private canOpenSheet()', '  private async importIcsTimetable()')}
    }
  `;
  const output = ts.transpileModule(code, {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const page = new Function('context', 'ScheduleSyncService', 'CalendarSyncStore', output + '; return new Home();')(
    context, exporter, { getInstance: () => ({ enabled: async () => state.enabled }) });
  return { page, state };
}

test('the entry opens a bottom confirmation sheet; only its confirm button starts export', () => {
  const more = slice('  tabMine()', '  appearanceSettings()');
  const sheet = slice('  calendarExportConfirmationSheet(', '  tabToday()');
  const active = slice('  activeSheet()', '  calendarExportConfirmationSheet(');
  assert.match(more, /this\.requestCalendarExport\(\)/);
  assert.doesNotMatch(more, /this\.exportToCalendar\(\)/);
  assert.match(active, /this\.calendarExportConfirmationSheet\(this\.calendarExportTimetable as EasTimetable\)/);
  assert.match(sheet, /Text\(timetable\.name\)/);
  assert.match(sheet, /Toggle\(\{ type: ToggleType.Switch, isOn: this\.calendarExportSyncEnabled \}\)/);
  assert.match(sheet, /Button\('保存'/);
  const reminder = slice('  classReminderSettings()', '  moreNavigationRow(');
  assert.doesNotMatch(reminder, /calendarSync|同步到手机日历|当前课表|立即同步/);
  assert.doesNotMatch(sheet, /将此课表|之后调课|提醒时间沿用/);
  assert.match(sheet, /\.onClick\(\(\) => this\.cancelCalendarExport\(\)\)/);
  assert.match(sheet, /\.onClick\(\(\) => this\.exportToCalendar\(\)\)/);
  assert.match(home, /\.bindSheet\(\$\$this\.activeSheetVisible,[\s\S]*?SheetSize\.FIT_CONTENT[\s\S]*?preferType: SheetType\.BOTTOM/);
});

test('opening or reopening the prompt never reaches the calendar or permission service', async () => {
  const { page, state } = harness();
  await page.exportToCalendar();
  page.requestCalendarExport();
  assert.equal(page.activeSheetVisible, true);
  assert.equal(page.calendarExportSheetOpen, true);
  assert.equal(page.calendarExportTimetable.id, 'a');
  page.currentTimetable = { id: 'b', name: 'Term B' };
  page.requestCalendarExport();
  assert.equal(page.calendarExportTimetable.id, 'a', 'repeated taps cannot replace the visible target');
  assert.deepEqual(state.calls, []);
});

test('cancel, swipe dismissal and mask dismissal never export, including stale confirm callbacks', async () => {
  for (const cancelButton of [true, false]) {
    const { page, state } = harness();
    page.requestCalendarExport();
    if (cancelButton) {
      page.cancelCalendarExport();
      assert.equal(page.activeSheetVisible, false);
      assert.equal(page.calendarExportTimetable.id, 'a', 'keep content stable during closing animation');
      await page.exportToCalendar();
    }
    page.dismissSheet();
    await page.exportToCalendar();
    assert.equal(page.calendarExportSheetOpen, false);
    assert.equal(page.calendarExportTimetable, undefined);
    assert.deepEqual(state.calls, []);
    page.currentTimetable = { id: 'b', name: 'Term B' };
    page.requestCalendarExport();
    assert.equal(page.calendarExportTimetable.id, 'b');
    assert.equal(page.activeSheetVisible, true);
  }
});

test('confirm exports the displayed timetable once and retains it after dismissal', async () => {
  const { page, state } = harness();
  let release;
  state.run = () => new Promise(resolve => { release = resolve; });
  const selected = page.currentTimetable;
  page.requestCalendarExport();
  page.currentTimetable = { id: 'b', name: 'Term B' };
  const first = page.exportToCalendar();
  assert.equal(page.activeSheetVisible, false);
  assert.equal(page.calendarExporting, true);
  await page.exportToCalendar();
  page.dismissSheet();
  page.requestCalendarExport();
  assert.equal(page.activeSheetVisible, false, 'cannot start a second prompt during export');
  assert.deepEqual(state.calls, [selected]);
  release({ success: true, message: 'Exported' });
  await first;
  assert.equal(page.calendarExporting, false);
  assert.deepEqual(state.toasts, ['已同步']);
  page.requestCalendarExport();
  assert.equal(page.calendarExportTimetable.id, 'b');
});

test('changing the draft switch and dismissing never changes calendar settings; reopening restores saved state', async () => {
  const { page, state } = harness();
  page.requestCalendarExport();
  assert.equal(page.calendarExportSyncEnabled, true);
  page.calendarExportSyncEnabled = false;
  page.cancelCalendarExport(); page.dismissSheet();
  assert.deepEqual(state.disabled, []);
  assert.deepEqual(state.calls, []);
  assert.equal(state.enabled, true);
  page.requestCalendarExport();
  assert.equal(page.calendarExportSyncEnabled, true);
});

test('saving off cleans only the displayed timetable, and an already-off setting never touches the calendar', async () => {
  const { page, state } = harness();
  page.requestCalendarExport();
  page.calendarExportSyncEnabled = false;
  page.currentTimetable = { id: 'b', name: 'Term B' };
  await page.exportToCalendar();
  assert.deepEqual(state.disabled, ['a']);
  assert.deepEqual(state.calls, []);
  assert.equal(state.enabled, false);
  page.dismissSheet();
  page.currentTimetable = { id: 'a', name: 'Term A' };
  page.calendarSyncEnabled = false;
  page.requestCalendarExport();
  await page.exportToCalendar();
  assert.deepEqual(state.disabled, ['a']);
  assert.equal(page.calendarExporting, false);
});

test('failed cleanup retains the enabled setting and releases the sheet operation lock', async () => {
  const { page, state } = harness();
  state.cleanup = async () => { throw Error('Permission denied'); };
  page.requestCalendarExport(); page.calendarExportSyncEnabled = false;
  await page.exportToCalendar(); page.dismissSheet();
  assert.equal(page.calendarSyncEnabled, true);
  assert.equal(page.calendarExporting, false);
  page.requestCalendarExport();
  assert.equal(page.calendarExportSyncEnabled, true);
  assert.match(state.toasts[0], /失败/);
});

test('missing selection and another active sheet cannot initiate calendar export', async () => {
  const { page, state } = harness();
  page.currentTimetable = undefined;
  page.requestCalendarExport();
  await page.exportToCalendar();
  assert.equal(page.activeSheetVisible, false);
  assert.equal(state.toasts.length, 1);
  page.currentTimetable = { id: 'a', name: 'Term A' };
  page.activeSheetVisible = true;
  page.requestCalendarExport();
  assert.equal(page.calendarExportSheetOpen, false);
  assert.equal(page.calendarExportTimetable, undefined);
  assert.deepEqual(state.calls, []);
});

test('permission denial and unexpected failures release the lock and require a new confirmation', async () => {
  for (const throws of [false, true]) {
    const { page, state } = harness();
    state.run = async () => {
      if (throws) throw Error('Calendar unavailable');
      return { success: false, message: 'Permission denied' };
    };
    page.requestCalendarExport();
    await page.exportToCalendar();
    page.dismissSheet();
    assert.equal(page.calendarExporting, false);
    assert.equal(state.toasts.length, 1);
    await page.exportToCalendar();
    assert.equal(state.calls.length, 1);
    page.requestCalendarExport();
    await page.exportToCalendar();
    assert.equal(state.calls.length, 2);
  }
});
