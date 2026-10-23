const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const cache = new Map();
global.$r = name => name;
function load(file) {
  file = path.resolve(root, file);
  if (cache.has(file)) return cache.get(file).exports;
  let source = fs.readFileSync(file, 'utf8');
  if (file.endsWith('CreditPage.ets')) {
    source = source.slice(0, source.indexOf('\n  @Builder')) + '\n}';
    source = source.replace(/^@(Entry|Component)\r?\n/gm, '')
      .replace(/@(State|Prop|StorageProp)(\([^)]*\))?\s+/g, '')
      .replace(/(?:export\s+)?struct CreditPage/, 'export class CreditPage');
  }
  const mod = { exports: {} }; cache.set(file, mod);
  const req = name => {
    if (name.startsWith('@kit.') || name.includes('/common/components/') || name.includes('/common/theme/') ||
      name.endsWith('/CreditGoalDialog')) return {};
    assert.ok(name.startsWith('.'), name);
    return load(path.resolve(path.dirname(file), name + '.ets'));
  };
  const output = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  new Function('require', 'module', 'exports', 'Scroller', output)(req, mod, mod.exports,
    class { scrollTo() {} currentOffset() { return { yOffset: 0 }; } });
  return mod.exports;
}
const { ShenzhenCreditParser: P } = load('feature/credit/ShenzhenCreditParser.ets');
const { CreditService, creditErrorMessage } = load('feature/credit/CreditService.ets');
const { CreditGoalStore } = load('feature/credit/CreditGoalStore.ets');
const { aggregateLocalCredits, creditPercent, creditNumber } = load('feature/credit/LocalCreditData.ets');
const { EasTermSubject, EasSubjectType: T } = load('common/model/timetable/TimetableModels.ets');
const { OfficialCreditProgress } = load('feature/credit/CreditModels.ets');
const { EasSession, EasCampus: C } = load('feature/eas/EasSession.ets');
const { EasTermItem } = load('feature/eas/model/EasModels.ets');
const json = JSON.stringify;
const response = (body, statusCode = 200) => ({ statusCode, body: typeof body === 'string' ? body : json(body) });
const session = () => Object.assign(new EasSession(), { campus: C.SHENZHEN,
  webBaseUrl: 'https://jw.hitsz.edu.cn', webCookies: new Map([['SESSION', 'fixture-only']]) });
const term = code => Object.assign(new EasTermItem(), { yearCode: '2026-2027', termCode: code });
const summary = { code: 200, content: { ywcxf: '89.5', wwcxf: '73', ywcms: '40', wwcms: '27',
  yqmsxf: { YQXF: '162.5', YQMS: '67', XFJ: '90.367', PM: '56', ZYRS: '609' } } };
const requirements = [
  { kclbdm: '29', kclbmc: '跨专业发展课程', yqwcxf: '10', ywcxf: '4', wwcxf: '6', ywcxs: '64' },
  { kcxzdm: '03', kclbdm: '04', kcxzmc: '任选', kclbmc: '文理通识', skyymc: '英文',
    yqwcxf: '8', ywcxf: '9', wwcxf: '0', moochdxf: '1', moocsjhdxf: '3' }
];
const groups = [{ kzid: 'ROOT', fkzid: '-1', title: '无', children: [
  { kzid: 'TRACK', fkzid: 'ROOT', title: '计算机轨道', yqxdms: 1, wc_ms: 2, wc_xf: 6.5, sftg: true }
] }];

test('Android identity, record lookup, plan and current-term payloads retain aliases and decimals', () => {
  const identity = P.identity(json({ content: { XH: 'fixture-student', ID: 'fixture-record', PYLX: '本科', NJMC: '2024级' } }));
  assert.equal(identity.studentNumber, 'fixture-student');
  assert.equal(identity.recordId, 'fixture-record');
  assert.equal(identity.studentType, '1'); assert.equal(identity.grade, '2024');
  assert.equal(P.recordId(json({ content: [{ XJID: 'record-2' }] })), 'record-2');
  assert.equal(P.currentTerm(json({ XN: '2025-2026', XQ: '2' })), '2025-20262');
  assert.equal(P.recordTotal(json({ R: 56 })), 56);
  for (const value of ['plain-plan-demo', '"quoted-plan-demo"', '{"FAH":"plan-demo"}', '{"content":[{"PYFADM":"plan-demo"}]}']) {
    assert.match(P.planId(value), /plan-demo/);
  }
  for (const value of ['<html>login</html>', '{}', '{"code":500}', 'null', 'NaN']) assert.equal(P.planId(value), '');
  const parsed = P.summary(json(summary));
  assert.equal(parsed.required, 162.5); assert.equal(parsed.completed, 89.5); assert.equal(parsed.remaining, 73);
  assert.equal(parsed.requiredCourses, 67); assert.equal(parsed.average, 90.367); assert.equal(parsed.rank, 56);
});

test('categories retain direction, MOOC accounting and distinct unnamed-code categories', () => {
  for (const payload of [{ content: { xflbyq: requirements } }, { content: { xflbyq: { list: requirements } } }]) {
    const rows = P.categories(json(payload));
    assert.equal(rows.length, 2); assert.equal(rows[0].hours, 64); assert.equal(rows[0].passed, false);
    assert.equal(rows[1].creditedMooc, 1); assert.equal(rows[1].earnedMooc, 3); assert.equal(rows[1].language, '英文');
    assert.equal(rows[1].passed, true);
  }
  const sameCodes = [requirements[0], { ...requirements[0], zyfxmc: '另一个方向' }, requirements[0]];
  assert.equal(P.categories(json({ content: { xflbyq: sameCodes } })).length, 2);
  assert.equal(P.summary(json({ content: { xflbyq: requirements } })).categories.length, 2);
});

test('nested groups, explicit failure, course records and missing summary are not fabricated as success', () => {
  const values = P.groups(json({ content: { mkyq: groups } }));
  assert.equal(values[0].hasChildren, true);
  assert.equal(values[1].depth, 1); assert.equal(values[1].passed, true); assert.equal(values[1].hasChildren, false);
  const notPassed = P.groups(json({ content: [{ kzid: 'g', title: 'g', yqxdxf: 2, wc_xf: 3, sftg: false }] }));
  assert.equal(notPassed[0].passed, false);
  assert.equal(P.groups(json({ content: [{ kzid: 'g', title: 'g' }] }))[0].passed, false);
  const course = P.groupCourses(json({ content: { list: [{ kcdm: 'COMP', kcmc: '实践', xf: '3.5', sfyxkc: '0', tjkkxnxq: '第二学年夏季' }] } }))[0];
  assert.equal(course.completed, false); assert.equal(course.credits, 3.5);
  const record = P.records(json({ content: { list: [{ rwh: 'task', xnxq: '2026春季', kcdm: 'COMP',
    kcmc: '实践', xf: '3.5', xscj: '优秀', jsxm: '测试教师' }] } }))[0];
  assert.equal(record.id, 'task'); assert.equal(record.score, '优秀'); assert.equal(record.teacher, '测试教师');
  for (const raw of ['{}', '{"code":500}', '{"content":{}}', '<html>error</html>']) {
    assert.equal(P.summary(raw), undefined); assert.equal(P.records(raw), undefined);
  }
  assert.deepEqual(P.records('{"content":{"list":[]}}'), []);
  assert.equal(P.summary('{"content":{"ywcxf":0}}').completed, 0);
  assert.equal(P.summary('{"content":{"ywcxf":0}}').required, undefined);
  assert.equal(P.summary('{"content":{"ywcxf":"NaN"}}'), undefined);
  assert.equal(creditPercent(200, 100), 100); assert.equal(creditPercent(0, 0), 0); assert.equal(creditNumber(undefined), '—');
});

test('local credits deduplicate all timetables, omit tags, preserve zero and support every Android category', () => {
  const subject = fields => Object.assign(new EasTermSubject(), fields);
  const stats = aggregateLocalCredits([
    subject({ name: 'A', code: 'A1', credit: 3.5, countInSPA: true, field: '数学' }),
    subject({ name: 'A renamed', code: 'A1', credit: 3.5, timetableId: 'other' }),
    subject({ name: 'B', credit: 2, type: T.COM_B }),
    subject({ name: 'B', credit: 2, type: T.COM_B }),
    subject({ name: 'C', credit: 1, type: T.OPT_A }),
    subject({ name: 'D', credit: 0, type: T.OPT_B }),
    subject({ name: 'E', credit: 1.5, type: T.MOOC }),
    subject({ name: 'event', credit: 999, type: T.TAG }),
    subject({ name: 'invalid', credit: NaN }), subject({ name: 'negative', credit: -1 })
  ], new Map([[T.COM_A, 10]]));
  assert.equal(stats.credits, 8); assert.equal(stats.count, 7); assert.equal(stats.spaCredits, 3.5);
  assert.equal(stats.nonSpaCredits, 4.5); assert.equal(stats.categories.length, 5);
  assert.equal(stats.categories[0].goal, 10); assert.equal(stats.categories[0].fields[0].name, '数学');
  assert.equal(aggregateLocalCredits([], new Map()).count, 0);
});

test('credit goals persist, clear on zero, and reject invalid values without a false save', async () => {
  const map = new Map(); let flushes = 0;
  const store = new CreditGoalStore();
  store.store = { get: async (key, fallback) => map.get(key) ?? fallback,
    put: async (key, value) => map.set(key, value), delete: async key => map.delete(key), flush: async () => { flushes++; } };
  await store.save(T.COM_A, 12.5); assert.equal((await store.load()).get(T.COM_A), 12.5);
  await store.save(T.COM_A, 0); assert.equal((await store.load()).has(T.COM_A), false);
  for (const value of [-1, NaN, Infinity, 1001]) await assert.rejects(store.save(T.COM_A, value));
  await assert.rejects(store.save(T.TAG, 1)); assert.equal(flushes, 2);
  store.store.flush = async () => { throw Error('disk'); };
  await assert.rejects(store.save(T.COM_B, 2), /disk/);
});

function fixtureService(overrides = () => undefined) {
  const calls = [];
  const service = new CreditService({ request: async (s, cfg, endpoint, options) => {
    calls.push({ endpoint, options });
    assert.equal(s.campus, C.SHENZHEN); assert.equal(cfg.campus, C.SHENZHEN);
    assert.equal(options.method, 'POST'); assert.equal(options.useCache, false);
    assert.equal(options.extraHeaders.get('RoleCode'), '01');
    assert.equal(options.extraHeaders.get('Origin'), 'https://jw.hitsz.edu.cn');
    const override = overrides(endpoint, options, calls.length);
    if (override !== undefined) return await override;
    if (endpoint.includes('queryxsxx')) return response({ XH: 'fixture-student', ID: 'fixture-record', PYLX: '本科', NJ: '2024' });
    if (endpoint.endsWith('getXs')) return response({ content: [{ xjid: 'looked-up' }] });
    if (endpoint.includes('queryqxnxq')) return response({ XN: '2026-2027', XQ: '1', R: 3 });
    if (endpoint.includes('queryfahHljdx')) return response({ FAH: 'fixture-plan' });
    if (endpoint.includes('queryfah?')) return response('"fallback-plan"');
    if (endpoint.includes('queryBxkqk')) return response(summary);
    if (endpoint.includes('queryXflbyq1')) return response({ content: { xflbyq: requirements } });
    if (endpoint.includes('queryMkyq')) return response({ content: groups });
    if (endpoint.includes('queryFaKzkc')) return response({ content: { pages: 2, list: [
      { kcdm: 'COMP' + JSON.parse(options.body).current, kcmc: '实践', xf: 3, sfyxkc: '1' }
    ] } });
    if (endpoint.includes('dyxwList')) {
      const page = new URLSearchParams(options.body).get('pageNum');
      return response({ content: { pages: 2, list: [{ rwh: 'same', kcmc: '共同课程', xf: 2 },
        { rwh: 'task-' + page, kcmc: '课程' + page, xf: '3.5' }] } });
    }
    assert.fail(endpoint);
  } });
  return { service, calls };
}

test('Shenzhen query ports Android forms, selected-term summary, pagination and lazy group details', async () => {
  const { service, calls } = fixtureService();
  const stages = [];
  const progress = await service.query(session(), term('2'), value => stages.push(value.snapshot()));
  assert.equal(stages[0].completed, 89.5); assert.equal(stages[0].records.length, 0);
  assert.equal(progress.term, '2026-20272'); assert.equal(progress.categories.length, 2);
  assert.equal(progress.records.length, 3, 'duplicate records across pages count once');
  assert.equal(progress.notices.length, 0);
  const summaryCall = calls.find(call => call.endpoint.includes('queryBxkqk'));
  assert.equal(JSON.parse(summaryCall.options.body).jzxnxq, '2026-20272');
  assert.equal(JSON.parse(summaryCall.options.body).zyfxdm, null);
  assert.match(summaryCall.options.extraHeaders.get('Content-Type'), /application\/json/);
  const recordsCall = calls.find(call => call.endpoint.includes('dyxwList'));
  assert.match(recordsCall.options.extraHeaders.get('Content-Type'), /form-urlencoded/);
  assert.equal(new URLSearchParams(recordsCall.options.body).get('sfcxfxcj'), '0');
  assert.equal(calls.some(call => call.endpoint.includes('queryFaKzkc')), false);
  const courses = await service.groupCourses(session(), progress.context, progress.groups[1]);
  assert.equal(courses.length, 2);
  assert.equal(courses[1].code, 'COMP2');
});

test('identity/plan fallbacks and missing optional summary retain categories without zero totals', async () => {
  const { service, calls } = fixtureService(endpoint => {
    if (endpoint.includes('queryxsxx')) return response({ XH: 'fixture-student', PYLX: '1', NJ: '2024' });
    if (endpoint.includes('queryfahHljdx')) return response('', 404);
    if (endpoint.includes('queryBxkqk')) return response('', 404);
  });
  const progress = await service.query(session(), undefined);
  assert.equal(progress.context.recordId, 'looked-up'); assert.equal(progress.context.planId, 'fallback-plan');
  assert.equal(progress.required, undefined); assert.equal(progress.completed, undefined);
  assert.equal(progress.categories.length, 2); assert.equal(progress.groups.length, 2);
  assert.ok(progress.notices.includes('教务暂未提供汇总学分'));
  assert.equal(calls.filter(call => call.endpoint.includes('queryfah')).length, 2);
});

test('ordinary optional failures retain summary and mark incomplete records rather than claim no data', async () => {
  const { service } = fixtureService((endpoint, options) => {
    if (endpoint.includes('queryXflbyq1')) return response('Forbidden', 403);
    if (endpoint.includes('queryMkyq')) return response('maintenance', 503);
    if (endpoint.includes('dyxwList') && new URLSearchParams(options.body).get('pageNum') === '2') return response('', 0);
  });
  const progress = await service.query(session(), term('1'));
  assert.equal(progress.completed, 89.5); assert.equal(progress.notices.length, 3);
  assert.equal(progress.records.length, 2); assert.match(progress.notices.join(''), /部分课程/);
});

test('expiry from optional endpoints propagates and stops requests; cached expiry makes no request', async () => {
  for (const failed of ['queryxsxx', 'queryXflbyq1', 'queryMkyq', 'dyxwList']) {
    const { service, calls } = fixtureService(endpoint => endpoint.includes(failed) ? response('{"code":401}') : undefined);
    await assert.rejects(service.query(session(), term('1')), /会话已失效/);
    assert.ok(calls.at(-1).endpoint.includes(failed));
  }
  const { service, calls } = fixtureService();
  const expired = session(); expired.loginExpired = true;
  await assert.rejects(service.query(expired, term('1')), /会话已失效/);
  assert.equal(calls.length, 0);
  assert.match(creditErrorMessage('教务会话已失效，请重新登录'), /登录已过期/);
  assert.doesNotMatch(creditErrorMessage('private-cookie server stack'), /private|cookie|stack/);
});

test('leaving during a query stops subsequent requests and prevents late progress', async () => {
  let active = true;
  const { service, calls } = fixtureService(endpoint => {
    if (endpoint.includes('queryBxkqk')) { active = false; return response(summary); }
  });
  await assert.rejects(service.query(session(), term('1'), () => assert.fail('stale progress'), () => active), /已取消/);
  assert.ok(calls.at(-1).endpoint.includes('queryBxkqk'));
});

test('malformed summaries and absent identity never become a successful zero-credit report', async () => {
  for (const body of [{}, { code: 500 }, { content: {} }]) {
    const { service } = fixtureService(endpoint => endpoint.includes('queryBxkqk') ? response(body) : undefined);
    await assert.rejects(service.query(session(), term('1')), /解析失败/);
  }
  const { service, calls } = fixtureService(() => response({}));
  await assert.rejects(service.query(session(), term('1')), /学号或入学年级/);
  assert.equal(calls.length, 1);
});

function deferred() { let resolve, reject; const promise = new Promise((r, j) => { resolve = r; reject = j; }); return { promise, resolve, reject }; }
test('changing the selected term and leaving the page ignore old summary, errors and loading state', async () => {
  const { CreditPage } = load('pages/CreditPage.ets');
  const page = new CreditPage(); page.session = session(); page.terms = [term('1'), term('2')];
  const old = deferred(), fresh = deferred(); const callbacks = [];
  page.service = { query: (_session, _term, onProgress) => { callbacks.push(onProgress); return callbacks.length === 1 ? old.promise : fresh.promise; } };
  const first = page.selectTerm(0); const second = page.selectTerm(1);
  const latest = new OfficialCreditProgress(); latest.term = '2026-20272'; latest.completed = 90;
  fresh.resolve(latest); await second;
  callbacks[0](new OfficialCreditProgress()); old.reject(new Error('obsolete')); await first;
  assert.equal(page.progress.term, latest.term); assert.equal(page.errorText, ''); assert.equal(page.loading, false);
  const pending = deferred(); page.service = { query: () => pending.promise };
  const last = page.selectTerm(0); page.onPageHide(); pending.resolve(latest); await last;
  assert.equal(page.ready, false);
});

test('category expansion remains stable when a saved goal updates totals', () => {
  const { CreditPage } = load('pages/CreditPage.ets');
  const page = new CreditPage();
  assert.equal(page.toggle(T.COM_A), true);
  page.subjects = [Object.assign(new EasTermSubject(), { name: 'Course', credit: 3 })];
  page.local = aggregateLocalCredits(page.subjects, new Map([[T.COM_A, 8]]));
  assert.deepEqual(page.expanded, [T.COM_A]);
  assert.equal(page.local.categories[0].goal, 8);
});
