const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const root = path.resolve(__dirname, '../entry/src/main/ets');
function setup() {
  const data = new Map();
  const reads = [];
  const cache = new Map();
  const preferences = {
    getPreferences: async () => ({
      get: async (key, fallback) => {
        reads.push(key);
        return data.has(key) ? data.get(key) : fallback;
      },
      put: async () => assert.fail('Session selection must not write preferences'),
      delete: async () => assert.fail('Session selection must not delete preferences')
    })
  };
  function load(file) {
    file = path.resolve(root, file);
    if (cache.has(file)) return cache.get(file).exports;
    const mod = { exports: {} };
    cache.set(file, mod);
    const output = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
    }).outputText;
    const requireLocal = name => {
      if (name === '@kit.ArkData') return { preferences };
      assert.ok(name.startsWith('.'), name);
      return load(path.resolve(path.dirname(file), name + '.ets'));
    };
    new Function('require', 'module', 'exports', output)(requireLocal, mod, mod.exports);
    return mod.exports;
  }
  const { EasSessionStore } = load('feature/eas/EasSessionStore.ets');
  const { EasSession, EasCampus } = load('feature/eas/EasSession.ets');
  return { data, reads, store: new EasSessionStore(), EasSession, EasCampus };
}

test('uninitialized and empty session stores do not invent a logged-in session', async () => {
  const { store, data } = setup();
  assert.equal(await store.loadPreferred(), undefined);
  await store.init({});
  assert.equal(await store.loadPreferred(), undefined);
  assert.equal(data.size, 0);
});

test('preferred session matches the old priority for every campus and login combination', async () => {
  const { data, reads, store, EasSession, EasCampus } = setup();
  await store.init({});
  const campuses = [EasCampus.BENBU, EasCampus.WEIHAI, EasCampus.SHENZHEN];
  for (const preferred of [undefined, ...campuses]) {
    for (let mask = 0; mask < 8; mask++) {
      data.clear();
      reads.length = 0;
      if (preferred !== undefined) data.set('eas_last_campus', preferred);
      for (const [index, campus] of campuses.entries()) {
        const session = new EasSession();
        session.campus = campus;
        if (mask & (1 << index)) session.webCookies.set('JSESSIONID', 'test-session');
        data.set('eas_session_' + campus, session.encode());
      }
      const order = preferred === undefined ? campuses :
        [preferred, ...campuses.filter(campus => campus !== preferred)];
      const expected = order.find(campus => mask & (1 << campuses.indexOf(campus)));
      assert.equal((await store.loadPreferred())?.campus, expected,
        `preferred=${preferred}, logged-in mask=${mask}`);
      const checked = reads.filter(key => key.startsWith('eas_session_'));
      assert.equal(new Set(checked).size, checked.length, 'each campus is checked at most once');
    }
  }
});

test('missing, corrupt and logged-out preferred sessions fall back without overwriting saved data', async () => {
  const { data, store, EasSession, EasCampus } = setup();
  await store.init({});
  const weihai = new EasSession();
  weihai.campus = EasCampus.WEIHAI;
  weihai.cookies.set('session', 'test-session');
  const loggedOut = new EasSession();
  loggedOut.campus = EasCampus.BENBU;
  data.set('eas_session_WEIHAI', weihai.encode());
  for (const preferred of ['BENBU', 'SHENZHEN', 'invalid']) {
    data.set('eas_last_campus', preferred);
    for (const raw of ['', '{invalid', loggedOut.encode()]) {
      data.set('eas_session_BENBU', raw);
      assert.equal((await store.loadPreferred()).campus, EasCampus.WEIHAI);
      assert.equal(data.get('eas_last_campus'), preferred);
      assert.equal(data.get('eas_session_BENBU'), raw);
    }
  }
});

test('all existing authentication forms and student types keep their serialized behavior', async () => {
  const { data, store, EasSession, EasCampus } = setup();
  await store.init({});
  for (const auth of ['accessToken', 'cookies', 'webCookies']) {
    for (const [input, expected] of [['1', '1'], ['2', '2'], [' 2 ', '2'], ['', '1']]) {
      const session = new EasSession();
      session.campus = EasCampus.SHENZHEN;
      session.setStudentType(input);
      if (auth === 'accessToken') session.accessToken = 'test-token';
      else session[auth].set('session', 'test-session');
      data.set('eas_session_SHENZHEN', session.encode());
      const loaded = await store.loadPreferred();
      assert.equal(loaded.campus, EasCampus.SHENZHEN);
      assert.equal(loaded.getStudentType(), expected);
      assert.equal(loaded.encode(), session.encode());
    }
  }
});

test('home and timetable import share session selection; active timetable actions remain wired', () => {
  const read = file => fs.readFileSync(path.join(root, file), 'utf8');
  for (const file of ['pages/Home.ets', 'feature/eas/EasTimetableImporter.ets']) {
    const source = read(file);
    assert.match(source, /await EasSessionStore\.getInstance\(\)\.loadPreferred\(\)/);
    assert.doesNotMatch(source, /const order: EasCampus\[\]/);
  }
  const home = read('pages/Home.ets');
  assert.doesNotMatch(home, /sessionText|gotoCurrentTimetableWeek|TAB_MORE/);
  assert.match(home, /Blank\(\)\.height\(this\.dockPageInset\(\) \+ HitaDesign\.spaceLg\)/);
  const manager = read('pages/TimetableManagerPage.ets');
  const card = manager.slice(manager.indexOf('  private addCard()'));
  for (const action of ['createEmptyTimetable', 'openImportPage', 'importIcs']) {
    assert.ok(card.includes(`this.${action}();`), action);
  }
  assert.match(read('pages/TimetableDetailPage.ets'), /this\.confirmDeleteCourse\(row\)/);
});
