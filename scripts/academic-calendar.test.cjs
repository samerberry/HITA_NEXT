const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');
global.$r = name => ({ id: -1, type: 10001, params: [name] });

const root = path.resolve(__dirname, '../entry/src/main/ets');
global.Scroller = class {};
function load(file, mocks = {}, cache = new Map()) {
  file = path.resolve(root, file);
  if (cache.has(file)) return cache.get(file).exports;
  let source = fs.readFileSync(file, 'utf8');
  if (file.endsWith('ImportTimetablePanel.ets')) {
    const helpers = source.slice(source.indexOf('\n  private static dateText'));
    source = source.slice(0, source.indexOf('\n  build()')) + helpers;
    source = source.replace(/^@(Entry|Component)\r?\n/gm, '')
      .replace(/@(State|StorageProp|Prop)(\([^)]*\))?\s+/g, '')
      .replace(/^import .*Compatible(LightModifier|SheetMaterial).*\r?\n/gm, '')
      .replace('struct ImportTimetablePanel', 'export class ImportTimetablePanel');
  }
  const mod = { exports: {} };
  cache.set(file, mod);
  const localRequire = name => {
    if (name in mocks) return mocks[name];
    if (name === '@kit.PerformanceAnalysisKit') return { hilog: { info() {}, warn() {}, error() {} } };
    if (name.startsWith('@kit.')) return {};
    assert.ok(name.startsWith('.'), name);
    return load(path.resolve(path.dirname(file), name + '.ets'), mocks, cache);
  };
  const compiled = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  new Function('require', 'module', 'exports', compiled)(localRequire, mod, mod.exports);
  return mod.exports;
}
const { EasTermItem, EasCourseItem } = load('feature/eas/model/EasModels.ets');
const { EasTimetable } = load('common/model/timetable/TimetableModels.ets');
const { EasCampus, EasSession } = load('feature/eas/EasSession.ets');
const { EasAcademicCalendar: calendar } = load('feature/eas/data/EasAcademicCalendar.ets');
const { EasDataProvider } = load('feature/eas/EasDataProvider.ets');
const { EasTimetableImporter: importer } = load('feature/eas/EasTimetableImporter.ets');
const date = (y, m, d) => new Date(y, m - 1, d).getTime();
function term(code = '1', year = '2026-2027') {
  return Object.assign(new EasTermItem(), {
    yearCode: year, yearName: year, termCode: code,
    termName: ['', '秋季学期', '春季学期', '夏季学期', '冬季学期'][Number(code)], isCurrent: true
  });
}
function html({ caption = '2026年9月', days = [31, 1, 2, 3, 4, 5, 6], week = '第1周' } = {}) {
  return `<div>${caption}</div><table><tr><th>周次</th>` +
    ['一', '二', '三', '四', '五', '六', '日'].map(d => `<th>星期${d}</th>`).join('') +
    `</tr><tr><td>${week}</td>${days.map(d => `<td>${d}</td>`).join('')}</tr></table>`;
}

test('legacy calendars use actual week one, including both sides of a month boundary', () => {
  assert.equal(calendar.parseLegacyHtml(html(), term()), date(2026, 8, 31));
  assert.equal(calendar.parseLegacyHtml(html({ caption: '2026年8月' }), term()), date(2026, 8, 31));
  assert.equal(calendar.parseLegacyHtml(html({
    caption: '2026年8月', days: [24, 25, 26, 27, 28, 29, 30], week: '一'
  }), term()), date(2026, 8, 24));
  assert.equal(calendar.parseLegacyHtml(html({
    caption: '2026年2月', days: [23, 24, 25, 26, 27, 28, 1]
  }), term('2', '2025-2026')), date(2026, 2, 23));
});

test('Weihai monthly tables leave adjacent-month days blank on both sides of week one', () => {
  const august = html({ caption: '2026年8月', days: [31, '', '', '', '', '', ''], week: '1' });
  const september = html({ caption: '2026年9月', days: ['', 1, 2, 3, 4, 5, 6], week: '1' });
  for (const body of [august, september, august + september]) {
    assert.equal(calendar.parseLegacyHtml(body, term()), date(2026, 8, 31));
  }
  const selected = '<form><select name="xnxq"><option value="">-请选择-</option>' +
    '<option value="2026-20271" selected>2026秋季</option></select></form>';
  assert.equal(calendar.parseLegacyHtml(selected + august + september, term()), date(2026, 8, 31));
});

test('clipped calendar weeks work at year boundaries and with a Sunday-only month fragment', () => {
  const december = html({ caption: '2026年12月', days: [28, 29, 30, 31, '', '', ''] });
  const january = html({ caption: '2027年1月', days: ['', '', '', '', 1, 2, 3] });
  assert.equal(calendar.parseLegacyHtml(december + january, term('4')), date(2026, 12, 28));
  assert.equal(calendar.parseLegacyHtml(html({
    caption: '2026年3月', days: ['', '', '', '', '', '', 1]
  }), term('2', '2025-2026')), date(2026, 2, 23));
});

test('missing dates inside a month, misplaced days and empty week rows are not accepted', () => {
  for (const days of [
    ['', '', '', '', '', '', ''],
    [7, '', 9, 10, 11, 12, 13],
    ['', 2, 3, 4, 5, 6, 7],
    ['', 1, 2, 3, 4, 5, ''],
    [0, 1, 2, 3, 4, 5, 6],
    ['', 1, 'unknown', 3, 4, 5, 6]
  ]) {
    assert.equal(calendar.parseLegacyHtml(html({ days }), term()), undefined);
  }
});

test('legacy full dates do not require a month heading; reject non-Mondays and invalid dates', () => {
  assert.equal(calendar.parseLegacyHtml(html({ caption: '', days: ['2026年8月24日'] }), term()), date(2026, 8, 24));
  for (const text of ['2026-08-25', '2026-02-30', '2026-13-01', 'unknown']) {
    assert.equal(calendar.parseLegacyHtml(html({ caption: '', days: [text] }), term()), undefined);
  }
});

test('legacy calendars handle cross-year weeks and nested layout tables', () => {
  const body = html({ caption: '2027年1月', days: [28, 29, 30, 31, 1, 2, 3] });
  assert.equal(calendar.parseLegacyHtml(`<table><tr><td>${body}</td></tr></table>`, term('4')),
    date(2026, 12, 28));
});

test('legacy calendar rowspans do not shift the week or Monday column', () => {
  const body = `<div>2026年9月</div><table>
    <tr><th>月份</th><th>周次</th><th>星期一</th><th>星期二</th><th>星期三</th>
    <th>星期四</th><th>星期五</th><th>星期六</th><th>星期日</th></tr>
    <tr><td rowspan="2">9月</td><td>0</td><td>24</td><td>25</td><td>26</td><td>27</td>
    <td>28</td><td>29</td><td>30</td></tr>
    <tr><td>1</td><td>31</td><td>1</td><td>2</td><td>3</td><td>4</td><td>5</td><td>6</td></tr>
    </table>`;
  assert.equal(calendar.parseLegacyHtml(body, term()), date(2026, 8, 31));
});

test('calendar parser never substitutes today, a different semester, week two or conflicting dates', () => {
  assert.equal(calendar.parseLegacyHtml(html({ week: '2' }), term()), undefined);
  assert.equal(calendar.parseLegacyHtml(html(), term('1', '2025-2026')), undefined);
  assert.equal(calendar.parseLegacyHtml('<form name="login"><input name="password"></form>', term()), undefined);
  const selector = '<form><select name="xnxq"><option value="2025-20261" selected>old</option></select></form>';
  assert.equal(calendar.parseLegacyHtml(selector + html(), term()), undefined);
  assert.equal(calendar.parseLegacyHtml(html() + html({
    caption: '2026年9月', days: [7, 8, 9, 10, 11, 12, 13]
  }), term()), undefined);
});

test('Shenzhen week-one dates support wrappers, unsorted days and explicit single rows', () => {
  for (const body of [
    [{ RQ: '2026-09-06' }, { RQ: '2026-08-31' }],
    { code: 200, data: { rqList: [{ rq: '2026-09-01' }] } },
    { content: { XN: '2026-2027', XQ: '1', DJZ: 1, KSRQ: '2026-08-31 00:00:00' } }
  ]) {
    assert.equal(calendar.parseShenzhenJson(JSON.stringify(body), term()), date(2026, 8, 31));
  }
  assert.equal(calendar.parseShenzhenJson(JSON.stringify([{ RQ1: '2026-02-23' }]),
    term('02', '2025-2026')), date(2026, 2, 23));
});

test('Shenzhen calendar rejects errors, stale metadata, week-two rows and inconsistent weeks', () => {
  for (const body of [
    { code: 500, data: [{ RQ: '2026-08-31' }] },
    [{ XN: '2025-2026', RQ: '2026-08-31' }],
    [{ XQ: '2', RQ: '2026-08-31' }],
    [{ ZC: 2, RQ: '2026-09-07' }],
    [{ RQ: '2026-08-31' }, { RQ: '2026-09-07' }],
    [{ RQ: '2026-02-30' }], [{ RQ: '2026-02-30T00:00:00+08:00' }], { content: [] }
  ]) {
    assert.equal(calendar.parseShenzhenJson(JSON.stringify(body), term()), undefined);
  }
  assert.equal(calendar.parseShenzhenJson('<html>login</html>', term()), undefined);
});

test('calendar timestamps are interpreted as campus dates rather than the previous UTC day', () => {
  for (const RQ of ['2026-08-30T16:00:00.000Z', '2026-08-31T00:00:00+08:00',
    Date.UTC(2026, 7, 30, 16), Date.UTC(2026, 7, 30, 16) / 1000]) {
    assert.equal(calendar.parseShenzhenJson(JSON.stringify({ data: [{ RQ }] }), term()), date(2026, 8, 31));
  }
});

test('a following non-calendar table cannot reuse a previous calendar header', () => {
  const body = html() + '<table><tr><td>1</td><td>2026-09-07</td></tr></table>';
  assert.equal(calendar.parseLegacyHtml(body, term()), date(2026, 8, 31));
});

test('calendar requests use the campus-specific endpoint and selected semester', async () => {
  for (const campus of [EasCampus.BENBU, EasCampus.WEIHAI, EasCampus.SHENZHEN]) {
    const calls = [];
    const provider = new EasDataProvider({
      async request(session, cfg, endpoint, options) {
        calls.push({ endpoint, options });
        return { statusCode: 200, body: campus === EasCampus.SHENZHEN ?
          JSON.stringify({ data: [{ RQ: '2026-08-31' }] }) : html() };
      }
    });
    const session = Object.assign(new EasSession(), { campus, webBaseUrl: 'https://jw.example.edu.cn' });
    assert.equal(await provider.getStartDate(session, term()), date(2026, 8, 31));
    assert.equal(calls.length, 1);
    assert.equal(calls[0].options.method, 'POST');
    const form = new URLSearchParams(calls[0].options.body);
    if (campus === EasCampus.SHENZHEN) {
      assert.equal(calls[0].endpoint, '/component/queryRlZcSj');
      assert.equal(form.get('xn'), '2026-2027');
      assert.equal(form.get('xq'), '1');
      assert.equal(form.get('djz'), '1');
    } else {
      assert.equal(calls[0].endpoint, '/xlcx/queryXlcx');
      assert.equal(form.get('xnxq'), '2026-20271');
    }
  }
});

test('calendar failures are distinct from authentication expiry', async () => {
  const session = Object.assign(new EasSession(), { campus: EasCampus.WEIHAI });
  for (const statusCode of [0, 404, 500]) {
    const provider = new EasDataProvider({ request: async () => ({ statusCode, body: html() }) });
    assert.equal(await provider.getStartDate(session, term()), undefined);
  }
  for (const statusCode of [401, 403]) {
    const provider = new EasDataProvider({ request: async () => ({ statusCode, body: '' }) });
    await assert.rejects(provider.getStartDate(session, term()), /会话已失效/);
  }
});

test('date resolution prefers the calendar, labels saved fallback, and leaves unknown dates empty', async () => {
  const session = Object.assign(new EasSession(), { campus: EasCampus.WEIHAI });
  const db = { getTimetableByEasCode: async key => {
    assert.equal(key, 'WEIHAI:2026-20271');
    return { startTime: date(2026, 9, 14) };
  } };
  let result = await importer.loadStartDate(db, { getStartDate: async () => date(2026, 8, 24) }, session, term());
  assert.equal(result.startTime, date(2026, 8, 24));
  assert.equal(result.fromSaved, false);
  result = await importer.loadStartDate(db, { getStartDate: async () => undefined }, session, term());
  assert.equal(result.startTime, date(2026, 9, 14));
  assert.equal(result.fromSaved, true);
  result = await importer.loadStartDate({ getTimetableByEasCode: async () => undefined },
    { getStartDate: async () => undefined }, session, term());
  assert.equal(result.startTime, 0);
  await assert.rejects(importer.loadStartDate(db, {
    getStartDate: async () => { throw new Error('教务会话已失效，请重新登录'); }
  }, session, term()), /会话已失效/);
});

function importSetup({ remote = date(2026, 8, 24), savedDate, selectedTerms = [term()], weeks = [1, 3] } = {}) {
  const events = [];
  let timetable = savedDate === undefined ? undefined : Object.assign(new EasTimetable(), {
    id: 'existing', code: 'WEIHAI:2026-20271', startTime: savedDate
  });
  const calls = { calendar: 0, writes: 0, timetable: 0 };
  const db = {
    init: async () => {},
    getTimetableByEasCode: async () => timetable,
    getTimetableById: async () => timetable,
    getSubjectsOfTimetable: async () => [],
    saveImportedTimetable: async (item, subjects, incoming, replaceCourses) => {
      assert.equal(replaceCourses, timetable !== undefined);
      calls.writes++;
      timetable = item;
      events.splice(0, events.length, ...incoming);
    },
    getEventsOfTimetable: async () => events
  };
  const session = Object.assign(new EasSession(), { campus: EasCampus.WEIHAI });
  class Provider {
    importWarnings = [];
    async getAllTerms() { return selectedTerms; }
    async getStartDate() { calls.calendar++; return remote; }
    async getTimetableOfTerm() {
      calls.timetable++;
      return [Object.assign(new EasCourseItem(), {
        name: 'Calendar regression', weekNumbers: weeks, dayOfWeek: 3, beginSection: 7, sectionCount: 2
      })];
    }
    async getLegacyCourseAttributes() { return { rows: [], diag: '' }; }
  }
  const mocks = {
    '../../common/db/RdbHelper': { RdbHelper: { getInstance: () => db } },
    './EasSessionStore': { EasSessionStore: { getInstance: () => ({
      init: async () => {}, loadPreferred: async () => session
    }) } },
    './EasDataProvider': { EasDataProvider: Provider }
  };
  return { ...load('feature/eas/EasTimetableImporter.ets', mocks), calls, events, getTimetable: () => timetable };
}

test('importer saves real calendar dates and expands teaching weeks without offset', async () => {
  const setup = importSetup({ savedDate: date(2026, 8, 31) });
  const result = await setup.EasTimetableImporter.importCurrent({});
  assert.equal(result.success, true);
  assert.equal(result.timetable.id, 'existing');
  assert.equal(result.timetable.startTime, date(2026, 8, 24));
  assert.equal(setup.events[0].from, new Date(2026, 7, 26, 16, 5).getTime());
  assert.equal(setup.events[1].from, new Date(2026, 8, 9, 16, 5).getTime());
  assert.equal(result.timetable.getWeekNumber(date(2026, 9, 9)), 3);
  assert.equal(result.timetable.getWeekNumber(date(2026, 9, 28)), -1);
});

test('manual dates are normalized to week-one Monday and are not overwritten by remote data', async () => {
  const setup = importSetup();
  const result = await setup.EasTimetableImporter.importCurrent({}, term(), date(2026, 9, 9));
  assert.equal(result.success, true);
  assert.equal(result.timetable.startTime, date(2026, 9, 7));
  assert.equal(setup.calls.calendar, 0);
});

test('unavailable and invalid dates or disappeared terms cause no destructive database writes', async () => {
  for (const invalid of [0, NaN, Infinity, 1e20]) {
    const setup = importSetup();
    const result = await setup.EasTimetableImporter.importCurrent({}, term(), invalid);
    assert.equal(result.success, false);
    assert.equal(setup.calls.writes, 0);
  }
  const missing = importSetup({ remote: null });
  const result = await missing.EasTimetableImporter.importCurrent({});
  assert.equal(result.success, false);
  assert.match(result.message, /手动选择/);
  assert.equal(missing.calls.writes, 0);
  const stale = importSetup({ selectedTerms: [term('2')] });
  assert.equal((await stale.EasTimetableImporter.importCurrent({}, term())).success, false);
  assert.equal(stale.calls.timetable, 0);
  assert.equal(stale.calls.writes, 0);
});

test('existing dates remain available on network failure with an explicit fallback warning', async () => {
  const setup = importSetup({ remote: null, savedDate: date(2026, 9, 7) });
  const result = await setup.EasTimetableImporter.importCurrent({});
  assert.equal(result.success, true);
  assert.equal(result.timetable.startTime, date(2026, 9, 7));
  assert.match(result.message, /沿用本地设置/);
});

test('database startup no longer rewrites saved dates to a hard-coded autumn Monday', () => {
  const source = fs.readFileSync(path.join(root, 'common/db/RdbHelper.ets'), 'utf8');
  assert.doesNotMatch(source, /repairLegacyAutumnTermStart|autumnTermStart/);
});

test('import page ignores late calendar responses after changing the selected term', async () => {
  const pending = [];
  const { ImportTimetablePanel } = load('pages/ImportTimetablePanel.ets', {
    '../common/db/RdbHelper': { RdbHelper: { getInstance: () => ({ init: async () => {} }) } },
    '../feature/eas/EasTimetableImporter': { EasTimetableImporter: {
      loadStartDate: async (db, provider, session, term) =>
        new Promise(resolve => pending.push({ term, resolve })),
      scheduleStructure: () => []
    } }
  });
  const page = new ImportTimetablePanel();
  page.getUIContext = () => ({ getHostContext: () => ({}) });
  page.session = Object.assign(new EasSession(), { campus: EasCampus.WEIHAI });
  page.terms = [term(), term('2')];
  page.selectedTermIndex = 0;
  const first = page.loadTermDetails();
  await new Promise(resolve => setImmediate(resolve));
  page.selectedTermIndex = 1;
  const second = page.loadTermDetails();
  await new Promise(resolve => setImmediate(resolve));
  pending[1].resolve({ startTime: date(2027, 3, 1), fromSaved: false });
  await second;
  pending[0].resolve({ startTime: date(2026, 8, 24), fromSaved: false });
  await first;
  assert.equal(page.startTime, date(2027, 3, 1));
  assert.equal(page.detailsLoading, false);
});

test('manual date selection uses Monday, and cannot race an in-flight calendar request', () => {
  const { ImportTimetablePanel } = load('pages/ImportTimetablePanel.ets');
  const page = new ImportTimetablePanel();
  const pickers = [];
  page.getUIContext = () => ({ showDatePickerDialog: picker => pickers.push(picker) });
  page.detailsLoading = true;
  page.chooseStartDate();
  assert.equal(pickers.length, 0);
  page.detailsLoading = false;
  page.chooseStartDate();
  pickers[0].onDateAccept(new Date(2026, 8, 9, 15));
  assert.equal(page.startTime, date(2026, 9, 7));
  page.chooseStartDate();
  page.detailsGeneration++;
  pickers[1].onDateAccept(new Date(2026, 7, 31));
  assert.equal(page.startTime, date(2026, 9, 7));
});

test('imported week choices end at the last real course week, not a fixed 25 weeks', async () => {
  for (const lastWeek of [3, 17, 21]) {
    const setup = importSetup({ weeks: [1, lastWeek] });
    const result = await setup.EasTimetableImporter.importCurrent({});
    assert.equal(result.success, true);
    assert.equal(result.timetable.endTime, result.timetable.startTime + lastWeek * 7 * 86400000 - 1);
    assert.equal(result.timetable.getWeekNumber(result.timetable.endTime), lastWeek);
  }
});
