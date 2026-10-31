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
function harness({ width = 720, rail = false, fold = false, available = true } = {}) {
  const animations = [], railMoves = [];
  const rendered = { x: 16, y: 648 };
  let onSide, unavailable, started = false;
  const globals = { ...geometry, TouchType, DockNavigationGuard,
    DOCK_GROUP_ID: 'home-dock-group', deviceInfo: { apiAvailable: () => true },
    Curve: { FastOutSlowIn: 'fast-out-slow-in' } };
  const Page = new Function(...Object.keys(globals), compile(`class Page {
    ${['startDockHandedness', 'bottomDockOffset', 'dockOffset', 'setBottomDockBounds', 'syncBottomDockBounds'].map(method).join('\n')}
  }`) + '; return Page;')(...Object.values(globals));
  const page = new Page();
  Object.assign(page, {
    homeWidth: width, dockSide: 0, foldRailDevice: fold, railRight: false,
    dockNavigation: new DockNavigationGuard(4, 3),
    railMode: () => rail, railFollowsHand: () => rail && fold,
    moveRailTo: side => railMoves.push(side),
    dockLightEnabled: () => true, dockLight: { stop() {} },
    getUIContext: () => ({
      animateTo: (options, change) => {
        const before = page.bottomDockOffset();
        change();
        animations.push({ before, after: page.bottomDockOffset(), ...options });
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
