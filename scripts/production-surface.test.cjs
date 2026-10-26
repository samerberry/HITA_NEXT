const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const root = path.resolve(__dirname, '..');
const etsRoot = path.join(root, 'entry/src/main/ets');
const cache = new Map();

// Execute the actual pure ArkTS modules; the app's UI still needs hvigor checks.
function loadEts(filename) {
  const file = path.resolve(etsRoot, filename);
  assert.ok(file.startsWith(etsRoot + path.sep));
  if (cache.has(file)) return cache.get(file).exports;
  const source = fs.readFileSync(file, 'utf8');
  const compiled = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const mod = { exports: {} };
  cache.set(file, mod);
  const localRequire = (specifier) => {
    assert.ok(specifier.startsWith('.'), `Unexpected platform dependency: ${specifier}`);
    return loadEts(path.resolve(path.dirname(file), specifier + '.ets'));
  };
  new Function('require', 'module', 'exports', compiled)(localRequire, mod, mod.exports);
  return mod.exports;
}

function allEts(dir = etsRoot) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const file = path.join(dir, entry.name);
    return entry.isDirectory() ? allEts(file) : entry.name.endsWith('.ets') ? [file] : [];
  });
}

const { TimetableResolver } = loadEts('feature/timetable/data/TimetableResolver.ets');
const { EasTimetable } = loadEts('common/model/timetable/TimetableModels.ets');
function table(code, startTime = 100) {
  const item = new EasTimetable();
  item.code = code;
  item.startTime = startTime;
  return item;
}
function database(timetables) {
  return { getTimetables: async () => timetables };
}

test('retired development routes and implementations are not shipped', () => {
  const routes = JSON.parse(fs.readFileSync(
    path.join(root, 'entry/src/main/resources/base/profile/main_pages.json'), 'utf8')).src;
  for (const name of ['Index', 'AboutPage', 'TimetablePreview', 'TimeLinePage', 'SubjectsPage', 'ProfilePage', 'SearchPage']) {
    assert.ok(!routes.includes(`pages/${name}`), name);
    assert.ok(!fs.existsSync(path.join(etsRoot, `pages/${name}.ets`)), name);
  }
  assert.ok(!fs.existsSync(path.join(etsRoot, 'feature/timetable/data/TimetableLocalDemo.ets')));
  for (const name of ['Home', 'ScorePage', 'ExamPage', 'AddEventPage',
    'TimetableManagerPage', 'TimetableDetailPage', 'ImportTimetablePage', 'NoticesPage']) {
    assert.ok(routes.includes(`pages/${name}`), name);
  }
});

test('production modules contain no generators or executable parser fixtures', () => {
  const forbidden = /\b(TimetableLocalDemo|seedDemo|runSelfCheck|runParserSelfCheck|testShenzhenScoreParser|testShenzhenTimetableParser|SHENZHEN_SCORES_SAMPLE|SHENZHEN_TIMETABLE_SAMPLE)\b/;
  for (const file of allEts()) {
    const source = fs.readFileSync(file, 'utf8');
    assert.doesNotMatch(source, forbidden, file);
    if (path.dirname(file) === path.join(etsRoot, 'pages')) {
      assert.doesNotMatch(source, /生成.*演示|载入样例|加载样例|LOCAL_DEMO_001/, file);
    }
  }
});

test('today empty state has no login or timetable management actions', () => {
  const home = fs.readFileSync(path.join(etsRoot, 'pages/Home.ets'), 'utf8');
  const empty = home.indexOf('  emptyToday()');
  assert.ok(empty >= 0 && home.indexOf('  eventRow(', empty) > empty, 'emptyToday precedes eventRow');
  const today = home.slice(empty, home.indexOf('  eventRow(', empty));
  assert.match(today, /还没有可展示的课表/);
  assert.doesNotMatch(today, /emptyTimetableActions|Button\(|openSessionSheet|pushUrl/);
  // The hero card and the exam card are also on the Today tab; neither offers account or import actions.
  const hero = home.slice(home.indexOf('  todayHeroCard()'), home.indexOf('  todaySectionHeader()'));
  assert.doesNotMatch(hero, /emptyTimetableActions|openSessionSheet|ImportTimetablePage|TimetableManagerPage/);
});

test('timetable empty state and more page retain timetable workflows', () => {
  const home = fs.readFileSync(path.join(etsRoot, 'pages/Home.ets'), 'utf8');
  assert.equal((home.match(/this\.emptyTimetableActions\(\)/g) || []).length, 1);
  const timetable = home.slice(home.indexOf('  tabTimetable()'), home.indexOf('  statusBanner('));
  assert.match(timetable, /this\.emptyTimetableActions\(\)/);
  const actions = home.slice(home.indexOf('  emptyTimetableActions()'), home.indexOf('  tabTimetable()'));
  assert.match(actions, /pages\/ImportTimetablePage/);
  assert.match(actions, /pages\/TimetableManagerPage/);
  assert.match(actions, /if \(this\.sessionInfo === undefined\) \{\s*this\.openSessionSheet\(\);/);
  assert.match(home, /selected !== undefined \? selected/);
});

test('local search and its empty section are not reachable or shipped', () => {
  for (const file of allEts()) {
    assert.doesNotMatch(fs.readFileSync(file, 'utf8'), /SearchPage|本地搜索|moreSectionTitle\('课程资源'\)/, file);
  }
  const home = fs.readFileSync(path.join(etsRoot, 'pages/Home.ets'), 'utf8');
  const more = home.slice(home.indexOf('  tabMine()'), home.indexOf('  userCard()'));
  for (const label of ['最近课表', '课表管理', '导入课表', '考试', '成绩管理', '空教室', '公告']) {
    assert.ok(more.includes(label), label);
  }
});

test('classroom lookup opens the query page as a sheet from More and keeps its route', () => {
  const home = fs.readFileSync(path.join(etsRoot, 'pages/Home.ets'), 'utf8');
  assert.match(home, /'空教室',\s*'[^']*', \(\) => \{\s*this\.openAcademicPanel\(4\);/);
  assert.match(home, /this\.academicPanelKind === 4\) \{\s*EmptyClassroomPage\(\{ presentedAsSheet: true, onClose: \(\) => this\.closeActiveSheet\(\) \}\)/);
  // The standalone route stays registered for direct navigation.
  const pages = JSON.parse(fs.readFileSync(path.join(etsRoot, '../resources/base/profile/main_pages.json'), 'utf8'));
  assert.ok(pages.src.includes('pages/EmptyClassroomPage'));
});

test('academic errors expose only known user messages, never internal diagnostics', () => {
  const { EasUserMessages } = loadEts('feature/eas/EasUserMessages.ets');
  const fallback = '导入课表失败，请稍后重试';
  for (const detail of [
    'SQLite: Generic error',
    'HTTP 500: <html>server error</html>',
    'EAS_SCORES_ENDPOINT_NOT_CAPTURED: internal/endpoint-config.txt',
    'C:\\Users\\developer\\project\\internal.ets',
    '',
    'unexpected response'
  ]) {
    assert.equal(EasUserMessages.fromError(detail, fallback), fallback);
  }
  assert.equal(EasUserMessages.fromError(' 深圳教务会话已失效，请重新登录 ', fallback),
    '教务登录已过期，请重新登录后重试');
  assert.equal(EasUserMessages.fromError('当前校区暂不支持成绩查询', fallback),
    '当前校区暂不支持成绩查询，请到学校教务网站查看');
  assert.equal(EasUserMessages.fromError('课表请求网络失败', fallback),
    '无法连接教务系统，请检查网络后重试');
  assert.equal(EasUserMessages.fromError('本地课表数据库写入失败，请重试', fallback),
    '课表保存失败，请重试');
});

test('import results omit course matching diagnostics and retain internal logs', () => {
  const importer = fs.readFileSync(path.join(etsRoot, 'feature/eas/EasTimetableImporter.ets'), 'utf8');
  assert.doesNotMatch(importer, /catalogDiag|课程属性 计划/);
  assert.match(importer, /hilog\.info\([\s\S]*?fetched\.diag/);
  assert.match(importer, /message = '已导入 ' \+ readback\.length\.toString\(\) \+ ' 个课次'/);
  assert.match(importer, /EasUserMessages\.fromError/);
  const provider = fs.readFileSync(path.join(etsRoot, 'feature/eas/EasDataProvider.ets'), 'utf8');
  assert.doesNotMatch(provider, /EAS_SCORES_ENDPOINT_NOT_CAPTURED|抓包回填/);
});

test('new courses use an explicit/current timetable, never a generated fallback', () => {
  const editor = fs.readFileSync(path.join(etsRoot, 'pages/AddEventPage.ets'), 'utf8');
  assert.match(editor, /ev\.timetableId = this\.timetableId/);
  assert.match(editor, /await selection\.load\(\)/);
  assert.match(editor, /TimetableResolver\.getForDisplay\(rdb\)/);
  assert.doesNotMatch(editor, /getTimetableByEasCode/);
});

test('a fresh installation stays empty without creating sample records', async () => {
  assert.equal(await TimetableResolver.getForDisplay(database([])), undefined);
});

test('legacy generated records are not automatic fallbacks and are not deleted', async () => {
  const legacy = table('LOCAL_DEMO_001');
  const rows = [legacy];
  assert.equal(await TimetableResolver.getForDisplay(database(rows)), undefined);
  assert.equal(await TimetableResolver.getRecent(database(rows), 200), undefined);
  assert.equal(rows.length, 1);
  assert.equal(rows[0], legacy);
});

test('imported and manual timetables still resolve correctly', async () => {
  const legacy = table('LOCAL_DEMO_001');
  const local = table('LOCAL:manual');
  const imported = table('WEIHAI:2026-2027:1');
  assert.equal(await TimetableResolver.getForDisplay(database([legacy, local, imported])), imported);
  assert.equal(await TimetableResolver.getForDisplay(database([legacy, local])), local);
  assert.equal(TimetableResolver.isLocal(local), true);
});

test('recent timetable selection skips future imported terms', async () => {
  const future = table('WEIHAI:future', 1000);
  const started = table('WEIHAI:started', 100);
  assert.equal(await TimetableResolver.getRecent(database([future, started]), 200), started);
});

test('score parsing works without runtime sample/self-check exports', () => {
  const scores = loadEts('feature/eas/data/ShenzhenWebScores.ets');
  const { EasTermItem } = loadEts('feature/eas/model/EasModels.ets');
  const term = new EasTermItem();
  term.yearName = '2026-2027';
  term.termName = '-1';
  const result = scores.parseShenzhenWebScores(JSON.stringify({
    code: 0,
    content: { list: [
      { kcdm: 'T1', kcmc: 'Course A', xscj: '92', xf: 4 },
      { kcdm: 'T2', kcmc: 'Course B', xscj: 'Pass', xf: 3.5 },
      { kcdm: 'T3', kcmc: 'Course C', zzcj: '88', xf: 2 }
    ] }
  }), term);
  assert.equal(result.list.length, 3);
  assert.deepEqual(result.list.map(item => item.finalScores), [92, -1, 88]);
  assert.equal(result.list[1].credits, 3.5);
  assert.equal(result.list[2].termName, term.name);
  assert.equal(scores.parseShenzhenWebScores('', term), undefined);
  assert.equal(scores.testShenzhenScoreParser, undefined);
});

test('timetable parsing retains week expansion and metadata lookup', () => {
  const parser = loadEts('feature/eas/data/ShenzhenWebTimetableParser.ets');
  const meta = new parser.ShenzhenSubjectMeta();
  meta.key = 'A1';
  meta.code = 'TEST101';
  meta.name = 'Course A';
  const result = parser.parseShenzhenWebTimetable(JSON.stringify({
    content: [{ list: [
      { KSJC: '1', JSJC: '2', XQJ: '1', ZC: '1-16', RWH: 'A1', SKSJ: 'Course A [Teacher][A101]' },
      { KSJC: 5, JSJC: 6, XQJ: 3, ZC: '0100000000000000000', RWH: 'A2', SKSJ: 'Course B [Teacher][B202]' }
    ] }]
  }), [meta]);
  assert.equal(result.length, 2);
  assert.equal(result[0].name, 'Course A');
  assert.equal(result[0].code, 'TEST101');
  assert.equal(result[0].weekNumbers.length, 16);
  // Shenzhen's week bitset reserves index zero, matching the Android parser.
  assert.deepEqual(result[1].weekNumbers, [1]);
  assert.equal(parser.parseShenzhenWebTimetable('invalid', []), undefined);
  assert.equal(parser.testShenzhenTimetableParser, undefined);
});

test('the repository notice feed contains no developer examples', () => {
  const feed = JSON.parse(fs.readFileSync(path.join(root, 'notices.json'), 'utf8'));
  assert.ok(Array.isArray(feed.notices));
  for (const notice of feed.notices) {
    assert.ok(!['hello-2026', 'example-critical'].includes(notice.id));
    assert.doesNotMatch(notice.title + notice.body, /示例公告|示例：重要通知/);
  }
});

test('the window fills the status bar instead of leaving a white top inset', () => {
  const ability = fs.readFileSync(path.join(etsRoot, 'entryability/EntryAbility.ets'), 'utf8');
  assert.match(ability, /setWindowLayoutFullScreen\(true\)/);
  assert.match(ability, /AppearanceStore\.getInstance\(\)\.attachWindow\(mainWindow\)/);
  const appearance = fs.readFileSync(path.join(etsRoot, 'common/theme/AppearanceStore.ets'), 'utf8');
  assert.match(appearance, /setWindowBackgroundColor\(dark \? '#101214' : '#F5F6F8'\)/);
  assert.match(appearance, /statusBarColor: '#00000000'/);
  const colors = fs.readFileSync(path.join(root, 'entry/src/main/resources/base/element/color.json'), 'utf8');
  assert.match(colors, /"name": "start_window_background"[\s\S]*?"value": "#F5F6F8"/);
  const home = fs.readFileSync(path.join(etsRoot, 'pages/Home.ets'), 'utf8');
  const tabPage = home.slice(home.indexOf('function tabPage'), home.indexOf('class TimetableMarqueeCallback'));
  assert.match(tabPage, /SafeAreaEdge\.BOTTOM/);
  assert.doesNotMatch(tabPage, /SafeAreaEdge\.TOP/);
  const tab = home.slice(home.indexOf('  tabTimetable()'), home.indexOf('  statusBanner('));
  assert.match(tab, /Image\(this\.timetableBgUri\)[\s\S]*SafeAreaEdge\.TOP, SafeAreaEdge\.BOTTOM/);
  assert.match(home, /new CompatibleDockModifier\(12 \+ this\.navBarInset,/);
  assert.match(ability, /captureSystemInsets/);
  assert.match(ability, /TYPE_NAVIGATION_INDICATOR/);
  assert.match(ability, /TYPE_KEYBOARD/);
  assert.match(ability, /captureKeyboardInset/);
  assert.match(ability, /hita_keyboard_vp|KEYBOARD_INSET_KEY/);
  assert.match(home, /setKeyboardAvoidMode\(KeyboardAvoidMode\.NONE\)/);
  assert.match(home, /setKeyboardAvoidMode\(KeyboardAvoidMode\.OFFSET\)/);
  assert.match(home, /SafeAreaType\.KEYBOARD/);
  assert.match(home, /padding\(\{ top: this\.statusBarInset \}\)/);
  assert.match(home, /\.tabPage\(0, Color\.Transparent\)/);
  assert.doesNotMatch(home, /AssistantTab|NewsTab/);
});

test('standalone assistant composer follows the keyboard without reserving a removed dock', () => {
  const assistant = fs.readFileSync(path.join(etsRoot, 'pages/AssistantPage.ets'), 'utf8');
  assert.doesNotMatch(assistant, /DOCK_CLEARANCE/);
  assert.match(assistant, /hita_keyboard_vp/);
  assert.match(assistant, /private inputBarBottom\(\): number/);
  assert.match(assistant, /return this\.navBarInset/);
  assert.match(assistant, /return this\.keyboardInset/);
  assert.match(assistant, /setKeyboardAvoidMode\(KeyboardAvoidMode\.NONE\)/);
  assert.match(assistant, /setKeyboardAvoidMode\(KeyboardAvoidMode\.OFFSET\)/);
  assert.match(assistant, /bottom: 8 \+ this\.inputBarBottom\(\)/);
  assert.match(assistant, /private dismissKeyboard\(\): void/);
  assert.match(assistant, /composerController\.stopEditing\(\)/);
  assert.match(assistant, /getFocusController\(\)\.clearFocus\(\)/);
  assert.match(assistant, /\.scrollBar\(BarState\.Off\)[\s\S]*this\.dismissKeyboard\(\)/);
  assert.doesNotMatch(assistant, /padding\(\{ left: 16, right: 16, top: 6, bottom: 8 \}\)/);
});
