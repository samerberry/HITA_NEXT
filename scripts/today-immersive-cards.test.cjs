const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');

test('Today schedule cards keep the API 26 material and omit the heading for an empty schedule', () => {
  const home = read('pages/Home.ets');
  const today = home.slice(home.indexOf('  tabToday()'), home.indexOf('  todayHeader()'));
  // No timetable: text-only empty state. Otherwise the heading appears only above a non-empty list.
  assert.match(today, /if \(!this\.hasTimetable\) \{\s*ListItem\(\) \{\s*this\.emptyToday\(\);/);
  assert.match(today, /\} else if \(this\.todayScheduleItems\(\)\.length > 0\) \{\s*ListItem\(\) \{\s*this\.todaySectionHeader\(\{ title: '今日安排', countText: this\.todayScheduleItems\(\)\.length \+ ' 项' \}\);/);
  assert.match(today, /ForEach\(this\.todayScheduleItems\(\), \(event: EasEventItem\) => \{\s*ListItem\(\) \{\s*if \(CompatibleSheetMaterial\.isEnabled\(\)\) \{\s*ImmersiveEventCard/);
  assert.match(today, /ImmersiveEventCard\(\{ content: \(\) => \{ this\.eventRow\(event, true\); \} \}\)[\s\S]*?\} else \{\s*this\.eventRow\(event\)/);
  assert.match(today, /\}, \(event: EasEventItem\) => Home\.todayItemKey\(event\)\)/);
  assert.doesNotMatch(home.slice(home.indexOf('  todaySectionHeader('), home.indexOf('  eventRow(')),
    /ImmersiveEventCard|CompatibleMaterialModifier|systemMaterial/);
});

test('card material lives inside the supported title host, matches measured content height and has no shadow', () => {
  const card = read('common/components/ImmersiveEventCard.ets');
  assert.match(card, /@State private contentHeight: number = 0/);
  assert.match(card, /if \(this\.contentHeight > 0 && !this\.hero\) \{[\s\S]*?Column\(\) \{\s*ImmersiveHeader\(\{ barHeight: this\.contentHeight \}\)/);
  assert.match(card, /Row\(\)\s*\.width\('100%'\)\s*\.height\(this\.contentHeight\)/);
  assert.match(card, /new CompatibleMaterialModifier\(\$r\('app\.color\.hita_surface'\)\)/);
  assert.match(card, /\.onAreaChange\(\(oldArea: Area, area: Area\) => \{ this\.updateHeight\(Number\(area\.height\)\); \}\)/);
  assert.match(card, /\.hitTestBehavior\(HitTestMode\.Transparent\)/);
  assert.match(card, /\.backgroundColor\(this\.contentHeight > 0 \? Color\.Transparent : \$r\('app\.color\.hita_surface'\)\)/);
  assert.doesNotMatch(card, /\.shadow\(/);
  assert.doesNotMatch(card, /\.height\(1[0-9][0-9]\)|\.height\(2[0-9][0-9]\)/);
  const material = read('common/theme/ImmersiveHeaderMaterial.ets');
  assert.match(material, /applyShadow: shadow === undefined \? blueSurface : shadow/);
  assert.match(material, /interactive: true/);
  assert.match(material, /lightEffect: deviceInfo\.apiAvailable\('27\.0\.0'\) \? \{ color: Color\.White \} : null/);
  assert.match(material, /new CompatibleLightModifier\(\)\.applyNormalAttribute\(instance\)/);
});

test('measured card height ignores invalid values and updates when event content changes', () => {
  const source = read('common/components/ImmersiveEventCard.ets');
  const start = source.indexOf('  private updateHeight(');
  const method = source.slice(start, source.indexOf('  @Builder', start));
  const compiled = ts.transpileModule('class Card { contentHeight = 0;\n' + method + '\n}; return Card;', {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const Card = new Function(compiled)();
  const card = new Card();
  for (const invalid of [0, -1, NaN, Infinity, -Infinity]) {
    card.updateHeight(invalid);
    assert.equal(card.contentHeight, 0);
  }
  card.updateHeight(127.2);
  assert.equal(card.contentHeight, 128);
  card.updateHeight(127.8);
  assert.equal(card.contentHeight, 128);
  card.updateHeight(201.1);
  assert.equal(card.contentHeight, 202);
});

test('card text, status colors, time rail and progress remain in the original content layer', () => {
  const home = read('pages/Home.ets');
  const row = home.slice(home.indexOf('  eventRow('), home.indexOf('  emptyTimetableActions()'));
  for (const source of ['EasTimeTools.printTime(event.from)', 'EasTimeTools.printTime(event.to)',
    'Home.todayChipText(event, this.nowTick)', 'Home.todayChipTone(event, this.nowTick)',
    'Home.placeTeacher(event)', 'timetableBlockColor(event.color)',
    'Progress({ value: event.getProgress(this.nowTick) * 100']) {
    assert.ok(row.includes(source), source);
  }
  assert.match(row, /eventRow\(event: EasEventItem, immersive: boolean = false\)/);
  assert.match(row, /\.backgroundColor\(immersive \? Color\.Transparent : COLOR_CARD\)/);
  assert.match(row, /\.hitTestBehavior\(immersive \? HitTestMode\.Transparent : HitTestMode\.Default\)/);
  // Both branches sit directly on the list's 12 vp spacing; no extra 2 vp margin makes the gap 14.
  assert.doesNotMatch(row, /\.margin\(\{ bottom: immersive/);
  assert.match(home.slice(home.indexOf('  tabToday()'), home.indexOf('  todayHeader()')), /List\(\{ space: HitaDesign\.gap \}\)/);
  assert.match(row, /event\.containsTimestamp\(this\.nowTick\) \? \$r\('app\.color\.hita_focus'\)/);
});

test('edited course fields re-key today rows so the list redraws without restarting the app', () => {
  const home = read('pages/Home.ets');
  const today = home.slice(home.indexOf('  tabToday()'), home.indexOf('  todayHeader()'));
  assert.match(today, /\}, \(event: EasEventItem\) => Home\.todayItemKey\(event\)\);/);
  const key = home.match(/private static todayItemKey\(event: EasEventItem\): string \{([\s\S]*?)\n  \}/)[1];
  for (const field of ['id', 'type', 'name', 'place', 'teacher', 'from', 'to', 'fromNumber', 'lastNumber', 'color']) {
    assert.match(key, new RegExp('event\\.' + field + '\\b'), field + ' must be part of the row key');
  }
});

test('Today lists the exam section between the schedule and the always-visible task entry', () => {
  const home = read('pages/Home.ets');
  const today = home.slice(home.indexOf('  tabToday()'), home.indexOf('  todayHeader()'));
  assert.match(today, /Home\.todayItemKey\(event\)\);\s*\}\s*if \(this\.todayExamItems\(\)\.length > 0\) \{\s*ListItem\(\) \{\s*this\.todaySectionHeader\(\{ title: '考试', countText: this\.todayExamItems\(\)\.length \+ ' 项' \}\);/);
  assert.match(today, /Home\.todayItemKey\(exam\)\);\s*\}\s*ListItem\(\) \{\s*this\.todaySectionHeader\(\{ title: '待办', countText: '共 ' \+ this\.todayLearningTaskCount \+ ' 项未处理' \}\);\s*\}\s*ListItem\(\) \{\s*this\.todayLearningTaskEntry\(\);/);
  assert.match(today, /ForEach\(this\.todayExamItems\(\),[\s\S]*?this\.todayExamCard\(exam\);/);
  assert.equal(today.split('this.todayLearningTaskEntry()').length - 1, 1);
  assert.doesNotMatch(today, /ForEach\(this\.todayLearningTasks/);
  const entry = home.slice(home.indexOf('  private todayLearningTaskEntry('), home.indexOf('  private todayExamRow('));
  assert.match(entry, /ImmersiveEventCard\(\{ content: \(\) => \{ this\.todayLearningTaskRow\(slot, true\);/);
  assert.match(entry, /Text\(this\.todayDeckTaskAt\(slot\)\?\.title \?\?/);
  assert.match(entry, /\.onClick\(\(\) => \{\s*if \(slot === 0 && !this\.todayDeckMoving\) this\.openAcademicPanel\(5\);/);
  assert.match(home, /LearningTasksPanel\(\{\s*initialTaskId: this\.pendingLearningTask/);
  const editor = read('feature/learning/LearningTaskEditor.ets');
  assert.match(editor, /this\.field\('提醒'[\s\S]*Text\('显示在今日页'\)[\s\S]*Toggle\(\{ type: ToggleType\.Switch, isOn: this\.draft\.showInToday \}\)[\s\S]*next\.showInToday = value/);
});

test('task cards use a horizontal gesture and a continuous sideways transition', () => {
  const home = read('pages/Home.ets');
  const entry = home.slice(home.indexOf('  private todayLearningTaskEntry('), home.indexOf('  private todayExamRow('));
  assert.match(entry, /if \(this\.todayTaskDeck\.length > 1\) \{/);
  assert.match(entry, /\.gesture\(PanGesture\(\{ fingers: 1, direction: PanDirection\.Horizontal[^\n]*\n\s*\.tag\(TODAY_TASK_DECK_PAN\)/);
  assert.match(entry, /this\.dragTodayDeck\(event\.offsetX\)/);
  assert.match(entry, /onActionCancel\(\(\) => \{ this\.settleTodayDeck\(0\); \}\)/);
  assert.doesNotMatch(entry, /priorityGesture|offsetY|PanDirection\.Vertical/);

  assert.match(entry, /\.transform3D\(taskFlipProjection\(slot - this\.todayDeckDrag,/);
  assert.doesNotMatch(entry, /todayTaskIncomingLayer/);
  const motion = read('feature/learning/TodayTaskFlip.ets');
  const compiled = ts.transpileModule(motion, {
    compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS }
  }).outputText;
  const deck = {};
  new Function('exports', 'require', compiled)(deck, () => ({
    matrix4: { identity: () => ({ setPolyToPoly: ({ dst }) => dst }) }
  }));
  const { taskFlipTarget, taskFlipProjection, taskFlipOpacity, taskFlipRelease } = deck;
  assert.equal(taskFlipTarget(-80, 360, 0, 16), -1);
  assert.equal(taskFlipTarget(80, 360, 0, 16), 1);
  assert.equal(taskFlipTarget(45, 360, 0, 16), 0);
  assert.equal(taskFlipTarget(8, 360, 650, 16), 0);
  assert.equal(taskFlipTarget(24, 360, 650, 16), 1);
  assert.equal(taskFlipTarget(24, 360, -650, 16), 0);
  assert.equal(taskFlipTarget(-100, 720, 0, 16), -1);

  const halfFold = taskFlipProjection(-0.5, 360, 80, 8);
  const incoming = taskFlipProjection(0.5, 360, 80, 8);
  assert.ok(halfFold[0].x < 0 && halfFold[1].x < 220, 'the outgoing card folds to the left');
  assert.ok(halfFold[1].y > halfFold[0].y, 'the far edge narrows in perspective');
  assert.ok((incoming[0].x + incoming[1].x) / 2 > 180, 'the card behind moves in from the right');
  for (const depth of [0.5, 1, 2]) {
    const layer = taskFlipProjection(depth, 360, 80, 8);
    assert.equal(layer[1].x, 360 + 8 * depth, 'each layer exposes a strip on the right');
    assert.ok(layer[0].y >= 0 && layer[2].y <= 80);
    assert.equal((layer[0].y + layer[2].y) / 2, 40, 'resting layers share the same vertical center');
  }
  assert.equal(taskFlipOpacity(-1, 2), 0);
  assert.equal(taskFlipOpacity(2, 2), 1);
  assert.equal(taskFlipOpacity(3, 2), 0);
  const almostFlat = taskFlipProjection(-0.001, 360, 80, 8);
  assert.ok(Math.abs(almostFlat[0].x) < 1 && Math.abs(almostFlat[1].x - 360) < 1);

  let last = 0;
  for (let frame = 0; frame <= 30; frame++) {
    const progress = taskFlipRelease(frame / 30, 2.4);
    assert.ok(progress >= last && progress <= 1);
    last = progress;
  }
  assert.equal(last, 1);
});

test('exam rows keep all of today’s exams plus the nearest reminder without duplicating the schedule', () => {
  const home = read('pages/Home.ets');
  const code = home.slice(home.indexOf('  private todayScheduleItems('), home.indexOf('  private async refreshTodayLearningTasks('));
  const compiled = ts.transpileModule('class Home {\n' + code + '\n}; return Home;', {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const day = 86_400_000;
  const Home = new Function('EasEventType', 'DAY_MS', compiled)({ EXAM: 'EXAM' }, day);
  const page = new Home();
  const start = new Date(2026, 10, 22).getTime();
  const hour = day / 24;
  page.nowTick = start + 12 * hour;
  const item = (id, when, type = 'EXAM') => ({ id, type, from: start + when * hour, to: start + (when + 1) * hour });
  const course = item('course', 8, 'CLASS'), ended = item('morning', 9), other = item('meeting', 10, 'OTHER');
  const later = item('afternoon', 14), tomorrow = item('tomorrow', 33), past = item('past', -24);
  page.todayItems = [course, ended, other, later];
  page.timetableEvents = [tomorrow, later, other, past, ended, course];
  assert.deepEqual(page.todayScheduleItems(), [course, other]);
  assert.deepEqual(page.todayExamItems(), [ended, later], 'the nearest reminder is already in today’s exams');
  assert.equal(Home.examDistanceText(later, page.nowTick), '今天');
  assert.equal(Home.examDistanceText(later, later.from), '进行中');
  assert.equal(Home.examDistanceText(later, later.to), '已结束');
  page.nowTick = later.to;
  assert.deepEqual(page.todayExamItems(), [ended, later, tomorrow], 'completed exams remain alongside the next reminder');
  page.todayItems = [];
  page.timetableEvents = [past, { ...tomorrow, from: page.nowTick + 14 * day, to: page.nowTick + 14 * day + hour }];
  assert.deepEqual(page.todayExamItems(), [], 'past and out-of-window exams do not produce a section');
});

test('today list runs to the screen bottom and keeps the dock inset as scroll end offset', () => {
  const home = require('node:fs').readFileSync(require('node:path').join(__dirname, '../entry/src/main/ets/pages/Home.ets'), 'utf8').replace(/\r\n/g, '\n');
  const today = home.slice(home.indexOf('  tabToday()'), home.indexOf('  todayHeader()'));
  assert.match(home, /this\.tabToday\(\);\s*\}\s*\/\/[^\n]*\n\s*\.tabPage\(0, COLOR_SURFACE, this\.railGutter\(\), this\.railGutter\(\)\)/);
  assert.match(today, /\.contentEndOffset\(this\.dockPageInset\(\) \+ 16\)/);
  assert.match(today, /\.expandSafeArea\(\[SafeAreaType\.SYSTEM\], \[SafeAreaEdge\.BOTTOM\]\)/);
  assert.doesNotMatch(today, /bottom: 16 \}/);
});
