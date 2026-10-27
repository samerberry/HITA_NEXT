const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');
global.$r = name => ({ id: -1, type: 10001, params: [name] });
const root = path.resolve(__dirname, '../entry/src/main/ets');
const cache = new Map();
const nativeRequests = [];
let nativeResponse = {};
function load(file) {
  file = path.resolve(root, file);
  if (cache.has(file)) return cache.get(file).exports;
  const mod = { exports: {} }; cache.set(file, mod);
  const req = name => {
    if (name === '@kit.PerformanceAnalysisKit') return { hilog: { info() {}, warn() {}, error() {} } };
    if (name === '@kit.ArkTS') return { url: { URL } };
    if (name === '@kit.NetworkKit') return { http: {
      RequestMethod: { GET: 'GET', POST: 'POST' }, HttpDataType: { STRING: 'STRING' },
      createHttp: () => ({ request: async (url, options) => {
        nativeRequests.push({ url, options }); return nativeResponse;
      }, destroy() {} })
    } };
    if (name.startsWith('@kit.')) return {};
    return load(path.resolve(path.dirname(file), name + '.ets'));
  };
  const js = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  new Function('require', 'module', 'exports', js)(req, mod, mod.exports);
  return mod.exports;
}
const { BenbuExperimentParser: parser } = load('feature/eas/data/BenbuExperimentParser.ets');
const { BenbuExperimentService: service } = load('feature/eas/BenbuExperimentService.ets');
const { EasApiClient: api } = load('feature/eas/EasApiClient.ets');
const { EasSession, EasCampus } = load('feature/eas/EasSession.ets');
const { EasTermItem, EasCourseItem } = load('feature/eas/model/EasModels.ets');
const { EasDataProvider } = load('feature/eas/EasDataProvider.ets');
const { EasTimetableImporter: importer } = load('feature/eas/EasTimetableImporter.ets');
const { EasTimetable } = load('common/model/timetable/TimetableModels.ets');
const grid = cell => '<table class="dataTable"><tr><th>课表</th></tr><tr><th>星期</th></tr><tr>' +
  ['下午', '第7,8节', cell, '', '', '', '', '', ''].map(x => '<td>' + x + '</td>').join('') + '</tr></table>';
const fixture = grid('<a>用拉伸法测定弹性模量</a><br>姚凤凤&nbsp;[11周第7，8节] 上课形式[线下]L622，<span class="red">15:40-18:10</span>');
const electronic = data => JSON.stringify({ code: 0, data });
const row = { subjectName: '电路实验', classDate: '2026-10-20', startTime: '13:00:00', teacher: '张三', address: '301', labsName: '电路实验室' };
const session = () => Object.assign(new EasSession(), { campus: EasCampus.BENBU,
  webCookies: new Map([['JSESSIONID', 'eas'], ['HIT', 'vpn']]), electronicExpToken: 'fixture-jwt' });

test('HTML retains names inside anchors, teachers, weeks, locations and exact free times', () => {
  const [course] = parser.parseHtml(fixture);
  assert.equal(course.name, '用拉伸法测定弹性模量');
  assert.equal(course.teacher, '姚凤凤'); assert.equal(course.classroom, 'L622');
  assert.deepEqual(course.weekNumbers, [11]); assert.equal(course.dayOfWeek, 1);
  assert.equal(course.startTime, '15:40'); assert.equal(course.endTime, '18:10');
  assert.equal(course.beginSection, -1);
});

test('HTML handles combined lines, repeated details, multiple courses and period fallback', () => {
  const courses = parser.parseHtml(grid('弹性模量 姚凤凤 [11周第7,8节] 上课形式[线下]L622，15:40-18:10<br>' +
    '电学实验<br>张三 [12周第5，6节] 上课形式[线下]L619<br>李四 [13周第5，6节] 上课形式[线下]L620'));
  assert.equal(courses.length, 3); assert.equal(courses[0].name, '弹性模量');
  assert.equal(courses[1].name, '电学实验'); assert.equal(courses[2].name, '电学实验');
  assert.equal(courses[1].beginSection, 5); assert.equal(courses[1].sectionCount, 2);
  assert.deepEqual(parser.parseHtml('<form>登录</form>'), []);
});

test('electronic dates are authoritative; missing end defaults to two hours; bad rows are isolated', () => {
  const courses = parser.parseElectronic(electronic([null, { ...row, classDate: '2026-02-30' },
    { ...row, startTime: '25:00' }, row, { ...row, endTime: '18:10:00' }]));
  assert.equal(courses.length, 2); assert.equal(courses[0].scheduledDate, '2026-10-20');
  assert.equal(courses[0].dayOfWeek, 2); assert.equal(courses[0].endTime, '15:00');
  assert.equal(courses[1].endTime, '18:10'); assert.equal(courses[0].classroom, '301(电路实验室)');
  assert.deepEqual(parser.parseElectronic('{"code":1}'), []);
  assert.equal(parser.isElectronicResponse('{"code":"0","data":[]}'), true);
  for (const code of [undefined, null, 401]) {
    const payload = JSON.stringify({ code, data: [row] });
    assert.equal(parser.isElectronicResponse(payload), false);
    assert.deepEqual(parser.parseElectronic(payload), []);
  }
});

test('requests exchange isolated experiment cookies and preserve Android electronic headers', async () => {
  const original = api.doHttp; const calls = []; const s = session();
  api.doHttp = async (url, method, headers, body, timeout, useCache) => {
    calls.push({ url, method, headers, body, timeout, useCache });
    return url.endsWith('loginSygl') ? { statusCode: 200, cookies: 'JSESSIONID=lab; Path=/; HttpOnly, other=ok; SameSite=Lax', body: '' } :
      { statusCode: 200, body: url.includes('queryXszkb') ? fixture : electronic([row]) };
  };
  try {
    assert.equal((await service.getExperiments(s)).length, 1);
    assert.match(calls[0].url, /jwts.*\/loginsysj\/loginSygl$/);
    assert.match(calls[1].url, /sjjx.*\/xskb\/queryXszkb$/);
    assert.doesNotMatch(calls[1].headers.get('Cookie'), /JSESSIONID=/,
      'a cookie issued by the EAS origin is not a laboratory cookie');
    assert.match(calls[1].headers.get('Cookie'), /HIT=vpn/);
    assert.doesNotMatch(calls[1].headers.get('Cookie'), /Path|SameSite/);
    assert.equal(s.webCookies.get('JSESSIONID'), 'eas');
    assert.equal((await service.getElectronicExperiments(s)).length, 1);
    assert.equal(calls[2].method, 'POST'); assert.equal(calls[2].headers.get('VcTchToken'), 'fixture-jwt');
    assert.equal(calls[2].headers.get('VcTchType'), 'stu'); assert.equal(calls[2].useCache, false);
    s.electronicExpToken = ''; await service.getElectronicExperiments(s); assert.equal(calls.length, 3);
    api.doHttp = async () => { throw Error('offline'); };
    assert.deepEqual(await service.getExperiments(s), []);
    assert.equal(s.loginExpired, false);
  } finally { api.doHttp = original; }
});

test('captured WebView experiment cookies query the authorized target directly', async () => {
  const original = api.doHttp; const calls = []; const s = session();
  s.sjjxCookies = new Map([['JSESSIONID', 'web-lab'], ['HIT', 'vpn']]);
  api.doHttp = async (url, method, headers, body, timeout, useCache) => {
    calls.push({ url, method, cookie: headers.get('Cookie'), useCache });
    return { statusCode: 200, body: fixture };
  };
  try {
    assert.equal((await service.getExperiments(s)).length, 1);
    assert.equal(calls.length, 1);
    assert.match(calls[0].url, /sjjx.*\/xskb\/queryXszkb$/);
    assert.match(calls[0].cookie, /JSESSIONID=web-lab/);
    assert.equal(calls[0].useCache, false);
    assert.equal(s.webCookies.get('JSESSIONID'), 'eas');
  } finally { api.doHttp = original; }
});

test('an expired captured experiment session falls back without expiring the teaching session', async () => {
  const original = api.doHttp; const calls = []; const s = session();
  s.sjjxCookies = new Map([['JSESSIONID', 'expired-lab']]);
  api.doHttp = async url => {
    calls.push(url);
    return { statusCode: 200, body: calls.length === 1 ? '页面过期，请重新登录' : fixture };
  };
  try {
    assert.equal((await service.getExperiments(s)).length, 1);
    assert.equal(calls.length, 3);
    assert.match(calls[1], /jwts.*\/loginsysj\/loginSygl$/);
    assert.equal(s.loginExpired, false);
  } finally { api.doHttp = original; }
});

test('older saved sessions decode without an experiment cookie field', () => {
  const s = EasSession.decode(JSON.stringify({ campus: 'BENBU', webCookies: [{ k: 'JSESSIONID', v: 'eas' }] }));
  assert.equal(s.webCookies.get('JSESSIONID'), 'eas');
  assert.equal(s.sjjxCookies.size, 0);
});

test('Benbu can import experiment-only schedules; other campuses never query experiments', async () => {
  const original = api.doHttp; let count = 0;
  api.doHttp = async url => { count++; return { statusCode: 200, body: url.includes('queryXszkb') ? fixture : electronic([row]) }; };
  const provider = new EasDataProvider({ request: async () => ({ statusCode: 200, body: '<table class="addlist_01"></table>' }) });
  try {
    assert.equal((await provider.getTimetableOfTerm(session(), new EasTermItem())).length, 2);
    assert.equal(count, 3);
    const s = session(); s.campus = EasCampus.WEIHAI;
    await assert.rejects(provider.getTimetableOfTerm(s, new EasTermItem())); assert.equal(count, 3);
  } finally { api.doHttp = original; }
});

test('save pipeline persists exact experimental timestamps, deduplicates and keeps ordinary periods', async () => {
  let saved;
  const db = { getTimetableByEasCode: async () => undefined, getSubjectsOfTimetable: async () => [],
    saveImportedTimetable: async (table, subjects, events) => { saved = { table, subjects, events }; } };
  const courses = [...parser.parseHtml(fixture), ...parser.parseHtml(fixture), ...parser.parseElectronic(electronic([row])),
    Object.assign(new EasCourseItem(), { name: '普通课', dayOfWeek: 3, weekNumbers: [2], beginSection: 1, sectionCount: 2 })];
  await importer.saveCourses(db, session(), new EasTermItem(), courses,
    EasTimetable.getBenbuTimeStructure(), new Date(2026, 7, 24).getTime());
  assert.equal(saved.events.length, 3);
  const lab = saved.events.find(x => x.name === '用拉伸法测定弹性模量');
  assert.equal(lab.from, new Date(2026, 10, 2, 15, 40).getTime());
  assert.equal(lab.to, new Date(2026, 10, 2, 18, 10).getTime()); assert.equal(lab.fromNumber, -1);
  const ee = saved.events.find(x => x.name === '电路实验');
  assert.equal(ee.from, new Date(2026, 9, 20, 13).getTime()); assert.equal(ee.lastNumber, -1);
  assert.equal(saved.events.find(x => x.name === '普通课').fromNumber, 1);
});

test('rowspan period labels do not drop subsequent rows or shift weekdays', () => {
  const detail = '[11周第7，8节] 上课形式[线下]L622，15:40-18:10';
  const html = '<table class="dataTable"><tr><td rowspan="2">下午</td><td>第7,8节</td>' +
    ['弹性模量<br>姚凤凤 ' + detail, '', '', '', '', '', ''].map(x => '<td>' + x + '</td>').join('') +
    '</tr><tr><td>第9,10节</td>' + ['', '', '', '', '', '', '电学实验<br>张三 ' + detail]
      .map(x => '<td>' + x + '</td>').join('') + '</tr></table>';
  const courses = parser.parseHtml(html);
  assert.equal(courses.length, 2);
  assert.deepEqual(courses.map(x => x.dayOfWeek), [1, 7]);
});

test('split time lines and spaced teacher names keep their course identity and exact time', () => {
  const courses = parser.parseHtml(grid('大学物理实验<br>张 三、李 四 [11周第7，8节] 上课形式[线下]L622，' +
    '<br><span class="red">15:40-18:10</span><br>王五 [12周第7，8节] 上课形式[线下]L623，<br>16:00-18:10'));
  assert.equal(courses.length, 2);
  assert.deepEqual(courses.map(x => x.name), ['大学物理实验', '大学物理实验']);
  assert.equal(courses[0].teacher, '张 三、李 四');
  assert.deepEqual(courses.map(x => x.startTime), ['15:40', '16:00']);
});

test('multiple combined entries retain distinct experiment names and individual slots', () => {
  const courses = parser.parseHtml(grid('实验甲 张三 [11周第7，8节] 上课形式[线下]L621，15:40-18:10<br>' +
    '实验乙 李四 [11周第9，10节] 上课形式[线下]L622，18:45-20:30'));
  assert.deepEqual(courses.map(x => x.name), ['实验甲', '实验乙']);
  assert.deepEqual(courses.map(x => x.startTime), ['15:40', '18:45']);
});

test('rowspan course cells are not duplicated while later weekday columns stay aligned', () => {
  const first = '实验甲<br>张三 [11周第7，8节] 上课形式[线下]L621，15:40-18:10';
  const last = '实验乙<br>李四 [11周第9，10节] 上课形式[线下]L622，18:45-20:30';
  const html = '<table class=dataTable><tr><td>下午</td><td>第7,8节</td><td rowspan=2>' + first + '</td>' +
    '<td></td>'.repeat(6) + '</tr><tr><td>晚上</td><td>第9,10节</td>' + '<td></td>'.repeat(5) +
    '<td>' + last + '</td></tr></table>';
  const courses = parser.parseHtml(html);
  assert.deepEqual(courses.map(x => x.name), ['实验甲', '实验乙']);
  assert.deepEqual(courses.map(x => x.dayOfWeek), [1, 7]);
});

test('the experimental table is found inside layout tables just as with Android Jsoup', () => {
  const courses = parser.parseHtml('<table class="layout"><tr><td>' + fixture + '</td></tr></table>');
  assert.equal(courses.length, 1);
  assert.equal(courses[0].name, '用拉伸法测定弹性模量');
  assert.equal(courses[0].startTime, '15:40');
});

test('native HTTP exposes redirect location and all Set-Cookie values with API 23 redirect control', async () => {
  nativeRequests.length = 0;
  nativeResponse = { responseCode: 302, result: '', header: {
    Location: '/sso/callback', 'Set-Cookie': ['JSESSIONID=lab; Path=/', 'route=node; Path=/']
  } };
  const response = await api.doHttp(service.EXPERIMENT_BASE, 'GET', new Map(), '', 5000, false, false);
  assert.equal(nativeRequests[0].options.maxRedirects, 0);
  assert.equal(response.location, '/sso/callback');
  assert.match(response.cookies, /JSESSIONID=lab/); assert.match(response.cookies, /route=node/);
  await api.doHttp(service.EXPERIMENT_BASE, 'GET', new Map(), '', 5000);
  assert.equal(nativeRequests[1].options.maxRedirects, undefined, 'other EAS requests keep native defaults');
});

test('SSO redirects forward the laboratory cookie without replacing the EAS session', async () => {
  const original = api.doHttp; const calls = []; const s = session();
  api.doHttp = async (target, method, headers, body, timeout, cache, followRedirects) => {
    calls.push({ target, cookie: headers.get('Cookie'), followRedirects });
    if (target.endsWith('/loginsysj/loginSygl')) return { statusCode: 302, cookies: 'JSESSIONID=new-eas; Path=/',
      location: service.EXPERIMENT_BASE + '/sso?ticket=fixture' };
    if (target.includes('/sso?')) return { statusCode: 302, cookies: 'JSESSIONID=lab; Path=/; HttpOnly', location: '/home' };
    return { statusCode: 200, body: target.endsWith('/home') ? '<html>实验系统</html>' : fixture };
  };
  try {
    assert.equal((await service.getExperiments(s)).length, 1);
    assert.equal(calls.length, 4);
    assert.equal(calls[0].target, 'http://jwts-hit-edu-cn.vpn.hit.edu.cn:1080/loginsysj/loginSygl');
    assert.ok(calls.every(x => x.followRedirects === false));
    assert.doesNotMatch(calls[1].cookie, /JSESSIONID=/, 'do not send the teaching system session to the laboratory');
    assert.match(calls[2].cookie, /JSESSIONID=lab/); assert.match(calls[3].cookie, /JSESSIONID=lab/);
    assert.equal(s.webCookies.get('JSESSIONID'), 'eas');
  } finally { api.doHttp = original; }
});

test('an SSO request failure still attempts the laboratory schedule like Android', async () => {
  const original = api.doHttp; const calls = [];
  api.doHttp = async target => {
    calls.push(target);
    if (target.endsWith('loginSygl')) throw Error('auth bridge unavailable');
    return { statusCode: 200, body: fixture };
  };
  try {
    assert.equal((await service.getExperiments(session())).length, 1);
    assert.equal(calls.length, 2);
  } finally { api.doHttp = original; }
});

test('the migrated bridge does not forward cookies to unconfigured VPN origins', async () => {
  const original = api.doHttp;
  try {
    for (const location of [
      'http://unrelated.vpn.hit.edu.cn:1080/sso',
      'http://jwts-hit-edu-cn.vpn.hit.edu.cn:1081/sso',
      'http://jwts-hit-edu-cn.vpn.hit.edu.cn.evil.example:1080/sso'
    ]) {
      const calls = [];
      api.doHttp = async target => {
        calls.push(target);
        return target.endsWith('loginSygl') ? { statusCode: 302, location } : { statusCode: 200, body: fixture };
      };
      assert.equal((await service.getExperiments(session())).length, 1);
      assert.equal(calls.length, 2);
      assert.ok(!calls.includes(location));
    }
  } finally { api.doHttp = original; }
});

test('redirect loops are bounded and external redirects never receive campus cookies', async () => {
  const original = api.doHttp; const calls = [];
  api.doHttp = async target => {
    calls.push(target);
    return { statusCode: 302, location: target.endsWith('loginSygl') ? target : 'https://example.com/sso' };
  };
  try {
    const warnings = [];
    assert.deepEqual(await service.getExperiments(session(), warnings), []);
    assert.ok(calls.length <= 8); assert.ok(calls.every(x => !x.includes('example.com')));
    assert.equal(warnings.length, 1);
  } finally { api.doHttp = original; }
});

test('partial laboratory imports report actionable warnings without expiring the main session', async () => {
  const original = api.doHttp; const s = session(); s.electronicExpToken = '';
  api.doHttp = async () => ({ statusCode: 503, body: '' });
  const ordinary = '<table class="addlist_01"><tr><th>课表</th></tr><tr><td>上午</td><td>第1,2节</td>' +
    '<td>高等数学<br>张三[1]周 正心101</td><td></td><td></td><td></td><td></td><td></td><td></td></tr></table>';
  const provider = new EasDataProvider({ request: async () => ({ statusCode: 200, body: ordinary }) });
  try {
    const courses = await provider.getTimetableOfTerm(s, new EasTermItem());
    assert.ok(courses.some(x => x.name === '高等数学'));
    assert.equal(provider.importWarnings.length, 2);
    assert.match(provider.importWarnings.join('；'), /实验/);
    assert.equal(s.loginExpired, false);
    s.campus = EasCampus.WEIHAI;
    await provider.getTimetableOfTerm(s, new EasTermItem());
    assert.deepEqual(provider.importWarnings, [], 'warnings belong only to the current request');
  } finally { api.doHttp = original; }
});
