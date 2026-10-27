const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');

test('timetable photo picker copies a gallery image and covers the page without stretching', () => {
  const store = read('feature/timetable/data/TimetableBackgroundStore.ets');
  assert.match(store, /picker\.PhotoViewPicker/);
  assert.match(store, /PhotoViewMIMETypes\.IMAGE_TYPE/);
  assert.match(store, /maxSelectNumber = 1/);
  assert.match(store, /await fileIo\.copyFile/);
  assert.match(store, /unlinkSync/);
  assert.match(store, /timetable-background\.jpg/);

  const home = read('pages/Home.ets');
  const tab = home.slice(home.indexOf('  tabTimetable()'), home.indexOf('  tabMine()'));
  assert.match(tab, /sys\.symbol\.picture/);
  assert.match(tab, /sys\.symbol\.slider_horizontal_2/);
  assert.doesNotMatch(tab, /sys\.symbol\.camera|Text\('A'\)/);
  assert.match(tab, /this\.canOpenSheet\(\)[\s\S]*this\.timetableDisplayOpen = true;[\s\S]*this\.activeSheetVisible = true;/);
  assert.match(tab, /this\.onTimetableBackgroundTap\(\)/);
  assert.match(home, /text: '选择图片作为壁纸'/);
  assert.match(home, /text: '移除壁纸'/);
  assert.match(home, /showActionMenu/);
  assert.match(home, /this\.removeTimetableBackground\(\)/);
  assert.match(home, /TimetableBackgroundStore\.remove/);
  assert.match(tab, /Image\(this\.timetableBgUri\)/);
  assert.match(tab, /objectFit\(ImageFit\.Cover\)/);
  assert.match(tab, /hitTestBehavior\(HitTestMode\.None\)/);
  assert.match(tab, /expandSafeArea\(\[SafeAreaType\.SYSTEM\], \[SafeAreaEdge\.TOP, SafeAreaEdge\.BOTTOM\]\)/);
  assert.match(tab, /backgroundColor\(Color\.Transparent\)/);
  assert.match(tab, /accessibilityText\('时间表显示设置'\)/);
  assert.match(home, /TimetableDisplaySettings\([\s\S]*onTextColorSave:[\s\S]*this\.setTimetableTextColor\(color\)/);
  const display = read('feature/timetable/views/TimetableDisplaySettings.ets');
  assert.match(display, /CourseColorEditor\([\s\S]*textMode: this\.editing === 'text',[\s\S]*TimetableTheme\.PALETTE/);
  assert.match(home, /drawTimetableWeek\([\s\S]*hourHeight, 0, false, false, this\.timetableInk\('time'\), this\.darkMode, cardLayer, this\.timetableDisplay,\s*this\.timetableBackdrop, this\.hasTimetableBackground\(\), false\)/);
  assert.match(tab, /Image\(this\.timetableBgUri\)[\s\S]*backgroundColor\(Color\.Black\)[\s\S]*opacity\(this\.timetableMaskDepth \/ 100\)/);
  assert.match(tab, /\.backgroundColor\(COLOR_SURFACE\)/,
    'heading and grid share one theme resource instead of independently painted backgrounds');
  assert.match(tab, /timetableDateHeader\(\)/);
  assert.match(tab, /timetableDateHeader\(\)[\s\S]*backgroundColor\(Color\.Transparent\)/);
  // The campus and term line paints no chip on wallpapers and starts at the title's left edge.
  const term = tab.slice(tab.indexOf('Text(this.timetableCampusTerm())'), tab.indexOf('.maxLines(', tab.indexOf('Text(this.timetableCampusTerm())')));
  assert.doesNotMatch(term, /\.backgroundColor\(|\.padding\(/);

  const draw = read('feature/timetable/views/TimetableWeekDraw.ets');
  const header = draw.slice(draw.indexOf('function drawWeekHeader'), draw.indexOf('export function drawTimetableWeek('));
  assert.match(header, /if \(fillPage\) \{[\s\S]*fillRect\(x, 4, colW, headerH - 2\)/);
  assert.match(draw, /labelColor: string = ''/);

  const theme = read('common/theme/TimetableTheme.ets');
  const palette = /PALETTE: string\[\] = \[([\s\S]*?)\]/.exec(theme)[1];
  assert.match(palette, /'#14213D'/);
  assert.match(palette, /'#FFFFFF'/);
  assert.match(palette, /'#E53935'/);
  assert.match(palette, /'#FB8C00'/);
  assert.match(palette, /'#F9A825'/);
  assert.match(palette, /'#43A047'/);
  assert.match(palette, /'#00ACC1'/);
  assert.match(palette, /'#1E88E5'/);
  assert.match(palette, /'#8E24AA'/);
  assert.equal((palette.match(/'#[0-9A-Fa-f]{6}'/g) || []).length, 9);

  const colors = read('feature/timetable/data/TimetableSelectionStore.ets');
  assert.match(colors, /timetable_text_color/);
});
