const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const root = path.resolve(__dirname, '../entry/src/main/ets');
function load(file, mocks = {}, cache = new Map()) {
  file = path.resolve(root, file);
  if (cache.has(file)) return cache.get(file).exports;
  let source = fs.readFileSync(file, 'utf8');
  if (file.endsWith('EmptyClassroomPage.ets')) {
    source = source.slice(0, source.indexOf('\n  build()')) + '\n}';
    source = source.replace(/^@(Entry|Component)\r?\n/gm, '')
      .replace(/@(State|Prop|StorageProp)(\([^)]*\))?\s+/g, '')
      .replace(/(?:export\s+)?struct EmptyClassroomPage/, 'export class EmptyClassroomPage');
  }
  const mod = { exports: {} };
  cache.set(file, mod);
  const req = name => {
    if (name in mocks) return mocks[name];
    if (name.startsWith('@kit.')) return {};
    if (name.includes('/common/components/') || name.includes('/common/theme/')) return {};
    assert.ok(name.startsWith('.'), name);
    return load(path.resolve(path.dirname(file), name + '.ets'), mocks, cache);
  };
  const js = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  new Function('require', 'module', 'exports', js)(req, mod, mod.exports);
  return mod.exports;
}
global.$r = name => name;
const { EmptyClassroomDisplay: display } = load('feature/eas/classroom/EmptyClassroomDisplay.ets');
const { EmptyClassroomCache: Cache } = load('feature/eas/classroom/EmptyClassroomCache.ets');
const { EasTimePeriodInDay: Period } = load('common/model/timetable/TimetableModels.ets');
const modules = new Map();
const { EmptyClassroomData: data, ClassroomBuilding, ClassroomRoom, ClassroomAvailability: A } =
  load('feature/eas/classroom/EmptyClassroomData.ets', {}, modules);
const { EmptyClassroomService: Service } = load('feature/eas/classroom/EmptyClassroomService.ets', {}, modules);
const { EasCampus: C, EasSession } = load('feature/eas/EasSession.ets', {}, modules);
const { EasTermItem } = load('feature/eas/model/EasModels.ets', {}, modules);
function session(campus = C.SHENZHEN) {
  const s = new EasSession();
  s.campus = campus;
  s.webCookies.set('SESSION', 'fixture-not-a-real-cookie');
  s.webBaseUrl = 'https://jw-hitsz-edu-cn.hitsz.edu.cn';
  return s;
}
const term = () => Object.assign(new EasTermItem(), { yearCode: '2026-2027', termCode: '1' });
const building = (id = '01', area = '') => Object.assign(new ClassroomBuilding(), { id, area, name: '教学楼' });
const roomBody = JSON.stringify({ content: { list: [{ DM: 'a1', MC: 'A-101', ZWS: '80' }], total: 1 } });
const json = value => JSON.stringify(value);
const response = (body, statusCode = 200) => ({ body: typeof body === 'string' ? body : json(body), statusCode });
function legacy(cells = new Map(), name = '正心101') {
  return '<table class="dataTable"><tr><th>教室名称</th><th>人数</th></tr><tr><td>' + name +
    '</td><td>80人</td>' + Array.from({ length: 42 }, (_, i) => '<td>' + (cells.get(i) ?? '&nbsp;') + '</td>').join('') +
    '</tr></table>';
}

test('building identifiers preserve leading zeroes and areas; accepted response wrappers include empty arrays', () => {
  for (const body of [[{ DM: '001', MC: 'A楼' }], { data: { list: [{ dm: '001', mc: 'A楼' }] } }]) {
    const [b] = data.parseBuildings(json(body), '01');
    assert.equal(b.id, '001');
    assert.equal(b.key(), '01/001');
    assert.equal(b.name, 'A楼');
  }
  assert.deepEqual(data.parseBuildings('{"data":{"list":[]}}'), []);
});

test('malformed, error and unrecognized JSON are failures, never empty success', () => {
  for (const body of ['<html>login</html>', '{}', 'null', '1', '{"code":500,"data":[]}',
    '{"success":false,"list":[]}', '[null]', '[1]', '[{}]']) {
    assert.throws(() => data.parseBuildings(body));
  }
  assert.throws(() => data.parseBuildings('{"code":401,"list":[]}'), e => e.kind === 'AUTH');
});

test('Shenzhen room and occupancy responses join by ID, including borrowing flags and mixed key case', () => {
  const page = data.parseShenzhenRooms(roomBody);
  assert.equal(page.total, 1);
  assert.equal(page.rooms[0].capacity, 80);
  data.applyShenzhenOccupancy(page.rooms, json({ rows: [
    { CDDM: 'a1', XQJ: 2, XJ: 3, PKBJ: '1' },
    { cddm: 'a1', xqj: '2', xj: '4', pkbj: '0', jybj: '是' },
    { CDDM: 'a1', XQJ: 2, XJ: 5, PKBJ: false, JYBJ: '否', PKJYBJ: '0' },
    { CDDM: 'a1', XQJ: 2, XJ: 3, PKBJ: '1' }
  ] }));
  const r = page.rooms[0];
  assert.equal(r.occupied.length, 2);
  assert.equal(data.availability(r, 2, 2, 4), A.OCCUPIED);
  assert.equal(data.availability(r, 2, 5, 6), A.FREE);
  assert.equal(data.availability(r, 1, 3, 4), A.FREE);
});

test('incomplete or invalid occupancy cannot manufacture availability', () => {
  const rooms = data.parseShenzhenRooms(roomBody).rooms;
  for (const body of ['{}', '<html/>', json([{ CDDM: 'a1', XQJ: 2, XJ: 3 }]),
    json([{ CDDM: 'a1', XQJ: 8, XJ: 3, PKBJ: 1 }]), json([{ CDDM: 'a1', XQJ: 2, XJ: 17, PKBJ: 1 }])]) {
    assert.throws(() => data.applyShenzhenOccupancy(rooms, body));
  }
  data.applyShenzhenOccupancy(rooms, '[]');
  assert.equal(data.availability(rooms[0], 7, 15, 16), A.FREE);
});

test('legacy six blocks map to the correct days and BOTH periods, including Sunday evening', () => {
  const occupied = '<div class="kjs_icon kjs_icon01"></div>';
  const [r] = data.parseLegacyRooms(legacy(new Map([[0, occupied], [6, occupied], [41, occupied]])));
  assert.equal(r.capacity, 80);
  for (const [d, s, e] of [[1, 1, 2], [2, 1, 2], [7, 11, 12]]) {
    assert.equal(data.availability(r, d, s, e), A.OCCUPIED);
  }
  assert.equal(data.availability(r, 1, 3, 12), A.FREE);
  assert.equal(data.availability(r, 7, 9, 10), A.FREE);
});

test('legacy metadata column counts vary; HTML spaces are free but unexplained text is unknown', () => {
  const html = legacy(new Map([[0, '&amp;nbsp;'], [1, '待确认']])).replace('<td>80人</td>', '');
  const [r] = data.parseLegacyRooms(html);
  assert.equal(r.capacity, 0);
  assert.equal(data.availability(r, 1, 1, 2), A.FREE);
  assert.equal(data.availability(r, 1, 3, 4), A.UNKNOWN);


});

test('legacy parser distinguishes explicit empty results from malformed tables/login/partial rows', () => {
  assert.deepEqual(data.parseLegacyRooms('<table class="dataTable"><tr><td colspan="44">暂无数据</td></tr></table>'), []);
  for (const html of ['<html>login</html>', '<table class="dataTable"></table>',
    '<table class="dataTable"><tr><td>A101</td><td>broken</td></tr></table>',
    legacy().replace('<td>&nbsp;</td>', '')]) {
    assert.throws(() => data.parseLegacyRooms(html));
  }
});

test('legacy parser selects the widest data table and excludes unknown icon states from availability', () => {
  const unrelated = '<table class="dataTable"><tr><td>导航</td><td>链接</td></tr></table>';
  const [r] = data.parseLegacyRooms(unrelated + legacy(new Map([[0, '<i class="kjs_icon03"></i>']])));
  assert.equal(r.name, '正心101');
  assert.equal(data.availability(r, 1, 1, 2), A.UNKNOWN);
  assert.equal(data.availability(r, 1, 3, 4), A.FREE);
});

test('Shenzhen queries both responses with the exact one-hot week mask and selected building', async () => {
  const calls = [];
  const api = { request: async (s, c, p, o) => {
    calls.push({ s, p, form: new URLSearchParams(o.body), headers: o.extraHeaders });
    return response(p.includes('left') ? roomBody : []);
  } };
  const rooms = await new Service(api).query(session(), term(), building('001'), 34);
  assert.equal(rooms.length, 1);
  assert.equal(calls.length, 2);
  assert.equal(calls[0].form.get('zc'), '0'.repeat(33) + '1');
  assert.equal(calls[0].form.get('jxl'), '001');
  assert.equal(calls[0].form.get('pxn'), '2026-2027');
  assert.equal(calls[1].form.has('pageNum'), false);
  assert.equal(calls[1].headers.get('Referer'), 'https://jw-hitsz-edu-cn.hitsz.edu.cn/cdkb/querycdzy');
  assert.equal(calls[1].headers.get('RoleCode'), '01');
});

test('Shenzhen pagination follows reported totals and rejects repeated/incomplete pages', async () => {
  const run = async repeated => {
    const api = { request: async (s, c, p, o) => {
      if (p.includes('right')) return response([]);
      const n = new URLSearchParams(o.body).get('pageNum');
      return response({ total: 2, list: [{ DM: repeated || n === '1' ? 'a' : 'b', MC: 'Room' }] });
    } };
    return new Service(api).query(session(), term(), building(), 1);
  };
  assert.equal((await run(false)).length, 2);
  await assert.rejects(run(true), e => e.kind === 'DATA');
  const api = { request: async () => response({ total: 4, list: [] }) };
  await assert.rejects(new Service(api).query(session(), term(), building(), 1), e => e.kind === 'DATA');
});

test('Shenzhen initializes classroom context before getting real buildings', async () => {
  const paths = [];
  const api = { request: async (s, c, p) => { paths.push(p); return response([{ DM: '001', MC: 'A' }]); } };
  assert.equal((await new Service(api).getBuildings(session()))[0].id, '001');
  assert.deepEqual(paths, ['/pksd/queryxiaoquList', '/pksd/querycdlbList', '/kbfbsz/querydqxnxq', '/pksd/queryjxlList']);
});

test('Benbu merges BOTH areas without confusing duplicate building IDs', async () => {
  const api = { request: async () => response([{ DM: '01', MC: '教学楼' }]) };
  const buildings = await new Service(api).getBuildings(session(C.BENBU));
  assert.deepEqual(buildings.map(b => b.key()), ['1/01', '2/01']);
});

test('Weihai first uses campus 01 and only falls back to 1/2 when it returns an empty list', async () => {
  const areas = [];
  const api = { request: async (s, c, p, o) => {
    const area = new URLSearchParams(o.body).get('id'); areas.push(area);
    return response(area === '01' ? [] : [{ DM: '09', MC: 'M' }]);
  } };
  const buildings = await new Service(api).getBuildings(session(C.WEIHAI));
  assert.deepEqual(areas, ['01', '1', '2']);
  assert.deepEqual(buildings.map(b => b.key()), ['1/09', '2/09']);
});

for (const campus of [C.BENBU, C.WEIHAI]) {
  test(`${campus} query uses Android campus parameters and parses the weekly HTML`, async () => {
    let captured;
    const api = { request: async (s, c, p, o) => { if (p.includes('queryJxl')) return response([]); captured = { p, o }; return response(legacy()); } };
    const rooms = await new Service(api).query(session(campus), term(), building('009', '01'), 3);
    assert.equal(rooms.length, 1);
    const form = new URLSearchParams(captured.o.body);
    assert.equal(form.get('pageXnxq'), '2026-20271');
    assert.equal(form.get('pageZc1'), '3');
    assert.equal(form.get('pageZc2'), '3');
    assert.equal(form.get('pageLhdm'), '009');
    assert.equal(form.get('pageXiaoqu'), campus === C.WEIHAI ? '01' : '');
    if (campus === C.WEIHAI) {
      assert.match(captured.p, /vpn-12-o1-jwts.hitwh.edu.cn/);
      assert.equal(captured.o.extraHeaders.get('Origin'), 'https://webvpn.hitwh.edu.cn');
    }
  });
}

test('Weihai empty-selector fallback never broadens the requested building', async () => {
  const forms = [];
  const api = { request: async (s, c, p, o) => {
    if (p.includes('queryJxl')) return response([]);
    forms.push(new URLSearchParams(o.body));
    return response(forms.length === 1 ? '<table class="dataTable"><tr><td>暂无数据</td></tr></table>' : legacy());
  } };
  assert.equal((await new Service(api).query(session(C.WEIHAI), term(), building('001', '01'), 1)).length, 1);
  assert.deepEqual(forms.map(f => f.get('pageCddm')), ['，', '']);
  assert.deepEqual(forms.map(f => f.get('pageLhdm')), ['001', '001']);
});

test('HTTP, network, auth and invalid data failures are distinguished and never returned as free classrooms', async () => {
  for (const [res, kind] of [[response('', 0), 'NETWORK'], [response('', 500), 'HTTP'],
    [response('', 401), 'AUTH'], [response('<form><input name="password"></form>'), 'AUTH'],
    [response({ code: 403, list: [] }), 'AUTH'], [response('{}'), 'DATA']]) {
    let count = 0;
    const api = { request: async () => { count++; return res; } };
    await assert.rejects(new Service(api).query(session(), term(), building(), 1), e => e.kind === kind);
    assert.equal(count, 1);
  }
  assert.equal(Service.isLoginResponse('<a href="loginCAS">教务</a>'), false);
});

test('input and unsupported sessions fail before making network calls', async () => {
  const api = { request: async () => { assert.fail('should not request'); } };
  for (const week of [0, 35, 1.5]) {
    await assert.rejects(new Service(api).query(session(), term(), building(), week), e => e.kind === 'INPUT');
  }
  const guest = new EasSession();
  await assert.rejects(new Service(api).getBuildings(guest), e => e.kind === 'AUTH');
  const grad = session(C.BENBU); grad.setStudentType('2');
  await assert.rejects(new Service(api).getBuildings(grad), e => e.kind === 'UNSUPPORTED');
});

test('Android classroom chips: occupied now, occupied next, free, unknown, and weekday isolation', () => {
  const r = Object.assign(new ClassroomRoom(), { occupied: [{ day: 1, period: 2 }] });
  assert.equal(display.state(r, 1, 20, true), '被占');
  assert.equal(display.state(r, 1, 15, true), '将占');
  assert.equal(display.state(r, 1, 10, true), '将占');
  assert.equal(display.state(r, 2, 20, true), '空闲');
  assert.equal(display.state(r, 1, 5, true), '空闲');
  assert.equal(display.state(r, 1, 20, false), '未知');
  r.unknown = [{ day: 1, period: 3 }];
  assert.equal(display.state(r, 1, 30, true), '未知');
});

test('Android detail rows follow the supplied bell schedule and day, including paired legacy occupancy', () => {
  const [r] = data.parseLegacyRooms(legacy(new Map([[0, '<i class="kjs_icon01"></i>']])));
  const schedule = [Period.ofHour(8, 0, 8, 50), Period.ofHour(8, 55, 9, 45), Period.ofHour(10, 5, 10, 55)];
  const rows = display.rows(r, 1, schedule);
  assert.deepEqual(rows.map(r => [r.number, r.time, r.state]), [
    [1, '8:00 - 8:50', '占用'], [2, '8:55 - 9:45', '占用'], [3, '10:05 - 10:55', '空']
  ]);
  assert.deepEqual(display.rows(r, 7, schedule).map(r => r.state), ['空', '空', '空']);
});

test('Android term display/current-year filtering and enrollment filtering preserve term codes', () => {
  const terms = [term(), Object.assign(new EasTermItem(), { yearCode: '2025-2026', termCode: '2', isCurrent: true }),
    Object.assign(new EasTermItem(), { yearCode: '2024-2025', termCode: '1' })];
  const now = new Date(2026, 3, 1);
  assert.equal(display.termName(terms[0]), '2026-2027 秋季');
  assert.equal(display.currentYearTerms(terms, now).length, 2);
  assert.deepEqual(display.pickerTerms(terms, '2025级', now).map(t => t.getCode()), ['2025-20262']);
  assert.equal(display.PICKER_WEEKS, 20);
});

function memoryCache() {
  const values = new Map();
  const cache = new Cache();
  cache.store = { get: async (k, d) => values.get(k) ?? d, put: async (k, v) => values.set(k, v),
    delete: async k => values.delete(k), getAll: async () => Object.fromEntries(values), flush: async () => {} };
  return { cache, values };
}

test('cache separates accounts, campuses, buildings and weeks; retains empty results and prunes old data', async () => {
  const { cache, values } = memoryCache();
  const s = session(); s.stuId = 'fixture-user-a';
  const key = Cache.key(s, term(), building(), 1);
  const keys = new Set([key, Cache.key(s, term(), building(), 2), Cache.key(s, term(), building('02'), 1)]);
  s.stuId = 'fixture-user-b'; keys.add(Cache.key(s, term(), building(), 1));
  s.campus = C.BENBU; keys.add(Cache.key(s, term(), building(), 1));
  assert.equal(keys.size, 5);
  values.set('expired', json({ savedAt: Date.now() - Cache.MAX_AGE - 1, rooms: [] }));
  values.set('broken', 'invalid json');
  await cache.write(key, []);
  assert.deepEqual((await cache.read(key)).rooms, []);
  assert.equal(values.has('expired'), false);
  assert.equal(values.has('broken'), false);
  await cache.write(key, data.parseLegacyRooms(legacy()));
  assert.equal((await cache.read(key)).rooms[0].name, '正心101');
});

function deferred() { let resolve; const promise = new Promise(r => { resolve = r; }); return { promise, resolve }; }
function pageWithService(service, mocks = {}) {
  const { EmptyClassroomPage } = load('pages/EmptyClassroomPage.ets', {
    '../feature/eas/classroom/EmptyClassroomService': { EmptyClassroomService: service }, ...mocks
  });
  const page = new EmptyClassroomPage();
  Object.assign(page, { session: session(), terms: [term()], buildings: [building()], loading: false });
  return page;
}

test('changing week automatically queries and ignores a late response for the previous week', async () => {
  const pending = deferred(); const calls = [];
  const page = pageWithService(class { query(s, t, b, w) {
    calls.push(w); return w === 1 ? pending.promise : Promise.resolve([Object.assign(new ClassroomRoom(), { id: 'new' })]);
  } });
  const old = page.query();
  await Promise.resolve();
  await page.changeWeek(2);
  pending.resolve([Object.assign(new ClassroomRoom(), { id: 'old' })]);
  await old;
  assert.deepEqual(calls, [1, 2]);
  assert.equal(page.rooms[0].id, 'new');
  assert.equal(page.querying, false);
});

test('building and term selections query automatically; same selection does not query again', async () => {
  const calls = [];
  const page = pageWithService(class { async query(s, t, b, w) { calls.push([t.getCode(), b.id, w]); return []; } });
  page.buildings.push(building('02'));
  page.terms.push(Object.assign(term(), { termCode: '2' }));
  page.loadTermContext = async () => { page.selectedWeek = 4; };
  await page.changeBuilding(1);
  await page.changeBuilding(1);
  await page.changeTerm(1);
  await page.changeWeek(21);
  assert.deepEqual(calls, [['2026-20271', '02', 1], ['2026-20272', '02', 4]]);
});

test('leaving the page prevents late results; an error without cache leaves no rooms', async () => {
  const pending = deferred();
  const page = pageWithService(class { query() { return pending.promise; } });
  const query = page.query(); await Promise.resolve();
  page.onPageHide(); pending.resolve([new ClassroomRoom()]); await query;
  assert.equal(page.rooms.length, 0);
  const failed = pageWithService(class { async query() { throw new Error('network failed'); } });
  failed.rooms = [new ClassroomRoom()];
  await failed.query();
  assert.equal(failed.rooms.length, 0);
  assert.equal(failed.queried, false);
  assert.ok(failed.error.length > 0);
});

test('Android cache-then-network keeps marked cache on failure and replaces it on successful empty results', async () => {
  const { cache } = memoryCache();
  const page = pageWithService(class { async query() { throw new Error('network failed'); } });
  page.cache = cache;
  const key = Cache.key(page.session, page.terms[0], page.buildings[0], 1);
  await cache.write(key, [Object.assign(new ClassroomRoom(), { name: 'A101' })]);
  await page.query();
  assert.equal(page.rooms[0].name, 'A101');
  assert.ok(page.cachedAt > 0);
  const fresh = pageWithService(class { async query() { return []; } }); fresh.cache = cache;
  await fresh.query();
  assert.equal(fresh.rooms.length, 0);
  assert.equal(fresh.cachedAt, 0);
  assert.equal(fresh.queried, true);
});

test('detail opens on today and changes weekday without querying the server', () => {
  const page = pageWithService(class { query() { assert.fail('detail must use weekly data'); } });
  page.schedule = [Period.ofHour(8, 0, 8, 50)];
  page.openDetail(Object.assign(new ClassroomRoom(), { occupied: [{ day: 1, period: 1 }] }));
  assert.equal(page.sheetVisible, true);
  assert.equal(page.detailDay, new Date().getDay() || 7);
  page.selectDay(1); assert.equal(page.detailRows[0].state, '占用');
  page.selectDay(2); assert.equal(page.detailRows[0].state, '空');
});

test('network refresh updates an already open cached detail and preserves its selected weekday', async () => {
  const pending = deferred(); const { cache } = memoryCache();
  const page = pageWithService(class { query() { return pending.promise; } }); page.cache = cache;
  page.schedule = [Period.ofHour(8, 0, 8, 50)];
  const cached = Object.assign(new ClassroomRoom(), { id: 'a', name: 'A101' });
  await cache.write(Cache.key(page.session, page.terms[0], page.buildings[0], 1), [cached]);
  const query = page.query();
  await new Promise(resolve => setImmediate(resolve));
  page.openDetail(page.rooms[0]); page.selectDay(1);
  assert.equal(page.detailRows[0].state, '空');
  pending.resolve([Object.assign(new ClassroomRoom(), { id: 'a', name: 'A101', occupied: [{ day: 1, period: 1 }] })]);
  await query;
  assert.equal(page.detailDay, 1);
  assert.equal(page.detailRows[0].state, '占用');
  assert.equal(page.cachedAt, 0);
});

test('Weihai resolves Android building code variants but never queries all buildings', async () => {
  const forms = [];
  const api = { request: async (s, c, p, o) => {
    const form = new URLSearchParams(o.body);
    if (p.includes('queryJxl')) return response([{ DM: '1', MC: '教学楼' }]);
    forms.push(form);
    return response(form.get('pageXiaoqu') === '1' && form.get('pageLhdm') === '1' ? legacy() :
      '<table class="dataTable"><tr><td>暂无数据</td></tr></table>');
  } };
  assert.equal((await new Service(api).query(session(C.WEIHAI), term(), building('001'), 1)).length, 1);
  assert.ok(forms.some(f => f.get('pageXiaoqu') === '01'));
  assert.ok(forms.some(f => f.get('pageXiaoqu') === '1'));
  assert.ok(forms.every(f => f.get('pageLhdm').length > 0));
});

for (const campus of [C.SHENZHEN, C.BENBU, C.WEIHAI]) {
  test(`${campus} entry uses preferred account and automatically queries current term/first building/local week`, async () => {
    const s = session(campus); const calls = [];
    const current = Object.assign(term(), { isCurrent: true });
    const provider = class { async getAllTerms() { return [Object.assign(term(), { termCode: '2' }), current]; } };
    const page = pageWithService(class {
      static assertSession() {}
      async getBuildings() { return [building('01'), building('02')]; }
      async query(account, t, b, w) { calls.push([account.campus, t.getCode(), b.id, w]); return []; }
    }, {
      '../feature/eas/EasDataProvider': { EasDataProvider: provider },
      '../feature/eas/EasSessionStore': { EasSessionStore: { getInstance: () => ({
        init: async () => {}, loadPreferred: async () => s
      }) } }
    });
    page.getUIContext = () => ({ getHostContext: () => ({}) });
    page.loadTermContext = async () => { page.selectedWeek = 6; };
    await page.loadOptions();
    assert.deepEqual(calls, [[campus, current.getCode(), '01', 6]]);
    assert.equal(page.loading, false);
    assert.equal(page.querying, false);
  });
}
