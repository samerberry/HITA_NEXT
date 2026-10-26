const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = name => fs.readFileSync(path.join(root, name), 'utf8');
const compile = source => ts.transpileModule(source.replace(/import lazy /g, 'import '), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText;

function clock() {
  let now = 0, id = 0;
  const tasks = new Map();
  return {
    setTimeout(callback, ms) { tasks.set(++id, { callback, due: now + ms }); return id; },
    clearTimeout(key) { tasks.delete(key); },
    advance(ms) {
      const end = now + ms;
      while (true) {
        const next = [...tasks].filter(([, t]) => t.due <= end).sort((a, b) => a[1].due - b[1].due)[0];
        if (!next) break;
        now = next[1].due; tasks.delete(next[0]); next[1].callback();
      }
      now = end;
    },
    get size() { return tasks.size; }
  };
}

function motionHarness() {
  const timer = clock();
  const mod = { exports: {} };
  new Function('exports', 'module', 'setTimeout', 'clearTimeout',
    compile(read('feature/timetable/views/FloatingActionsMotion.ets')))(mod.exports, mod,
    timer.setTimeout, timer.clearTimeout);
  const renders = [], animations = [];
  const movement = new mod.exports.FloatingActionsMotion(
    frame => renders.push({ ...frame }),
    (frame, stiffness, exiting, generation, finish) => animations.push({ ...frame, stiffness, exiting, generation, finish }));
  const finish = () => {
    assert.ok(animations.length, 'expected a pending native animation');
    const next = animations.shift(); next.finish(); return next;
  };
  return { movement, renders, animations, finish, timer, constants: mod.exports };
}

test('both controls first render outside the same edge and enter on the specified spring', () => {
  const h = motionHarness();
  h.movement.update(true, true, true, false);
  assert.equal(h.renders.at(-1).eveningMounted, true);
  assert.equal(h.renders.at(-1).returnMounted, true);
  assert.equal(h.renders.at(-1).eveningX, 84);
  assert.equal(h.renders.at(-1).returnX, 84);
  assert.equal(h.animations[0].eveningX, 0);
  assert.equal(h.animations[0].returnX, 0);
  assert.equal(h.animations[0].returnLift, 60);
  assert.equal(h.animations[0].stiffness, 170);
  h.finish();
  assert.equal(h.animations.length, 0);
});

test('departure keeps content mounted and lowers the return control in the same animation', () => {
  const h = motionHarness();
  h.movement.update(true, true, true, false); h.finish();
  h.movement.update(true, false, true, false);
  assert.equal(h.animations[0].eveningMounted, true);
  assert.equal(h.animations[0].eveningX, 84);
  assert.equal(h.animations[0].returnLift, 0);
  assert.equal(h.animations[0].exiting, true);
  h.finish();
  assert.equal(h.renders.at(-1).eveningMounted, false);
  assert.equal(h.animations.length, 0);
  h.movement.update(true, false, false, false);
  assert.equal(h.animations[0].returnMounted, true);
  h.finish();
  assert.equal(h.renders.at(-1).returnMounted, false);
});

test('evening hint entry starts together with slot movement without waiting for a spring tail', () => {
  const h = motionHarness();
  h.movement.update(true, false, true, false); h.finish();
  h.movement.update(true, true, true, false);
  assert.equal(h.animations[0].returnLift, 60);
  assert.equal(h.renders.at(-1).eveningMounted, true);
  assert.equal(h.renders.at(-1).eveningX, 84);
  assert.equal(h.animations[0].eveningMounted, true);
  assert.equal(h.animations[0].eveningX, 0);
  assert.equal(h.animations[0].returnLift, 60);
  h.finish();
  assert.equal(h.animations.length, 0);
});

test('hand changes take the whole group around the edges without changing height or order', () => {
  const h = motionHarness();
  h.movement.update(true, true, true, false); h.finish();
  h.movement.setSide(true);
  assert.equal(h.animations[0].side, 1);
  assert.equal(h.animations[0].eveningX, 84);
  assert.equal(h.animations[0].returnX, 84);
  assert.equal(h.animations[0].returnLift, 60);
  h.finish();
  assert.equal(h.renders.at(-1).side, -1);
  assert.equal(h.renders.at(-1).eveningX, -84);
  assert.equal(h.renders.at(-1).returnX, -84);
  assert.equal(h.renders.at(-1).returnLift, 60);
  assert.equal(h.animations[0].side, -1);
  assert.equal(h.animations[0].returnLift, 60);
  h.finish();
  h.movement.setSide(false);
  assert.equal(h.animations[0].eveningX, -84);
  h.finish(); h.finish();
  assert.equal(h.renders.at(-1).side, 1);
});

test('single-button mirroring preserves its lower slot', () => {
  for (const evening of [false, true]) {
    const h = motionHarness();
    h.movement.update(true, evening, !evening, false); h.finish();
    h.movement.setSide(true);
    assert.equal(h.animations[0].returnLift, evening ? 60 : 0);
    h.finish();
    assert.equal(h.animations[0].returnLift, evening ? 60 : 0);
    h.finish();
  }
});

test('pressing either target defers relocation until release and click handling complete', () => {
  const h = motionHarness();
  h.movement.update(true, true, true, false); h.finish();
  h.movement.setPressed(1, true); h.movement.setPressed(2, true);
  h.movement.setSide(true);
  h.movement.setPressed(1, false);
  assert.equal(h.animations.length, 0);
  h.movement.setPressed(2, false);
  h.timer.advance(15); assert.equal(h.animations.length, 0);
  // The click starts week navigation before the delay elapses.
  h.movement.update(true, true, true, true);
  h.timer.advance(1); assert.equal(h.animations.length, 0);
  h.movement.update(true, true, true, false);
  assert.equal(h.animations[0].eveningX, 84);
});

test('repeated visibility and side changes reconcile the latest intent without stale deletion', () => {
  const h = motionHarness();
  h.movement.update(true, true, true, false);
  const initial = h.animations.at(-1);
  h.movement.update(true, false, false, false);
  const departing = h.animations.at(-1);
  h.movement.update(true, true, false, false);
  assert.equal(h.animations.at(-1).eveningX, 0);
  assert.equal(h.animations.at(-1).returnX, 84);
  assert.equal(h.movement.isCurrent(initial.generation), false);
  assert.equal(h.movement.isCurrent(departing.generation), false);
  h.movement.setSide(true); h.movement.setSide(false); h.movement.setSide(true);
  // Even callbacks delivered out of order cannot remove a newly shown control.
  while (h.animations.length) h.finish();
  assert.equal(h.renders.at(-1).side, -1);
  assert.equal(h.renders.at(-1).eveningMounted, true);
  assert.equal(h.renders.at(-1).returnMounted, false);
  assert.equal(h.animations.length, 0);
});

test('hide and re-show immediately retargets departure before its completion', () => {
  const h = motionHarness();
  h.movement.update(true, false, true, false); h.finish();
  h.movement.update(true, false, false, false);
  const departure = h.animations[0];
  h.movement.update(true, false, true, false);
  assert.equal(h.animations.length, 2);
  assert.equal(h.movement.isCurrent(departure.generation), false);
  h.finish();
  assert.equal(h.animations[0].returnX, 0);
  assert.equal(h.animations[0].returnMounted, true);
  h.finish();
});

test('an entry can immediately reverse on a downward scroll and back on an upward scroll', () => {
  const h = motionHarness();
  h.movement.update(true, false, true, false); h.finish();
  h.movement.update(true, true, true, false);
  const entry = h.animations.shift();
  h.movement.update(true, false, true, false);
  const exit = h.animations.shift();
  assert.equal(exit.eveningX, 84);
  assert.equal(exit.returnLift, 0);
  assert.equal(exit.exiting, true);
  h.movement.update(true, true, true, false);
  const reentry = h.animations[0];
  assert.equal(reentry.eveningX, 0);
  assert.equal(reentry.returnLift, 60);
  const count = h.renders.length;
  exit.finish(); entry.finish();
  assert.equal(h.renders.length, count);
  assert.equal(h.movement.isCurrent(reentry.generation), true);
  h.finish();
});

test('handoff begins opposite entry directly from bounded exit completion with no idle timer', () => {
  const h = motionHarness();
  h.movement.update(true, true, true, false); h.finish();
  h.movement.setSide(true);
  const departure = h.animations[0];
  assert.equal(departure.exiting, true);
  h.timer.advance(500); // Elapsed JS time alone never jumps an unfinished native animation.
  assert.equal(h.renders.at(-1).side, 1);
  assert.equal(h.animations.length, 1);
  h.finish();
  assert.equal(h.animations.length, 1);
  assert.equal(h.animations[0].side, -1);
  assert.equal(h.animations[0].eveningX, 0);
  assert.equal(h.animations[0].exiting, false);
  assert.equal(h.timer.size, 0);
});

test('hand changes during an ordinary departure reuse that exit and honor the latest visibility', () => {
  const h = motionHarness();
  h.movement.update(true, true, false, false); h.finish();
  h.movement.update(true, false, false, false);
  const departure = h.animations[0];
  h.movement.setSide(true);
  h.movement.update(true, true, false, false);
  assert.equal(h.animations.length, 1);
  assert.equal(h.movement.isCurrent(departure.generation), true);
  assert.equal(h.renders.at(-1).side, 1);
  h.finish();
  assert.equal(h.animations[0].side, -1);
  assert.equal(h.animations[0].eveningMounted, true);
  assert.equal(h.animations[0].eveningX, 0);
});

test('duplicate updates do not keep restarting motion or delay its completion', () => {
  const h = motionHarness();
  h.movement.update(true, true, true, false); h.finish();
  h.movement.update(true, false, true, false);
  for (let i = 0; i < 10; i++) h.movement.update(true, false, true, false);
  assert.equal(h.animations.length, 1);
  h.finish();
  assert.equal(h.renders.at(-1).eveningMounted, false);
  assert.equal(h.animations.length, 0);
});

test('bounded exit is monotonic, ends offscreen in 180ms, and simultaneous slot motion avoids overlap', () => {
  const { constants: c } = motionHarness();
  assert.equal(c.FLOATING_ACTION_EXIT_DURATION, 180);
  assert.equal(c.floatingActionExitProgress(0), 0);
  assert.equal(c.floatingActionExitProgress(1), 1);
  assert.ok(c.FLOATING_ACTION_EXIT >= 18 + 48 + 16);
  let previous = 0;
  for (let i = 0; i <= 180; i++) {
    const p = c.floatingActionExitProgress(i / 180);
    assert.ok(p >= previous && p <= 1);
    previous = p;
    // Center separation on both diagonal paths stays greater than the 48vp diameter.
    assert.ok(Math.hypot(c.FLOATING_ACTION_EXIT * p, c.FLOATING_ACTION_GAP * (1 - p)) > 48);
    assert.ok(Math.hypot(c.FLOATING_ACTION_EXIT * (1 - p), c.FLOATING_ACTION_GAP * p) > 48);
  }
});

test('leaving and reopening invalidates old frame and finish callbacks and pending releases', () => {
  const h = motionHarness();
  h.movement.update(true, true, false, false);
  const stale = h.animations.shift();
  h.movement.setPressed(1, true); h.movement.setPressed(1, false);
  h.movement.update(false, true, false, false);
  assert.equal(h.timer.size, 0);
  assert.equal(h.movement.isCurrent(stale.generation), false);
  assert.equal(h.renders.at(-1).eveningMounted, false);
  h.movement.update(true, false, true, false);
  stale.finish();
  assert.equal(h.animations.length, 1);
  assert.equal(h.animations[0].eveningMounted, false);
  assert.equal(h.animations[0].returnMounted, true);
  h.finish();
});

function observerHarness(options = {}) {
  const timer = clock(), sides = [], subscriptions = [], removals = [];
  const motion = {
    HoldingHandStatus: { LEFT_HAND_HELD: 1, RIGHT_HAND_HELD: 2 },
    on(type, callback) {
      if (options.error) throw { code: options.error };
      subscriptions.push({ type, callback });
    },
    off(type, callback) { removals.push({ type, callback }); if (options.offError) throw { code: 31500003 }; }
  };
  const mod = { exports: {} };
  new Function('require', 'module', 'exports', 'setTimeout', 'clearTimeout', 'canIUse', 'console',
    compile(read('feature/timetable/data/HoldingHandObserver.ets')))(name => {
    if (name === '@kit.BasicServicesKit') return { deviceInfo: { sdkApiVersion: options.api ?? 23 } };
    if (name === '@kit.MultimodalAwarenessKit') return { motion };
    throw new Error(name);
  }, mod, mod.exports, timer.setTimeout, timer.clearTimeout, () => options.supported !== false, { warn() {} });
  const observer = new mod.exports.HoldingHandObserver();
  const start = () => observer.start(left => sides.push(left));
  return { observer, start, sides, subscriptions, removals, timer };
}

test('unsupported API, missing capability, unsupported models and service errors keep the right fallback', () => {
  for (const options of [{ api: 19 }, { supported: false }, { error: 801 }, { error: 201 }, { error: 31500001 }]) {
    const h = observerHarness(options); h.start(); h.start();
    assert.deepEqual(h.sides, [false]);
    assert.equal(h.subscriptions.length, 0);
    h.observer.stop(); assert.equal(h.removals.length, 0);
  }
});

test('supported API 23+ devices subscribe exactly once and debounce unstable grips', () => {
  for (const api of [23, 24, 25, 26, 27]) {
    const h = observerHarness({ api }); h.start(); h.start();
    assert.equal(h.subscriptions.length, 1);
    assert.equal(h.subscriptions[0].type, 'holdingHandChanged');
    const notify = h.subscriptions[0].callback;
    notify(1); h.timer.advance(40); notify(2);
    h.timer.advance(79); assert.deepEqual(h.sides, []);
    h.timer.advance(1); assert.deepEqual(h.sides, [false]);
    notify(1); h.timer.advance(80); assert.deepEqual(h.sides, [false, true]);
    for (const unknown of [0, 3, 16, 99]) { notify(unknown); h.timer.advance(200); }
    assert.deepEqual(h.sides, [false, true]);
  }
});

test('the dock variant reports subscription and centres itself instead of falling back right', () => {
  for (const options of [{ api: 19 }, { supported: false }, { error: 801 }, { error: 201 }]) {
    const h = observerHarness(options);
    let unavailable = 0;
    assert.equal(h.observer.start(left => h.sides.push(left), () => unavailable++), false);
    assert.equal(unavailable, 1);
    assert.deepEqual(h.sides, []);
  }
  const h = observerHarness({ api: 26 });
  assert.equal(h.observer.start(left => h.sides.push(left), () => assert.fail('available')), true);
  assert.equal(h.observer.start(() => {}), true, 'a repeated start reports the live subscription');
  h.observer.stop();
});

test('unknown grip cancels a pending relocation and teardown removes only its own callback', () => {
  const h = observerHarness({ offError: true }); h.start();
  const notify = h.subscriptions[0].callback;
  notify(1); h.timer.advance(40); notify(16); h.timer.advance(80);
  assert.deepEqual(h.sides, []);
  notify(1); h.observer.stop();
  assert.equal(h.timer.size, 0);
  assert.equal(h.removals[0].callback, notify);
  h.start(); notify(2); h.timer.advance(200);
  assert.deepEqual(h.sides, []);
  h.subscriptions[1].callback(1); h.timer.advance(180);
  assert.deepEqual(h.sides, [true]);
});

test('UI wiring retains hidden controls, bounds both hit targets, and observes only visible page actions', () => {
  const ui = read('feature/timetable/views/TimetableFloatingActions.ets');
  const home = read('pages/Home.ets');
  assert.ok(ui.includes('interpolatingSpring(0, 1, stiffness, 17)'));
  assert.ok(ui.includes('duration: FLOATING_ACTION_EXIT_DURATION'));
  assert.ok(ui.includes('curves.customCurve(floatingActionExitProgress)'));
  assert.match(ui, /onFinish: finish/);
  assert.match(ui, /postFrameCallback/);
  assert.ok(ui.includes('height(48 + FLOATING_ACTION_GAP)'));
  assert.ok(ui.includes('left: this.edgeMargin + this.leftInset, bottom: this.bottomInset + 20'));
  assert.ok(ui.includes('right: this.edgeMargin + this.rightInset, bottom: this.bottomInset + 20'));
  assert.ok(ui.includes('this.active && (this.eveningVisible || this.returnVisible)'));
  assert.ok(ui.includes('eveningMounted ? Visibility.Visible : Visibility.Hidden'));
  assert.ok(ui.includes('returnMounted ? Visibility.Visible : Visibility.Hidden'));
  assert.match(home, /active: this.pageVisible && this.currentTab === TAB_TIMETABLE/);
  assert.ok(home.includes('interactionBlocked: this.tabTransitionRunning || this.timetableAnimating || this.activeSheetVisible'));
  assert.ok(home.includes('.onDidScroll(() => {'));
  assert.ok(home.includes('this.updateEveningCourseHint();'));
  const manifest = fs.readFileSync(path.join(root, '../module.json5'), 'utf8');
  assert.match(manifest, /ohos.permission.DETECT_GESTURE/);
  assert.doesNotMatch(manifest, /ohos.permission.ACTIVITY_MOTION/);
});
