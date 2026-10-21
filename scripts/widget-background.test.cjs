const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
function load(file) {
  const mod = { exports: {} };
  const code = ts.transpileModule(read(file), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  new Function('require', 'module', 'exports', code)(() => ({}), mod, mod.exports);
  return mod.exports;
}
const { WidgetBackgroundModel: M } = load('feature/widget/WidgetBackgroundModel.ets');
const near = (a, b) => assert.ok(Math.abs(a - b) < 1e-6, `${a} != ${b}`);

test('placement keeps the image ratio: cover fills the card, contain shows the whole image', () => {
  const cover = M.place(M.coverFrame(), 400, 200, 100, 100);
  near(cover.width / cover.height, 2);
  near(cover.height, 100);
  near(cover.left, -50);
  const contain = M.place(M.containFrame(400, 200, 100, 100), 400, 200, 100, 100);
  near(contain.width, 100);
  near(contain.height, 50);
  near(contain.top, 25);
  near(M.minScale(400, 200, 100, 100), 0.5);
});

test('pan follows the finger and stops at the card edge; zoom keeps the pinch point fixed', () => {
  const start = M.coverFrame();
  near(M.place(M.pan(start, 20, 0, 400, 200, 100, 100), 400, 200, 100, 100).left, -30);
  near(M.pan(start, 500, 0, 400, 200, 100, 100).x, 0);
  const zoomed = M.zoom(start, 2, 50, 50, 50, 50, 400, 200, 100, 100);
  near(zoomed.scale, 2);
  const placed = M.place(zoomed, 400, 200, 100, 100);
  near((50 - placed.left) / placed.width, 0.5);
  near((50 - placed.top) / placed.height, 0.5);
  assert.equal(M.withScale(start, 99, 400, 200, 100, 100).scale, 4);
});

test('the same frame gives the same framing in the preview and the baked output', () => {
  const frame = M.frame(1.6, 0.2, 0.7);
  const small = M.place(frame, 3000, 2000, 150, 150);
  const large = M.place(frame, 3000, 2000, 600, 600);
  near(small.left / 150, large.left / 600);
  near(small.width / 150, large.width / 600);
  const region = M.bakeRegion(M.containFrame(400, 200, 600, 600), 400, 200, 600, 600);
  assert.deepEqual([region.destX, region.destY, region.destW, region.destH], [0, 150, 600, 300]);
  assert.deepEqual([region.srcX, region.srcY, region.srcW, region.srcH], [0, 0, 400, 200]);
});

test('orientation, veil and stored state are parsed defensively', () => {
  assert.equal(M.orientationCode('6'), 6);
  assert.equal(M.orientationCode('Right-top'), 6);
  assert.equal(M.orientationCode('Left-bottom'), 8);
  assert.equal(M.orientationCode('?'), 1);
  assert.equal(M.veilChannel(0, 30), 77);
  assert.equal(M.veilChannel(200, 0), 200);
  assert.equal(M.parseState('{"revision":1,"source":"../x","sourceWidth":1,"sourceHeight":1}'), undefined);
  const state = M.parseState('{"revision":5,"source":"source-5.jpg","sourceWidth":10,"sourceHeight":20,' +
    '"veil":500,"compact":{"scale":9,"x":2,"y":-1}}');
  assert.equal(state.veil, 80);
  assert.deepEqual([state.compact.scale, state.compact.x, state.compact.y], [4, 1, 0]);
  assert.equal(state.wide.scale, 1);
});

test('card uses the documented background attributes; More expands into two single-option rows', () => {
  const card = read('widget/pages/NextClassCard.ets');
  assert.match(card, /\.backgroundImage\(this\.backgroundSource\(\)\)/);
  assert.match(card, /\.backgroundImageSize\(ImageSize\.Cover\)/);
  assert.match(card, /\.borderRadius\(\$r\('sys\.float\.ohos_id_corner_radius_card'\)\)/);
  assert.match(card, /\.clip\(true\)/);
  assert.match(card, /'memory:\/\/' \+ name/);
  // backgroundImageResizable is not available in ArkTS widgets and would stretch the image.
  assert.doesNotMatch(card, /backgroundImageResizable|onAreaChange/);
  const service = read('feature/widget/NextClassWidgetService.ets');
  assert.match(service, /payload\.formImages = images/);
  assert.match(service, /finally \{\s*NextClassWidgetService\.close\(opened\)/);
  const home = read('pages/Home.ets');
  const menu = home.slice(home.indexOf('  desktopWidgetSettings() {'), home.indexOf('  appearanceSettings() {'));
  assert.match(menu, /this\.widgetMenuExpanded = !this\.widgetMenuExpanded/);
  assert.ok(menu.indexOf("'设置桌面服务卡片'") < menu.indexOf("'自定义背景'"));
  assert.match(menu, /this\.openWidgetBackgroundSheet\(\)/);
  assert.match(menu, /this\.openDesktopWidgetManager\(\)/);
  assert.doesNotMatch(read('pages/WidgetBackgroundPage.ets'), /bindSheet/);
});

test('background editor uses a size segment and gates immersive materials and light to API 26', () => {
  const page = read('pages/WidgetBackgroundPage.ets');
  // The size segment is the course editor's 具体时间/按节次 control, so both behave identically on every API.
  assert.match(page, /CourseModeSegment\(\{\s*labels: \['2×2 卡片', '2×4 卡片'\]/);
  assert.match(page, /onControlPressingChanged: \(pressing: boolean\) => \{ this\.sizeControlPressing = pressing; \}/);
  assert.match(page, /\.zIndex\(this\.sizeControlPressing \? 3 : 1\)/);
  assert.doesNotMatch(page, /TabSegmentButtonV2|ImmersiveWidgetBackgroundSizeSegment/);
  // API 26 renders button materials only inside the course editor's native title host.
  assert.match(page, /CourseControlHost\(\{ barHeight: 40, itemWeight: 1 \}\) \{\s*ImmersiveFollowButton\(\{ label: label, isEnabled: !this\.busy, onPress: action \}\)/);
  assert.match(page, /CourseControlHost\(\{ barHeight: 40 \}\) \{\s*ImmersiveFollowButton\(\{\s*label: this\.busy \? '正在读取…' : '从图库选择'/);
  assert.equal((page.match(/if \(this\.usesApi26ImmersiveControls\(\)\) \{\s*(\/\/.*\s*)?(Column\(\) \{\s*)?CourseControlHost/g) || []).length, 2);
  assert.match(page, /apiAvailable\('26\.0\.0'\) && !deviceInfo\.apiAvailable\('27\.0\.0'\)/);
  assert.match(page, /getNumberByName\('ohos_id_corner_radius_card'\)/);
  assert.match(page, /borderRadius\(this\.cardCornerRadius\)/);
  assert.doesNotMatch(page, /borderRadius\(this\.cardCornerRadius \* this\.mockScale\(\)\)/);
  assert.doesNotMatch(page, /拖动调整位置，双指缩放；缩小后空白处保留卡片底色。|100% 为刚好铺满卡片；数值越小，图片显示得越完整。|卡片文字为深色，图片较暗或较杂时适当加深蒙版。两种尺寸共用此设置。/);
  assert.match(page, /private adjustmentsScroller: Scroller = new Scroller\(\)/);
  assert.match(page, /HeaderFade\.opacity\(this\.adjustmentsScroller\.currentOffset\(\)\.yOffset\)/);
  assert.match(page, /HeaderFadeMask\(\{ maskOpacity: this\.adjustmentsFadeOpacity, rgb: '246,247,250' \}\)/);
  assert.match(read('common/components/HeaderFadeMask.ets'), /\.hitTestBehavior\(HitTestMode\.None\)/);
  assert.doesNotMatch(page, /sizeOption\(/);
  const controls = read('feature/widget/ImmersiveWidgetBackgroundControls.ets');
  // Buttons follow the Button spec through sub-styles rather than hand-set sizes.
  assert.match(controls, /Button\(this\.label, \{ type: ButtonType\.Capsule \}\)/);
  assert.match(controls, /buttonStyle\(this\.primary \? ButtonStyleMode\.EMPHASIZED : ButtonStyleMode\.NORMAL\)/);
  assert.match(controls, /controlSize\(ControlSize\.NORMAL\)/);
  // The emphasized fill is also the material colour, so low-power devices keep a legible blue button.
  assert.match(controls, /new CompatibleMaterialModifier\(\s*\$r\('app\.color\.hita_primary_fill'\), true, true, \$r\('app\.color\.hita_primary_fill'\), false\)/);
  // Busy states toggle isEnabled; a material that switched off with it would reset the fill to the Button default blue.
  assert.match(controls, /new CompatibleMaterialModifier\(\s*\$r\('app\.color\.hita_surface_soft'\), false, true, undefined, false\)/);
  assert.match(controls, /\.attributeModifier\(this\.primary \? this\.emphasizedMaterial : this\.normalMaterial\)/);
  assert.doesNotMatch(controls, /CompatibleMaterialModifier\([^)]*this\.isEnabled/);
  assert.match(controls, /\.enabled\(this\.isEnabled\)/);
  assert.match(controls, /fontColor\(this\.primary \? \$r\('sys\.color\.font_on_primary'\) : HitaColors\.primary\)/);
  assert.doesNotMatch(controls, /hita_immersive_hero_tint|Color\.White/);
  assert.match(controls, /\.onClick\(\(\) => this\.onPress\(\)\)/);
});

test('empty state is unboxed and the adjustment fade spans the sheet width', () => {
  const page = read('pages/WidgetBackgroundPage.ets');
  const empty = page.slice(page.indexOf('  emptyState() {'), page.indexOf('  @Builder\n  editor()'));
  assert.match(empty, /Text\('选择背景图'\)/);
  assert.doesNotMatch(empty, /为桌面服务卡片选择一张背景图|选好后可拖动、双指缩放/);
  assert.doesNotMatch(empty, /\.backgroundColor\(CARD_BG\)|\.borderRadius\(16\)/);

  const editor = page.slice(page.indexOf('  editor() {'), page.indexOf('  @Builder\n  sizeSelector()'));
  assert.match(editor, /this\.sizeSelector\(\)[\s\S]*?\.padding\(\{ left: 16, right: 16 \}\)\s*Stack\(\{ alignContent: Alignment\.Top \}\)/);
  assert.match(editor, /Scroll\(this\.adjustmentsScroller\)[\s\S]*?\.padding\(\{ left: 16, right: 16 \}\)[\s\S]*?HeaderFadeMask\(\{ maskOpacity: this\.adjustmentsFadeOpacity[\s\S]*?\.width\('100%'\)\s*\.layoutWeight\(1\)/);
});
