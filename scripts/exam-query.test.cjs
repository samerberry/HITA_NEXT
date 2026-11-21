const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const root = path.resolve(__dirname, '../entry/src/main/ets');

function load(file, mocks = {}, cache = new Map()) {
  file = path.resolve(root, file);
  if (cache.has(file)) return cache.get(file).exports;
  const source = fs.readFileSync(file, 'utf8');
  const mod = { exports: {} };
  cache.set(file, mod);
  const compiled = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const localRequire = name => {
    if (name in mocks) return mocks[name];
    if (name.startsWith('@kit.')) return {};
    assert.ok(name.startsWith('.'), `Unexpected platform import ${name}`);
    return load(path.resolve(path.dirname(file), name + '.ets'), mocks, cache);
  };
  new Function('require', 'module', 'exports', compiled)(localRequire, mod, mod.exports);
  return mod.exports;
}

const { EasEventType } = load('common/model/timetable/TimetableModels.ets');
const { EasExamItem, EasTermItem } = load('feature/eas/model/EasModels.ets');
const { parseShenzhenWebExams } = load('feature/eas/data/ShenzhenWebExams.ets');
const { ExamSchedule } = load('feature/eas/ExamSchedule.ets');
const { EasDataProvider } = load('feature/eas/EasDataProvider.ets', {
  '@kit.PerformanceAnalysisKit': { hilog: { info() {}, warn() {}, error() {} } }
});
const { EasSession, EasCampus } = load('feature/eas/EasSession.ets');

function term() {
  const item = new EasTermItem();
  item.yearCode = '2026-2027';
  item.yearName = '2026-2027学年';
  item.termCode = '1';
  item.termName = '秋季';
  return item;
}

const webExam = {
  KCMC: '合成测试课程', KSRQ: '2026-12-19T16:00:00Z', KSJTSJ: '09:00-11:00',
  KSSJDMC: '期末', JXLMC: '测试楼', JXCDMC: 'A101', ZWH: '12'
};

test('Shenzhen web exams preserve Android fields, China date and room/seat information', () => {
  for (const body of [JSON.stringify([webExam]), JSON.stringify({ rows: [webExam], total: 1 }),
    JSON.stringify({ code: 200, data: { list: [webExam] } })]) {
    const item = parseShenzhenWebExams(body, term()).list[0];
    assert.equal(item.examDate, '2026-12-20');
    assert.equal(item.examTime, '09:00-11:00');
    assert.equal(item.examType, '期末');
    assert.equal(item.examLocation, '测试楼 A101 座位 12');
    assert.ok(ExamSchedule.parseRange(item.examDate, item.examTime));
  }
});

test('only recognized empty exam lists count as no exams', () => {
  for (const body of ['[]', '{"rows":[],"total":0}', '{"code":200,"content":{"list":[]}}']) {
    assert.deepEqual(parseShenzhenWebExams(body, term()).list, []);
  }
  for (const body of ['<html>maintenance</html>', '{}', '{"message":"service unavailable"}',
    '{"rows":[{"unknown":"value"}]}', JSON.stringify({ rows: [webExam, {}] }),
    '{"rows":[null]}']) {
    assert.equal(parseShenzhenWebExams(body, term()), undefined);
  }
});

function webSession() {
  const session = new EasSession();
  session.campus = EasCampus.SHENZHEN;
  session.webBaseUrl = 'https://synthetic-jw.example';
  session.webCookies.set('SESSION', 'synthetic-session');
  return session;
}

test('Shenzhen requests the Android web exam endpoint with its form and referer', async () => {
  const calls = [];
  const provider = new EasDataProvider({ async request(session, cfg, endpoint, options) {
    calls.push({ endpoint, options });
    return { statusCode: 200, body: JSON.stringify({ rows: [webExam], total: 1 }) };
  } });
  const result = await provider.getExamResult(webSession(), term());
  assert.equal(calls.length, 1);
  assert.equal(calls[0].endpoint, '/kscxtj/queryXsksByxhList');
  const options = calls[0].options;
  assert.equal(options.method, 'POST');
  assert.deepEqual(Object.fromEntries(new URLSearchParams(options.body)), {
    pxn: '2026-2027', pxq: '1', pageNum: '1', pageSize: '500'
  });
  assert.match(options.extraHeaders.get('Content-Type'), /^application\/x-www-form-urlencoded/);
  assert.equal(options.extraHeaders.get('Referer'), 'https://synthetic-jw.example/kscxtj/queryXsksByxh');
  assert.equal(options.useCache, false);
  assert.equal(result.items.length, 1);
  assert.equal(result.items[0].campusName, '深圳校区');
});

test('Shenzhen failures never masquerade as an empty result or an expired ordinary 403', async () => {
  for (const [response, expected] of [
    [{ statusCode: 0, body: '' }, /考试请求网络失败/],
    [{ statusCode: 403, body: 'Forbidden' }, /教务考试查询暂不可用/],
    [{ statusCode: 500, body: 'Error' }, /教务考试查询暂不可用/],
    [{ statusCode: 401, body: '' }, /会话已失效/],
    [{ statusCode: 200, body: '{"code":401,"msg":"未登录"}' }, /会话已失效/],
    [{ statusCode: 200, body: '{"code":500,"rows":[]}' }, /考试页面无法识别/],
    [{ statusCode: 200, body: '{}' }, /考试页面无法识别/]
  ]) {
    let calls = 0;
    const provider = new EasDataProvider({ async request() { calls++; return response; } });
    await assert.rejects(provider.getExamResult(webSession(), term()), expected);
    assert.equal(calls, 1);
  }
});

test('shenzhen exam parser reads content.list and semantic field aliases', () => {
  const body = JSON.stringify({
    code: 0,
    msg: 'ok',
    content: {
      list: [{
        kcmc: '大学物理',
        ksrq: '2026-12-18',
        kssjms: '14:00-16:00',
        kscd: 'T4-203',
        kslxmc: '期末考试',
        xnxqmc: '2026-2027学年秋季'
      }]
    }
  });
  const parsed = parseShenzhenWebExams(body, term());
  assert.equal(parsed.list.length, 1);
  assert.equal(parsed.list[0].courseName, '大学物理');
  assert.equal(parsed.list[0].examLocation, 'T4-203');
  assert.equal(parsed.list[0].examType, '期末考试');
  assert.equal(parsed.list[0].termName, '2026-2027学年秋季');
});

test('exam schedule parses Chinese dates and countdown labels', () => {
  const range = ExamSchedule.parseRange('2026年12月20日', '9:00-11:00');
  assert.ok(range);
  assert.equal(ExamSchedule.dateOf(range[0]), '2026-12-20');
  assert.equal(ExamSchedule.timeOf(range[0]), '09:00');
  assert.equal(ExamSchedule.timeOf(range[1]), '11:00');
  const now = new Date(2026, 11, 18, 8).getTime();
  assert.equal(ExamSchedule.remainingLabel(range[0], range[1], now), '还有 2 天');
  assert.equal(ExamSchedule.remainingLabel(range[0], range[1], range[0] + 1000), '进行中');
  assert.equal(ExamSchedule.remainingLabel(range[0], range[1], range[1] + 1000), '已结束');
});

test('imported exams keep source identity when the school changes their time or room', () => {
  const item = Object.assign(new EasExamItem(), {
    courseName: '线性代数',
    examDate: '2026-12-20',
    examTime: '09:00-11:00',
    examLocation: 'A-101',
    examType: '期末'
  });
  const source = 'SHENZHEN:2026-20271/';
  const event = ExamSchedule.toEvent(item, 'current', source);
  assert.equal(event.type, EasEventType.EXAM);
  assert.equal(event.timetableId, 'current');
  assert.equal(event.place, 'A-101');
  assert.equal(event.examSource, ExamSchedule.sourceKey(source, { ...item, examDate: '2026-12-22' }));
  assert.notEqual(event.examSource, ExamSchedule.sourceKey(source, { ...item, examType: '补考' }));
});
