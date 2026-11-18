const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

function setup() {
  const root = path.resolve(__dirname, '../entry/src/main/ets');
  const modules = new Map();
  const data = new Map();
  let requests = 0;
  global.AppStorage = { get() { return 0; }, setOrCreate() {} };
  function load(file) {
    file = path.resolve(root, file);
    if (modules.has(file)) return modules.get(file).exports;
    const mod = { exports: {} };
    modules.set(file, mod);
    const req = name => {
      if (name === '@kit.ArkData') return { preferences: { getPreferences: async () => ({
        get: async (key, fallback) => data.get(key) ?? fallback,
        put: async (key, value) => { data.set(key, value); },
        delete: async key => { data.delete(key); }, flush: async () => {}
      }) } };
      if (name === '@kit.NetworkKit') return { http: { createHttp() { requests++; throw Error('Unexpected network'); } } };
      if (name === '@kit.PerformanceAnalysisKit') return { hilog: { info() {}, warn() {}, error() {} } };
      if (name.startsWith('@kit.')) return {};
      return load(path.resolve(path.dirname(file), name + '.ets'));
    };
    const js = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
    }).outputText;
    new Function('require', 'module', 'exports', js)(req, mod, mod.exports);
    return mod.exports;
  }
  const { DemoAccount } = load('feature/eas/demo/DemoAccount.ets');
  const { EasSession } = load('feature/eas/EasSession.ets');
  const { EasSessionStore } = load('feature/eas/EasSessionStore.ets');
  return { load, DemoAccount, EasSession, store: EasSessionStore.getInstance(), data, requests: () => requests };
}

test('older Shenzhen local sessions keep their mode and discard placeholder account details', () => {
  const { DemoAccount, EasSession } = setup();
  const legacy = DemoAccount.createSession();
  legacy.username = 'legacy-local-account';
  legacy.stuId = 'legacy-local-account';
  legacy.name = '演示同学';
  const restored = EasSession.decode(legacy.encode());
  assert.equal(DemoAccount.isSession(restored), true);
  assert.equal(restored.isLogin(), true);
  assert.equal(restored.username, '');
  assert.equal(restored.stuId, '');
  assert.equal(restored.name, '');
});

test('demo session persists without school credentials, survives expiry calls and logs out normally', async () => {
  const { DemoAccount: demo, EasSession, store } = setup();
  await store.init({});
  const session = demo.createSession();
  assert.equal(session.isLogin(), true);
  assert.equal(session.hasShenzhenWebSession(), true);
  assert.equal(session.webCookies.size, 0);
  assert.equal(session.accessToken, '');
  assert.equal(session.password, '');
  assert.equal(await store.save(session), true);
  const restored = await store.loadPreferred();
  assert.equal(demo.isSession(restored), true);
  await store.markExpired(restored, 'late failure');
  assert.equal((await store.loadPreferred()).loginExpired, false);
  const staleRealRequest = EasSession.decode(restored.encode());
  staleRealRequest.demoMode = false;
  await store.markExpired(staleRealRequest, 'late real-account failure');
  assert.equal((await store.loadPreferred()).loginExpired, false);
  const ordinary = new EasSession();
  ordinary.username = session.username;
  ordinary.stuId = session.stuId;
  assert.equal(demo.isSession(ordinary), false, 'matching student number alone is not a demo session');
  assert.equal(EasSession.decode('{}').demoMode, false);
  const benbuLocal = EasSession.decode(demo.createSession('BENBU').encode());
  assert.equal(demo.isSession(benbuLocal), true);
  assert.equal(benbuLocal.hasShenzhenWebSession(), false);
  await store.clear('SHENZHEN');
  assert.equal(await store.loadPreferred(), undefined);
});

test('demo HTTP and silent renewal never reach school services', async () => {
  const h = setup();
  const { EasApiClient, EasApiClientOptions } = h.load('feature/eas/EasApiClient.ets');
  const { EasSessionRenewal } = h.load('feature/eas/EasSessionRenewal.ets');
  const session = h.DemoAccount.createSession();
  await assert.rejects(new EasApiClient().request(session, {}, '/anything', new EasApiClientOptions()), /暂无数据/);
  assert.equal(h.requests(), 0);
  const renewal = new EasSessionRenewal();
  renewal.attach(async () => assert.fail('Demo must not open a hidden authentication Web'));
  assert.equal(await renewal.renew(session, 'test'), false);
});
