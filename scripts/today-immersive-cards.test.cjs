const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');

test('only Today event cards use the API 26-capable material branch; heading and empty state stay unchanged', () => {
  const home = read('pages/Home.ets');
  const today = home.slice(home.indexOf('  tabToday()'), home.indexOf('  todayHeader()'));
  // No timetable: text-only empty state. Otherwise the heading appears only above a non-empty list.
  assert.match(today, /if \(!this\.hasTimetable\) \{\s*ListItem\(\) \{\s*this\.emptyToday\(\);/);
  assert.match(today, /\} else if \(this\.todayItems\.length > 0\) \{\s*ListItem\(\) \{\s*this\.todaySectionHeader\(\);/);
  assert.match(today, /ForEach\(this\.todayItems, \(event: EasEventItem\) => \{\s*ListItem\(\) \{\s*if \(CompatibleSheetMaterial\.isEnabled\(\)\) \{\s*ImmersiveEventCard/);
  assert.match(today, /ImmersiveEventCard\(\{ content: \(\) => \{ this\.eventRow\(event, true\); \} \}\)[\s\S]*?\} else \{\s*this\.eventRow\(event\)/);
  assert.match(today, /\}, \(event: EasEventItem\) => Home\.todayItemKey\(event\)\)/);
  assert.doesNotMatch(home.slice(home.indexOf('  todaySectionHeader()'), home.indexOf('  eventRow(')),
    /ImmersiveEventCard|CompatibleMaterialModifier|systemMaterial/);
});

test('card material lives inside the supported title host, matches measured content height and has no shadow', () => {
  const card = read('common/components/ImmersiveEventCard.ets');
  assert.match(card, /@State private contentHeight: number = 0/);
  assert.match(card, /if \(this\.contentHeight > 0\) \{[\s\S]*?Column\(\) \{\s*ImmersiveHeader\(\{ barHeight: this\.contentHeight \}\)/);
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
  const method = source.slice(source.indexOf('  private updateHeight('), source.indexOf('  build()'));
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

test('today list runs to the screen bottom and keeps the dock inset as scroll end offset', () => {
  const home = require('node:fs').readFileSync(require('node:path').join(__dirname, '../entry/src/main/ets/pages/Home.ets'), 'utf8').replace(/\r\n/g, '\n');
  const today = home.slice(home.indexOf('  tabToday()'), home.indexOf('  todayHeader()'));
  assert.match(home, /this\.tabToday\(\);\s*\}\s*\/\/[^\n]*\n\s*\.tabPage\(0, COLOR_SURFACE, this\.railGutter\(\), this\.railGutter\(\)\)/);
  assert.match(today, /\.contentEndOffset\(this\.dockPageInset\(\) \+ 16\)/);
  assert.match(today, /\.expandSafeArea\(\[SafeAreaType\.SYSTEM\], \[SafeAreaEdge\.BOTTOM\]\)/);
  assert.doesNotMatch(today, /bottom: 16 \}/);
});
