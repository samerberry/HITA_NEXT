const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const load = (file, globals = {}) => {
  const mod = { exports: {} };
  const output = ts.transpileModule(read(file), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  new Function('module', 'exports', ...Object.keys(globals), output)(mod, mod.exports, ...Object.values(globals));
  return mod.exports;
};

const geometry = load('common/util/DockHandedness.ets');

test('rail mode: landscape tablets and fully unfolded tri-folds only, never phones or dual-folds', () => {
  const { dockRailMode } = geometry;
  // Tablet portrait keeps the bottom dock; landscape gets the rail.
  assert.equal(dockRailMode(800, 1200, true, false), false);
  assert.equal(dockRailMode(1280, 760, true, false), true);
  // Tablet split screen or floating window keeps the bottom dock.
  assert.equal(dockRailMode(400, 1200, true, false), false);
  // Tri-fold fully unfolded: rail in landscape, bottom dock in portrait.
  assert.equal(dockRailMode(1000, 900, false, true), true);
  assert.equal(dockRailMode(900, 1000, false, true), false);
  // Phone landscape and an opened dual-fold have similar widths and stay at the bottom.
  assert.equal(dockRailMode(860, 380, false, false), false);
  assert.equal(dockRailMode(720, 800, false, false), false);
  // Too short for an upright 212 vp capsule, or not measured yet.
  assert.equal(dockRailMode(1280, 200, true, true), false);
  assert.equal(dockRailMode(0, 0, true, true), false);
  assert.equal(dockRailMode(NaN, 900, true, true), false);
});

test('the rail starts on the left and moves only for a right-hand grip', () => {
  assert.equal(geometry.dockRailOnRight(0), false);
  assert.equal(geometry.dockRailOnRight(-1), false);
  assert.equal(geometry.dockRailOnRight(1), true);
  assert.equal(geometry.DOCK_RAIL_INSET, 16 + 56 + 8);
});

const TouchType = { Down: 0, Up: 1, Move: 2, Cancel: 3 };
let nowMs = 0;
const Guard = load('common/util/DockNavigationGuard.ets', { TouchType, Date: { now: () => nowMs } })
  .DockNavigationGuard;
let stamp = 0;
const ev = (type, x, y) => ({ type, timestamp: ++stamp, changedTouches: [{ windowX: x, windowY: y, id: 0 }],
  touches: type === TouchType.Up ? [] : [{ windowX: x, windowY: y, id: 0 }], getHistoricalPoints: () => [] });
function heldRelease(guard, x, y) {
  nowMs = 0;
  const down = ev(TouchType.Down, x, y);
  guard.begin(down, true);
  guard.observe(down);
  nowMs = 220;
  guard.activateHold();
  guard.observe(ev(TouchType.Up, x, y));
  const result = [];
  guard.commitClick(guard.requestClick(), 0, i => result.push(i));
  return result;
}

test('vertical rail: held release picks the item under the finger along Y', () => {
  for (const target of [0, 1, 2]) {
    const guard = new Guard();
    guard.setBounds(16, 400, 56, 212, 4, true);
    const y = 400 + 4 + (target + 0.5) * (212 - 8) / 3;
    assert.deepEqual(heldRelease(guard, 44, y), [target]);
  }
});

test('vertical rail: tolerance is across the rail, and leaving its ends clears the target', () => {
  const guard = new Guard();
  guard.setBounds(16, 400, 56, 212, 4, true);
  assert.deepEqual(heldRelease(guard, 16 - 6, 450), [0], 'slightly off the side still counts');
  assert.deepEqual(heldRelease(guard, 44, 400 - 6), [], 'above the rail never snaps to the first item');
  assert.deepEqual(heldRelease(guard, 44, 612 + 6), [], 'below the rail never snaps to the last item');
});

test('vertical rail: the press light maps the rail length onto the shared 0-212 light axis', () => {
  const guard = new Guard();
  guard.setBounds(16, 400, 56, 212, 4, true);
  nowMs = 0;
  const down = ev(TouchType.Down, 44, 400 + 4 + 102);
  guard.begin(down, true);
  guard.observe(down);
  assert.equal(guard.lightPosition(down), 106);
  // A horizontal bar keeps its original X mapping.
  const bar = new Guard();
  bar.setBounds(300, 1500, 212, 56);
  const tap = ev(TouchType.Down, 300 + 53, 1528);
  bar.begin(tap, true);
  bar.observe(tap);
  assert.equal(bar.lightPosition(tap), 53);
});

test('wiring: the rail replaces the bottom dock and every surface keeps clear of it', () => {
  const home = read('pages/Home.ets');
  assert.match(home, /if \(this\.railMode\(\)\) \{\s*this\.dockRail\(\);\s*\} else \{\s*this\.splitDock\(\);/);
  assert.match(home, /if \(this\.railMode\(\)\) \{\s*this\.dockRail\(\);\s*\} else \{\s*this\.compatibleDock\(\);/);
  assert.match(home, /\.barHeight\(0\)/);
  assert.doesNotMatch(home, /new CompatibleDockModifier/);
  assert.match(home, /return this\.railMode\(\) \? this\.navBarInset : 64 \+ this\.navBarInset;/);
  assert.match(home, /FOLD_STATUS_EXPANDED_WITH_SECOND_EXPANDED/);
  assert.match(home, /deviceInfo\.deviceType === 'tablet'/);
  // Tablets pin the rail left; only a fully opened tri-fold follows the grip.
  assert.ok(home.includes('private railFollowsHand(): boolean {\n    return this.railMode() && this.foldRailDevice;'));
  assert.ok(home.includes('return this.railFollowsHand() && this.railRight;'));
  // Switching edges leaves through the current edge, swaps offscreen, then springs in like the floating controls.
  assert.equal(geometry.DOCK_RAIL_EXIT, 16 + 56 + 16);
  const move = home.slice(home.indexOf('  private moveRailTo('), home.indexOf('  private dockOffset()'));
  assert.match(move, /curve: curves\.customCurve\(floatingActionExitProgress\),\s*onFinish: \(\) => \{\s*if \(generation !== this\.railGeneration\) return;\s*this\.railRight = right;\s*this\.railShift = right \? DOCK_RAIL_EXIT : -DOCK_RAIL_EXIT;\s*this\.springRailIn\(\);/);
  assert.match(move, /this\.railShift = this\.railRight \? DOCK_RAIL_EXIT : -DOCK_RAIL_EXIT;/);
  assert.match(move, /curves\.interpolatingSpring\(0, 1, 170, 17\)[\s\S]*?this\.railShift = 0;/);
  assert.match(home, /if \(this\.railFollowsHand\(\)\) \{\s*this\.dockSide = side;\s*this\.moveRailTo\(side > 0\);\s*return;/);
  assert.ok(home.includes('.translate({ x: this.railShift, y: 0 })'));
  assert.ok(home.includes('x: this.railOnRight() ? this.homeWidth'));
  assert.ok(home.includes('const needed: boolean = this.railMode() ? this.foldRailDevice : true;'));
  // Gutters are symmetric and side-independent, so content never shifts with the rail.
  assert.ok(home.includes('private railGutter(): number {\n    return this.railMode() ? DOCK_RAIL_INSET : 0;'));
  assert.ok(!home.includes('railInset('));
  // Timetable layers take an explicit centred width instead of 100% plus margin, which overflowed.
  assert.ok(home.includes('Math.max(0, this.homeWidth - this.railGutter() * 2)'));
  assert.equal(home.split('.width(this.railContentWidth())').length - 1, 3);
  assert.ok(!/\.margin\(\{ left: this\.rail/.test(home));
  assert.equal(home.split('.tabPage(0, COLOR_SURFACE, this.railGutter(), this.railGutter())').length - 1, 2);
  assert.match(home, /TimetableFloatingActions\(\{[\s\S]*?leftInset: this\.floatingActionsInGutter\(\) \? 0 : this\.railGutter\(\),\s*rightInset: this\.floatingActionsInGutter\(\) \? 0 : this\.railGutter\(\),/);
  // The rail keeps hold-to-slide and the API 26 light, laid out along its height.
  const rail = home.slice(home.indexOf('  dockRail() {'), home.indexOf('  compatibleDock() {'));
  assert.match(rail, /this\.updateDockBounds\(area, 4, true\)/);
  assert.match(rail, /this\.observeDockTouch\(event, true\)/);
  // Drawn upright on its own canvas: a rotated 212×56 canvas was squeezed by the 56 vp column first.
  assert.ok(rail.includes('DockLightOverlay({ controller: this.dockLight, vertical: true, itemPadding: 4 })'));
  assert.ok(!rail.includes('.rotate('));
  const light = read('common/components/DockLightOverlay.ets');
  assert.ok(light.includes('if (this.vertical) this.canvas.setTransform(0, 1, -1, 0, 56, 0);'));
  assert.ok(light.includes('.width(this.vertical ? 56 : DOCK_WIDTH)'));
  // API 26 renders ordinary-component materials only in a Navigation title bar or the bottom TabBar,
  // so the API 26+ capsule is hosted in a native title region enlarged for its shadow.
  const railUi = read('common/components/DockRail.ets');
  const host = railUi.slice(railUi.indexOf('  build() {'));
  assert.match(host, /if \(this\.systemGlass\) \{[\s\S]*?ImmersiveHeader\(\{ barHeight: DOCK_WIDTH \+ RAIL_OVERFLOW \* 2 \}\) \{[\s\S]*?this\.capsule\(\);/);
  assert.ok(host.includes('.position({ x: -RAIL_OVERFLOW, y: -RAIL_OVERFLOW })'));
  assert.match(host, /\} else \{\s*this\.capsule\(\);/);
  assert.ok(railUi.includes('.attributeModifier(new CompatibleRailModifier(this.darkMode))'));
  // The rail wears exactly the bottom bar's glass and light; systemMaterial owns its border and shadow.
  const glass = read('common/theme/ImmersiveDockModifier.ets');
  const applyRail = glass.slice(glass.indexOf('  static applyRail('), glass.indexOf('  private static styleForDevice'));
  assert.ok(applyRail.includes('DockBarMaterial.material(lightAlpha);'));
  assert.ok(!applyRail.includes('.border('));
  assert.ok(!glass.includes('materialColor'));
  // Same 92 vp edge mask as the bottom bar, hidden over a timetable wallpaper, sliding with the rail.
  const mask = home.slice(home.indexOf('  dockRailMask() {'), home.indexOf('  dockRail() {'));
  assert.ok(mask.includes('.width(DOCK_RAIL_MASK_WIDTH)'));
  // Dark mode fades to a transparent dark; a transparent light end drew a white band down the edge.
  assert.ok(mask.includes("colors: [[this.darkMode ? '#99101214' : '#66F1F3F5', 0], [this.darkMode ? '#00101214' : '#00F1F3F5', 1]]"));
  assert.ok(mask.includes('.translate({ x: this.railShift, y: 0 })'));
  assert.match(home, /if \(!\(this\.selectedNav === TAB_TIMETABLE && this\.hasTimetableBackground\(\)\)\) \{\s*this\.dockRailMask\(\);/);
});

test('fold rails: fully opened tri-folds and opened wide folds, not book-style dual folds', () => {
  assert.equal(geometry.DOCK_RAIL_MASK_WIDTH, 92);
  // Wide fold inner screen (about 16:10) versus a near-square book fold.
  assert.equal(geometry.dockWideFoldScreen(2284, 1440), true);
  assert.equal(geometry.dockWideFoldScreen(1440, 2284), true);
  assert.equal(geometry.dockWideFoldScreen(2496, 2224), false);
  assert.equal(geometry.dockWideFoldScreen(0, 0), false);
  assert.equal(geometry.dockWideFoldScreen(NaN, 1000), false);
  const home = read('pages/Home.ets');
  const read_ = home.slice(home.indexOf('  private static readFoldRailDevice()'), home.indexOf('  private onHomeArea('));
  assert.ok(read_.includes('FOLD_STATUS_EXPANDED_WITH_SECOND_EXPANDED) return true;'));
  assert.ok(read_.includes('screenDisplay.FoldStatus.FOLD_STATUS_EXPANDED'));
  assert.ok(read_.includes('FoldDisplayMode.FOLD_DISPLAY_MODE_FULL'));
  assert.ok(read_.includes('return dockWideFoldScreen(screen.width, screen.height);'));
  assert.ok(home.includes('this.foldRailDevice = Home.readFoldRailDevice();'));
});

test('landscape tri-fold rails move the evening / return buttons into the side gutter', () => {
  assert.equal(geometry.DOCK_GUTTER_ACTION_EDGE, 16 + 28 - 24);
  const home = read('pages/Home.ets');
  assert.ok(home.includes('if (!this.railFollowsHand()) return false;'));
  assert.ok(home.includes('return belowRail >= 20 + 48 + FLOATING_ACTION_GAP + 8;'));
  assert.ok(home.includes('leftInset: this.floatingActionsInGutter() ? 0 : this.railGutter(),'));
  assert.ok(home.includes('edgeMargin: this.floatingActionsInGutter() ? DOCK_GUTTER_ACTION_EDGE : 18,'));
  const ui = read('feature/timetable/views/TimetableFloatingActions.ets');
  assert.ok(ui.includes('@Prop edgeMargin: number = 18;'));
});

test('evening / return buttons sit beside a rail on their edge and fully clear it when hidden', () => {
  const ui = read('feature/timetable/views/TimetableFloatingActions.ets');
  assert.ok(ui.includes('left: this.edgeMargin + this.leftInset, bottom: this.bottomInset + 20'));
  assert.ok(ui.includes('right: this.edgeMargin + this.rightInset, bottom: this.bottomInset + 20'));
  assert.ok(ui.includes('return x * (FLOATING_ACTION_EXIT + inset) / FLOATING_ACTION_EXIT;'));
  assert.ok(ui.includes('.translate({ x: this.travel(this.frame.eveningX), y: 0 })'));
  assert.ok(ui.includes('.translate({ x: this.travel(this.frame.returnX), y: -this.frame.returnLift })'));
});

test('rail glass: native material on API 26+, API 23 blur otherwise; native bar stands down', () => {
  const rail = read('common/theme/CompatibleRailModifier.ets');
  assert.match(rail, /import lazy \{ DockBarMaterial \}/);
  assert.match(rail, /if \(deviceInfo\.apiAvailable\('26\.0\.0'\)\) \{\s*if \(DockBarMaterial\.applyRail/);
  assert.match(rail, /backgroundEffect\(\{/);
  const dock = read('common/theme/CompatibleDockModifier.ets');
  assert.match(dock, /if \(this\.rail\) \{[\s\S]*?instance\.barFloatingStyle\(undefined\);\s*return;/);
  const view = read('common/components/DockRail.ets');
  assert.match(view, /'今日', 0\)[\s\S]*'时间表', 1\)[\s\S]*'更多', 2\)/);
  assert.match(view, /blendMode\(BlendMode\.DIFFERENCE, BlendApplyType\.OFFSCREEN\)/);
});

test('rail selection only highlights the icon, like the native bottom bar', () => {
  const ui = read('common/components/DockRail.ets');
  assert.ok(!ui.includes('RAIL_ITEM'));
  assert.ok(!ui.includes("'#18FFFFFF'"));
  assert.ok(ui.includes("$r('sys.color.ohos_id_color_text_primary')"));
  assert.ok(ui.includes('.fontSize(HitaDesign.dockLabel)'));
  assert.match(read('common/theme/HitaDesign.ets'), /static readonly dockLabel: number = 11;/);
});

test('bottom navigation, assistant and light share one grip transform', () => {
  const home = read('pages/Home.ets');
  const shared = home.slice(home.indexOf('  splitDock() {'), home.indexOf('  compatibleDock() {'));
  assert.match(shared, /Stack\([\s\S]*?SplitDock\([\s\S]*?DockLightOverlay\([\s\S]*?\.id\(DOCK_GROUP_ID\)/);
  assert.match(shared, /\.translate\(\{ x: this\.bottomDockOffset\(\), y: 0 \}\)/);
  assert.match(shared, /\.margin\(\{ bottom: HitaDesign\.spaceSm \+ this\.navBarInset \}\)/);
  assert.match(shared, /\.hitTestBehavior\(HitTestMode\.Default\)/);
  assert.doesNotMatch(home, /trackDockBar|findDockCapsule|dockCapsuleX|dockBarModifier/);
  const ui = read('common/components/SplitDock.ets');
  assert.match(ui, /ImmersiveHeader\([\s\S]*?new CompatibleRailModifier\(this\.darkMode\)/);
  assert.match(ui, /AssistantDockButton\([\s\S]*?\.position\(\{ x: DOCK_ACTION_START, y: 0 \}\)/);
  assert.doesNotMatch(ui, /sideOffset|dockSide|animateTo|\.translate\(/);
  assert.match(home, /group\.getPositionToWindowWithTransform\(\)/);
  assert.match(home, /this\.syncBottomDockBounds\(\);\s*this\.dockNavigation\.begin\(event, true\);/);
});
