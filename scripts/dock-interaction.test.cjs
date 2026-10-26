const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const home = fs.readFileSync(path.join(root, 'pages/Home.ets'), 'utf8').replace(/\r\n/g, '\n');
const guardSource = fs.readFileSync(path.join(root, 'common/util/DockNavigationGuard.ets'), 'utf8');
const lightSource = fs.readFileSync(path.join(root, 'common/util/DockLightEffect.ets'), 'utf8');
const envelopeSource = fs.readFileSync(path.join(root, 'common/util/ImmersiveLightEffect.ets'), 'utf8');
const TouchType = { Down: 0, Up: 1, Move: 2, Cancel: 3 };
const transpile = source => ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText;

function harness({ api = 26, controllerDelay = 0, withBounds = true, localPoint, fixedTimestamp } = {}) {
  const api26 = api >= 26;
  const clock = { now: 0 };
  const timers = new Map();
  let timerId = 0;
  let timestamp = 0;
  const setTimer = (callback, delay) => {
    timers.set(++timerId, { callback, due: clock.now + delay });
    return timerId;
  };
  const advance = elapsed => {
    const end = clock.now + elapsed;
    while (true) {
      const next = [...timers].filter(([, timer]) => timer.due <= end)
        .sort((a, b) => a[1].due - b[1].due)[0];
      if (!next) break;
      clock.now = Math.max(clock.now, next[1].due);
      timers.delete(next[0]);
      next[1].callback();
    }
    clock.now = end;
  };
  const guardModule = { exports: {} };
  new Function('module', 'exports', 'TouchType', 'Date', transpile(guardSource))(
    guardModule, guardModule.exports, TouchType, { now: () => clock.now });
  const lightModule = { exports: {} };
  const envelopeModule = { exports: {} };
  new Function('module', 'exports', transpile(envelopeSource))(envelopeModule, envelopeModule.exports);
  new Function('require', 'module', 'exports', transpile(lightSource))(
    () => envelopeModule.exports, lightModule, lightModule.exports);
  const envelope = new envelopeModule.exports.ImmersiveLightEnvelope();
  const lightTouches = [];
  const from = home.indexOf('  private requestDockClick(');
  const to = home.indexOf('  @Builder\n  homeTabs()', from);
  assert.ok(from >= 0 && to > from);
  const changes = [];
  const lights = [];
  const stoppedLights = [];
  const changeRequests = [];
  const code = `
    class Home {
      dockNavigation = new Guard();
      dockHolding = false;
      dockLightAlpha = DOCK_TAP_LIGHT_ALPHA;
      dockLightGeneration = 0;
      dockHoldTimer = -1;
      dockPressSource = 0;
      selectedNav = 0;
      // No native bar is measured here (host width 0), so capsule tracking leaves the
      // guard bounds that updateDockBounds sets below.
      dockBarHostW = 0;
      dockCapsuleX = -1;
      dockBarTrackUntil = 0;
      dockBarTracking = false;
      pageVisible = true;
      railMode() { return true; }
      getUIContext() { return { postFrameCallback: frame => setTimeout(() => frame.onFrame(), 16) }; }
      dockLight = { transfer: (from, to) => lights.push([from, to]),
        stop: () => { stoppedLights.push(clock.now); envelope.reset(); },
        press: source => { lightTouches.push(['press', source]); envelope.press(clock.now); },
        move: x => lightTouches.push(['move', x]),
        release: cancelled => { lightTouches.push(['release', cancelled]); envelope.release(clock.now, cancelled); } };
      tabsController = { changeIndex: target => {
        changeRequests.push(target);
        const accept = () => {
          if (!this.dockNavigation.allowsChange(target)) throw new Error('unauthorized target');
          changes.push(target);
          this.selectedNav = target;
        };
        if (controllerDelay > 0) setTimeout(accept, controllerDelay);
        else accept();
      } };
      ${home.slice(from, to)}
    }
  `;
  const page = new Function('Guard', 'DOCK_HOLD_DELAY_MS', 'deviceInfo', 'TouchType',
    'setTimeout', 'clearTimeout', 'changes', 'lights', 'stoppedLights', 'changeRequests',
    'clock', 'controllerDelay', 'Date', 'DOCK_TAP_LIGHT_ALPHA', 'DOCK_HOLD_LIGHT_RAMP_MS',
    'sampleDockHoldLight', 'DockHoldLightCallback', 'envelope', 'lightTouches', transpile(code) + '; return new Home();')(
    guardModule.exports.DockNavigationGuard, guardModule.exports.DOCK_HOLD_DELAY_MS,
    { apiAvailable: version => api >= Number(version.split('.')[0]) },
    TouchType, setTimer, id => timers.delete(id), changes, lights,
    stoppedLights, changeRequests, clock, controllerDelay, { now: () => clock.now },
    lightModule.exports.DOCK_TAP_LIGHT_ALPHA, lightModule.exports.DOCK_HOLD_LIGHT_RAMP_MS,
    lightModule.exports.sampleDockHoldLight,
    class { constructor(callback) { this.onFrame = callback; } }, envelope, lightTouches);
  if (withBounds) {
    page.updateDockBounds({
      globalPosition: { x: 300, y: 700 }, width: 212, height: 56
    }, api26 ? 0 : 4);
  }
  const touch = (type, x = 35, y = 28, noReleasePoint = false) => {
    const points = noReleasePoint ? [] : [{ x: localPoint?.x ?? x, y: localPoint?.y ?? y,
      windowX: 300 + x, windowY: 700 + y, id: 0 }];
    const e = { type, timestamp: fixedTimestamp ?? ++timestamp, changedTouches: points,
      touches: type === TouchType.Up || type === TouchType.Cancel ? [] : points,
      getHistoricalPoints: () => [] };
    if (type === TouchType.Down) page.dockNavigation.begin(e, false);
    page.observeDockTouch(e, true);
    page.observeDockTouch(e); // parent receives the same bubbled event
  };
  return { page, clock, touch, advance, changes, lights, stoppedLights, changeRequests, timers,
    lightTouches, alpha: () => envelope.sample(clock.now) };
}

test('a tap draws from the selected page and commits only after release dispatch', () => {
  const h = harness();
  h.page.selectedNav = 2;
  h.touch(TouchType.Down, 35);
  h.advance(60);
  assert.equal(h.page.dockHolding, false);
  assert.deepEqual(h.changes, []);
  h.page.requestDockClick(2); // early native callback while the pointer is still pressed
  h.touch(TouchType.Up, 35);
  h.page.requestDockClick(0); // actual clicked item
  assert.deepEqual(h.changes, []);
  h.advance(0);
  assert.deepEqual(h.changes, [0]);
  assert.deepEqual(h.lights, [[2, 0]]);
  h.advance(1000);
  assert.equal(h.page.dockHolding, false, 'the cancelled hold timer cannot brighten the released dock');
});

test('holds keep API 26 light active and release at the final icon on both renderers', () => {
  for (const api of [23, 24, 25, 26]) {
    const h = harness({ api });
    h.touch(TouchType.Down, 35);
    h.advance(179);
    assert.equal(h.page.dockHolding, false);
    h.advance(1);
    assert.equal(h.page.dockHolding, api === 26);
    for (const x of [177, 106, 35, 177]) {
      h.touch(TouchType.Move, x);
      h.advance(200);
      assert.equal(h.page.dockHolding, api === 26, 'only API 26 has held light feedback');
      assert.equal(h.page.dockNavigation.isHolding(), true);
      assert.deepEqual(h.changes, [], 'content must remain at its original page while pressed');
    }
    h.touch(TouchType.Up, 0, 0, true);
    h.page.requestDockClick(0);
    h.advance(16);
    assert.deepEqual(h.changes, [2]);
    assert.deepEqual(h.lights, [], 'held feedback uses its existing touch light, not a second tap flash');
    assert.equal(h.page.dockHolding, false);
    assert.equal(h.timers.size, 0);
  }
});

test('a held stationary icon is released even when the system suppresses click callbacks', () => {
  const h = harness();
  h.touch(TouchType.Down, 106);
  h.advance(300);
  h.touch(TouchType.Up, 106);
  h.advance(0);
  assert.deepEqual(h.changes, [1]);
});

test('a long release still works if the timer was delayed by a busy frame', () => {
  const h = harness();
  h.touch(TouchType.Down, 35);
  h.clock.now = 500; // no timer callback has run yet
  h.touch(TouchType.Up, 177);
  h.advance(0);
  assert.deepEqual(h.changes, [2]);
  assert.equal(h.page.dockHolding, false);
});

test('route hide invalidates deferred clicks and delayed hold brightness', () => {
  for (const released of [true, false]) {
    const h = harness();
    h.touch(TouchType.Down, 177);
    if (released) h.touch(TouchType.Up, 177);
    h.page.resetDockInteraction();
    h.advance(1000);
    assert.deepEqual(h.changes, []);
    assert.equal(h.page.dockHolding, false);
  }
});

test('accessibility switches light the currently selected source icon', () => {
  const h = harness();
  h.page.selectedNav = 2;
  h.page.requestDockClick(1);
  h.advance(0);
  h.page.requestDockClick(0);
  h.advance(0);
  assert.deepEqual(h.changes, [1, 0]);
  assert.deepEqual(h.lights, [[2, 1], [1, 0]]);
});

test('delayed native change validation accepts taps and held releases once', () => {
  for (const held of [false, true]) {
    const h = harness({ controllerDelay: 16 });
    h.touch(TouchType.Down, held ? 35 : 106);
    h.advance(held ? 220 : 60);
    if (held) h.touch(TouchType.Move, 177);
    h.touch(TouchType.Up, held ? 177 : 106);
    h.page.requestDockClick(held ? 0 : 1);
    h.advance(0);
    const target = held ? 2 : 1;
    assert.deepEqual(h.changeRequests, [target]);
    assert.deepEqual(h.changes, [], 'the controller has returned before native validation');
    assert.equal(h.page.dockNavigation.allowsChange((target + 1) % 3), false,
      'an unrelated native transition cannot consume the pending authorization');
    h.advance(16);
    assert.deepEqual(h.changes, [target]);
    assert.equal(h.page.dockNavigation.allowsChange(target), false, 'the grant is consumed once');
    assert.deepEqual(h.lights, held ? [] : [[0, 1]]);
  }
});

test('taps use native item indices even before dock geometry is available', () => {
  for (const target of [0, 1, 2]) {
    const h = harness({ withBounds: false });
    h.page.selectedNav = (target + 1) % 3;
    h.touch(TouchType.Down, 35);
    h.advance(60);
    h.touch(TouchType.Up, 35);
    h.page.requestDockClick(target);
    h.advance(0);
    assert.deepEqual(h.changes, [target]);
    assert.deepEqual(h.lights, [[(target + 1) % 3, target]]);
  }
});

test('long press selection uses layout bounds when child touch coordinates are misleading', () => {
  for (const api of [23, 26]) {
    for (const target of [0, 1, 2]) {
      const h = harness({ api, localPoint: { x: 2, y: 2 } });
      h.touch(TouchType.Down, 106);
      h.advance(220);
      h.touch(TouchType.Move, [35, 106, 177][target]);
      h.touch(TouchType.Up, 0, 0, true);
      h.advance(0);
      assert.deepEqual(h.changes, [target]);
    }
  }
});

test('repeated timestamps do not freeze hold motion or the next gesture', () => {
  const h = harness({ fixedTimestamp: 0 });
  h.touch(TouchType.Down, 35);
  h.advance(220);
  h.touch(TouchType.Move, 106);
  h.touch(TouchType.Move, 177);
  h.touch(TouchType.Up, 0, 0, true);
  h.advance(0);
  assert.deepEqual(h.changes, [2]);
  h.touch(TouchType.Down, 106);
  h.advance(60);
  h.touch(TouchType.Up, 106);
  h.page.requestDockClick(1);
  h.advance(0);
  assert.deepEqual(h.changes, [2, 1]);
  assert.deepEqual(h.lights, [[2, 1]]);
});

test('other APIs never transfer or stop new light effects during taps, holds or lifecycle cleanup', () => {
  for (const api of [23, 24, 25, 27, 28]) {
    const h = harness({ api });
    h.touch(TouchType.Down, 106);
    h.advance(60);
    h.touch(TouchType.Up, 106);
    h.page.requestDockClick(1);
    h.advance(0);
    h.touch(TouchType.Down, 106);
    h.advance(220);
    h.touch(TouchType.Move, 177);
    h.touch(TouchType.Up, 177);
    h.advance(0);
    h.page.resetDockInteraction();
    assert.deepEqual(h.changes, [1, 2]);
    assert.deepEqual(h.lights, []);
    assert.deepEqual(h.stoppedLights, []);
    assert.equal(h.page.dockHolding, false);
  }
});

test('held feedback uses the shared continuous envelope, follows scrubbing, and fades after release', () => {
  for (const hide of [false, true]) {
    const h = harness();
    h.touch(TouchType.Down, 106);
    h.advance(180);
    assert.equal(h.page.dockHolding, true);
    assert.equal(h.alpha(), 0.28, 'the hold threshold does not cause a jump');
    const levels = [];
    for (let i = 0; i < 24; i++) {
      h.advance(16);
      levels.push(h.alpha());
    }
    assert.ok(levels[0] > 0.28 && levels[0] < 0.3);
    assert.equal(levels.at(-1), 1);
    assert.ok(levels.slice(1).every((alpha, index) => alpha >= levels[index]));
    h.touch(TouchType.Move, 177);
    assert.equal(h.alpha(), 1);
    assert.ok(h.lightTouches.some(action => action[0] === 'move' && action[1] === 177));
    if (hide) h.page.resetDockInteraction();
    else h.touch(TouchType.Up, 177);
    h.advance(1000);
    assert.equal(h.alpha(), 0);
    assert.equal(h.page.dockHolding, false);
    assert.equal(h.timers.size, 0);
  }
  const early = harness();
  early.touch(TouchType.Down, 106);
  early.advance(196);
  assert.ok(early.alpha() > 0.28 && early.alpha() < 1);
  early.touch(TouchType.Cancel, 106);
  early.advance(1000);
  assert.equal(early.alpha(), 0, 'a cancelled ramp cannot restore released brightness');
  assert.deepEqual(early.changes, []);
});
