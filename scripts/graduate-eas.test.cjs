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
  const mod = { exports: {} };
  cache.set(file, mod);
  const req = name => {
    if (name === '@kit.PerformanceAnalysisKit') return { hilog: { info() {}, warn() {}, error() {} } };
    if (name.startsWith('@kit.')) return {};
    assert.ok(name.startsWith('.'), name);
    return load(path.resolve(path.dirname(file), name + '.ets'));
  };
  const js = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  new Function('require', 'module', 'exports', js)(req, mod, mod.exports);
  return mod.exports;
}
const { BenbuGraduateData: Benbu } = load('feature/eas/data/BenbuGraduateData.ets');
const { WeihaiGraduateRecords: Weihai } = load('feature/eas/data/WeihaiGraduateRecords.ets');
const { EasApiClient: Client } = load('feature/eas/EasApiClient.ets');
const { EasSession, EasCampus } = load('feature/eas/EasSession.ets');
const { EasTermItem } = load('feature/eas/model/EasModels.ets');
const { ExamSchedule } = load('feature/eas/ExamSchedule.ets');

function currentTerm() {
  return Object.assign(new EasTermItem(), {
    yearCode: '2026-2027', termCode: '1', yearName: '2026-2027学年', termName: '秋季', isCurrent: true
  });
}

function session(campus) {
  const value = new EasSession();
  value.campus = campus;
  value.setStudentType('2');
  value.webCookies.set('JSESSIONID', 'portal-session');
  return value;
}

function reply(body, statusCode = 200, location = '', cookies = '') {
  return { body: typeof body === 'string' ? body : JSON.stringify(body), statusCode, location, cookies };
}

const profile = { isSuccess: true, module: { data: { XH: 'SYNTH101' } } };
const origin = 'http://gcourse-hit-edu-cn.vpn.hit.edu.cn:1080';
const monday = {
  JCMC: '5,6',
  MON: '<a>计算方法</a>◇教师甲[1-5周(单)]虚构楼101，教师乙[2-6周(双)]虚构楼202[5,6]节',
  TUES: '算法导论[1-4周]虚构楼303[教师丙，必修]'
};

test('Benbu grad imports distinct alternating weeks and uses the graduate bell schedule', () => {
  const rows = Benbu.parseTimetable(JSON.stringify([monday]));
  assert.deepEqual(rows.map(row => [row.name, row.dayOfWeek, row.beginSection, row.sectionCount,
    row.weekNumbers, row.teacher, row.classroom, row.courseProperty]), [
    ['计算方法', 1, 5, 2, [1, 3, 5], '教师甲', '虚构楼101', ''],
    ['计算方法', 1, 5, 2, [2, 4, 6], '教师乙', '虚构楼202', ''],
    ['算法导论', 2, 5, 2, [1, 2, 3, 4], '教师丙', '虚构楼303', '必修']
  ]);
  assert.equal(Benbu.schedule()[4].from.hour, 14);
  assert.throws(() => Benbu.parseTimetable('<html>请登录</html>'), /无法识别/);
  assert.throws(() => Benbu.parseTimetable(JSON.stringify([{ JCMC: '1,2', MON: monday.MON }])), /无法识别/);
});

test('Benbu grad bridges through school course host and keeps its session separate from portal', async () => {
  const requests = [];
  const client = new Benbu({ request: async (_session, cfg, endpoint, options) => {
    assert.equal(cfg.studentType, '2');
    requests.push([endpoint, options.method]);
    if (endpoint.includes('getXsJbxx')) return reply(profile);
    assert.equal(endpoint, '/yjsgl/outInterface/grkb');
    return reply('', 302, origin + '/to-welcome?credential=sample');
  } });
  const original = Client.doHttp;
  const value = session(EasCampus.BENBU);
  Client.doHttp = async (url, method, headers) => {
    requests.push([url, method]);
    if (url.includes('/to-welcome')) {
      assert.equal(headers.get('Cookie'), '');
      return reply('', 302, '/kbgl/queryxskbxsy', 'gcourse\tFALSE\t/\tFALSE\t0\tJSESSIONID\tcourse-session');
    }
    assert.equal(headers.get('Cookie'), 'JSESSIONID=course-session');
    if (url.endsWith('/queryxskbxsy')) return reply('<html>课表</html>');
    assert.equal(url, origin + '/kbgl/queryXsckcb?xh=SYNTH101&xnxq=2026-20271&ys=1');
    return reply([monday]);
  };
  try {
    assert.equal((await client.courses(value, currentTerm())).length, 3);
    assert.equal(requests.length, 5);
    assert.equal(value.webCookies.get('JSESSIONID'), 'portal-session');
    const unexpected = new Benbu({ request: async (_session, _config, endpoint) =>
      endpoint.includes('getXsJbxx') ? reply(profile) : reply('', 302, 'https://example.invalid/') });
    await assert.rejects(unexpected.courses(value, currentTerm()), /课程系统连接失败/);
    assert.equal(requests.length, 5);
  } finally {
    Client.doHttp = original;
  }
});

test('Benbu grad distinguishes a grade table filtered by semester from the undated official table', async () => {
  const value = session(EasCampus.BENBU);
  const current = currentTerm();
  const oldTerm = '2025-2026学年春季学期';
  const versioned = '<table><tr><th>课程名称</th><th>总成绩</th><th>学年学期</th></tr>' +
    '<tr><td>甲</td><td>85.5</td><td>202620271</td></tr>' +
    '<tr><td>乙</td><td>合格</td><td>' + oldTerm + '</td></tr></table>';
  const unversioned = '<table><tr><th>课程名称</th><th>成绩</th></tr>' +
    '<tr><td>乙</td><td>合格</td></tr></table>';
  assert.equal(Benbu.gradeTerm(oldTerm), '2025-20262');
  const terms = Benbu.parseTerms(JSON.stringify({ data: [
    { xnxq: '2025-20262' }, { xnxq: current.getCode(), current: true }
  ] }));
  assert.equal(terms[0].getCode(), current.getCode());
  assert.equal(terms[0].isCurrent, true);
  const client = new Benbu({ request: async (_session, _config, endpoint) =>
    endpoint.includes('getXsJbxx') ? reply(profile) : reply('', 302, origin + '/xscjb/queryXscjbByXh?xh=SYNTH101') });
  const original = Client.doHttp;
  try {
    Client.doHttp = async () => reply(versioned);
    let result = await client.grades(value, current);
    assert.equal(result.includesAllTerms, false);
    assert.deepEqual(result.items.map(item => item.courseName), ['甲']);
    Client.doHttp = async () => reply(unversioned);
    result = await client.grades(value, current);
    assert.equal(result.includesAllTerms, true);
    assert.equal(result.items[0].finalScoresText, '合格');
  } finally {
    Client.doHttp = original;
  }
});

test('Weihai grad sends student level and only exposes published grades', async () => {
  const client = new Weihai({ request: async (_session, _config, path, options) => {
    assert.equal(path, '/cjgl/grcjcx/grcjcx');
    assert.equal(options.weihaiRefererPath, '/cjgl/grcjcx/go/2');
    assert.equal(options.extraHeaders.get('RoleCode'), '02');
    assert.deepEqual(JSON.parse(options.body), {
      xn: '2026-2027', xq: '1', kcmc: null, cxbj: '-1', pylx: '2', current: 1, pageSize: 20, sffx: null
    });
    const list = [
      { kcmc: '课程甲', kcdm: 'A01', xscj: '合格', xszscj: '', zzzscj: '99' },
      { kcmc: '课程乙', kcdm: 'A02', xscj: '89.5', xszscj: '89.5', zzzscj: '95' }
    ];
    return reply({ code: 0, content: { total: 2, pageNum: 1, pageSize: 2, list } });
  } });
  const grades = await client.grades(session(EasCampus.WEIHAI), currentTerm());
  assert.equal(grades[0].finalScoresText, '合格');
  assert.equal(grades[0].finalScores, -1);
  assert.equal(grades[1].finalScoresText, '89.5');
});

test('Weihai grad exams complete all pages and reject duplicates before schedule sync', async () => {
  const pages = [];
  let duplicate = false;
  const example = { KCMC: '教学示例', KCDM: 'G001', PYLX: '2', KSRQ2: '2026-12-20',
    KSJTSJ: '09:00-11:00', JXLMC: '虚构楼', CDMC: '101' };
  const periodOnly = { ...example, KCDM: 'G002', KSJTSJ: '', KSJC: 3, JSJC: 4 };
  const client = new Weihai({ request: async (_session, _config, path, options) => {
    assert.equal(path, '/kscxtj/queryXsksByxhList');
    const args = new URLSearchParams(options.body);
    assert.equal(args.get('ppylx'), '2');
    assert.equal(args.get('pxn'), '2026-2027');
    const pageNum = Number(args.get('pageNum'));
    pages.push(pageNum);
    return reply({ pageNum, pageSize: 1, total: 2, list: [pageNum === 1 || duplicate ? example : periodOnly] });
  } });
  const value = session(EasCampus.WEIHAI);
  const items = await client.exams(value, currentTerm());
  assert.deepEqual(pages, [1, 2]);
  assert.equal(items[0].examLocation, '虚构楼 101');
  assert.equal(items[1].examTime, '第3-4节');
  assert.equal(ExamSchedule.toEvent(items[1], 'table', 'WEIHAI:GRAD:2026-20271/'), undefined);
  assert.ok(ExamSchedule.toEvent(items[0], 'table', 'WEIHAI:GRAD:2026-20271/'));
  duplicate = true;
  await assert.rejects(client.exams(value, currentTerm()), /未返回完整/);
});

test('Weihai grad classroom requests the selected week and refuses uncertain occupancy', async () => {
  let broken = false;
  const positions = [
    { CDDM: '001', XQJ: '1', XJ: '2', PKBJ: '排', JYBJ: null, PKJYBJ: '0', PKSB: null, JYSB: null },
    { CDDM: '001', XQJ: '2', XJ: '3', PKBJ: null, JYBJ: '借', PKJYBJ: '0', PKSB: null, JYSB: null },
    { CDDM: '001', XQJ: '3', XJ: '4', PKBJ: null, JYBJ: null, PKJYBJ: null, PKSB: null, JYSB: null }
  ];
  const client = new Weihai({ request: async (_session, _config, path, options) => {
    if (path === '/pksd/queryjxlList') return reply([{ DM: 'A', MC: '虚构楼' }]);
    const args = new URLSearchParams(options.body);
    assert.equal(args.get('zc'), '7');
    assert.equal(args.get('jxl'), 'A');
    if (path === '/cdkb/querycdzyleftzhou') {
      assert.equal(args.get('pageNum'), '1');
      return reply({ pageNum: 1, pageSize: 20, total: 1, list: [{ DM: '001', MC: '101', ZWS: '30' }] });
    }
    assert.equal(path, '/cdkb/querycdzyrightzhou');
    assert.equal(args.has('pageNum'), false);
    return reply(broken ? [{ ...positions[0], PKSB: '1' }] : positions);
  } });
  const value = session(EasCampus.WEIHAI);
  const [building] = await client.buildings(value);
  const [classroom] = await client.classrooms(value, currentTerm(), building, 7);
  assert.equal(classroom.capacity, 30);
  assert.equal(classroom.occupied.length, 2);
  broken = true;
  await assert.rejects(client.classrooms(value, currentTerm(), building, 7));
});
