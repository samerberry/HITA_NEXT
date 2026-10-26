const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

function harness() {
  const source = fs.readFileSync(path.resolve(__dirname, '../entry/src/main/ets/pages/Home.ets'), 'utf8');
  const methods = source.slice(source.indexOf('  private onPendingReminderChanged()'),
    source.indexOf('  private showExamReminderTimePicker()'));
  const state = { selected: '', tabs: [], toasts: [],
    event: { id: 'course', timetableId: 'term', from: 1000 } };
  const code = `class Home {
    remindersReady = true; pageVisible = true; reminderOpening = false; pendingReminderEvent = 'course';
    currentTab = 2; selectedNav = 2; activeSheetVisible = false; timetableEvents = [];
    currentTimetable = { getWeekNumber: () => 5 };
    tabsController = { changeIndex: index => {
      state.tabs.push(index);
      setTimeout(() => { this.closeActiveSheet(); this.currentTab = index; this.selectedNav = index; }, 5);
    } };
    getUIContext() { return { getPromptAction: () => ({ showToast: value => state.toasts.push(value.message) }) }; }
    closeActiveSheet() { this.activeSheetVisible = false; this.courseSheetOpen = false; }
    resetDockInteraction() {}
    async refreshSummaries() { this.timetableEvents = [state.event]; }
    selectTab(index) { this.currentTab = index; }
    drawTimetableNow() {}
    ${methods}
  }`;
  const compiled = ts.transpileModule(code, { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText;
  let page;
  page = new Function('state', 'RdbHelper', 'TimetableSelectionStore', 'AppStorage', 'TAB_TIMETABLE', 'TAB_SWIPE_MS',
    compiled + '; return new Home();')(
    state, { getInstance: () => ({ getEventById: async () => state.event }) },
    { getInstance: () => ({ save: async id => { state.selected = id; } }) },
    { setOrCreate: (key, value) => { page.pendingReminderEvent = value; } }, 1, 0);
  return { page, state };
}

test('notification navigation waits for the real Tabs animation before opening occurrence details', async () => {
  const { page, state } = harness();
  await page.openPendingReminder();
  assert.deepEqual(state.tabs, [1]);
  assert.equal(state.selected, 'term');
  assert.equal(page.currentTab, 1);
  assert.equal(page.selectedNav, 1);
  assert.equal(page.timetableWeek, 5);
  assert.equal(page.selectedCourse.id, 'course');
  assert.equal(page.activeSheetVisible, true);
  assert.equal(page.courseSheetOpen, true);
  assert.equal(page.pendingReminderEvent, '');
});

test('deleted notifications show a message without changing timetable or opening a blank sheet', async () => {
  const { page, state } = harness(); state.event = undefined;
  await page.openPendingReminder();
  assert.match(state.toasts[0], /已被删除/);
  assert.equal(state.selected, '');
  assert.deepEqual(state.tabs, []);
  assert.equal(page.activeSheetVisible, false);
  assert.equal(page.reminderOpening, false);
});
