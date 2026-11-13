const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const cache = new Map();
function load(file) {
  file = path.resolve(root, file);
  if (cache.has(file)) return cache.get(file).exports;
  let source = fs.readFileSync(file, 'utf8');
  if (file.endsWith('ScorePage.ets')) {
    source = source.slice(0, source.indexOf('\n  @Builder')) + '\n}';
    source = source.replace(/^@(Entry|Component)\r?\n/gm, '')
      .replace(/@(State|Prop|StorageProp)(\([^)]*\))?\s+/g, '')
      .replace(/(?:export\s+)?struct (ScorePage)/, 'export class $1');
  }
  const mod = { exports: {} }; cache.set(file, mod);
  const req = name => {
    if (name.startsWith('@kit.') || name.includes('/common/components/') || name.includes('/common/theme/StatusBarInset')) return {};
    assert.ok(name.startsWith('.'), name);
    return load(path.resolve(path.dirname(file), name + '.ets'));
  };
  const js = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText;
  new Function('require', 'module', 'exports', 'Scroller', js)(req, mod, mod.exports,
    class { currentOffset() { return { xOffset: 0, yOffset: 0 }; } });
  return mod.exports;
}
global.$r = name => name;
const scores = load('feature/eas/data/ScoreData.ets');
const { EasTermItem, EasCourseScoreItem } = load('feature/eas/model/EasModels.ets');
const { EasCampus: C, EasSession } = load('feature/eas/EasSession.ets');
const { ScoreService, ScoreQueryResult } = load('feature/eas/ScoreService.ets');
const term = Object.assign(new EasTermItem(), { yearCode: '2026-2027', termCode: '1', yearName: '2026-2027', termName: '秋' });
const T = scores.ScoreTestType;
const json = JSON.stringify;
const response = (body, statusCode = 200) => ({ statusCode, body: typeof body === 'string' ? body : json(body) });
const session = campus => Object.assign(new EasSession(), { campus, webBaseUrl: 'https://jw.hitsz.edu.cn', webCookies: new Map([['SESSION', 'fixture-only']]) });
const grade = (text, credits) => Object.assign(new EasCourseScoreItem(), { courseName: '测试课程', finalScoresText: text, credits });

test('campus/type selection preserves Android endpoints, term and retake parameters', () => {
  const all = scores.legacyScoreRequest(C.BENBU, term, T.ALL);
  assert.equal(all.path, '/xfj/queryListXfj');
  assert.equal(all.fields.get('pageXnxqks'), '2026-20271');
  assert.equal(all.fields.get('pageXnxqjs'), '2026-20271');
  for (const campus of [C.BENBU, C.WEIHAI]) {
    const normal = scores.legacyScoreRequest(campus, term, T.NORMAL);
    assert.equal(normal.path, '/cjcx/queryQmcj');
    assert.equal(normal.fields.get('pageBkcxbj'), campus === C.BENBU ? '0' : '');
    assert.equal(scores.legacyScoreRequest(campus, term, T.RETAKE).fields.get('pageBkcxbj'), '2');
    const middle = scores.legacyScoreRequest(campus, term, T.MIDTERM);
    assert.equal(middle.path, '/cjcx/queryQzcj');
    assert.equal(middle.fields.get('pageXnxq'), '2026-20271');
    assert.equal(middle.fields.has('pageBkcxbj'), false);
  }
});

const legacyTable = '<table><tr><th>学分</th><th>课程名称</th><th>最终成绩</th><th>课程代码</th></tr>' +
  '<tr><td>2.5</td><td>代数 &amp; 几何</td><td>89.5</td><td>MATH1002</td></tr></table>';
test('legacy parser uses named columns, preserves decimals, distinguishes empty from unrecognized', () => {
  const [item] = scores.parseLegacyScores(legacyTable, term);
  assert.equal(item.credits, 2.5); assert.equal(item.finalScores, 89.5);
  assert.equal(item.courseName, '代数 & 几何'); assert.equal(item.courseCode, 'MATH1002');
  assert.equal(item.termName, term.name);
  assert.deepEqual(scores.parseLegacyScores('<table><tr><td>课程名称</td><td>成绩</td></tr></table>', term), []);
  for (const raw of ['<form>统一登录</form>', '<html>500</html>', '{}', '<table><tr><td>未知表格</td></tr></table>']) {
    assert.equal(scores.parseLegacyScores(raw, term), undefined);
  }
});

test('official summaries preserve scope, missing values and supplied GPA/rank only', () => {
  const cumulative = scores.parseOfficialLegacySummary('<span id="pjxfj">87.35</span><span id="zrs">5 / 120</span>');
  assert.match(cumulative.scope, /累计/); assert.equal(cumulative.weightedAverage, '87.35');
  assert.equal(cumulative.rank, '5'); assert.equal(cumulative.total, '120'); assert.equal(cumulative.gpa, '');
  const current = scores.parseOfficialShenzhenSummary(json({ GPA: 3.7, PJXFJ: 88.1, PM: 5, ZRS: 120, HDXF: 0 }));
  assert.equal(current.gpa, '3.7'); assert.equal(current.rank, '5'); assert.equal(current.earnedCredits, '0');
  assert.equal(scores.parseOfficialShenzhenSummary('{}').available(), false);
});

test('local calculations exclude nonnumeric/pending grades from means, retain zero and fractional credits', () => {
  const stats = scores.localScoreStatistics([grade('90.5', 2.5), grade('60', 1), grade('0', 1), grade('通过', 2), grade('缓考', 3)]);
  assert.equal(stats.count, 5); assert.equal(stats.passed, 3); assert.equal(stats.failed, 1); assert.equal(stats.pending, 1);
  assert.equal(stats.passedCredits, 5.5); assert.equal(stats.numericCount, 3);
  assert.equal(stats.average, 150.5 / 3); assert.equal(stats.weightedAverage, 286.25 / 4.5);
  assert.equal(scores.localScoreStatistics([grade('优秀', 2)]).weightedAverage, -1);
  assert.equal(scores.numericScore('95分'), -1); assert.equal(scores.numericScore('101'), -1);
  const middle = scores.localScoreStatistics([grade('20', 3)], false);
  assert.equal(middle.average, 20); assert.equal(middle.failed, 0); assert.equal(middle.passedCredits, 0);
  assert.equal(scores.localScoreStatistics([grade('D', 2)]).pending, 1);
});

test('Shenzhen queries use student level, selected term and selected exam endpoint; official failure retains grades', async () => {
  const service = new ScoreService(); const seen = [];
  const s = session(C.SHENZHEN); s.setStudentType('2');
  service.api.request = async (_s, _cfg, url, options) => {
    seen.push([url, options]);
    if (url.endsWith('getgpa')) throw new Error('network');
    return response({ code: 0, content: { list: [{ kcmc: '课程', xscj: '89.5', xf: 2.5 }] } });
  };
  const result = await service.query(s, term, T.MIDTERM);
  assert.equal(seen[0][0], '/cjgl/grcjcx/qzcjcx');
  assert.deepEqual(JSON.parse(seen[0][1].body), { xn: '2026-2027', xq: '1', kcmc: '', pylx: '2', current: 1, pageSize: 1000 });
  assert.equal(seen[0][1].useCache, false); assert.equal(result.items[0].displayScore(), '89.5');
  assert.match(result.summaryMessage, /官方统计暂不可用/);
});

test('all campuses reject expired/error/unrecognized responses instead of reporting empty grades', async () => {
  for (const campus of [C.SHENZHEN, C.BENBU, C.WEIHAI]) {
    for (const resp of [response('{}'), response('server error', 500), response('login', 401)]) {
      const service = new ScoreService(); service.api.request = async () => resp;
      await assert.rejects(service.query(session(campus), term, T.NORMAL));
    }
  }
});

test('legacy grades and cumulative official summary use different requests; graduate unsupported is explicit', async () => {
  const service = new ScoreService(); const seen = [];
  service.api.request = async (_s, _cfg, url, options) => {
    seen.push([url, options]);
    return response(url === '/xfj/queryListXfj' ? '<span id="pjxfj">87.4</span>' : legacyTable);
  };
  const result = await service.query(session(C.WEIHAI), term, T.RETAKE);
  assert.match(seen[0][1].body, /pageBkcxbj=2/); assert.equal(seen[1][1].method, 'GET');
  assert.equal(result.summary.weightedAverage, '87.4'); assert.equal(result.items.length, 1);
  const graduate = session(C.BENBU); graduate.setStudentType('2');
  await assert.rejects(service.query(graduate, term, T.NORMAL), /研究生/);
});

function deferred() { let resolve, reject; const promise = new Promise((r, j) => { resolve = r; reject = j; }); return { promise, resolve, reject }; }
test('changing term/type discards old in-flight results and failures; leaving page discards late results', async () => {
  const { ScorePage } = load('pages/ScorePage.ets');
  const page = new ScorePage(); page.session = session(C.SHENZHEN); page.terms = [term];
  const old = deferred(), fresh = deferred(); let calls = 0;
  page.service = { query: () => calls++ === 0 ? old.promise : fresh.promise };
  page.fadeOpacity = 1;
  const a = page.queryReal(); page.typeIndex = 1; const b = page.queryReal();
  assert.equal(page.fadeOpacity, 0, 'refreshing must clear the previous scroll fade');
  const result = new ScoreQueryResult(); result.items = [grade('95', 3)];
  fresh.resolve(result); await b;
  old.reject(new Error('old request failed')); await a;
  assert.equal(page.scores[0].displayScore(), '95'); assert.equal(page.errorText, ''); assert.equal(page.loading, false);
  const last = deferred(); page.service = { query: () => last.promise };
  const c = page.queryReal(); page.onPageHide(); last.resolve(result); await c;
  assert.equal(page.queried, false); assert.equal(page.scores.length, 0);
});

test('score errors never reveal raw server content or internal paths', () => {
  assert.doesNotMatch(scores.scoreErrorMessage('HTTP 500 private/path user=abc'), /private|abc|500/);
  assert.match(scores.scoreErrorMessage('教务会话已失效，请重新登录'), /重新登录/);
});

test('evening hint includes exams, respects the displayed week and the 18:30 boundary', () => {
  const { hasEveningCourse, eveningHintVisible } = load('feature/timetable/data/EveningCourseHint.ets');
  const { eventsOfWeek } = load('feature/timetable/views/TimetableWeekDraw.ets');
  const { EasTimetable, EasEventItem, EasEventType } = load('common/model/timetable/TimetableModels.ets');
  const table = new EasTimetable(); table.startTime = new Date(2026, 9, 12).getTime();
  const event = (day, hour, minute) => Object.assign(new EasEventItem(), { type: EasEventType.CLASS, from: new Date(2026, 9, day, hour, minute).getTime() });
  const early = event(12, 18, 29), late = event(19, 18, 30);
  assert.equal(hasEveningCourse(eventsOfWeek(table, [early, late], 1)), false);
  assert.equal(hasEveningCourse(eventsOfWeek(table, [early, late], 2)), true);
  early.type = EasEventType.EXAM;
  late.type = EasEventType.EXAM;
  assert.equal(hasEveningCourse(eventsOfWeek(table, [early, late], 1)), false);
  assert.equal(hasEveningCourse(eventsOfWeek(table, [early, late], 2)), true);
  const onlyExam = event(12, 20, 0);
  onlyExam.type = EasEventType.EXAM;
  assert.equal(eveningHintVisible(hasEveningCourse([onlyExam]), 0, 300), true);
  assert.equal(eveningHintVisible(hasEveningCourse([onlyExam]), 236, 300), false);
  late.type = EasEventType.TAG;
  assert.equal(hasEveningCourse([late]), false);
  assert.equal(hasEveningCourse([]), false);
});

test('evening hint disappears near the bottom and when no scrolling or evening event remains', () => {
  const { eveningHintVisible } = load('feature/timetable/data/EveningCourseHint.ets');
  assert.equal(eveningHintVisible(true, 0, 300), true);
  assert.equal(eveningHintVisible(true, 235, 300), true);
  assert.equal(eveningHintVisible(true, 236, 300), false);
  assert.equal(eveningHintVisible(true, 300, 300), false);
  assert.equal(eveningHintVisible(true, 0, 0), false);
  assert.equal(eveningHintVisible(false, 0, 300), false);
});
