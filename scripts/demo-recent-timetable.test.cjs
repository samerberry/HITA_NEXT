const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const source = fs.readFileSync(path.resolve(__dirname, '../entry/src/main/ets/pages/Home.ets'), 'utf8');
const from = source.indexOf('  private async openRecentTimetable()');
const method = source.slice(from, source.indexOf('\n  /**', from));
function setup() {
  const routes = [], toasts = [];
  const compiled = ts.transpileModule('class Home { ' + method + ' }', {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const page = new Function(compiled + '; return new Home();')();
  page.pageVisible = true;
  page.getUIContext = () => ({
    getPromptAction: () => ({ showToast: value => toasts.push(value.message) }),
    getRouter: () => ({ pushUrl: async value => routes.push(value) })
  });
  page.refreshSummaries = async () => {};
  page.importTimetable = async () => assert.fail('Unexpected import');
  return { page, routes, toasts };
}

test('recent shortcut refreshes before routing, so an old cached table cannot win', async () => {
  const { page, routes } = setup();
  page.recentTimetable = { id: 'real' };
  page.refreshSummaries = async () => { page.recentTimetable = { id: 'demo' }; };
  await page.openRecentTimetable();
  assert.deepEqual(routes, [{ url: 'pages/TimetableDetailPage', params: { timetableId: 'demo' } }]);
});

test('explicit tap retries a missing demo import and opens only the restored demo', async () => {
  const { page, routes } = setup();
  page.sessionInfo = { demoMode: true };
  let imports = 0;
  page.importTimetable = async () => { imports++; page.recentTimetable = { id: 'restored-demo' }; };
  await page.openRecentTimetable();
  assert.equal(imports, 1);
  assert.equal(routes[0].params.timetableId, 'restored-demo');
});

test('pending import, missing local data and read errors produce feedback instead of silent taps', async () => {
  const { page, routes, toasts } = setup();
  page.importing = true;
  await page.openRecentTimetable();
  assert.match(toasts.pop(), /正在准备/);
  page.importing = false;
  await page.openRecentTimetable();
  assert.match(toasts.pop(), /请先导入/);
  page.refreshSummaries = async () => { throw Error('read failed'); };
  await page.openRecentTimetable();
  assert.match(toasts.pop(), /无法打开/);
  assert.equal(page.openingRecentTimetable, false);
  assert.equal(routes.length, 0);
});

test('duplicate taps and leaving the page cannot open extra or late detail pages', async () => {
  const { page, routes } = setup();
  let release;
  page.recentTimetable = { id: 'demo' };
  page.refreshSummaries = () => new Promise(resolve => { release = resolve; });
  const pending = page.openRecentTimetable();
  await page.openRecentTimetable();
  page.pageVisible = false;
  release();
  await pending;
  assert.equal(routes.length, 0);
  assert.equal(page.openingRecentTimetable, false);
});

test('failed demo restoration does not navigate to another account table', async () => {
  const { page, routes, toasts } = setup();
  page.sessionInfo = { demoMode: true };
  page.importTimetable = async () => { toasts.push('导入失败，请重试'); };
  await page.openRecentTimetable();
  assert.equal(routes.length, 0);
  assert.match(toasts[0], /重试/);
});
