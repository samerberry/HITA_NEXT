const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const cache = new Map();
function load(file) {
  const absolute = path.resolve(root, file);
  if (cache.has(absolute)) return cache.get(absolute).exports;
  const mod = { exports: {} };
  cache.set(absolute, mod);
  const output = ts.transpileModule(fs.readFileSync(absolute, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const requireLocal = name => {
    assert.ok(name.startsWith('.'), name);
    return load(path.resolve(path.dirname(absolute), name + '.ets'));
  };
  new Function('require', 'module', 'exports', output)(requireLocal, mod, mod.exports);
  return mod.exports;
}
const { placeMarqueeFrame, PLACE_MARQUEE_PAUSE_MS, PLACE_MARQUEE_SPEED } =
  load('feature/timetable/views/PlaceMarquee.ets');
const { drawTimetableWeek, drawTimetablePlaces, TimetablePlaceLabel, timetableEventSpan,
  timetableBlockColor, argbToCss, TimetableDrawStyle, TimetableCardLayer, drawTimetableCardText,
  drawTimetableCardSnapshot } =
  load('feature/timetable/views/TimetableWeekDraw.ets');
const { TimetableCardPainter } = load('feature/timetable/views/TimetableCardPainter.ets');
const { EasEventItem, EasTimetable } = load('common/model/timetable/TimetableModels.ets');
const { TimetableTheme } = load('common/theme/TimetableTheme.ets');
const { TimetableDisplayOptions } = load('feature/timetable/data/TimetableDisplayOptions.ets');
const { TimetableBackdropPixels } = load('common/theme/TimetableBackdrop.ets');
const close = (actual, expected) => assert.ok(Math.abs(actual - expected) < 0.0001, `${actual} != ${expected}`);

test('fitting classrooms stay still and do not request animation frames', () => {
  for (const [text, width] of [[20, 30], [30, 30], [10, 0]]) {
    const frame = placeMarqueeFrame(9999, text, width);
    assert.equal(frame.offset, 0);
    assert.equal(frame.nextFrameDelayMs, -1);
  }
});

test('overflowing text pauses at its readable beginning, then moves at a time-based speed', () => {
  assert.equal(PLACE_MARQUEE_PAUSE_MS, 1200);
  assert.equal(PLACE_MARQUEE_SPEED, 30);
  assert.equal(placeMarqueeFrame(0, 90, 30).nextFrameDelayMs, 1200);
  assert.equal(placeMarqueeFrame(1199, 90, 30).offset, 0);
  assert.equal(placeMarqueeFrame(1200, 90, 30).nextFrameDelayMs, 0);
  close(placeMarqueeFrame(1950, 90, 30).offset, 22.5);
});

test('a complete loop wraps continuously and pauses for 1.2 seconds again', () => {
  const distance = 90 + 30 / 3;
  const cycle = 1200 + distance / 30 * 1000;
  close(placeMarqueeFrame(cycle - 0.01, 90, 30).offset, distance - 0.0003);
  close(placeMarqueeFrame(cycle, 90, 30).offset, 0);
  close(placeMarqueeFrame(cycle + 600, 90, 30).nextFrameDelayMs, 600);
  close(placeMarqueeFrame(cycle * 20 + 600, 90, 30).offset, 0);
  close(placeMarqueeFrame(cycle + 1500, 90, 30).offset, 9);
});

test('classrooms with different lengths pause independently', () => {
  const shortCycle = 1200 + 100 / 30 * 1000;
  assert.equal(placeMarqueeFrame(shortCycle + 200, 90, 30).offset, 0);
  assert.ok(placeMarqueeFrame(shortCycle + 200, 180, 30).offset > 0);
  assert.equal(placeMarqueeFrame(shortCycle + 200, 180, 30).nextFrameDelayMs, 0);
});

test('60 Hz, 120 Hz and delayed rendering reach the same position at the same time', () => {
  const offsetAfter = times => times.map(t => placeMarqueeFrame(t, 200, 30).offset).at(-1);
  const sixty = Array.from({ length: 121 }, (_, i) => i * 2000 / 120);
  const highRefresh = Array.from({ length: 241 }, (_, i) => i * 2000 / 240);
  close(offsetAfter(sixty), offsetAfter(highRefresh));
  close(offsetAfter([0, 800, 1400, 2000]), offsetAfter(sixty));
  close(offsetAfter(sixty), 24);
});

function canvas() {
  const ctx = { calls: [], font: '', textBaseline: 'alphabetic' };
  for (const method of ['clearRect', 'fillRect', 'fillText', 'beginPath', 'moveTo', 'lineTo',
    'quadraticCurveTo', 'closePath', 'fill', 'stroke', 'setLineDash', 'save', 'restore', 'rect', 'clip']) {
    ctx[method] = (...args) => ctx.calls.push([method, ...args]);
  }
  ctx.paints = [];
  for (const method of ['fill', 'stroke', 'fillText', 'fillRect']) {
    const record = ctx[method];
    ctx[method] = (...args) => {
      ctx.paints.push({ method, color: method === 'stroke' ? ctx.strokeStyle : ctx.fillStyle, args });
      record(...args);
    };
  }
  ctx.measureText = text => {
    ctx.calls.push(['measureText', text]);
    return { width: text.length * 7 };
  };
  return ctx;
}

function fixture() {
  const timetable = new EasTimetable();
  timetable.startTime = new Date(2026, 8, 28).getTime();
  const first = new EasEventItem();
  first.name = 'Course A';
  first.place = 'M-building-118';
  first.from = timetable.startTime + 8 * 3600000;
  first.to = first.from + 105 * 60000;
  const second = new EasEventItem();
  second.name = 'Course B';
  second.place = 'A1';
  second.from = timetable.startTime + 24 * 3600000 + 10 * 3600000;
  second.to = second.from + 105 * 60000;
  return { timetable, events: [first, second] };
}

function luminance(argb) {
  const linear = shift => {
    const value = ((argb >>> shift) & 255) / 255;
    return value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
  };
  return 0.2126 * linear(16) + 0.7152 * linear(8) + 0.0722 * linear(0);
}

test('the grid switch hides time lines and day dividers without changing labels or courses', () => {
  const { timetable, events } = fixture();
  const visible = canvas(), hidden = canvas();
  const before = new TimetableCardLayer(), after = new TimetableCardLayer();
  const options = new TimetableDisplayOptions();
  options.drawTimeLines = false;
  drawTimetableWeek(visible, 380, 830, timetable, events, 1, false, 50, 0, false, false, '', false, before);
  drawTimetableWeek(hidden, 380, 830, timetable, events, 1, false, 50, 0, false, false, '', false, after, options);
  assert.deepEqual(after, before);
  assert.deepEqual(hidden.paints.filter(p => p.method === 'fillText'), visible.paints.filter(p => p.method === 'fillText'));
  assert.equal(hidden.paints.filter(p => p.method === 'stroke').length, 0, 'no background dividers remain');
  assert.equal(visible.paints.filter(p => p.method === 'stroke').length, 37);
  assert.equal(hidden.calls.some(c => c[0] === 'setLineDash' && c[1].length > 0), false);
});

test('custom time-line color applies in both themes while course colors and date labels are retained', () => {
  const { timetable, events } = fixture();
  const options = new TimetableDisplayOptions();
  options.timeLineColor = '#E53935';
  for (const dark of [false, true]) {
    const ctx = canvas();
    drawTimetableWeek(ctx, 380, 830, timetable, events, 1, false, 50, 0, false, false, '#135ABC', dark, undefined, options);
    const strokes = ctx.paints.filter(p => p.method === 'stroke');
    assert.equal(strokes.filter(p => p.color === (dark ? 'rgba(229,57,53,0.22)' : '#E53935')).length, 16);
    assert.equal(strokes.filter(p => p.color === (dark ? 'rgba(229,57,53,0.09)' : 'rgba(229,57,53,0.35)')).length, 21);
    assert.equal(ctx.paints.find(p => p.method === 'fillText' && p.args[0] === '8:00').color, '#135ABC');
  }
});

test('wallpaper grid uses translucent colors, retains today highlight when disabled and never changes card paint', () => {
  const { timetable, events } = fixture();
  const background = new TimetableBackdropPixels(1, 1, 4, new Uint8Array([0, 0, 0, 255]), false)
    .colors(false, 0, 380, 830, 200, 64, 3);
  const options = new TimetableDisplayOptions();
  const before = new TimetableCardLayer(), after = new TimetableCardLayer();
  const visible = canvas();
  drawTimetableWeek(visible, 380, 830, timetable, events, 1, true, 50, 0, false, false,
    '#FFFFFF', false, before, options, background, true);
  assert.equal(visible.paints.filter(p => p.method === 'stroke' && p.color === background.line).length, 16);
  assert.equal(visible.paints.filter(p => p.method === 'stroke' && p.color === background.minorLine).length, 21);
  options.drawTimeLines = false;
  const hidden = canvas();
  drawTimetableWeek(hidden, 380, 830, timetable, events, 1, true, 50, 0, false, false,
    '#FFFFFF', false, after, options, background, true);
  assert.deepEqual(before, after);
  assert.equal(hidden.paints.filter(p => p.method === 'stroke').length, 0);
  assert.ok(hidden.paints.some(p => p.method === 'fillRect' && p.color === background.todayMask));
  options.drawTimeLines = true; options.timeLineColor = '#FFFFFF';
  const custom = canvas();
  drawTimetableWeek(custom, 380, 830, timetable, events, 1, true, 50, 0, false, false,
    '#FFFFFF', false, new TimetableCardLayer(), options, background, true);
  assert.ok(custom.paints.filter(p => p.method === 'stroke')
    .every(p => ['rgba(255,255,255,0.22)', 'rgba(255,255,255,0.09)'].includes(p.color)));
});

test('dark timetable changes the canvas surface and labels without moving or recoloring courses', () => {
  const { timetable, events } = fixture();
  const light = canvas(), dark = canvas();
  drawTimetableWeek(light, 380, 830, timetable, events, 1, false, 50, 64, true, true, '', false);
  drawTimetableWeek(dark, 380, 830, timetable, events, 1, false, 50, 64, true, true, '', true);
  assert.deepEqual(dark.calls, light.calls);
  assert.equal(dark.paints.find(p => p.method === 'fillRect').color, '#101214');
  assert.equal(dark.paints.find(p => p.method === 'fillText' && p.args[0] === '8:00').color, '#BCC3CF');
  assert.equal(dark.paints.find(p => p.method === 'stroke').color, '#3A414B');
  assert.deepEqual(dark.paints.filter(p => p.method === 'fill'), light.paints.filter(p => p.method === 'fill'));
  const headerText = dark.paints.filter(p => p.method === 'fillText').slice(0, 15);
  assert.ok(headerText.every(p => ['#ECEFF4', '#BCC3CF'].includes(p.color)));
});

test('dark timetable does not paint a solid background over a wallpaper or overwrite custom labels', () => {
  const { timetable, events } = fixture();
  const ctx = canvas();
  drawTimetableWeek(ctx, 380, 830, timetable, events, 1, false, 50, 64, true, false, '#FFFFFF', true);
  assert.equal(ctx.paints.filter(p => p.method === 'fillRect').length, 0);
  assert.ok(ctx.paints.filter(p => p.method === 'fillText').every(p => p.color === '#FFFFFF'));
  assert.equal(TimetableTheme.resolveText('auto', true, false), '#ECEFF4');
  assert.equal(TimetableTheme.resolveText('auto', false, false), '#14213D');
  for (const custom of TimetableTheme.PALETTE) {
    assert.equal(TimetableTheme.resolveText(custom, true, true), custom);
    if (custom !== TimetableTheme.DEFAULT_TEXT) {
      assert.equal(TimetableTheme.resolveText(custom, true, false), custom);
    }
  }
});

test('saved pastel colors and custom colors retain readable white text without changing the model palette', () => {
  const models = fs.readFileSync(path.join(root, 'common/model/timetable/TimetableModels.ets'), 'utf8');
  const detail = fs.readFileSync(path.join(root, 'pages/TimetableDetailPage.ets'), 'utf8');
  const colors = [...models.matchAll(/0xFF[0-9A-F]{6}/gi),
    ...detail.matchAll(/0xFF[0-9A-F]{6}/gi)].map(match => Number(match[0]));
  // Include arbitrary custom colors, signed ARGB, zero fallback and channel extremes.
  for (let r = 0; r <= 255; r += 51) {
    for (let g = 0; g <= 255; g += 51) {
      for (let b = 0; b <= 255; b += 51) colors.push(0xFF000000 | r << 16 | g << 8 | b);
    }
  }
  colors.push(0, 0xFFFFFFFF, 0xFF14213D);
  for (const color of colors) {
    const result = timetableBlockColor(color);
    assert.ok(1.05 / (luminance(result) + 0.05) >= 4.5, result.toString(16));
    assert.equal(result >>> 24, 255);
    assert.equal(timetableBlockColor(result), result);
    if (color !== 0 && luminance(color) <= 0.18) assert.equal(result, color >>> 0);
  }
  assert.equal(timetableBlockColor(0), timetableBlockColor(0xFF2E86E8));
});

test('cards are opaque on both default and wallpaper backgrounds and classroom text stays white', () => {
  const { timetable, events } = fixture();
  events[0].color = 0xFFFFB74D;
  events[1].color = 0xFF81C784;
  const originalColors = events.map(event => event.color);
  for (const fillPage of [true, false]) {
    const base = canvas();
    const labels = drawTimetableWeek(base, 380, 830, timetable, events, 1, false, 50, 0, fillPage);
    const fills = base.paints.filter(paint => paint.method === 'fill');
    assert.deepEqual(fills.map(paint => paint.color),
      originalColors.map(color => argbToCss(timetableBlockColor(color), 1)));
    const firstCard = base.paints.findIndex(paint => paint.method === 'fill');
    const cardText = base.paints.slice(firstCard).filter(paint => paint.method === 'fillText');
    assert.ok(cardText.length >= 3);
    assert.ok(cardText.every(paint => paint.color === '#FFFFFF'));
    const overlay = canvas();
    drawTimetablePlaces(overlay, 380, 830, labels, 1600);
    assert.ok(overlay.paints.length > 0);
    assert.ok(overlay.paints.every(paint => paint.color === TimetableDrawStyle.blockText));
    assert.deepEqual(events.map(event => event.color), originalColors);
  }
});

test('static layout draws short classrooms but caches only overflowing labels for animation', () => {
  const { timetable, events } = fixture();
  const base = canvas();
  const labels = drawTimetableWeek(base, 380, 830, timetable, events, 1, false, 50, 0, false);
  assert.equal(labels.length, 1);
  assert.equal(labels[0].text, events[0].place);
  assert.ok(base.calls.some(c => c[0] === 'fillText' && c[1] === 'A1'));
  assert.ok(!base.calls.some(c => c[0] === 'fillText' && c[1] === events[0].place));
  assert.equal(base.calls.filter(c => c[0] === 'measureText').length, 2);
  const repeated = drawTimetableWeek(canvas(), 380, 830, timetable, events, 1, false, 50, 0, false);
  assert.ok(labels[0].matches(repeated[0]));
  repeated[0].text += ' changed';
  assert.ok(!labels[0].matches(repeated[0]));
});

test('events with only a start hour or one section keep readable title and place text', () => {
  const { timetable } = fixture();
  const hourOnly = new EasEventItem();
  hourOnly.name = '办公时间安排';
  hourOnly.place = 'N-118';
  hourOnly.from = timetable.startTime + 8 * 3600000;
  hourOnly.to = 0;
  const hourSpan = timetableEventSpan(timetable, hourOnly, 1);
  assert.ok(hourSpan);
  assert.equal(hourSpan.to - hourSpan.from, 3600000);
  const hourCanvas = canvas();
  const hourLabels = drawTimetableWeek(hourCanvas, 380, 830, timetable, [hourOnly], 1, false, 50, 0, false);
  const hourTitleCalls = hourCanvas.calls.filter(c =>
    c[0] === 'fillText' && c[3] >= 30 && c[3] <= 60);
  assert.equal(hourTitleCalls.length, 2);
  assert.ok(hourTitleCalls[1][3] > hourTitleCalls[0][3]);
  assert.ok(hourLabels.some(label => label.text === 'N-118') ||
    hourCanvas.calls.some(c => c[0] === 'fillText' && String(c[1]).includes('N-118')));

  const onePeriod = new EasEventItem();
  onePeriod.name = '单节课程';
  onePeriod.place = 'M-201';
  onePeriod.from = timetable.startTime + 8 * 3600000 + 30 * 60000;
  onePeriod.to = 0;
  onePeriod.fromNumber = 1;
  onePeriod.lastNumber = 1;
  const periodSpan = timetableEventSpan(timetable, onePeriod, 1);
  assert.ok(periodSpan);
  assert.equal(periodSpan.from, onePeriod.from);
  assert.equal(periodSpan.to - periodSpan.from, 50 * 60000);
  const periodCanvas = canvas();
  const periodLabels = drawTimetableWeek(periodCanvas, 380, 830, timetable, [onePeriod], 1, false, 50, 0, false);
  assert.ok(periodCanvas.calls.some(c => c[0] === 'fillText' && String(c[1]).includes('单节')));
  assert.ok(periodLabels.some(label => label.text === 'M-201') ||
    periodCanvas.calls.some(c => c[0] === 'fillText' && String(c[1]).includes('M-201')));
});

test('animation redraws only clipped classroom text without measuring text or repainting the grid', () => {
  const { timetable, events } = fixture();
  const labels = drawTimetableWeek(canvas(), 380, 830, timetable, events, 1, false, 50, 0, false);
  const overlay = canvas();
  assert.equal(drawTimetablePlaces(overlay, 380, 830, labels, 0), 1200);
  assert.equal(drawTimetablePlaces(overlay, 380, 830, labels, 1600), 0);
  assert.ok(!overlay.calls.some(c => ['measureText', 'fillRect', 'stroke'].includes(c[0])));
  assert.equal(overlay.calls.filter(c => c[0] === 'clip').length, 2);
  assert.ok(overlay.calls.filter(c => c[0] === 'fillText').every(c => c[1] === labels[0].text));
  const positions = overlay.calls.filter(c => c[0] === 'fillText');
  close(positions[0][2] - positions[2][2], 12);
  assert.equal(drawTimetablePlaces(canvas(), 380, 830, [], 0), -1);
});

test('the overlay preserves vp font units even when the native canvas getter normalizes to pixels', () => {
  const { timetable, events } = fixture();
  const base = canvas();
  Object.defineProperty(base, 'font', {
    get: () => '10px sans-serif',
    set: () => {}
  });
  const labels = drawTimetableWeek(base, 380, 830, timetable, events, 1, false, 50, 0, false);
  assert.equal(labels[0].font, '10vp sans-serif');
});

test('the next wake-up is the earliest label pause ending, or the next vsync while one moves', () => {
  const a = new TimetablePlaceLabel();
  a.text = 'A';
  a.textWidth = 90;
  a.width = 30;
  const b = new TimetablePlaceLabel();
  b.text = 'B';
  b.textWidth = 105;
  b.width = 30;
  const bothPausedAt = 1200 + 115 / 30 * 1000 + 100;
  close(drawTimetablePlaces(canvas(), 380, 830, [a, b], bothPausedAt), 600);
  assert.equal(drawTimetablePlaces(canvas(), 380, 830, [a, b], 4600), 0);
});

test('the host uses cancellable-by-generation vsync callbacks and a non-interactive overlay', () => {
  const home = fs.readFileSync(path.join(root, 'pages/Home.ets'), 'utf8');
  const loop = home.slice(home.indexOf('  private startTimetableMarquee()'), home.indexOf('  async refreshSummaries('));
  assert.match(home, /frameTimeInNano \/ 1000000/);
  assert.match(loop, /postFrameCallback\(callback\)/);
  assert.match(loop, /postDelayedFrameCallback\(callback, Math\.ceil\(nextDelay\)\)/);
  assert.match(loop, /generation !== this\.timetableMarqueeGeneration/);
  assert.match(loop, /timetableCardPainter\.drawPlaces/);
  assert.doesNotMatch(loop, /drawTimetableNow|drawTimetableWeek\(|eventsOfWeek/);
  assert.doesNotMatch(home, /timetableMarqueeTimer|timetableMarqueeOffset/);
  assert.match(home, /onPageHide\(\): void \{[\s\S]*?this\.stopTimetableMarquee\(\)/);
  const cards = fs.readFileSync(path.join(root, 'feature/timetable/views/TimetableCardMaterials.ets'), 'utf8');
  assert.match(cards, /Canvas\(this\.placeCanvas\)[\s\S]*?\.hitTestBehavior\(HitTestMode\.None\)/);
});

test('timetable taps open detail for exams as well as classes', () => {
  const home = fs.readFileSync(path.join(root, 'pages/Home.ets'), 'utf8');
  const tap = home.slice(home.indexOf('  private openCourseAt'), home.indexOf('  private courseProgressText'));
  assert.match(tap, /event\.type === EasEventType\.CLASS \|\| event\.type === EasEventType\.EXAM/);
  assert.match(tap, /timetableEventSpan/);
  assert.match(home, /periodText: Home\.coursePeriodText\(event\)/);
  const detail = fs.readFileSync(path.join(root, 'feature/timetable/views/CourseDetailContent.ets'), 'utf8');
  assert.match(detail, /this\.event\.type === EasEventType\.EXAM \? '考试详情' : '课程详情'/);
  assert.match(detail, /this\.event\.type === EasEventType\.EXAM \? '考场' : '教室'/);
  assert.match(detail, /if \(this\.event\.type !== EasEventType\.EXAM\) \{[\s\S]*?'节次', this\.periodText\)/);
  assert.match(detail, /'类型', '考试'/);
});

test('native card surfaces match legacy bounds and preserve all title and classroom positions', () => {
  const { timetable, events } = fixture();
  const add = (id, name, day, hour, duration, color) => {
    const event = new EasEventItem();
    Object.assign(event, { id, name, place: 'Classroom-long-name-118', color,
      from: timetable.startTime + (day - 1) * 86400000 + hour * 3600000 });
    event.to = duration === 0 ? 0 : event.from + duration * 60000;
    events.push(event);
  };
  add('short', 'One period', 3, 8, 45, 0xFFFFB74D);
  add('missing-end', 'One hour', 4, 9, 0, 0xFF81C784);
  add('overlap-a', 'Course C', 5, 10, 120, 0xFF3949AB);
  add('overlap-b', 'Course D', 5, 10, 60, 0xFF8E24AA);
  add('merge', 'Course C', 5, 10.5, 60, 0xFF3949AB);
  add('sunday', 'Sunday exam', 7, 18, 90, 0xFF8A2E42);
  add('clip', 'Early class', 2, 7.5, 60, 0xFF546E7A);
  const saved = events.map(event => JSON.stringify(event));
  for (const width of [320, 380, 600]) {
    for (const dark of [false, true]) {
      for (const fillPage of [false, true]) {
        const legacy = canvas(), grid = canvas();
        const layer = new TimetableCardLayer();
        const args = [width, 830, timetable, events, 1, true, 50, 0, false, fillPage, '', dark];
        const previousLabels = drawTimetableWeek(legacy, ...args);
        const labels = drawTimetableWeek(grid, ...args, layer);
        assert.deepEqual(labels, previousLabels);
        assert.equal(layer.surfaces.length, events.length - 1, 'merged courses have one surface');
        const normalize = paints => paints.map(p => ({ ...p,
          args: p.args.map(value => typeof value === 'number' ? Math.round(value * 1e8) / 1e8 : value) }));
        const nativeText = layer.surfaces.flatMap(card => {
          const text = canvas();
          drawTimetableCardText(text, card);
          assert.ok(text.paints.every(p => p.method === 'fillText'), 'text canvas must remain transparent');
          return text.paints.map(p => ({ ...p, args: [p.args[0], p.args[1] + card.left, p.args[2] + card.top] }));
        });
        assert.deepEqual(normalize(nativeText),
          normalize(legacy.paints.filter(p => p.method === 'fillText' && p.color === '#FFFFFF')));
        assert.ok(grid.paints.every(p => p.method !== 'fill' &&
          !(p.method === 'fillText' && p.color === '#FFFFFF')), 'grid cannot cover the material or duplicate card text');
        const bounds = [];
        let path = [];
        for (const call of legacy.calls) {
          if (call[0] === 'beginPath') path = [];
          if (['moveTo', 'lineTo', 'quadraticCurveTo'].includes(call[0])) path.push(call);
          if (call[0] === 'fill') bounds.push(path);
        }
        layer.surfaces.forEach((card, index) => {
          close(card.left + card.radius, bounds[index][0][1]);
          close(card.top, bounds[index][0][2]);
          close(card.left + card.width, bounds[index][2][1]);
          close(card.top + card.height, bounds[index][4][2]);
          assert.ok(card.left >= 48 && card.left + card.width <= width);
          assert.ok(card.top >= 24 && card.top + card.height <= 774);
          assert.equal(argbToCss(card.color, 1), legacy.paints.filter(p => p.method === 'fill')[index].color);
          assert.equal(card.tint() & 0xFFFFFF, card.color & 0xFFFFFF);
          assert.ok(card.tint() >>> 24 > 0 && card.tint() >>> 24 < 255);
        });
        const keys = layer.surfaces.map(card => card.renderKey());
        assert.equal(new Set(keys).size, keys.length);
        drawTimetableWeek(grid, ...args, layer);
        assert.deepEqual(layer.surfaces.map(card => card.renderKey()), keys, 'redraws do not recreate unchanged materials');
        assert.deepEqual(events.map(event => JSON.stringify(event)), saved, 'rendering cannot change saved course colors or times');
      }
    }
  }
});

test('refreshing to an empty week removes native cards and their text together', () => {
  const { timetable, events } = fixture();
  const grid = canvas(), layer = new TimetableCardLayer();
  drawTimetableWeek(grid, 380, 830, timetable, events, 1, false, 50, 0, false, true, '', false, layer);
  assert.equal(layer.surfaces.length, 2);
  drawTimetableWeek(grid, 380, 830, timetable, [], 2, false, 50, 0, false, true, '', false, layer);
  assert.equal(layer.surfaces.length, 0);
});

test('course color edits and resizing invalidate native geometry without changing the saved palette', () => {
  const { timetable, events } = fixture();
  const grid = canvas(), layer = new TimetableCardLayer();
  const draw = width => drawTimetableWeek(grid, width, 830, timetable, events, 1,
    false, 50, 0, false, false, '', false, layer);
  draw(380);
  const oldKeys = layer.surfaces.map(card => card.renderKey());
  events[0].color = 0xFF8E24AA;
  draw(380);
  assert.notEqual(layer.surfaces[0].renderKey(), oldKeys[0]);
  assert.equal(layer.surfaces[1].renderKey(), oldKeys[1]);
  assert.equal(events[0].color, 0xFF8E24AA);
  events[1].name = 'Updated title';
  draw(380);
  assert.notEqual(layer.surfaces[1].renderKey(), oldKeys[1], 'title edits invalidate the card text canvas');
  events[1].name = 'Course B';
  draw(600);
  assert.notEqual(layer.surfaces[1].renderKey(), oldKeys[1]);
});

test('card-local classroom canvases share the page clock and retain the loop pause', () => {
  const { timetable, events } = fixture();
  const layer = new TimetableCardLayer();
  const labels = drawTimetableWeek(canvas(), 380, 830, timetable, events, 1,
    false, 50, 0, false, false, '', false, layer);
  const painter = new TimetableCardPainter();
  assert.equal(painter.drawPlaces(labels, 0), 1200, 'animation starts even before card canvases mount');
  const ctx = canvas(), card = layer.surfaces[0];
  painter.attach(card, ctx);
  assert.equal(ctx.calls.filter(call => call[0] === 'fillText').length, 2);
  const legacy = canvas();
  assert.equal(painter.drawPlaces(labels, 1600), 0);
  drawTimetablePlaces(legacy, 380, 830, labels, 1600);
  const moved = ctx.paints.slice(-2);
  legacy.paints.forEach((paint, i) => {
    assert.equal(moved[i].args[0], paint.args[0]);
    close(moved[i].args[1] + card.left, paint.args[1]);
    close(moved[i].args[2] + card.top, paint.args[2]);
  });
  assert.ok(ctx.paints.every(p => p.method === 'fillText' && p.args[0] === card.place.text));
  assert.ok(!ctx.calls.some(call => ['measureText', 'stroke', 'fillRect'].includes(call[0])));
  const cycle = 1200 + (card.place.textWidth + card.place.width / 3) / 30 * 1000;
  close(painter.drawPlaces(labels, cycle + 600), 600);
  painter.detach(ctx);
  const count = ctx.calls.length;
  painter.drawPlaces(labels, cycle + 800);
  assert.equal(ctx.calls.length, count, 'removed or hidden cards stop receiving drawing calls');
  painter.attach(card, ctx);
  close(ctx.paints.at(-2).args[1], card.place.left);
});

test('replacing a course canvas cannot leave duplicate frames or unregister the replacement', () => {
  const { timetable, events } = fixture();
  const layer = new TimetableCardLayer();
  const labels = drawTimetableWeek(canvas(), 380, 830, timetable, events, 1,
    false, 50, 0, false, false, '', false, layer);
  const painter = new TimetableCardPainter(), old = canvas(), current = canvas();
  painter.attach(layer.surfaces[0], old);
  painter.attach(layer.surfaces[0], current);
  painter.detach(old);
  const oldCalls = old.calls.length, currentCalls = current.calls.length;
  painter.drawPlaces(labels, 1800);
  assert.equal(old.calls.length, oldCalls);
  assert.equal(current.calls.length - currentCalls, 8, 'exactly one clipped two-copy classroom frame');
});

test('both title and scrolling classroom are inside the material card so native press movement includes text', () => {
  const source = fs.readFileSync(path.join(root, 'feature/timetable/views/TimetableCardMaterials.ets'), 'utf8');
  const card = source.slice(source.indexOf('struct TimetableMaterialCard'), source.indexOf('export struct'));
  assert.match(card, /Stack\(\{ alignContent: Alignment\.TopStart \}\) \{\s*Canvas\(this\.textCanvas\)/);
  assert.match(card, /Canvas\(this\.placeCanvas\)[\s\S]*\.attributeModifier\(new CompatibleMaterialModifier/);
  const home = fs.readFileSync(path.join(root, 'pages/Home.ets'), 'utf8');
  assert.doesNotMatch(home, /timetableTextCanvas/);
  assert.match(home, /TimetableCardMaterials\(\{[\s\S]*?painter: this\.timetableCardPainter/);
  assert.match(home, /timetableCardPainter\.drawPlaces\(this\.timetablePlaceLabels, this\.timetableMarqueeElapsedMs\)/);
});

test('material taps select by card identity and the grid retains its coordinate hit target', () => {
  const source = fs.readFileSync(path.join(root, 'feature/timetable/views/TimetableCardMaterials.ets'), 'utf8');
  const card = source.slice(source.indexOf('struct TimetableMaterialCard'), source.indexOf('export struct'));
  assert.match(card, /\.attributeModifier\(new CompatibleMaterialModifier[\s\S]*?\.onClick\(/);
  const handler = card.match(/\.onClick\(\(\) => (this\.onCardClick\([^\n]+)\)/)[1];
  const clicks = [];
  new Function(handler).call({
    card: { key: 'scrolled-course', left: 51, top: 240 }, onCardClick: key => clicks.push(key)
  });
  assert.deepEqual(clicks, ['scrolled-course']);
  const home = fs.readFileSync(path.join(root, 'pages/Home.ets'), 'utf8');
  const timetable = home.slice(home.indexOf('  tabTimetable()'), home.indexOf('  timetableToolbar()'));
  assert.match(timetable, /onCardClick: \(key: string\) => this\.openCourseCard\(key\)/);
  assert.match(timetable, /\.onClick\(\(event: ClickEvent\) => \{\s*this\.openCourseAt\(event\.x, event\.y\)/);
});

test('the particle overlay excludes its entire subtree so hidden snapshot containers cannot intercept material presses', () => {
  const source = fs.readFileSync(path.join(root, 'feature/timetable/views/TimetableCardMaterials.ets'), 'utf8');
  const overlay = source.slice(source.indexOf('      Stack(', source.indexOf('      ImmersiveHeader')),
    source.indexOf("    .accessibilityLevel('no-hide-descendants')"));
  assert.match(overlay, /DeleteParticleCard\(/);
  assert.match(overlay, /captureSource:.*this\.painter\.capture/);
  assert.match(overlay, /\.height\(this\.contentHeight\)\s*\.clip\(false\)\s*\/\/[^\n]*\s*\.hitTestBehavior\(HitTestMode\.BLOCK_DESCENDANTS\)/);
  const materialCard = source.slice(source.indexOf('struct TimetableMaterialCard'), source.indexOf('export struct'));
  assert.doesNotMatch(materialCard, /BLOCK_DESCENDANTS/);
  assert.match(materialCard, /\.onClick\(\(\) => this\.onCardClick\(this\.card\.key\)\)/);
});

test('merged lesson cards retain occurrence IDs, while same-name exams remain separate', () => {
  const { timetable, events } = fixture();
  const first = events[0];
  first.type = 'CLASS';
  const duplicate = Object.assign(new EasEventItem(), first, { id: 'second-teacher' });
  const exam = Object.assign(new EasEventItem(), first, { id: 'same-name-exam', type: 'EXAM' });
  const layer = new TimetableCardLayer();
  drawTimetableWeek(canvas(), 380, 830, timetable, [first, duplicate, exam], 1, false,
    50, 0, false, false, '', false, layer);
  assert.equal(layer.surfaces.length, 2);
  assert.deepEqual(layer.surfaces[0].eventIds, [first.id, duplicate.id]);
  assert.deepEqual(layer.surfaces[1].eventIds, [exam.id]);
});

test('dissolve source includes the full course fill, original title and current classroom position', () => {
  const { timetable, events } = fixture();
  const layer = new TimetableCardLayer();
  const labels = drawTimetableWeek(canvas(), 380, 830, timetable, events, 1,
    false, 50, 0, false, false, '', false, layer);
  for (const card of layer.surfaces) {
    const source = canvas(), title = canvas();
    drawTimetableCardSnapshot(source, card, 1900);
    drawTimetableCardText(title, card);
    assert.deepEqual(source.paints.slice(0, title.paints.length), title.paints);
    assert.equal(source.calls.filter(call => call[0] === 'clearRect').length, 1,
      'adding the classroom cannot clear the title or background');
    assert.equal(source.paints.at(-1).method, 'fill');
    assert.equal(source.paints.at(-1).color, argbToCss(card.color, 1));
    if (card.place.textWidth > card.place.width) {
      const painter = new TimetableCardPainter(), live = canvas();
      painter.drawPlaces(labels, 1900);
      painter.attach(card, live);
      assert.deepEqual(source.paints.slice(-3, -1), live.paints);
    }
  }
});

test('offscreen course capture follows the same vp geometry and bounds bitmap allocation', async () => {
  const { timetable, events } = fixture();
  const layer = new TimetableCardLayer();
  drawTimetableWeek(canvas(), 380, 830, timetable, events, 1,
    false, 50, 0, false, false, '', false, layer);
  const originalCanvas = global.OffscreenCanvasRenderingContext2D;
  const originalSettings = global.RenderingContextSettings;
  const captured = [];
  global.RenderingContextSettings = class {};
  global.OffscreenCanvasRenderingContext2D = class {
    constructor(w, h) {
      const ctx = canvas();
      ctx.scale = (...args) => ctx.calls.push(['scale', ...args]);
      ctx.getPixelMap = (...bounds) => ({ w, h, bounds });
      captured.push(ctx);
      return ctx;
    }
  };
  try {
    const painter = new TimetableCardPainter();
    const small = await painter.capture(layer.surfaces[0], 3.25);
    assert.equal(small.w, layer.surfaces[0].width);
    assert.equal(small.h, layer.surfaces[0].height);
    assert.deepEqual(captured[0].calls[0], ['scale', 1, 1]);
    const bigCard = Object.assign(layer.surfaces[0], { width: 200, height: 1500 });
    const big = await painter.capture(bigCard, 4);
    assert.ok(big.w * big.h * 16 <= 360001);
    assert.equal(captured[1].paints.at(-1).color, argbToCss(bigCard.color, 1));
  } finally {
    global.OffscreenCanvasRenderingContext2D = originalCanvas;
    global.RenderingContextSettings = originalSettings;
  }
});
