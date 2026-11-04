const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const compile = text => ts.transpileModule(text, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText;
function load(file, globals = {}) {
  const mod = { exports: {} };
  new Function('module', 'exports', ...Object.keys(globals), compile(read(file)))(
    mod, mod.exports, ...Object.values(globals));
  return mod.exports;
}
const geometry = load('common/util/DockHandedness.ets');
const TouchType = { Down: 0, Up: 1, Move: 2, Cancel: 3 };
const { DockNavigationGuard } = load('common/util/DockNavigationGuard.ets', { TouchType });
const home = read('pages/Home.ets');
function method(name) {
  const start = home.indexOf('  private ' + name + '(');
  assert.ok(start >= 0, name);
  let at = home.indexOf('{', start), depth = 1, end = at + 1;
  for (; depth > 0; end++) {
    if (home[end] === '{') depth++;
    if (home[end] === '}') depth--;
  }
  return home.slice(start, end);
}
function harness({ width = 720, rail = false, fold = false, available = true, phone = false } = {}) {
  const animations = [], railMoves = [];
  const rendered = { x: 16, y: 648 };
  let onSide, unavailable, started = false;
  const globals = { ...geometry, TouchType, DockNavigationGuard,
    DOCK_GROUP_ID: 'home-dock-group', deviceInfo: { apiAvailable: () => true },
    Curve: { FastOutSlowIn: 'fast-out-slow-in' },
    curves: { customCurve: () => 'exit', interpolatingSpring: () => 'spring' },
    FLOATING_ACTION_EXIT_DURATION: 180, floatingActionExitProgress: x => x };
  const Page = new Function(...Object.keys(globals), compile(`class Page {
    ${['startDockHandedness', 'bottomDockOffset', 'dockOffset', 'setBottomDockBounds', 'syncBottomDockBounds',
      'placePhoneDock', 'movePhoneActionTo', 'springPhoneActionIn', 'applyAssistantDockVisibility'].map(method).join('\n')}
  }`) + '; return Page;')(...Object.values(globals));
  const page = new Page();
  Object.assign(page, {
    homeWidth: width, dockSide: 0, foldRailDevice: fold, railRight: false,
    assistantDockVisible: true,
    phoneActionLeft: false, phoneActionShift: 0, phoneNavShift: 0, phoneActionGeneration: 0, phoneDockWasActive: false,
    phoneDock: () => phone,
    resetDockInteraction: () => {},
    dockNavigation: new DockNavigationGuard(4, 3),
    railMode: () => rail, railFollowsHand: () => rail && fold,
    moveRailTo: side => railMoves.push(side),
    dockLightEnabled: () => true, dockLight: { stop() {} },
    getUIContext: () => ({
      animateTo: (options, change) => {
        const before = page.bottomDockOffset();
        change();
        animations.push({ before, after: page.bottomDockOffset(), shift: page.phoneActionShift,
          left: page.phoneActionLeft, nav: page.phoneNavShift, ...options });
      },
      getFrameNodeById: id => {
        assert.equal(id, 'home-dock-group');
        return { getPositionToWindowWithTransform: () => rendered };
      }
    }),
    dockHandObserver: {
      start(side, missing) {
        if (started) return available;
        started = true;
        onSide = side;
        unavailable = missing;
        if (!available) missing();
        return available;
      },
      stop() { started = false; }
    }
  });
  page.placePhoneDock();
  page.startDockHandedness();
  return { page, animations, railMoves, rendered, grip: left => onSide(left), unavailable: () => unavailable() };
}

test('rapid grip reversals retarget immediately without waiting for the prior 300 ms slide', () => {
  const h = harness();
  h.grip(true);
  assert.equal(h.page.bottomDockOffset(), -204);
  h.grip(false); // previous animation has not completed
  assert.equal(h.page.bottomDockOffset(), 204);
  h.grip(true);
  assert.equal(h.page.bottomDockOffset(), -204);
  assert.deepEqual(h.animations.map(a => [a.before, a.after]), [[0, -204], [-204, 204], [204, -204]]);
  assert.ok(h.animations.every(a => a.duration === 300 && a.curve === 'fast-out-slow-in'));
  h.grip(true);
  h.page.startDockHandedness();
  h.grip(true);
  assert.equal(h.animations.length, 3, 'duplicate readings and area changes cannot restart the slide');
});

test('toggling the assistant uses the grip exit and re-entry curves without shifting phone navigation', () => {
  const h = harness({ phone: true, width: 390 });
  const nav = h.page.phoneNavShift;
  h.page.applyAssistantDockVisibility(false);
  assert.equal(h.page.assistantDockVisible, false);
  h.page.applyAssistantDockVisibility(true);
  assert.equal(h.page.assistantDockVisible, true);
  assert.deepEqual(h.animations.map(a => [a.curve, a.nav]), [['exit', nav], ['spring', nav]]);
});

test('folding centres the complete group; unfolding reuses its most recent grip', () => {
  const h = harness();
  h.grip(false);
  for (const width of [378, 590, 0]) {
    h.page.homeWidth = width;
    assert.equal(h.page.bottomDockOffset(), 0);
  }
  h.page.homeWidth = 720;
  assert.equal(h.page.bottomDockOffset(), 204);
  h.unavailable();
  assert.equal(h.page.bottomDockOffset(), 0);
  assert.equal(harness({ available: false }).page.bottomDockOffset(), 0);
});

test('rail switching preserves its own edge transition and tablet rails stay pinned', () => {
  const fold = harness({ rail: true, fold: true });
  fold.grip(false);
  fold.grip(true);
  assert.deepEqual(fold.railMoves, [true, false]);
  assert.deepEqual(fold.animations, []);
  const tablet = harness({ rail: true });
  assert.equal(tablet.page.dockSide, 0);
  assert.equal(tablet.page.dockHandednessActive, false);
});

test('during a grip slide the drawn group defines navigation, gap and assistant hit areas', () => {
  const h = harness();
  let stamp = 0;
  for (const left of [16, 100, 220, 424]) {
    h.rendered.x = left;
    h.page.syncBottomDockBounds();
    for (const [x, action, target] of [[44, -1, 0], [108, -1, 1], [172, -1, 2], [220, -1, -1], [252, 3, -1]]) {
      const guard = h.page.dockNavigation;
      const point = { id: 0, windowX: left + x, windowY: 676 };
      const down = { type: TouchType.Down, timestamp: ++stamp, touches: [point], changedTouches: [point],
        getHistoricalPoints: () => [] };
      guard.begin(down, true);
      guard.observe(down);
      assert.equal(guard.actionTarget(), action);
      if (target >= 0 || action >= 0) assert.equal(guard.lightPosition(down), x);
      guard.observe({ ...down, type: TouchType.Up, timestamp: ++stamp, touches: [] });
      assert.equal(guard.releaseTarget(), action >= 0 ? action : target);
      const changes = [];
      guard.commitClick(guard.requestClick(), guard.releaseTarget(), index => changes.push(index));
      assert.deepEqual(changes, target >= 0 ? [target] : [], 'assistant and gap never select a page');
      guard.reset();
    }
  }
});

test('hiding the assistant preserves the three page targets and clears the old assistant hit area', () => {
  const h = harness();
  h.page.assistantDockVisible = false;
  h.page.syncBottomDockBounds();
  const guard = h.page.dockNavigation;
  for (const [x, target] of [[44, 0], [108, 1], [172, 2], [252, -1]]) {
    const point = { id: 0, windowX: h.rendered.x + x, windowY: h.rendered.y + 28 };
    const down = { type: TouchType.Down, timestamp: 1, touches: [point], changedTouches: [point],
      getHistoricalPoints: () => [] };
    guard.begin(down, true);
    guard.observe(down);
    assert.equal(guard.actionTarget(), -1);
    guard.observe({ ...down, type: TouchType.Up, timestamp: 2, touches: [] });
    assert.equal(guard.releaseTarget(), target);
    guard.reset();
  }
});

test('phones keep the navigation centred and send only the assistant to the holding-hand edge', () => {
  const h = harness({ width: 378, phone: true });
  assert.equal(h.page.phoneActionLeft, false, 'the assistant starts on the right');
  assert.equal(h.page.phoneNavShift, 0, 'a 378 vp phone has room for the centred navigation');
  h.grip(true);
  // Leave through the right edge with the bounded exit, swap while offscreen, spring in from the left.
  assert.deepEqual(h.animations.map(a => [a.curve, a.duration, a.shift, a.left]),
    [['exit', 180, geometry.DOCK_ACTION_EXIT, false]]);
  h.animations[0].onFinish();
  assert.equal(h.page.phoneActionLeft, true);
  assert.deepEqual(h.animations.slice(1).map(a => [a.curve, a.shift]), [['spring', 0]]);
  assert.equal(h.page.bottomDockOffset(), 0, 'the navigation never follows the grip on phones');
  h.unavailable();
  assert.equal(h.animations[2].curve, 'exit', 'losing the sensor sends the assistant back to the right');
  h.animations[2].onFinish();
  assert.equal(h.page.phoneActionLeft, false);
});

test('a reversed grip before the swap springs back without changing edge, and stale exits are ignored', () => {
  const h = harness({ width: 378, phone: true });
  h.grip(true);
  const exit = h.animations[0];
  h.grip(false);
  assert.deepEqual(h.animations.slice(1).map(a => [a.curve, a.shift, a.left]), [['spring', 0, false]]);
  exit.onFinish();
  assert.equal(h.page.phoneActionLeft, false, 'the superseded exit cannot swap edges');
});

test('narrow phones move the navigation just far enough from the assistant', () => {
  const { dockPhoneNavShift, DOCK_NAV_WIDTH, DOCK_SIDE_MARGIN, DOCK_ACTION_SIZE, DOCK_PHONE_GAP } = geometry;
  for (const width of [378, 400, 599]) {
    assert.equal(dockPhoneNavShift(width, 1), 0);
    assert.equal(dockPhoneNavShift(width, -1), 0);
  }
  for (const width of [320, 340, 360]) {
    const right = dockPhoneNavShift(width, 1);
    assert.ok(right < 0, 'moves left, away from a right-hand assistant');
    assert.equal(dockPhoneNavShift(width, -1), -right);
    const navRight = width / 2 + DOCK_NAV_WIDTH / 2 + right;
    assert.ok(navRight + DOCK_PHONE_GAP <= width - DOCK_SIDE_MARGIN - DOCK_ACTION_SIZE + 1e-9);
    assert.ok(width / 2 - DOCK_NAV_WIDTH / 2 + right >= DOCK_SIDE_MARGIN - 1e-9, 'never past the far margin');
  }
  assert.equal(dockPhoneNavShift(0, 1), 0);
  assert.equal(dockPhoneNavShift(NaN, -1), 0);
});

test('phone navigation bounds keep the page grid and never reach the assistant slot', () => {
  const h = harness({ width: 378, phone: true });
  let stamp = 0;
  h.rendered.x = 72;
  h.page.syncBottomDockBounds();
  for (const [x, target] of [[44, 0], [108, 1], [172, 2], [210, 2]]) {
    const guard = h.page.dockNavigation;
    const point = { id: 0, windowX: 72 + x, windowY: 676 };
    const down = { type: TouchType.Down, timestamp: ++stamp, touches: [point], changedTouches: [point],
      getHistoricalPoints: () => [] };
    guard.begin(down, true);
    guard.observe(down);
    assert.equal(guard.actionTarget(), -1);
    guard.observe({ ...down, type: TouchType.Up, timestamp: ++stamp, touches: [] });
    assert.equal(guard.releaseTarget(), target);
    guard.reset();
  }
});
