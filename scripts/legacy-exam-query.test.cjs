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
const { LegacyWebExams: Parser } = load('feature/eas/data/LegacyWebExams.ets');
const { EasDataProvider: Provider } = load('feature/eas/EasDataProvider.ets');
const { EasSession, EasCampus: Campus } = load('feature/eas/EasSession.ets');
const { EasTermItem } = load('feature/eas/model/EasModels.ets');
const { ExamSchedule } = load('feature/eas/ExamSchedule.ets');
const { EasApiClient: Client } = load('feature/eas/EasApiClient.ets');
const { EasCampusUrls: Urls } = load('feature/eas/webLogin/EasWebLoginConfig.ets');
const term = () => Object.assign(new EasTermItem(), {
  yearCode: '2026-2027', termCode: '1', yearName: '2026-2027学年', termName: '秋季', isCurrent: true
});
function session(campus) {
  const s = new EasSession();
  s.campus = campus;
  s.webCookies.set('JSESSIONID', 'synthetic-session-for-test');
  return s;
}
const headers = ['序号', '课程名称', '课程代码', '考试地点', '座位号', '考试具体时间', '考试时间段'];
const cells = (values, tag = 'td') => '<tr>' + values.map(v => `<${tag}>${v}</${tag}>`).join('') + '</tr>';
const row = (time = '2026年12月20日(第16周 星期日)09:00-11:00', name = '数学分析（2）',
  place = '正心楼-正心21') => ['1', name, 'SYNTH101', place, '', time, ''];
function html(rows = [row()], head = headers) {
  return '<table class="bot_line">' + cells(head, 'th') + rows.map(r => cells(r)).join('') + '</table>';
}
const response = (body, statusCode = 200) => ({ body, statusCode });
const parse = (body, type = '期末', campus = '本部') => Parser.parse(body, term(), type, campus);

test('Benbu seven-column and Weihai six-column tables map the same fields as Android', () => {
  const benbu = parse(html())[0];
  assert.equal(benbu.courseName, '数学分析（2）');
  assert.equal(benbu.examLocation, '正心楼-正心21');
  assert.equal(benbu.examDate, '2026-12-20');
  assert.equal(benbu.examTime, '09:00-11:00');
  assert.equal(benbu.termName, '2026-2027学年秋季');
  assert.equal(benbu.campusName, '本部');
  const weihai = parse(html([row().slice(0, 6)], headers.slice(0, 6)), '补考', '威海校区')[0];
  assert.equal(weihai.examType, '补考');
  assert.equal(weihai.examDate, benbu.examDate);
  assert.equal(weihai.campusName, '威海校区');
});

test('semantic headers handle reordered columns and never confuse the period with the actual date/time', () => {
  const order = [2, 6, 5, 3, 1, 4, 0];
  const remap = values => order.map(i => values[i]);
  const body = '<table><tr><td>navigation</td></tr></table>' +
    html([remap(row())], remap(headers)).replace(/th>/g, 'td>');
  const item = parse(body)[0];
  assert.equal(item.courseName, '数学分析（2）');
  assert.equal(item.examTime, '09:00-11:00');
});

test('HTML text is decoded, preserving course names and removing encoded spaces in classroom cells', () => {
  const item = parse(html([row('2026年5月9日<br>8：30－10：00',
    '<a>信号<span>与</span>系统 &amp; 实验</a>', '&amp;nbsp;M楼&#160;118&nbsp;&#x20;')]))[0];
  assert.equal(item.courseName, '信号与系统 & 实验');
  assert.equal(item.examLocation, 'M楼 118');
  assert.equal(item.examDate, '2026-05-09');
  assert.equal(item.examTime, '08:30-10:00');
});

test('only recognized exam tables may produce an empty result', () => {
  assert.deepEqual(parse(html([])), []);
  assert.deepEqual(parse(html([]).replace('</table>', '<tr><td colspan="7">暂无考试安排</td></tr></table>')), []);
  for (const body of ['', '<html>服务维护中</html>', '<table class="bot_line"></table>',
    '<table><tr><th>课程名称</th><th>成绩</th></tr></table>',
    html([]).replace('</table>', '<tr><td colspan="7">服务不可用</td></tr></table>'),
    '<script>' + html([]) + '</script>', '<!--' + html([]) + '-->']) {
    assert.throws(() => parse(body), /考试页面无法识别/);
  }
});

test('malformed rows cannot silently become partial or empty success', () => {
  for (const broken of [row().slice(0, 4), row().map((v, i) => i === 1 ? '' : v)]) {
    assert.throws(() => parse(html([row(), broken])), /考试页面无法识别/);
  }
  assert.throws(() => parse(html().replace('</table>',
    '<tr><td colspan="7">暂无数据</td></tr></table>')), /考试页面无法识别/);
});

test('unknown or invalid date/time text stays visible but cannot create a scheduled exam', () => {
  for (const raw of ['待通知', '', '2026年12月20日 时间另行通知', '2026-12-20 09:00',
    '2026年02月30日 09:00-11:00', '2026年12月20日 24:00-26:00',
    '2026年12月20日 09:80-11:00', '2026年12月20日 11:00-09:00']) {
    const item = parse(html([row(raw)]))[0];
    assert.equal(item.examTime, raw);
    assert.equal(ExamSchedule.toEvent(item, 'current'), undefined);
  }
});

test('valid leap dates and hour ranges are accepted; invalid dates never roll into another day', () => {
  for (const [date, time] of [['2028-02-29', '08:00-09:00'], ['2026/5/9', '8:30～10:00']]) {
    assert.ok(ExamSchedule.parseRange(date, time));
  }
  for (const [date, time] of [['2026-02-29', '08:00-09:00'], ['2026-04-31', '08:00-09:00'],
    ['2026-12-20', '08:00'], ['2026-12-20', '08:00-08:00'], ['2026-12-20', '09:70-11:00']]) {
    assert.equal(ExamSchedule.parseRange(date, time), undefined);
  }
});

for (const campus of [Campus.BENBU, Campus.WEIHAI]) {
  test(`${campus}: queries all three periods with the reference endpoint, method, headers and term`, async () => {
    const calls = [];
    const source = session(campus);
    const provider = new Provider({
      request: async (s, cfg, endpoint, options) => {
        assert.equal(s, source);
        assert.equal(cfg.campus, campus);
        const query = new URLSearchParams(campus === Campus.BENBU ? endpoint.split('?')[1] : options.body);
        assert.equal(query.get('xnxq'), '2026-20271');
        const period = query.get('kssjd');
        calls.push(period);
        assert.match(options.extraHeaders.get('Accept'), /text\/html/);
        assert.equal(options.timeoutMs, 20000);
        if (campus === Campus.BENBU) {
          assert.match(endpoint, /^\/kscx\/queryKcForXs1\?/);
          assert.equal(options.method, 'GET');
          assert.equal(options.body, '');
        } else {
          assert.equal(endpoint, '/kscx/queryKcForXs');
          assert.equal(options.method, 'POST');
          assert.equal(options.extraHeaders.get('Origin'), Urls.WEIHAI_BASE);
          assert.equal(options.extraHeaders.get('Referer'), Urls.WEIHAI_EAS_PREFIX + endpoint);
        }
        return response(html([row(), row()]));
      }
    });
    const result = await provider.getExamResult(source, term());
    assert.deepEqual(calls, ['01', '02', '03']);
    assert.equal(result.items.length, 3, 'duplicate rows removed within each period, not across exam types');
    assert.deepEqual(result.items.map(x => x.examType), ['期末', '期中', '补考']);
    assert.deepEqual(result.failedTypes, []);
  });
}

test('legacy query returns known partial results with failed types, never hides failed categories', async () => {
  let index = 0;
  const provider = new Provider({ request: async () => {
    index++;
    return index === 1 ? response(html()) : index === 2 ? response('', 500) : response(html([]));
  } });
  const result = await provider.getExamResult(session(Campus.WEIHAI), term());
  assert.equal(result.items.length, 1);
  assert.deepEqual(result.failedTypes, ['期中']);
});

test('three valid empty tables succeed, while three failures produce an error', async () => {
  const s = session(Campus.BENBU);
  const empty = await new Provider({ request: async () => response(html([])) }).getExamResult(s, term());
  assert.deepEqual(empty.items, []);
  assert.deepEqual(empty.failedTypes, []);
  for (const res of [response('', 0), response('maintenance', 503), response('<html>portal</html>')]) {
    await assert.rejects(new Provider({ request: async () => res }).getExamResult(s, term()));
  }
});

test('authentication failures abort immediately even if other exam periods have already loaded', async () => {
  for (const expired of [response('', 401), response('', 302),
    response("<form action='/login'><input type='password' name='password'></form>"),
    response('<script>top.location.href="/loginCAS";</script>'), response('会话已过期，请重新登录')]) {
    let count = 0;
    const provider = new Provider({ request: async () => ++count === 1 ? response(html()) : expired });
    await assert.rejects(provider.getExamResult(session(Campus.BENBU), term()), /会话已失效/);
    assert.equal(count, 2);
  }
  // A plain 403 is a refusal, not a sign-in page: that period is reported as failed and the others still load.
  let count = 0;
  const refused = new Provider({ request: async () => ++count === 1 ? response(html()) : response('', 403) });
  const partial = await refused.getExamResult(session(Campus.BENBU), term());
  assert.equal(partial.items.length, 1, 'the period that loaded keeps its exam');
  assert.ok(partial.failedTypes.length > 0);
});

test('ordinary menu links to loginCAS do not make a valid exam table look expired', async () => {
  const provider = new Provider({ request: async () =>
    response('<a href="/loginCAS">教务首页</a>' + html()) });
  assert.equal((await provider.getExamResult(session(Campus.WEIHAI), term())).items.length, 3);
});

test('exam terms come from the exam page and retain the selected term, including older current terms', async () => {
  const body = '<select name="xnxq"><option value="2026-20272">2027春季</option>' +
    '<option value="2026-20271" selected>2026秋季</option></select>';
  const provider = new Provider({ request: async () => response(body) });
  provider.getAllTerms = async () => assert.fail('Do not replace the exam page selection with registration terms');
  const terms = await provider.getExamTerms(session(Campus.BENBU));
  assert.equal(terms.find(t => t.isCurrent).getCode(), '2026-20271');
});

test('missing exam term options fall back to the existing term loader; expired sessions do not', async () => {
  const provider = new Provider({ request: async () => response(html([])) });
  provider.getAllTerms = async () => [term()];
  assert.equal((await provider.getExamTerms(session(Campus.WEIHAI)))[0].getCode(), '2026-20271');
  provider.api = { request: async () => response('', 401) };
  await assert.rejects(provider.getExamTerms(session(Campus.WEIHAI)), /会话已失效/);
});

test('POST-only deployments use the normal term list and the Aura exam form on a definite GET rejection', async () => {
  const calls = [];
  const provider = new Provider({ request: async (_s, _cfg, endpoint, options) => {
    calls.push({ endpoint, options });
    if (options.method === 'GET') return response('', 405);
    assert.equal(endpoint, '/kscx/queryKcForXs1');
    assert.equal(new URLSearchParams(options.body).get('xnxq'), '2026-20271');
    return response(html());
  } });
  provider.getAllTerms = async () => [term()];
  const s = session(Campus.BENBU);
  assert.equal((await provider.getExamTerms(s))[0].getCode(), '2026-20271');
  const result = await provider.getExamResult(s, term());
  assert.equal(result.items.length, 3);
  assert.equal(calls.filter(x => x.options.method === 'POST').length, 3);
});

test('missing terms, missing web cookies and unsupported graduate sessions cannot issue requests', async () => {
  const provider = new Provider({ request: async () => assert.fail('Invalid request') });
  await assert.rejects(provider.getExamResult(session(Campus.BENBU), undefined), /学期/);
  await assert.rejects(provider.getExamResult(session(Campus.BENBU), new EasTermItem()), /学期/);
  const loggedOut = session(Campus.WEIHAI);
  loggedOut.webCookies.clear();
  await assert.rejects(provider.getExamResult(loggedOut, term()), /会话/);
  for (const campus of [Campus.BENBU, Campus.WEIHAI]) {
    const graduate = session(campus);
    graduate.setStudentType('2');
    await assert.rejects(provider.getExamTerms(graduate), /研究生考试接口暂未接入/);
    await assert.rejects(provider.getExamResult(graduate, term()), /研究生考试接口暂未接入/);
  }
});

test('the existing client uses the correct VPN host and sends saved cookies for both campuses', async () => {
  const original = Client.doHttp;
  const calls = [];
  Client.doHttp = async (url, method, headers, body) => {
    calls.push({ url, method, headers, body });
    return response(html([]));
  };
  try {
    for (const campus of [Campus.BENBU, Campus.WEIHAI]) {
      await new Provider(new Client()).getExamResult(session(campus), term());
    }
    assert.equal(calls.length, 6);
    for (const c of calls) {
      assert.equal(c.headers.get('Cookie'), 'JSESSIONID=synthetic-session-for-test');
      assert.match(c.headers.get('User-Agent'), /Macintosh/);
    }
    assert.ok(calls[0].url.startsWith(Urls.JWTS_BASE + '/kscx/queryKcForXs1?'));
    assert.ok(calls[3].url.startsWith(Urls.WEIHAI_EAS_PREFIX + '/kscx/queryKcForXs'));
  } finally {
    Client.doHttp = original;
  }
});

test('Shenzhen uses its web exam endpoint through the shared result wrapper', async () => {
  const s = session(Campus.SHENZHEN);
  s.webCookies.set('route', 'synthetic-route');
  s.webBaseUrl = Urls.SHENZHEN_PROXY_BASE;
  const calls = [];
  const provider = new Provider({ request: async (_session, _cfg, endpoint) => {
    calls.push(endpoint);
    return response(JSON.stringify({ code: 0, content: { list: [{
      kcmc: '线性代数', ksrq: '2026-12-20', kssj: '09:00-11:00', kscd: 'T1-101'
    }] } }));
  } });
  const result = await provider.getExamResult(s, term());
  assert.equal(result.items[0].examLocation, 'T1-101');
  assert.equal(result.items[0].campusName, '深圳校区');
  assert.deepEqual(result.failedTypes, []);
  assert.equal(calls[0], '/kscxtj/queryXsksByxhList');
});
