const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const home = fs.readFileSync(path.resolve(__dirname, '../entry/src/main/ets/pages/Home.ets'), 'utf8');
const slice = (start, end) => {
  const from = home.indexOf(start);
  const to = home.indexOf(end, from);
  assert.ok(from >= 0 && to > from, start);
  return home.slice(from, to);
};

function harness() {
  const queued = [];
  const intervals = [];
  const intervalPeriods = [];
  const clearedIntervals = [];
  const code = `
    class Home {
      currentTab = 0;
      selectedNav = 0;
      pageVisible = true;
      tabTransitionRunning = false;
      sheetRequestGeneration = 0;
      timetableMarqueeCallback;
      timetableMarqueeGeneration = 0;
      timetableMarqueeElapsedMs = 500;
      timetableMarqueeLastFrameMs = -1;
      timetablePlaceLabels = [{}];
      timetableAreaW = 380;
      timetableCanvasHeight = 800;
      timetableCardPainter = { drawPlaces: () => 1200 };
      courseDeleteEffects = { resume() {}, pause() {} };
      finishCourseSheetDismissal() {}
      clockTimer = -1;
      classReminderEnabled = false;
      dayKey = 'today';
      nowTick = 0;
      paints = 0;
      highlights = 0;
      refreshes = 0;
      getUIContext() { return context; }
      drawTimetableNow() { this.paints++; }
      updateTodayHighlights() { this.highlights++; }
      refreshSummaries() { this.refreshes++; }
      ${slice('  private closeActiveSheet()', '  private requestCalendarExport()')}
      ${slice('  private startClock()', '  async refreshSummaries(')}
      ${slice('  private static durationText(', '  private static campusName(')}
      ${slice('  private selectTab(', '  private dockPageInset()')}
    }`;
  const output = ts.transpileModule(code, {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const context = {
    postFrameCallback: callback => queued.push(callback),
    postDelayedFrameCallback: callback => queued.push(callback)
  };
  const clock = { day: 'today', printDate() { return this.day; } };
  const page = new Function('context', 'TimetableMarqueeCallback', 'drawTimetablePlaces', 'TAB_TIMETABLE',
    'setInterval', 'clearInterval', 'EasTimeTools', 'EasEventType', output + '; return new Home();')(
    context, class { constructor(callback) { this.run = callback; } },
    () => 1200, 1, (callback, period) => { intervals.push(callback); intervalPeriods.push(period); return 1; },
    id => clearedIntervals.push(id), clock, { CLASS: 'CLASS' });
  return { page, queued, intervals, intervalPeriods, clearedIntervals, clock };
}

test('returning to the cached timetable resumes labels without repainting the full grid', () => {
  const { page, queued } = harness();
  page.selectTab(1);
  assert.equal(page.paints, 0);
  assert.equal(queued.length, 1);
  assert.equal(page.timetableMarqueeElapsedMs, 500);
  page.selectTab(2);
  queued.shift().run(1000);
  assert.equal(queued.length, 0, 'stale label callbacks cannot keep running on More');
  page.selectTab(1);
  assert.equal(queued.length, 1);
  assert.equal(page.paints, 0);
});

test('tab transitions pause labels and resume once even when change precedes animation end', () => {
  const { page, queued } = harness();
  page.tabTransitionRunning = true;
  page.selectTab(1);
  page.startTimetableMarquee();
  assert.equal(queued.length, 0);
  page.finishTabAnimation(1);
  assert.equal(queued.length, 1);
  page.selectTab(1);
  page.finishTabAnimation(1);
  assert.equal(queued.length, 1);
  assert.equal(page.selectedNav, 1);
  assert.equal(page.paints, 0);
});

test('a cancelled swipe resumes the current timetable and restores the selected indicator', () => {
  const { page, queued } = harness();
  page.selectTab(1);
  page.tabTransitionRunning = true;
  page.stopTimetableMarquee();
  page.selectedNav = 2;
  queued.shift().run(1000);
  assert.equal(queued.length, 0);
  page.finishTabAnimation(1);
  assert.equal(page.selectedNav, 1);
  assert.equal(queued.length, 1);
  assert.equal(page.paints, 0);
});

test('animation end before change also resumes only one label callback', () => {
  const { page, queued } = harness();
  page.tabTransitionRunning = true;
  page.finishTabAnimation(1);
  page.selectTab(1);
  assert.equal(page.currentTab, 1);
  assert.equal(queued.length, 1);
  page.finishTabAnimation(2);
  queued.shift().run(2000);
  assert.equal(queued.length, 0);
  assert.equal(page.currentTab, 2);
  assert.equal(page.selectedNav, 2);
});

test('finishing on another page or hiding the page never starts background label frames', () => {
  for (const hidden of [false, true]) {
    const { page, queued } = harness();
    page.pageVisible = !hidden;
    page.tabTransitionRunning = true;
    page.finishTabAnimation(hidden ? 1 : 2);
    assert.equal(queued.length, 0);
  }
});

test('the home clock updates course progress every second without repainting the static grid', () => {
  const { page, intervals, intervalPeriods, clock } = harness();
  page.startClock();
  page.startClock();
  assert.equal(intervals.length, 1);
  assert.equal(intervalPeriods[0], 1000);
  for (let i = 0; i < 4; i++) intervals[0]();
  assert.equal(page.highlights, 4);
  assert.equal(page.paints, 0);
  assert.equal(page.refreshes, 0);
  clock.day = 'tomorrow';
  intervals[0]();
  assert.equal(page.refreshes, 1);
  intervals[0]();
  assert.equal(page.refreshes, 1);
});

test('today upcoming and ongoing course countdowns show whole minutes', () => {
  const { page } = harness();
  const home = page.constructor;
  const contains = function (ts) { return ts >= this.from && ts <= this.to; };
  page.nextClass = { from: 120_000, to: 600_000 };
  assert.equal(page.heroMinutesLeft(), 2);
  assert.equal(page.heroCountdownSuffix(), ' 后上课');
  page.nowTick = 61_000;
  assert.equal(page.heroMinutesLeft(), 1, 'partial minutes round up');
  page.activeClass = { from: -60_000, to: 7_380_000 };
  page.nowTick = 0;
  assert.equal(page.heroMinutesLeft(), 123, 'the ongoing class counts down to its end');
  assert.equal(page.heroCountdownSuffix(), ' 后下课');
  page.nowTick = 8_000_000;
  assert.equal(page.heroMinutesLeft(), 0, 'never negative');
  const soon = { type: 'CLASS', from: 120_000, to: 600_000, containsTimestamp: contains };
  assert.equal(home.todayChipText(soon, 0), '2分钟后');
  assert.equal(home.todayChipText(soon, 300_000), '进行中');
  assert.equal(home.todayChipText(soon, 700_000), '已结束');
  assert.equal(home.todayChipText(soon, -3_600_000), '', 'no chip for classes far ahead');
});

test('the home clock stops while hidden and can start again when shown', () => {
  const { page, intervals, intervalPeriods, clearedIntervals } = harness();
  page.startClock();
  page.stopClock();
  assert.deepEqual(clearedIntervals, [1]);
  assert.equal(page.clockTimer, -1);
  page.startClock();
  assert.equal(intervals.length, 2);
  assert.deepEqual(intervalPeriods, [1000, 1000]);
  assert.match(slice('  onPageHide()', '  private async onSessionRevisionChanged'), /this\.stopClock\(\)/);
});

test('data, appearance, wallpaper, week and geometry changes still repaint the timetable', () => {
  assert.match(slice('  async refreshSummaries(', '  private classReminderSubtitle'),
    /this\.drawTimetableNow\(\)/);
  assert.match(slice('  private onAppearanceChanged()', '  private timetableInk'),
    /this\.drawTimetableNow\(\)/);
  assert.match(slice('  private shiftTimetableWeek(', '  private timetableDragLimit'),
    /this\.drawTimetableNow\(\)/);
  assert.match(slice('  private onTimetableArea(', '  private hasTimetableBackground'),
    /this\.drawTimetableNow\(\)/);
  const tab = slice('  tabTimetable()', '  tabMine()');
  assert.match(tab, /if \(width !== this\.timetableAreaW \|\| height !== this\.timetableAreaH\)/);
  assert.match(tab, /height !== this\.timetableChromeH[\s\S]*this\.onTimetableArea/);
  assert.match(home, /onAnimationStart[\s\S]*?this\.tabTransitionRunning = true;[\s\S]*?this\.stopTimetableMarquee\(\)/);
  assert.match(home, /onAnimationEnd[\s\S]*?this\.finishTabAnimation\(index\)/);
  // Countdowns re-render from nowTick on each clock tick instead of repainting the grid.
  assert.match(home, /Span\(\(this\.heroMinutesLeft\(\) % 60\)\.toString\(\)\)/);
  assert.match(home, /HitaTag\(\{ text: Home\.todayChipText\(event, this\.nowTick\), tone: Home\.todayChipTone\(event, this\.nowTick\) \}\)/);
});
