const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const source = fs.readFileSync(path.join(root, 'common/util/DockNavigationGuard.ets'), 'utf8');
const output = ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText;
const TouchType = { Down: 0, Up: 1, Move: 2, Cancel: 3 };
const mod = { exports: {} };
let nowMs = 0;
new Function('module', 'exports', 'TouchType', 'Date', output)(
  mod, mod.exports, TouchType, { now: () => nowMs });
const Guard = mod.exports.DockNavigationGuard;
const point = (x = 100, y = 700, id = 0) => ({ windowX: x, windowY: y, id });
let timestamp = 0;
function event(type, points = [point()], history = []) {
  return { type, timestamp: ++timestamp, changedTouches: points,
    touches: type === TouchType.Up ? [] : points,
    getHistoricalPoints: () => history.map(touchObject => ({ touchObject })) };
}
function down(guard) {
  nowMs = 0;
  const e = event(TouchType.Down);
  guard.begin(e, false); // parent hit test
  guard.begin(e, true); // native bar hit test
  guard.observe(e);
}
function click(guard, index = 1) {
  const ticket = guard.requestClick();
  assert.equal(guard.allowsChange(index), false, 'native automatic change must be vetoed');
  const changes = [];
  guard.commitClick(ticket, index, i => {
    assert.equal(guard.allowsChange(i), true, 'only the validated controller call is authorized');
    assert.equal(guard.allowsChange((i + 1) % 3), false);
    changes.push(i);
  });
  assert.equal(guard.allowsChange(index), false, 'authorization must not leak to later native changes');
  return changes;
}

test('Dock changes only after a released, validated icon click, exactly once', () => {
  const guard = new Guard();
  down(guard);
  assert.deepEqual(click(guard), [], 'holding is not a click');
  guard.observe(event(TouchType.Up));
  assert.equal(guard.allowsChange(1), false, 'Up by itself is not a click');
  assert.deepEqual(click(guard), [1]);
  assert.deepEqual(click(guard), [], 'duplicate native callbacks cannot change twice');
  down(guard);
  guard.observe(event(TouchType.Move, [point(103, 702)]));
  guard.observe(event(TouchType.Up, [point(103, 702)]));
  assert.deepEqual(click(guard, 2), [2], 'ordinary stationary tap jitter remains usable');
});

for (const [name, points] of [
  ['short left', [point(85)]], ['short right', [point(115)]],
  ['long left', [point(-500)]], ['long right', [point(800)]],
  ['leave Dock vertically', [point(100, 200)]],
  ['diagonal', [point(400, 300)]],
  ['out and back', [point(500), point()]],
  ['reverse repeatedly', [point(500), point(-500), point(500), point()]]
]) {
  test('a short drag never changes a page: ' + name, () => {
    const guard = new Guard();
    down(guard);
    for (const p of points) {
      guard.observe(event(TouchType.Move, [p]));
      for (const index of [0, 1, 2]) assert.equal(guard.allowsChange(index), false);
      assert.deepEqual(click(guard), [], 'even a synthesized click while dragging must fail');
    }
    guard.observe(event(TouchType.Up, [points.at(-1)]));
    for (const index of [0, 1, 2]) assert.deepEqual(click(guard, index), []);
  });
}

test('coalesced out-and-back movement and a fling whose only displacement is in Up are rejected', () => {
  for (const release of [event(TouchType.Up, [point()], [point(500)]),
    event(TouchType.Up, [point(500)])]) {
    const guard = new Guard();
    down(guard);
    guard.observe(release);
    assert.deepEqual(click(guard), []);
  }
});

test('cancel and multiple fingers never turn into a Dock click', () => {
  for (const invalid of [event(TouchType.Cancel),
    event(TouchType.Down, [point(), point(150, 700, 1)])]) {
    const guard = new Guard();
    down(guard);
    guard.begin(invalid, true);
    guard.observe(invalid);
    guard.observe(event(TouchType.Up));
    assert.deepEqual(click(guard), []);
  }
});

test('click-before-Up callback ordering works after dispatch but movement invalidates it', () => {
  for (const moved of [false, true]) {
    const guard = new Guard();
    down(guard);
    const ticket = guard.requestClick();
    assert.equal(guard.allowsChange(1), false);
    guard.observe(event(TouchType.Up, [moved ? point(500) : point()]));
    const changes = [];
    guard.commitClick(ticket, 1, i => changes.push(i));
    assert.deepEqual(changes, moved ? [] : [1]);
  }
});

test('API 26 duplicate native callbacks select the final clicked item rather than index zero', () => {
  for (const target of [0, 1, 2]) {
    const guard = new Guard();
    down(guard);
    const early = guard.requestClick(); // floating bar callback: index 0
    guard.observe(event(TouchType.Up));
    const actual = guard.requestClick(); // actual item callback
    const changes = [];
    guard.commitClick(early, 0, i => changes.push(i));
    guard.commitClick(actual, target, i => changes.push(i));
    assert.deepEqual(changes, [target]);
  }
});

test('duplicate API 26 callbacks cannot authorize a drag or restore an obsolete click', () => {
  const guard = new Guard();
  down(guard);
  guard.observe(event(TouchType.Move, [point(500)]));
  const early = guard.requestClick();
  guard.observe(event(TouchType.Up, [point()]));
  const actual = guard.requestClick();
  guard.commitClick(early, 0, () => assert.fail('early callback after drag'));
  guard.commitClick(actual, 2, () => assert.fail('actual callback after drag'));
  down(guard);
  guard.observe(event(TouchType.Up));
  assert.deepEqual(click(guard, 1), [1]);
});

test('new content gestures restore page swiping and invalidate any deferred Dock click', () => {
  const guard = new Guard();
  down(guard);
  guard.observe(event(TouchType.Up));
  const ticket = guard.requestClick();
  guard.begin(event(TouchType.Down, [point(100, 100)]), false);
  assert.equal(guard.isDock(), false);
  for (const index of [0, 1, 2]) assert.equal(guard.allowsChange(index), true);
  guard.commitClick(ticket, 1, () => assert.fail('stale click'));
  // A child can stop bubbling Up. A genuinely new Down must still recover.
  down(guard);
  guard.observe(event(TouchType.Up));
  assert.deepEqual(click(guard), [1]);
});

test('content scrolling does not copy native touch history for Dock validation', () => {
  const guard = new Guard();
  guard.begin(event(TouchType.Down), false);
  for (let i = 0; i < 120; i++) {
    const move = event(TouchType.Move, [point(100, 700 - i)]);
    move.getHistoricalPoints = () => assert.fail('content gesture requested Dock history');
    guard.observe(move);
  }
  guard.observe(event(TouchType.Up));
  assert.equal(guard.allowsChange(1), true);
  down(guard);
  guard.observe(event(TouchType.Up));
  assert.deepEqual(click(guard, 2), [2], 'the next Dock click remains usable');
});

test('cancelled Dock gestures skip further history work but still process release', () => {
  const guard = new Guard();
  down(guard);
  guard.observe(event(TouchType.Move, [point(500)]));
  guard.observe(event(TouchType.Down, [point(), point(150, 700, 1)]));
  for (const type of [TouchType.Move, TouchType.Up]) {
    const next = event(type);
    next.getHistoricalPoints = () => assert.fail('cancelled drag requested history');
    guard.observe(next);
  }
  assert.deepEqual(click(guard), []);
  down(guard);
  guard.observe(event(TouchType.Up));
  assert.deepEqual(click(guard), [1]);
});

test('Home wires both renderers through the release target and deferred change guard', () => {
  const home = fs.readFileSync(path.join(root, 'pages/Home.ets'), 'utf8');
  assert.match(home, /onContentWillChange[\s\S]*?return this\.dockNavigation\.allowsChange\(comingIndex\)/);
  assert.match(home, /onTabBarClick[\s\S]*?this\.requestDockClick\(index\)/);
  assert.match(home, /onSelect:[\s\S]*?this\.requestDockClick\(index\)/);
  assert.match(home, /onDockTouch:[\s\S]*?this\.observeDockTouch\(event, true\)/);
  assert.match(home, /releaseTarget\(\)[\s\S]*?this\.requestDockClick\(target\)/);
  assert.match(home, /setTimeout\(\(\) => \{\s*this\.dockNavigation\.commitClick/);
  // dock 提交路径一次；提醒通知深链打开课表再切换一次。
  const switches = home.match(/tabsController\.changeIndex/g) || [];
  assert.equal(switches.length, 2);
  assert.match(home, /setTimeout\(\(\) => \{\s*this\.dockNavigation\.commitClick[\s\S]*?this\.tabsController\.changeIndex\(target\)/);
  assert.match(home, /resetDockInteraction\(\);\s*\n\s*this\.tabsController\.changeIndex\(TAB_TIMETABLE\)/);
});

function boundedGuard() {
  const guard = new Guard();
  guard.setBounds(0, 672, 212, 56);
  down(guard);
  return guard;
}

test('a stationary hold releases onto its current icon without requiring a native click', () => {
  const guard = boundedGuard();
  assert.equal(guard.activateHold(179), false);
  assert.equal(guard.activateHold(180), true);
  assert.equal(guard.releaseTarget(), -1, 'held content must stay fixed');
  guard.observe(event(TouchType.Up));
  assert.equal(guard.releaseTarget(), 1);
  assert.deepEqual(click(guard, 0), [1], 'native index zero cannot override pointer geometry');
  assert.deepEqual(click(guard, 2), [], 'one release commits exactly once');
});

for (const [name, points, target] of [
  ['right', [point(177)], 2],
  ['left', [point(35)], 0],
  ['out and back', [point(177), point(35), point(106)], 1],
  ['outside and back', [point(500), point(177)], 2],
  ['vertical exit and re-entry', [point(106, 300), point(35)], 0]
]) {
  test('long press scrubbing uses the last icon on release: ' + name, () => {
    const guard = boundedGuard();
    nowMs = 220;
    assert.equal(guard.activateHold(), true);
    for (const p of points) {
      guard.observe(event(TouchType.Move, [p]));
      for (const index of [0, 1, 2]) assert.equal(guard.allowsChange(index), false);
      assert.deepEqual(click(guard), [], 'movement never navigates while pressed');
    }
    guard.observe(event(TouchType.Up, [points.at(-1)]));
    assert.equal(guard.releaseTarget(), target);
    assert.deepEqual(click(guard, 0), [target]);
  });
}

test('an Up without touch coordinates preserves the final held Move target', () => {
  const guard = boundedGuard();
  nowMs = 240;
  guard.observe(event(TouchType.Move, [point(177)]));
  guard.observe(event(TouchType.Up, []));
  assert.deepEqual(click(guard, 1), [2]);
});

test('release displacement and coalesced motion use the final location after a hold', () => {
  const guard = boundedGuard();
  nowMs = 240;
  guard.observe(event(TouchType.Up, [point(35)], [point(177), point(106)]));
  assert.deepEqual(click(guard, 2), [0]);
});

test('holds released outside the dock, cancelled or interrupted by another finger do not switch', () => {
  for (const invalid of [
    () => event(TouchType.Up, [point(300)]),
    () => event(TouchType.Up, [point(106, 500)]),
    () => event(TouchType.Cancel),
    () => event(TouchType.Down, [point(), point(150, 700, 1)])
  ]) {
    const guard = boundedGuard();
    nowMs = 240;
    guard.activateHold();
    guard.observe(invalid());
    guard.observe(event(TouchType.Up));
    assert.equal(guard.releaseTarget(), -1);
    assert.deepEqual(click(guard), []);
    down(guard);
    guard.observe(event(TouchType.Up));
    assert.deepEqual(click(guard), [1], 'a cancelled hold cannot poison the next tap');
  }
});

test('parent and dock duplicate touch delivery is processed once', () => {
  const guard = boundedGuard();
  const move = event(TouchType.Move, [point(177)]);
  nowMs = 220;
  assert.equal(guard.observe(move), true);
  assert.equal(guard.observe(move), false);
  const up = event(TouchType.Up, []);
  assert.equal(guard.observe(up), true);
  assert.equal(guard.observe(up), false);
  assert.deepEqual(click(guard), [2]);
});

test('native and fallback held geometry use their own window origin and item padding', () => {
  for (const padding of [0, 4]) {
    for (const target of [0, 1, 2]) {
      const guard = new Guard();
      guard.setBounds(300, 1500, 212, 56, padding);
      const x = 300 + padding + (target + 0.5) * (212 - padding * 2) / 3;
      nowMs = 0;
      const e = event(TouchType.Down, [point(x, 1528)]);
      guard.begin(e, true);
      guard.observe(e);
      nowMs = 220;
      guard.activateHold();
      guard.observe(event(TouchType.Up, [point(x, 1528)]));
      assert.deepEqual(click(guard, 0), [target]);
    }
  }
});

test('accessibility clicks without a dock pointer use native indices and remain repeatable', () => {
  const guard = new Guard();
  guard.setBounds(300, 1500, 212, 56);
  for (const target of [2, 1, 0]) {
    assert.deepEqual(click(guard, target), [target]);
  }
  guard.begin(event(TouchType.Down, [point(100, 100)]), false);
  guard.observe(event(TouchType.Up, [point(100, 100)]));
  assert.deepEqual(click(guard, 2), [2], 'previous content touches do not supply a dock coordinate');
});

test('ordinary taps use the native item even when geometry reports another target', () => {
  for (const withBounds of [false, true]) {
    for (const target of [0, 1, 2]) {
      const guard = new Guard();
      if (withBounds) guard.setBounds(0, 672, 212, 56);
      down(guard);
      guard.observe(event(TouchType.Up));
      assert.deepEqual(click(guard, target), [target]);
    }
  }
});

test('controller authorization survives an asynchronous native validation and is consumed once', () => {
  const guard = new Guard();
  down(guard);
  guard.observe(event(TouchType.Up));
  const requests = [];
  guard.commitClick(guard.requestClick(), 2, index => requests.push(index));
  assert.deepEqual(requests, [2]);
  assert.equal(guard.allowsChange(1), false, 'unrelated automatic changes stay vetoed');
  assert.equal(guard.allowsChange(2), true, 'validation after changeIndex returns remains authorized');
  assert.equal(guard.allowsChange(2), false, 'the matching native validation consumes the grant');
  assert.deepEqual(click(guard, 2), [], 'duplicate clicks cannot reauthorize a consumed release');
});

test('a new dock gesture or controller exception revokes an unconsumed authorization', () => {
  for (const throws of [false, true]) {
    const guard = new Guard();
    down(guard);
    guard.observe(event(TouchType.Up));
    const ticket = guard.requestClick();
    if (throws) {
      assert.throws(() => guard.commitClick(ticket, 2, () => { throw new Error('controller failed'); }),
        /controller failed/);
    } else {
      guard.commitClick(ticket, 2, () => {});
      down(guard);
    }
    assert.equal(guard.allowsChange(2), false);
  }
});

test('a zero-size or invalid transient layout does not discard valid held bounds', () => {
  const guard = boundedGuard();
  for (const bounds of [[0, 0, 0, 0], [NaN, 0, 212, 56], [0, Infinity, 212, 56]]) {
    guard.setBounds(...bounds);
  }
  nowMs = 220;
  guard.observe(event(TouchType.Move, [point(177)]));
  guard.observe(event(TouchType.Up, []));
  assert.deepEqual(click(guard), [2]);
});
