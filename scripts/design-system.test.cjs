// Checks for docs/design-system.md: token scales, token-only shared components, the pages already brought onto
// the scale, and a repository-wide count of loose values that may only go down.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');

function walk(dir, out = []) {
  for (const name of fs.readdirSync(dir)) {
    const file = path.join(dir, name);
    if (fs.statSync(file).isDirectory()) walk(file, out);
    else if (name.endsWith('.ets')) out.push(file);
  }
  return out;
}

const sources = walk(root).map(file => ({
  file: path.relative(root, file).replace(/\\/g, '/'),
  text: fs.readFileSync(file, 'utf8').replace(/\r\n/g, '\n')
}));

const tokens = Object.fromEntries([...read('common/theme/HitaDesign.ets')
  .matchAll(/static readonly (\w+): number = ([\d.]+);/g)].map(m => [m[1], Number(m[2])]));

/** Numeric literals in padding, margin and space arguments; digits inside identifiers such as space2xs do not count. */
function spacingLiterals(text) {
  const values = [];
  for (const m of text.matchAll(/\.(?:padding|margin)\(\s*(\{[^}]*\}|[^)]*)\)|\bspace:\s*([^,}\s]+)/g)) {
    const chunk = m[1] !== undefined ? m[1] : m[2];
    for (const n of chunk.matchAll(/(?<![\w.$])(?<!(?:===|!==|==|!=|<=|>=|<|>)\s*)\d+(?:\.\d+)?(?![\w.])/g)) {
      values.push(Number(n[0]));
    }
  }
  return values;
}

const offGrid = text => spacingLiterals(text).filter(value => value % 4 !== 0);
const literalFontSizes = text => text.match(/\.fontSize\(\s*\d/g) || [];
const literalRadii = text => text.match(/\.borderRadius\(\s*\d/g) || [];
const hexColors = text => text.match(/['"]#[0-9A-Fa-f]{6,8}['"]/g) || [];

function builder(source, name) {
  const start = source.indexOf(`  ${name}(`);
  assert.ok(start >= 0, name);
  const next = source.indexOf('  @Builder', start + 1);
  return source.slice(start, next < 0 ? source.length : next);
}

test('design tokens follow the documented type, spacing and corner scales', () => {
  assert.deepEqual(['display', 'title', 'section', 'body', 'caption', 'label'].map(name => tokens[name]),
    [28, 22, 18, 16, 14, 12]);
  assert.deepEqual(['space2xs', 'spaceXs', 'spaceSm', 'spaceMd', 'spaceLg', 'spaceXl'].map(name => tokens[name]),
    [4, 8, 12, 16, 24, 32]);
  assert.deepEqual(['radiusSm', 'radiusMd', 'radiusLg', 'radiusXl'].map(name => tokens[name]), [8, 12, 16, 24]);
  // Semantic aliases stay on the scales.
  assert.equal(tokens.inset, tokens.spaceMd);
  assert.equal(tokens.gap, tokens.spaceSm);
  assert.equal(tokens.sectionGap, tokens.spaceLg);
  assert.equal(tokens.cardRadius, tokens.radiusLg);
  assert.equal(tokens.fieldRadius, tokens.radiusMd);
  assert.equal(tokens.heroRadius, tokens.radiusXl);
  for (const name of ['buttonHeight', 'controlHeight', 'compactControlHeight', 'rowMinHeight', 'listIconSize']) {
    assert.equal(tokens[name] % 4, 0, name);
  }
  // Row dividers start exactly where row text starts.
  assert.equal(tokens.listTextInset, tokens.inset + tokens.listIconSize + tokens.spaceSm);
});

test('shared components use tokens only and never pair white text with an untinted material', () => {
  for (const file of ['HitaButton', 'HeaderActionButton', 'HitaTag', 'HitaListRow']) {
    const source = read(`common/components/${file}.ets`);
    assert.deepEqual(spacingLiterals(source), [], `${file}: spacing literals`);
    assert.deepEqual(literalFontSizes(source), [], `${file}: font size literals`);
    assert.deepEqual(literalRadii(source), [], `${file}: radius literals`);
    assert.deepEqual(hexColors(source), [], `${file}: hex colors`);
  }
  const button = read('common/components/HitaButton.ets');
  assert.match(button, /Button\(this\.label, \{ type: ButtonType\.Capsule \}\)/);
  assert.doesNotMatch(button, /CompatibleMaterialModifier|systemMaterial/);
  const action = read('common/components/HeaderActionButton.ets');
  assert.match(action, /\.fontColor\(this\.materialEnabled \? CompatibleMaterialModifier\.foreground\(HitaColors\.primary\) : HitaColors\.primary\)/);
  assert.match(action, /new CompatibleMaterialModifier\(HitaColors\.selected, false, this\.materialEnabled\)/);
  const tag = read('common/components/HitaTag.ets');
  // 12 fp text with 4 vp above and below is 24 vp tall; radiusMd is half of that.
  assert.match(tag, /\.fontSize\(HitaDesign\.label\)/);
  assert.match(tag, /top: HitaDesign\.space2xs,\s*bottom: HitaDesign\.space2xs/);
  assert.match(tag, /\.borderRadius\(HitaDesign\.radiusMd\)/);
});

test('no button anywhere puts fixed white text on an untinted material', () => {
  const white = /\.fontColor\(\s*(?:'#FFFFFF'|'#ffffff'|HitaColors\.onPrimary|\$r\('app\.color\.hita_on_primary'\))\s*\)/;
  const violations = [];
  for (const { file, text } of sources) {
    for (const m of text.matchAll(/\bButton\(/g)) {
      const end = text.indexOf('.onClick(', m.index);
      const chain = text.slice(m.index, end < 0 ? m.index + 800 : end);
      // A second argument of true selects the tinted material; inside a material host it keeps a dark fill behind the label.
      const untinted = /new CompatibleMaterialModifier\([^,()]*(?:\([^()]*\))?[^,()]*(?:\)|,\s*false)/.test(chain);
      if (untinted && white.test(chain)) violations.push(`${file}:${text.slice(0, m.index).split('\n').length}`);
    }
  }
  assert.deepEqual(violations, []);
});

test('white icons outside a material host sit on solid fills', () => {
  // Outside an ImmersiveHeader or a sheet even a tinted material renders clear, leaving white icons on the light page.
  const assistant = read('pages/AssistantPage.ets');
  const composer = assistant.slice(assistant.indexOf('  inputBar() {'));
  const detail = read('pages/TimetableDetailPage.ets');
  const swipeDelete = detail.slice(detail.indexOf('  private courseDeleteAction('), detail.indexOf('  private sessionRow('));
  for (const control of [composer, swipeDelete]) assert.doesNotMatch(control, /CompatibleMaterialModifier/);
  assert.match(composer, /paperplane_fill[\s\S]*?\.backgroundColor\(\$r\('app\.color\.hita_primary_fill'\)\)/);
  assert.match(swipeDelete, /\.backgroundColor\(\$r\('app\.color\.hita_error_fill'\)\)/);
});

test('pages brought onto the scale keep 4 vp spacing and token sizes', () => {
  const home = read('pages/Home.ets');
  const pilot = ['tabToday', 'todayHeader', 'todayHeroCard', 'todayExamCard', 'todaySectionHeader', 'emptyToday',
    'eventRow', 'tabMine', 'desktopWidgetSettings', 'appearanceSettings', 'appearanceOption', 'userCard',
    'sessionSheet', 'sessionCampusButton', 'moreShortcut', 'moreSectionTitle', 'classReminderSettings'];
  for (const name of pilot) {
    const source = builder(home, name);
    assert.deepEqual(offGrid(source), [], `${name}: spacing off the 4 vp grid`);
    assert.deepEqual(literalFontSizes(source), [], `${name}: font size literals`);
    assert.deepEqual(literalRadii(source), [], `${name}: radius literals`);
    assert.deepEqual(hexColors(source), [], `${name}: hex colors`);
  }
  // More rows, status tags and sheet buttons go through the shared components.
  const more = builder(home, 'tabMine');
  assert.ok((more.match(/HitaListRow\(\{/g) || []).length >= 12);
  assert.doesNotMatch(home, /moreNavigationRow/);
  assert.match(builder(home, 'eventRow'), /HitaTag\(\{ text: Home\.todayChipText/);
  assert.match(builder(home, 'todayExamCard'), /HitaTag\(\{ text: Home\.examDistanceText\(exam, this\.nowTick\), tone: HitaTagTone\.EXAM \}\)/);
  assert.match(builder(home, 'sessionSheet'), /HitaTag\(\{ text: this\.sessionSheetStatus/);
  // List group headings are quieter than the 22 fp page title.
  assert.match(builder(home, 'moreSectionTitle'),
    /\.fontSize\(HitaDesign\.caption\)\s*\.fontWeight\(FontWeight\.Medium\)\s*\.fontColor\(COLOR_TEXT_SECONDARY\)/);
  // Panel headers share one text action.
  for (const file of ['pages/ExamPage.ets', 'pages/ScorePage.ets', 'feature/learning/LearningTasksPanel.ets']) {
    const source = read(file);
    assert.match(source, /HeaderActionButton\(\{ label: '/, file);
    assert.match(source, /materialEnabled: /, file);
  }
});

test('flat content cards stay distinct from the light page while keeping the dark material look', () => {
  const card = read('common/components/ImmersiveEventCard.ets');
  const face = card.indexOf("$r('app.color.hita_immersive_card_base')");
  const material = card.indexOf('ImmersiveHeader({ barHeight: this.contentHeight })');
  assert.ok(face > 0 && face < material, 'the solid face is drawn beneath the material');
  const color = mode => JSON.parse(fs.readFileSync(path.resolve(root, `../resources/${mode}/element/color.json`), 'utf8'))
    .color.find(item => item.name === 'hita_immersive_card_base').value;
  assert.equal(color('base'), '#FFFFFF');
  assert.match(color('dark'), /^#00[0-9A-F]{6}$/i);
});

// Repository-wide counts after every page and sheet moved onto the scale (first audit: 186, 43, 123, 183). What is
// left sits in the exempt Canvas, Dock and desktop-card drawing code. New code must not raise them; lower a number when
// a change removes loose values. Raising one to let new code pass defeats the check.
const BASELINE = { offGridSpacing: 11, literalFontSizes: 20, literalRadii: 14, hexColors: 158 };

// Drawing code whose sizes follow the canvas, the dock painter or the desktop card rather than the page scale.
const DRAWING_EXEMPT = ['common/components/DockRail.ets', 'common/components/FrostedDock.ets',
  'feature/timetable/views/CourseColorEditor.ets', 'feature/widget/WidgetBackgroundPage.ets',
  'widget/pages/NextClassCard.ets'];

test('every page, sheet and dialog outside the drawing exemptions is fully on the scale', () => {
  const loose = [];
  for (const { file, text } of sources) {
    if (DRAWING_EXEMPT.includes(file)) continue;
    const found = [...offGrid(text).map(value => 'spacing ' + value), ...literalFontSizes(text), ...literalRadii(text)];
    if (found.length > 0) loose.push(file + ': ' + found.join(', '));
  }
  assert.deepEqual(loose, []);
});

test('loose spacing, font sizes, radii and hex colors only go down', () => {
  const counts = { offGridSpacing: 0, literalFontSizes: 0, literalRadii: 0, hexColors: 0 };
  for (const { text } of sources) {
    counts.offGridSpacing += offGrid(text).length;
    counts.literalFontSizes += literalFontSizes(text).length;
    counts.literalRadii += literalRadii(text).length;
    counts.hexColors += hexColors(text).length;
  }
  for (const key of Object.keys(BASELINE)) {
    assert.ok(counts[key] <= BASELINE[key],
      `${key}: ${counts[key]} > baseline ${BASELINE[key]}. Use HitaDesign / HitaColors tokens (docs/design-system.md).`);
  }
});
