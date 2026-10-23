const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const cache = new Map();
function load(file) {
  const absolute = path.resolve(root, file);
  if (cache.has(absolute)) return cache.get(absolute).exports;
  const mod = { exports: {} };
  cache.set(absolute, mod);
  const source = fs.readFileSync(absolute, 'utf8')
    .replace(/^@Component\r?\n/gm, '')
    .replace(/@(Prop|StorageProp|Builder)(\([^)]*\))?\s+/g, '')
    .replace('export struct HeaderFadeMask', 'export class HeaderFadeMask');
  const output = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const requireLocal = name => {
    assert.ok(name.startsWith('.'), name);
    return load(path.resolve(path.dirname(absolute), name + '.ets'));
  };
  new Function('require', 'module', 'exports', output)(requireLocal, mod, mod.exports);
  return mod.exports;
}
const { HeaderFade } = load('common/theme/HeaderFade.ets');
const { HeaderFadeMask } = load('common/components/HeaderFadeMask.ets');

test('header fade opacity ramps in over the first 24vp of scrolling', () => {
  assert.equal(HeaderFade.opacity(-30), 0);
  assert.equal(HeaderFade.opacity(0), 0);
  assert.equal(HeaderFade.opacity(12), 0.5);
  assert.equal(HeaderFade.opacity(240), 1);
});

test('the shared header mask supplies the existing curve and reverses it for bottom bars', () => {
  const mask = new HeaderFadeMask();
  for (const height of [0, 56]) {
    mask.headerHeight = height;
    const offsets = height > 0 ? HeaderFade.HEADER_OFFSETS : HeaderFade.OFFSETS;
    const alphas = height > 0 ? HeaderFade.HEADER_ALPHAS : HeaderFade.ALPHAS;
    mask.fromBottom = false;
    const expected = offsets.map((offset, i) => [HeaderFade.rgba(mask.rgb, alphas[i]), offset]);
    assert.deepEqual(mask.stops(), expected);
    assert.equal(expected[0][0], 'rgba(244,247,252,1.000)');
    assert.equal(expected.at(-1)[0], 'rgba(244,247,252,0.000)');
    mask.fromBottom = true;
    assert.deepEqual(mask.stops(), expected.slice().reverse().map(([color, offset]) => [color, 1 - offset]));
  }
  assert.match(read('common/components/HeaderFadeMask.ets'), /hitTestBehavior\(HitTestMode\.None\)/);
});

test('tabs swipe between neighbours except over a timetable grid, whose swipes page weeks', () => {
  const home = read('pages/Home.ets');
  const shell = home.slice(home.indexOf('  build() {'), home.indexOf('  activeSheet()'));
  assert.match(shell, /Tabs\(\{ barPosition: BarPosition\.End, controller: this\.tabsController, barModifier: this\.dockBarModifier \}\)/);
  assert.match(shell, /\.scrollable\(true\)/);
  assert.doesNotMatch(home, /tabSwipeLocked|handleChromeTabPanEnd/);
  assert.match(shell, /\.onAnimationStart\([\s\S]*?this\.selectedNav = targetIndex/);
  assert.match(shell, /\.onChange\(\(index: number\) => \{\s*this\.selectTab\(index\);\s*this\.selectedNav = index;/);
  assert.match(shell, /\.animationDuration\(TAB_SWIPE_MS\)/);
  assert.match(home, /\.priorityGesture\(\s*PanGesture\(\{ direction: PanDirection\.Horizontal/);
  assert.match(home, /\.tag\('timetable-week'\)/);
  assert.match(home, /return this\.judgeTimetableWeekPan\(info, event\)/);
});

test('header and footer masks use the dark page color without changing the fade curve', () => {
  const mask = new HeaderFadeMask();
  mask.darkMode = true;
  mask.headerHeight = 56;
  const expected = HeaderFade.HEADER_OFFSETS.map((offset, i) =>
    [HeaderFade.rgba('16,18,20', HeaderFade.HEADER_ALPHAS[i]), offset]);
  assert.deepEqual(mask.stops(), expected);
  mask.fromBottom = true;
  assert.deepEqual(mask.stops(), expected.slice().reverse().map(([color, offset]) => [color, 1 - offset]));
});

test('week paging commits on a shorter drag or a quick flick', () => {
  const home = read('pages/Home.ets');
  const ratio = Number(/const TIMETABLE_SWIPE_RATIO: number = ([\d.]+);/.exec(home)[1]);
  assert.ok(ratio > 0 && ratio < 0.15, String(ratio));
  const panEnd = home.slice(home.indexOf('  private handleTimetablePanEnd'), home.indexOf('  private selectTab'));
  assert.match(panEnd, /event\.velocityX/);
  assert.match(panEnd, /width \* TIMETABLE_SWIPE_RATIO/);
});

test('slower week slides finish before swapping data or accepting another gesture', () => {
  const home = read('pages/Home.ets');
  const constant = home.match(/const TIMETABLE_SLIDE_MS: number = \d+;/)[0];
  const methods = home.slice(home.indexOf('  private resetTimetableAnimationState()'),
    home.indexOf('  private handleTimetablePanUpdate('));
  const output = ts.transpileModule(`${constant}
    class Host {
      timetableWeek = 3;
      timetableAnimating = false;
      timetableDragOffset = -60;
      timetableDragLimit() { return 360; }
      shiftTimetableWeek(delta) { this.timetableWeek += delta; }
      ${methods}
    }`, { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText;
  const queued = [];
  const page = new Function('setTimeout', output + '; return new Host();')(
    (run, delay) => { queued.push({ run, delay }); return queued.length; });
  page.animateTimetableWeek(1);
  const exit = queued.shift();
  assert.ok(exit.delay >= page.timetableAnimationDuration);
  assert.equal(page.timetableWeek, 3);
  page.animateTimetableWeek(1);
  assert.equal(queued.length, 0, 'extra gestures must not queue a second transition');
  exit.run();
  assert.equal(page.timetableWeek, 4);
  assert.equal(page.timetableAnimationDuration, 0);
  assert.equal(page.timetableDragOffset, 360);
  queued.shift().run();
  const enter = queued.shift();
  assert.ok(enter.delay >= page.timetableAnimationDuration);
  assert.equal(page.timetableAnimating, true);
  enter.run();
  assert.equal(page.timetableAnimating, false);
  assert.equal(page.timetableDragOffset, 0);
  page.timetableDragOffset = 30;
  page.animateTimetableSnapBack();
  const snap = queued.shift();
  assert.ok(snap.delay >= page.timetableAnimationDuration);
  assert.equal(page.timetableAnimating, true);
  snap.run();
  assert.equal(page.timetableAnimating, false);
  assert.equal(page.timetableWeek, 4);
});

test('latched grid drags reject native horizontal page gestures but retain vertical scrolling', () => {
  const home = read('pages/Home.ets');
  const method = home.slice(home.indexOf('  private judgeTimetableWeekPan'), home.indexOf('  @Builder\n  homeTabs()'));
  const output = ts.transpileModule('class Judge { weekGestureActive = false; dockGestureActive = false; dockNavigation = { isDock: () => this.dockGestureActive }; ' + method + ' }', {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const judge = new Function('GestureJudgeResult', 'GestureControl', 'PanDirection', output + '; return new Judge();')(
    { CONTINUE: 'continue', REJECT: 'reject' }, { GestureType: { PAN_GESTURE: 2, SWIPE_GESTURE: 3 } },
    { Left: 1, Right: 2, Horizontal: 3, Vertical: 12, All: 15 });
  const info = { tag: 'timetable-week' };
  const pan = (direction, builtIn = true) => ({ isBuiltIn: () => builtIn, getType: () => 2,
    getPanGestureOptions: () => ({ getDirection: () => direction }) });
  assert.equal(judge.judgeTimetableWeekPan(info, {}), 'reject');
  assert.equal(judge.judgePagePan(pan(3)), 'continue');
  judge.weekGestureActive = true;
  assert.equal(judge.judgeTimetableWeekPan(info, {}), 'continue');
  for (const direction of [1, 2, 3, 15]) assert.equal(judge.judgePagePan(pan(direction)), 'reject');
  assert.equal(judge.judgePagePan(pan(12)), 'continue');
  assert.equal(judge.judgePagePan(pan(3, false)), 'continue');
  assert.equal(judge.judgeTimetableWeekPan({ tag: 'other' }, {}), 'continue');
  // Dock-originated dragging must not hand off to native page swiping, even
  // on Today/More. Taps and long presses retain their native feedback.
  judge.weekGestureActive = false;
  judge.dockGestureActive = true;
  for (const direction of [1, 2, 3, 15]) assert.equal(judge.judgePagePan(pan(direction)), 'reject');
  for (const type of [0, 1]) {
    assert.equal(judge.judgePagePan({ isBuiltIn: () => true, getType: () => type }), 'continue');
  }
  assert.equal(judge.judgePagePan({ isBuiltIn: () => true, getType: () => 3 }), 'reject');
  judge.dockGestureActive = false;
  assert.equal(judge.judgePagePan(pan(3), true), 'reject', 'bar recognizer also handles pointer/trackpad swipes');
  assert.equal(judge.judgePagePan(pan(3)), 'continue', 'a new content drag still pages normally');
  assert.match(home, /this\.dockNavigation\.begin\(event, false\)/);
  assert.match(home, /event\.type === TouchType\.Down[\s\S]*event\.touches\[0\]\.windowY >= this\.timetableDateBottom/);
  assert.match(home, /this\.timetableDateBottom = \(newValue\.globalPosition\.y as number\) \+ \(newValue\.height as number\)/);
});

test('news, notices and the timetable fade content scrolling under their headers', () => {
  for (const file of ['pages/NewsPage.ets', 'pages/NoticesPage.ets', 'pages/PortalsPage.ets']) {
    const source = read(file);
    assert.match(source, /HeaderFadeMask\(\{ maskOpacity: this\.fadeOpacity/, file);
    assert.match(source, /\.onDidScroll\(\(\) => \{\s*this\.fadeOpacity = HeaderFade\.opacity\(/, file);
  }
  const home = read('pages/Home.ets');
  const tab = home.slice(home.indexOf('  tabTimetable()'), home.indexOf('  statusBanner('));
  assert.match(tab, /HeaderFadeMask\(\{[\s\S]*headerHeight: this\.timetableChromeH/);
  assert.match(tab, /Blank\(\)\.height\(this\.timetableChromeH\)/);
  assert.match(tab, /this\.timetableDateHeader\(\)/);
});

test('notices and the function centre share the transparent header that content scrolls under', () => {
  const home = read('pages/Home.ets');
  const more = home.slice(home.indexOf('  tabMine()'), home.indexOf('  userCard()'));
  assert.match(more, /HeaderFadeMask\(\{[\s\S]*?headerHeight: MORE_HEADER_HEIGHT/);
  assert.match(more, /Text\('功能中心'\)[\s\S]*?\.hitTestBehavior\(HitTestMode\.Transparent\)/);

  const tab = home.slice(home.indexOf('  tabTimetable()'), home.indexOf('  statusBanner('));
  assert.match(tab, /HeaderFadeMask\(\{[\s\S]*headerHeight: this\.timetableChromeH/);
  assert.match(tab, /Blank\(\)\.height\(this\.timetableChromeH\)/);
  assert.match(tab, /this\.timetableDateHeader\(\)/);

  const notices = read('pages/NoticesPage.ets');
  const page = notices.slice(notices.indexOf('  build()'));
  assert.match(page, /HeaderFadeMask\(\{[^}]*headerHeight: HEADER_HEIGHT/);
  assert.match(page, /Row\(\) \{\s*HeaderBackButton\(\{[\s\S]*?\.height\(HEADER_HEIGHT\)[\s\S]*?\.hitTestBehavior\(HitTestMode\.Transparent\)/);
  assert.doesNotMatch(page, /\.border\(\{ width: \{ bottom: 1 \}/);
  // The first list row reserves the header height so notices start below it, then scroll beneath.
  assert.match(page, /List\(\{[^)]*\}\) \{\s*\/\/[^\n]*\n\s*ListItem\(\) \{\s*Column\(\)\s*\.width\('100%'\)\s*\.height\(HEADER_HEIGHT\)/);

  assert.equal(HeaderFade.HEADER_ALPHAS[0], 1);
  assert.equal(HeaderFade.HEADER_ALPHAS.at(-1), 0);
});

test('function-centre secondary pages use the same transparent header', () => {
  const pages = ['NoticesPage', 'ScorePage', 'ExamPage',
    'ImportTimetablePage', 'TimetableManagerPage', 'TimetableDetailPage', 'PortalsPage'];
  for (const page of pages) {
    const source = read(page === 'ImportTimetablePage' ? 'pages/ImportTimetablePanel.ets' : `pages/${page}.ets`);
    const build = source.slice(source.indexOf('  build()'));
    assert.match(build, /HeaderFadeMask\(\{[\s\S]*?headerHeight: HEADER_HEIGHT/, page);
    assert.match(build, /Row\(\s*(?:\{[^{}\n]*\}\s*)?\)\s*\{\s*HeaderBackButton\(\{[\s\S]*?\.height\(HEADER_HEIGHT\)[\s\S]*?\.hitTestBehavior\(HitTestMode\.Transparent\)/, page);
    assert.doesNotMatch(build, /\.border\(\{ width: \{ bottom: 1 \}/, page);
  }
});

test('score results scroll beneath the header and clear its fade when refreshing', () => {
  const source = read('pages/ScorePage.ets');
  const build = source.slice(source.indexOf('  build()'));
  assert.match(build, /Stack\(\{ alignContent: Alignment\.Top \}\)/);
  assert.match(build, /Scroll\(this\.pageScroller\) \{[\s\S]*?this\.queryFilters\(\)[\s\S]*?this\.statisticsCard\(\)/);
  assert.match(build, /top: HEADER_HEIGHT, bottom: 16 \+ this\.navBarInset/);
  assert.match(build, /\.onDidScroll\(\(\) => \{\s*this\.fadeOpacity = HeaderFade\.opacity\(this\.pageScroller\.currentOffset\(\)\.yOffset\)/);
  assert.ok(build.indexOf('Scroll(this.pageScroller)') < build.indexOf('HeaderFadeMask('));
  assert.ok(build.indexOf('HeaderFadeMask(') < build.indexOf('ImmersiveHeader({ barHeight: HEADER_HEIGHT'));
  assert.match(source, /private resetResult\(\): void \{[^}]*this\.fadeOpacity = 0;/);
  assert.match(build, /\.padding\(\{ top: this\.presentedAsSheet \? 0 : this\.statusBarInset \}\)/);
});

test('timetable today column is a single tint that stops at the date header', () => {
  const home = read('pages/Home.ets');
  const tab = home.slice(home.indexOf('  tabTimetable()'), home.indexOf('  statusBanner('));
  assert.match(home, /this\.timetableBackdrop, this\.hasTimetableBackground\(\), false\);/);
  assert.match(tab, /x: TIMETABLE_GUTTER_WIDTH \+ this\.timetableTodayColumn\(\) \* this\.timetableTodayColumnWidth\(\),\s*y: this\.timetableChromeH\s*\}/);
  assert.match(tab, /\.backgroundColor\(this\.timetableBackdrop\.todayHeader\)[\s\S]*?Scroll\(this\.timetableScroller\)/);
  assert.match(home, /Math\.max\(0, gridBottom - this\.timetableScrollY\)/);
  assert.match(tab, /highlight: this\.timetableTodayColumn\(\) >= 0 \? this\.timetableBackdrop\.todayHeader : 0/);
  assert.match(tab, /highlightTop: this\.timetableChromeH/);
  const draw = read('feature/timetable/views/TimetableWeekDraw.ets');
  assert.match(draw, /if \(isCurrentWeek && drawTodayMask\)/);
});

test('the fade over the today column is page colour composited with the today tint', () => {
  // 0x17 alpha of #2E86E8 over the light page.
  const argb = ((23 << 24) | 0x2E86E8) >>> 0;
  const a = 23 / 255;
  const expected = [0x2E, 0x86, 0xE8].map((c, i) => Math.round(c * a + [244, 247, 252][i] * (1 - a))).join(',');
  assert.equal(HeaderFade.blendRgb('244,247,252', argb), expected);
  assert.equal(HeaderFade.blendRgb('244,247,252', 0), '244,247,252');
  const mask = new HeaderFadeMask();
  mask.headerHeight = 150;
  mask.highlight = argb;
  mask.highlightWidth = 40;
  mask.maskWidth = 400;
  mask.highlightTop = 150;
  assert.equal(mask.hasHighlight(), true);
  mask.highlight = 0;
  assert.equal(mask.hasHighlight(), false);
});

test('the fixed today column re-renders once the timetable area is measured', () => {
  const home = read('pages/Home.ets');
  assert.match(home, /@State private timetableAreaW: number = 0;/);
  assert.match(home, /@State private timetableAreaH: number = 0;/);
});
