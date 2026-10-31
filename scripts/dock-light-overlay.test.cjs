const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = relative => fs.readFileSync(path.join(root, relative), 'utf8');
const compile = source => ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText;

function harness() {
  const clock = { now: 1000 };
  const modules = new Map();
  const load = relative => {
    if (modules.has(relative)) return modules.get(relative);
    const mod = { exports: {} };
    new Function('require', 'module', 'exports', compile(read(relative)))(
      name => load(path.posix.normalize(path.posix.join(path.posix.dirname(relative), name + '.ets'))),
      mod, mod.exports);
    modules.set(relative, mod.exports);
    return mod.exports;
  };
  const light = load('common/util/DockLightEffect.ets');
  const envelope = load('common/util/ImmersiveLightEffect.ets');
  const frames = [];
  const draws = [];
  const clippedArcs = [];
  let clearCount = 0;
  class CanvasContext {
    clearRect() { clearCount++; }
    save() {} restore() {} beginPath() {} moveTo() {} lineTo() {}
    arc(x, y, radius) { clippedArcs.push({ x, y, radius }); }
    closePath() {} clip() {}
    createRadialGradient(x, y, _inner, _x, _y, radius) {
      return { x, y, radius, stops: [], addColorStop(position, color) { this.stops.push([position, color]); } };
    }
    fillRect() { draws.push({ time: clock.now, ...this.fillStyle }); }
  }
  const source = read('common/components/DockLightOverlay.ets').replace('@Component', '')
    .replace('export struct', 'export class');
  const mod = { exports: {} };
  new Function('require', 'module', 'exports', 'CanvasRenderingContext2D',
    'RenderingContextSettings', 'Date', compile(source))(
    name => {
      if (name === '@kit.ArkUI') return { FrameCallback: class {} };
      if (name.includes('DockHandedness')) return load('common/util/DockHandedness.ets');
      return name.includes('DockLightEffect') ? light : envelope;
    }, mod, mod.exports, CanvasContext, class {}, { now: () => clock.now });
  const controller = new light.DockLightController();
  const overlay = new mod.exports.DockLightOverlay();
  overlay.controller = controller;
  overlay.ready = true;
  overlay.getUIContext = () => ({ postFrameCallback: frame => frames.push(frame) });
  overlay.aboutToAppear();
  const advance = elapsed => {
    for (let elapsedMs = 0; elapsedMs < elapsed; elapsedMs += 10) {
      clock.now += Math.min(10, elapsed - elapsedMs);
      const pending = frames.splice(0);
      for (const frame of pending) frame.onFrame(clock.now * 1000000);
    }
  };
  const alpha = draw => Number(draw.stops[0][1].match(/,([\d.]+)\)$/)[1]);
  return { controller, overlay, advance, draws, frames, alpha, envelope, clippedArcs,
    clearCount: () => clearCount };
}

test('the actual Dock painter uses the same white tap peak for a stationary tap and flowing page change', () => {
  for (const transfer of [false, true]) {
    const h = harness();
    h.controller.press(0);
    h.advance(60);
    h.controller.release(false);
    if (transfer) h.controller.transfer(0, 2);
    h.advance(540);
    assert.equal(Math.max(...h.draws.map(h.alpha)), h.envelope.IMMERSIVE_TAP_ALPHA);
    assert.ok(h.draws.every(draw => draw.stops[0][1].startsWith('rgba(255,255,255,')));
    if (transfer) {
      const moving = h.draws.filter(draw => draw.time >= 1060);
      assert.ok(moving.some(draw => draw.x > 50 && draw.x < 175));
      assert.equal(moving.at(-1).x, 172);
      assert.ok(moving.every((draw, index) => index === 0 || draw.x >= moving[index - 1].x));
    }
    assert.equal(h.alpha(h.draws.at(-1)), 0);
    assert.equal(h.frames.length, 0, 'release leaves no live frame loop');
  }
});

test('assistant feedback is clipped to its independent circle and cannot glow over More', () => {
  const h = harness();
  h.controller.press(3);
  h.controller.move(252);
  h.advance(30);
  assert.ok(h.clippedArcs.length > 0);
  assert.ok(h.clippedArcs.every(arc => arc.x - arc.radius >= 224 && arc.x + arc.radius <= 280));
});

test('held Dock light grows to full intensity, tracks the finger, fades smoothly and cannot revive after removal', () => {
  const h = harness();
  h.controller.press(1);
  h.advance(180);
  assert.equal(h.alpha(h.draws.at(-1)), h.envelope.IMMERSIVE_TAP_ALPHA);
  h.controller.move(177);
  h.advance(360);
  assert.equal(h.alpha(h.draws.at(-1)), 1);
  assert.equal(h.draws.at(-1).x, 177);
  h.controller.release(false);
  h.advance(180);
  assert.ok(h.alpha(h.draws.at(-1)) > 0 && h.alpha(h.draws.at(-1)) < 1);
  h.advance(180);
  assert.equal(h.alpha(h.draws.at(-1)), 0);
  h.controller.press(2);
  h.advance(220);
  const count = h.draws.length;
  const cleared = h.clearCount();
  h.overlay.aboutToDisappear();
  h.controller.transfer(2, 0);
  h.advance(1000);
  assert.equal(h.draws.length, count);
  assert.ok(h.clearCount() > cleared);
  assert.equal(h.frames.length, 0);
});

test('a rapid second page change bends the flowing light toward the new tab without teleporting', () => {
  const h = harness();
  h.controller.press(0);
  h.advance(30);
  h.controller.release(false);
  h.controller.transfer(0, 2);
  h.advance(60);
  const turning = h.draws.at(-1).x;
  assert.ok(turning > 44 + 5, 'light has left the first tab');
  // Second tap lands on the middle tab while the light is still travelling right.
  h.controller.press(2);
  h.controller.release(false);
  h.controller.transfer(2, 0);
  const after = h.draws.length;
  h.advance(600);
  const path = h.draws.slice(after).map(draw => draw.x);
  let maxJump = Math.abs(path[0] - turning);
  for (let i = 1; i < path.length; i++) maxJump = Math.max(maxJump, Math.abs(path[i] - path[i - 1]));
  assert.ok(maxJump < 30, 'no teleport: largest per-frame step ' + maxJump);
  assert.ok(Math.abs(path[0] - turning) < 30, 'continues from where the light was');
  assert.ok(Math.abs(path.at(-1) - 44) < 1, 'settles on the final tab');
  assert.equal(h.frames.length, 0);
});
