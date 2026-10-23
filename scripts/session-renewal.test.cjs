const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const flush = async () => { for (let i = 0; i < 60; i++) await Promise.resolve(); };
const response = (body = '', statusCode = 200) => ({ statusCode, body, cookies: '', location: '' });
const terms = '<select name="xnxq"><option value="2026-20271">秋季</option></select>';
const PROMPT = 'hita-credential-prompt';

function setup() {
  const timers = new Map();
  const cache = new Map();
  const state = { now: 10000, cookie: '', currentUrl: '', navigations: [], scripts: [], stops: 0,
    activations: 0, probeResult: 'none' };
  let timerId = 0;
  const setTimer = (callback, delay) => {
    const id = ++timerId;
    timers.set(id, { callback, time: state.now + (delay ?? 0) });
    return id;
  };
  const clearTimer = id => timers.delete(id);
  const clock = class extends Date { static now() { return state.now; } };
  const web = {
    getUserAgent: () => 'test UA', setCustomUserAgent() {},
    loadUrl: url => state.navigations.push(url), stop: () => state.stops++,
    onActive: () => state.activations++,
    runJavaScript: async script => {
      state.scripts.push(script);
      return script.includes(PROMPT) ? state.probeResult : 'false';
    },
    getUrl: () => state.currentUrl
  };
  const webview = {
    WebviewController: class {
      constructor() { return web; }
      static addIntelligentTrackingPreventionBypassingList() {}
    },
    WebCookieManager: {
      fetchCookie: () => Promise.resolve(state.cookie),
      putAcceptCookieEnabled() {}, putAcceptThirdPartyCookieEnabled() {},
      isThirdPartyCookieAllowed: () => true
    }
  };
  const http = {
    RequestMethod: { GET: 'GET', POST: 'POST' }, HttpDataType: { STRING: 'STRING' },
    createHttp: () => ({
      request: async () => ({ responseCode: 200, result: terms }),
      destroy() {}
    })
  };
  const appState = new Map();
  global.AppStorage = { get: key => appState.get(key), setOrCreate: (key, value) => appState.set(key, value) };
  function load(file) {
    file = path.resolve(root, file);
    if (cache.has(file)) return cache.get(file).exports;
    const mod = { exports: {} };
    cache.set(file, mod);
    const localRequire = name => {
      if (name === '@kit.ArkWeb') return { webview };
      if (name === '@kit.NetworkKit') return { http };
      if (name === '@kit.BasicServicesKit') return { deviceInfo: { apiAvailable: () => true, sdkApiVersion: 26 } };
      if (name === '@kit.PerformanceAnalysisKit') return { hilog: { info() {}, warn() {}, error() {} } };
      if (name.startsWith('@kit.')) return {};
      assert.ok(name.startsWith('.'), name);
      return load(path.resolve(path.dirname(file), name + '.ets'));
    };
    const output = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
    }).outputText;
    new Function('require', 'module', 'exports', 'setTimeout', 'clearTimeout', 'Date', output)(
      localRequire, mod, mod.exports, setTimer, clearTimer, clock);
    return mod.exports;
  }
  async function tick(ms) {
    const end = state.now + ms;
    for (let guard = 0; guard < 1000; guard++) {
      await flush();
      const next = [...timers.entries()].filter(([, timer]) => timer.time <= end)
        .sort((a, b) => a[1].time - b[1].time)[0];
      if (!next) break;
      const [id, timer] = next;
      timers.delete(id);
      state.now = timer.time;
      timer.callback();
    }
    state.now = end;
    await flush();
  }
  const { EasSession, EasCampus } = load('feature/eas/EasSession.ets');
  const { EasSessionStore } = load('feature/eas/EasSessionStore.ets');
  const { EasApiClient, EasApiClientOptions } = load('feature/eas/EasApiClient.ets');
  const { EasSessionRenewal } = load('feature/eas/EasSessionRenewal.ets');
  const { EasSilentLogin, SILENT_LOGIN_TIMEOUT_MS } = load('feature/eas/webLogin/EasSilentLogin.ets');
  const { easWebLoginConfigFor, EasCampusUrls } = load('feature/eas/webLogin/EasWebLoginConfig.ets');

  const data = new Map();
  const store = new EasSessionStore();
  store.store = {
    get: async (key, fallback) => data.has(key) ? data.get(key) : fallback,
    put: async (key, value) => { data.set(key, value); },
    delete: async key => { data.delete(key); }, flush: async () => {}
  };
  EasSessionStore.instance = store;
  const session = (campus, jsession, name = '') => {
    const s = new EasSession();
    s.campus = campus;
    s.name = name;
    s.webCookies.set('JSESSIONID', jsession);
    s.webCookies.set('HIT', 'gateway');
    return s;
  };
  const request = (api, s, endpoint = '/kbcx/queryGrkb') =>
    api.request(s, easWebLoginConfigFor(s.campus, s.getStudentType()), endpoint, new EasApiClientOptions());
  return { state, web, timers, tick, load, store, appState, session, request, EasSession, EasCampus,
    EasApiClient, EasSessionRenewal, EasSilentLogin, SILENT_LOGIN_TIMEOUT_MS, EasCampusUrls };
}

/** Server fixture: only the listed session cookie is still accepted. */
function serveOnly(h, accepted, rejected = response('', 401)) {
  const sent = [];
  h.EasApiClient.doHttp = async (url, method, header) => {
    const cookie = header.get('Cookie') ?? '';
    sent.push(cookie);
    return cookie.includes('JSESSIONID=' + accepted) ? response(terms) : rejected;
  };
  return sent;
}

function renewalWith(h, runner) {
  const renewal = new h.EasSessionRenewal();
  renewal.attach(runner);
  return renewal;
}

test('an authentication failure renews silently, keeps the account and campus choice, and retries once', async () => {
  const h = setup();
  const saved = h.session(h.EasCampus.BENBU, 'old', 'Fixture');
  await h.store.save(saved);
  await h.store.save(h.session(h.EasCampus.WEIHAI, 'weihai'));
  const revision = h.appState.get('hita_eas_session_revision');
  const logins = [];
  renewalWith(h, async (campus, studentType) => {
    logins.push([campus, studentType]);
    return h.session(campus, 'fresh');
  });
  const sent = serveOnly(h, 'fresh');
  const result = await h.request(new h.EasApiClient(), saved);
  assert.equal(result.body, terms);
  assert.deepEqual(logins, [[h.EasCampus.BENBU, '1']]);
  assert.equal(sent.length, 2);
  assert.match(sent[1], /JSESSIONID=fresh/);
  const stored = await h.store.load(h.EasCampus.BENBU);
  assert.equal(stored.loginExpired, false);
  assert.equal(stored.name, 'Fixture');
  assert.equal(stored.webCookies.get('JSESSIONID'), 'fresh');
  assert.equal(saved.sessionGeneration, stored.sessionGeneration, 'later requests reuse the renewed session');
  assert.equal(saved.webCookies.get('JSESSIONID'), 'fresh');
  assert.equal(await h.store.loadLastCampus(), h.EasCampus.WEIHAI);
  assert.equal(h.appState.get('hita_eas_session_revision'), revision + 1);
});

test('the retry after a renewal bypasses the HTTP cache, so a cached sign-in page cannot expire the new session', async () => {
  const h = setup();
  const saved = h.session(h.EasCampus.WEIHAI, 'old');
  await h.store.save(saved);
  renewalWith(h, async campus => h.session(campus, 'fresh'));
  const cacheFlags = [];
  h.EasApiClient.doHttp = async (url, method, header, body, timeout, useCache) => {
    cacheFlags.push(useCache);
    // A caching client would replay the stored sign-in page whenever the cache may be used.
    return useCache ? response('', 401) : response(terms);
  };
  assert.equal((await h.request(new h.EasApiClient(), saved)).body, terms);
  assert.deepEqual(cacheFlags, [true, false]);
  assert.equal((await h.store.load(h.EasCampus.WEIHAI)).loginExpired, false);
});

test('when sign-in is required the session stays expired with its data, and the same generation is not retried', async () => {
  const h = setup();
  const saved = h.session(h.EasCampus.SHENZHEN, 'old', 'Fixture');
  await h.store.save(saved);
  let logins = 0;
  renewalWith(h, async () => { logins++; return undefined; });
  const sent = serveOnly(h, 'never');
  const result = await h.request(new h.EasApiClient(), saved);
  assert.equal(result.statusCode, 401);
  assert.equal(sent.length, 1, 'no retry without new credentials');
  const stored = await h.store.load(h.EasCampus.SHENZHEN);
  assert.equal(stored.loginExpired, true);
  assert.equal(stored.name, 'Fixture');
  assert.equal(stored.webCookies.get('JSESSIONID'), 'old');
  await h.request(new h.EasApiClient(), saved);
  assert.equal(logins, 1);
});

test('a renewal that fails before expiry is recorded is not repeated for the same generation', async () => {
  const h = setup();
  const saved = h.session(h.EasCampus.WEIHAI, 'old');
  await h.store.save(saved);
  let logins = 0;
  const renewal = renewalWith(h, async () => { logins++; return undefined; });
  assert.equal(await renewal.renew(saved, 'fixture'), false);
  assert.equal(await renewal.renew(saved, 'fixture'), false);
  assert.equal(logins, 1);
  assert.equal((await h.store.load(h.EasCampus.WEIHAI)).loginExpired, false, 'only EasApiClient marks expiry');
});

test('concurrent authentication failures share one hidden login', async () => {
  const h = setup();
  const first = h.session(h.EasCampus.WEIHAI, 'old');
  await h.store.save(first);
  const second = h.EasSession.decode(first.encode());
  let release;
  let logins = 0;
  renewalWith(h, () => { logins++; return new Promise(resolve => { release = resolve; }); });
  const sent = serveOnly(h, 'fresh');
  const pending = [h.request(new h.EasApiClient(), first), h.request(new h.EasApiClient(), second)];
  await flush();
  release(h.session(h.EasCampus.WEIHAI, 'fresh'));
  const results = await Promise.all(pending);
  assert.deepEqual(results.map(r => r.body), [terms, terms]);
  assert.equal(logins, 1);
  assert.equal(sent.filter(cookie => cookie.includes('JSESSIONID=fresh')).length, 2);
});

test('a request holding an older generation reuses the renewed session without another login', async () => {
  const h = setup();
  const stale = h.session(h.EasCampus.BENBU, 'old');
  await h.store.save(stale);
  const staleCopy = h.EasSession.decode(stale.encode());
  await h.store.save(h.session(h.EasCampus.BENBU, 'fresh'));
  let logins = 0;
  renewalWith(h, async () => { logins++; return undefined; });
  const sent = serveOnly(h, 'fresh');
  assert.equal((await h.request(new h.EasApiClient(), staleCopy)).body, terms);
  assert.equal(logins, 0);
  assert.match(sent[1], /JSESSIONID=fresh/);
});

test('a manual login during renewal wins, and a logout is never undone', async () => {
  const h = setup();
  const saved = h.session(h.EasCampus.SHENZHEN, 'old');
  await h.store.save(saved);
  let release;
  renewalWith(h, () => new Promise(resolve => { release = resolve; }));
  const sent = serveOnly(h, 'manual');
  const pending = h.request(new h.EasApiClient(), saved);
  await flush();
  await h.store.save(h.session(h.EasCampus.SHENZHEN, 'manual', 'Manual'));
  release(h.session(h.EasCampus.SHENZHEN, 'silent'));
  assert.equal((await pending).body, terms);
  assert.match(sent.at(-1), /JSESSIONID=manual/);
  assert.equal((await h.store.load(h.EasCampus.SHENZHEN)).webCookies.get('JSESSIONID'), 'manual');

  const loggedOut = h.session(h.EasCampus.BENBU, 'old');
  await h.store.save(loggedOut);
  serveOnly(h, 'never');
  const afterLogout = h.request(new h.EasApiClient(), loggedOut);
  await flush();
  await h.store.clear(h.EasCampus.BENBU);
  release(h.session(h.EasCampus.BENBU, 'silent'));
  assert.equal((await afterLogout).statusCode, 401);
  assert.equal(await h.store.load(h.EasCampus.BENBU), undefined);
});

test('a Shenzhen aTrust login redirect starts the hidden login and the retry uses the renewed session', async () => {
  const h = setup();
  const saved = h.session(h.EasCampus.SHENZHEN, 'old');
  await h.store.save(saved);
  let logins = 0;
  renewalWith(h, async campus => { logins++; return h.session(campus, 'fresh'); });
  const sent = [];
  h.EasApiClient.doHttp = async (url, method, header, body, timeout, useCache, follow) => {
    const cookie = header.get('Cookie') ?? '';
    sent.push([cookie.includes('JSESSIONID=fresh'), follow]);
    if (cookie.includes('JSESSIONID=fresh')) return response(terms);
    return follow === false ?
      { statusCode: 302, body: '', cookies: '', location: 'https://trust.hitsz.edu.cn/portal/shortcut.html?r=1' } :
      response('<html>405 Not Allowed</html>', 405);
  };
  assert.equal((await h.request(new h.EasApiClient(), saved, '/component/queryXnxq')).body, terms);
  assert.equal(logins, 1);
  assert.deepEqual(sent, [[false, false], [true, false]]);
  assert.equal((await h.store.load(h.EasCampus.SHENZHEN)).loginExpired, false);
});

test('network, permission and unrecognized responses never start a hidden login', async () => {
  const h = setup();
  let logins = 0;
  renewalWith(h, async () => { logins++; return h.session(h.EasCampus.WEIHAI, 'fresh'); });
  for (const result of [response('', 0), response('maintenance', 503), response('Forbidden', 403),
    response('Not allowed', 405), response('unrecognized')]) {
    const saved = h.session(h.EasCampus.WEIHAI, 'old');
    await h.store.save(saved);
    h.EasApiClient.doHttp = async () => result;
    await h.request(new h.EasApiClient(), saved);
    assert.equal((await h.store.load(h.EasCampus.WEIHAI)).loginExpired, false);
  }
  assert.equal(logins, 0);
});

// ---------------------------------------------------------------------------
// Hidden Web login
// ---------------------------------------------------------------------------

function silent(h, campus, studentType = '1') {
  const mounted = { releases: 0 };
  const result = new h.EasSilentLogin(campus, studentType).run((url, controller, login) => {
    mounted.url = url;
    mounted.login = login;
    return () => { mounted.releases++; };
  });
  let settled;
  result.then(value => { settled = { value }; });
  mounted.result = () => settled;
  mounted.page = async url => {
    h.state.currentUrl = url;
    mounted.login.pageBegin(url);
    mounted.login.pageEnd(url);
    await flush();
  };
  mounted.login.attached();
  return mounted;
}

test('hidden login completes through the shared login flow and releases its web view', async () => {
  const h = setup();
  h.state.cookie = 'JSESSIONID=fresh; HIT=gateway';
  h.web.loadUrl = () => { throw Error('optional laboratory site unavailable'); };
  const run = silent(h, h.EasCampus.BENBU);
  assert.equal(run.url, h.EasCampusUrls.BENBU_LOGIN);
  assert.ok(h.state.activations > 0, 'an unattached web view must be activated to run scripts');
  await run.page(h.EasCampusUrls.BENBU_JWTS);
  await h.tick(0);
  assert.equal(run.result().value.webCookies.get('JSESSIONID'), 'fresh');
  assert.equal(run.releases, 1);
  assert.equal(h.timers.size, 0);
});

test('a CAS sign-in or MFA page ends hidden login without reading or filling the form', async () => {
  for (const url of ['https://ids.hit.edu.cn/authserver/login?service=x',
    'https://authserver.hitsz.edu.cn/authserver/reAuthCheck/reAuthLoginView.do']) {
    const h = setup();
    const run = silent(h, h.EasCampus.SHENZHEN);
    await run.page(url);
    await h.tick(0);
    assert.deepEqual(run.result(), { value: undefined });
    assert.equal(run.releases, 1);
    assert.ok(h.state.stops > 0);
    for (const script of h.state.scripts) assert.doesNotMatch(script, /\.value\s*=|\.submit\(|\.click\(\)/);
  }
});

test('a visible password or code input on a portal ends hidden login, but not on the Shenzhen EAS entry', async () => {
  const h = setup();
  h.state.probeResult = PROMPT;
  const run = silent(h, h.EasCampus.WEIHAI);
  await run.page('https://webvpn.hitwh.edu.cn/login');
  await h.tick(0);
  assert.deepEqual(run.result(), { value: undefined });

  const entry = setup();
  entry.state.probeResult = PROMPT;
  const sz = silent(entry, entry.EasCampus.SHENZHEN);
  await sz.page(entry.EasCampusUrls.SHENZHEN_PROXY_BASE + '/');
  await entry.tick(5000);
  assert.equal(sz.result(), undefined, 'the controller clicks unified login on this page');
  assert.equal(entry.state.scripts.some(script => script.includes(PROMPT)), false);
});

test('forms rendered after page end are found by the periodic check', async () => {
  const h = setup();
  const run = silent(h, h.EasCampus.SHENZHEN);
  await run.page('https://trust.hitsz.edu.cn/portal/');
  await h.tick(1000);
  assert.equal(run.result(), undefined);
  h.state.probeResult = PROMPT;
  await h.tick(1600);
  assert.deepEqual(run.result(), { value: undefined });
});

test('a main-frame load failure ends hidden login at once, but a navigation cancelled by a reload does not', async () => {
  const h = setup();
  const run = silent(h, h.EasCampus.SHENZHEN);
  run.login.mainFrameError('ERR_ABORTED');
  await h.tick(1000);
  assert.equal(run.result(), undefined);
  run.login.mainFrameError('ERR_EMPTY_RESPONSE');
  await h.tick(0);
  assert.deepEqual(run.result(), { value: undefined });
  assert.equal(run.releases, 1);
  assert.equal(h.timers.size, 0);
});

test('hidden login gives up after its time limit and leaves no timers behind', async () => {
  const h = setup();
  const run = silent(h, h.EasCampus.BENBU);
  await h.tick(h.SILENT_LOGIN_TIMEOUT_MS - 1);
  assert.equal(run.result(), undefined);
  await h.tick(1);
  assert.deepEqual(run.result(), { value: undefined });
  assert.equal(run.releases, 1);
  assert.equal(h.timers.size, 0);
});

test('a failed mount settles immediately', async () => {
  const h = setup();
  const result = await new h.EasSilentLogin(h.EasCampus.WEIHAI, '1').run(() => { throw Error('no window'); });
  assert.equal(result, undefined);
});
