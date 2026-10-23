const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const cache = new Map();
const requests = [];
function load(file) {
  file = path.resolve(root, file);
  if (cache.has(file)) return cache.get(file).exports;
  const mod = { exports: {} };
  cache.set(file, mod);
  const req = name => {
    if (name === '@kit.PerformanceAnalysisKit') return { hilog: { info() {}, warn() {}, error() {} } };
    if (name === '@kit.NetworkKit') return { http: {
      createHttp: () => ({
        request: async (url, options) => { requests.push({ url, options }); return { responseCode: 200, result: '' }; },
        destroy() {}
      }), RequestMethod: { GET: 'GET', POST: 'POST' }, HttpDataType: { STRING: 'STRING' }
    } };
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
const { EasDataProvider: Provider } = load('feature/eas/EasDataProvider.ets');
const { EasSession, EasCampus: Campus } = load('feature/eas/EasSession.ets');
const { EasSessionStatus: Status, isExpiredEasResponse } = load('feature/eas/EasSessionStatus.ets');
const { EasApiClient, EasApiClientOptions } = load('feature/eas/EasApiClient.ets');
const { easWebLoginConfigFor, EasCampusUrls } = load('feature/eas/webLogin/EasWebLoginConfig.ets');
const response = (body = '', statusCode = 200) => ({ body, statusCode });
const session = campus => {
  const saved = new EasSession();
  saved.campus = campus;
  saved.webBaseUrl = EasCampusUrls.SHENZHEN_PROXY_BASE;
  saved.webCookies.set('JSESSIONID', 'synthetic-session');
  return saved;
};
const terms = name => `<select name="${name}"><option value="2026-20271">秋季</option></select>`;
const shenzhenTerms = JSON.stringify({ code: 200, data: [{ xn: '2026-2027', xq: '1' }] });
// Minimal markup from the public, unauthenticated Benbu EAS redirect observed on 2026-10-15.
const benbuVpnShortcut = '<html><head><title>Loading...</title>' +
  '<script src="./old/jssdk/shortcut_api.js?v=fixture"></script>' +
  '<script src="./old/shortcut_main.js?v=fixture"></script></head>' +
  '<body><div id="loading">Loading...</div></body></html>';
// Reduced from the HTTP 200 returned with the affected saved session; no real token or identity.
const benbuVpnVerify = `<html><head><script>
    var sfDomainParam = "";
    var locationUrl = "https://ivpn.hit.edu.cn:443/controller/v1/public/verify?t=fixture";
    try {
        var args = location.search, pos = args.search('__sdpData=');
        var search = pos === -1 ? args : args.substring(0, pos - 1);
        sessionStorage.setItem('sdp-app-url-data', search + location.hash);
    } catch (e) {}
    if (sfDomainParam) {
        var delimiter = locationUrl.indexOf("?") === -1 ? "?" : "&";
        sfDomainParam = delimiter + "sfDomain=" + sfDomainParam;
    }
    navigator.userAgent.search('ms-office') == -1 && location.replace(locationUrl + sfDomainParam);
</script></head></html>`;

test('all campuses require authenticated business data rather than the presence of saved credentials', async () => {
  for (const campus of Object.values(Campus)) {
    const saved = session(campus);
    const original = saved.encode();
    const calls = [];
    const provider = new Provider({ request: async (s, cfg, endpoint, options) => {
      calls.push(endpoint);
      assert.equal(s, saved);
      assert.equal(cfg.campus, campus);
      assert.equal(options.useCache, false);
      assert.equal(options.extraHeaders.get('Cache-Control'), 'no-cache');
      assert.ok(options.timeoutMs <= 6000);
      if (campus === Campus.SHENZHEN) {
        assert.equal(options.method, 'POST');
        assert.equal(options.extraHeaders.get('RoleCode'), '01');
        return response(shenzhenTerms);
      }
      assert.equal(options.method, 'GET');
      assert.match(options.extraHeaders.get('Accept'), /text\/html/);
      return response('<a href="/loginCAS">教务首页</a>' + terms('xnxq'));
    } });
    assert.equal(await provider.checkSessionStatus(saved), Status.CONNECTED);
    assert.equal(calls.length, 1);
    assert.equal(saved.encode(), original, 'verification does not mutate credentials');
  }
});

test('expired cookies return expired for HTTP 401, login forms, redirects and JSON authentication failures', async () => {
  const expired = [
    response('', 401),
    response('<form action="/loginCAS?service=/kbcx/queryGrkb"><input type="password"></form>'),
    response('<form><input name=mm></form>'),
    response('<script>top.location.href="/cas/login";</script>'),
    response('<script>window.location.replace("/authentication/require");</script>'),
    response('<meta http-equiv="refresh" content="0;url=/cas/login">'),
    response('<p>教务会话已过期，请重新登录</p>'),
    response(JSON.stringify({ code: 401, msg: 'Unauthorized' })),
    response(JSON.stringify({ code: -1, msg: '未登录' })),
    response(JSON.stringify({ code: 'LOGIN_EXPIRED', data: [] }))
  ];
  for (const campus of Object.values(Campus)) {
    const saved = session(campus);
    assert.equal(saved.isLogin(), true, 'old presence predicate is not a validity check');
    for (const value of expired) {
      let calls = 0;
      const provider = new Provider({ request: async () => { calls++; return value; } });
      assert.equal(await provider.checkSessionStatus(saved), Status.EXPIRED, value.body);
      assert.equal(calls, 1, 'do not retry invalid credentials');
    }
  }
});

test('offline, maintenance, permission failures and unrecognized pages are never claimed connected or expired', async () => {
  for (const value of [response('', 0), response('maintenance', 503),
    response('rate limited', 429), response('Forbidden', 403), response('<html>Portal</html>'),
    response('{"data":[]}'), response('{"code":200,"msg":"OK"}')]) {
    const provider = new Provider({ request: async () => value });
    assert.equal(await provider.checkSessionStatus(session(Campus.WEIHAI)), Status.UNKNOWN, value.body);
  }
  const provider = new Provider({ request: async () => { throw Error('offline'); } });
  assert.equal(await provider.checkSessionStatus(session(Campus.BENBU)), Status.UNKNOWN);
  assert.equal(isExpiredEasResponse(response('<a href="/loginCAS">退出登录</a>' + terms('xnxq'))), false);
});

test('Benbu VPN authentication bootstrap is expired, but generic loading pages and gateway errors are not', async () => {
  for (const body of [benbuVpnShortcut, benbuVpnShortcut.replaceAll('./old/', 'https://ivpn.hit.edu.cn/portal/old/'),
    benbuVpnShortcut.replaceAll('?v=fixture', '').replaceAll('"', "'")]) {
    assert.equal(isExpiredEasResponse(response(body)), true);
    const provider = new Provider({ request: async () => response(body) });
    assert.equal(await provider.checkSessionStatus(session(Campus.BENBU)), Status.EXPIRED);
  }
  for (const value of [
    response('<title>Loading...</title><div id="loading">Loading...</div>'),
    response('<script src="./old/jssdk/shortcut_api.js"></script>'),
    response('<script src="./old/shortcut_main.js"></script>'),
    response('<!--' + benbuVpnShortcut + '-->' + terms('xnxq')),
    response(benbuVpnShortcut, 503),
    response(benbuVpnShortcut, 0)
  ]) {
    assert.equal(isExpiredEasResponse(value), false);
  }
});

test('Benbu SDP verification redirects through a variable require re-login instead of reporting missing terms', async () => {
  for (const body of [benbuVpnVerify, benbuVpnVerify.replace(':443', ''),
    benbuVpnVerify.replaceAll('"', "'"),
    benbuVpnVerify.replaceAll('locationUrl', 'verifyTarget'),
    benbuVpnVerify.replace('location.replace(', 'window.location.assign(')]) {
    assert.equal(isExpiredEasResponse(response(body)), true);
    const provider = new Provider({ request: async () => response(body) });
    assert.equal(await provider.checkSessionStatus(session(Campus.BENBU)), Status.EXPIRED);
    await assert.rejects(provider.getAllTerms(session(Campus.BENBU)), /教务会话已失效，请重新登录/);
  }
});

test('a VPN URL alone, ordinary redirects, and failed network requests do not prove session expiry', () => {
  for (const result of [
    response(benbuVpnVerify, 0), response(benbuVpnVerify, 503),
    response(benbuVpnVerify.replace('location.replace(locationUrl + sfDomainParam)', 'console.log(locationUrl)')),
    response(benbuVpnVerify.replace('/public/verify?', '/public/verifyHelp?')),
    response(benbuVpnVerify.replace('ivpn.hit.edu.cn', 'example.com')),
    response('<!--' + benbuVpnVerify + '-->' + terms('xnxq')),
    response('<script>/* ' + benbuVpnVerify.replace(/<[^>]*>/g, '') + ' */</script>' + terms('xnxq')),
    response('<a href="https://ivpn.hit.edu.cn/controller/v1/public/verify">VPN</a>' + terms('xnxq')),
    response('<script>var locationUrl="/kbcx/queryGrkb";location.replace(locationUrl);</script>')
  ]) {
    assert.equal(isExpiredEasResponse(result), false);
  }
});

test('term reads use the shared expiry decision and stop on either authenticated endpoint failure', async () => {
  const authResponses = [response('', 401), response(benbuVpnShortcut), response(benbuVpnVerify),
    response('<script>top.location.href="/loginCAS?service=/kbcx/queryGrkb";</script>'),
    response('<form action="/loginCAS?service=/kbcx/queryGrkb"><input type="password"></form>'),
    response('{"code":"LOGIN_EXPIRED"}')];
  for (const campus of [Campus.BENBU, Campus.WEIHAI]) {
    for (const failedEndpoint of [0, 1]) {
      for (const auth of authResponses) {
        let calls = 0;
        const provider = new Provider({ request: async (_s, _cfg, _path, options) => {
          assert.equal(options.useCache, false);
          assert.equal(options.extraHeaders.get('Cache-Control'), 'no-cache');
          return calls++ === failedEndpoint ? auth : response(terms('pageXnxq'));
        } });
        await assert.rejects(provider.getAllTerms(session(campus)), /教务会话已失效，请重新登录/);
        assert.equal(calls, failedEndpoint + 1, 'stop fetching once reauthentication is required');
      }
    }
  }
});

test('missing terms and transient failures are distinguished from expiry and retain valid endpoint fallback', async () => {
  for (const failure of [response('', 0), response('Forbidden', 403), response('maintenance', 503),
    response('<html>Unrecognized page</html>'), response('<select name="xnxq"></select>')]) {
    const provider = new Provider({ request: async () => failure });
    await assert.rejects(provider.getAllTerms(session(Campus.BENBU)),
      failure.statusCode === 0 ? /学期请求网络失败/ : /未获取到学期列表/);
    for (const validFirst of [true, false]) {
      let count = 0;
      const fallback = new Provider({ request: async () =>
        ((count++ === 0) === validFirst) ? response(terms(validFirst ? 'pageXnxq' : 'xnxq')) : failure });
      assert.equal((await fallback.getAllTerms(session(Campus.BENBU))).length, 1);
    }
  }
  for (const campus of Object.values(Campus)) {
    const saved = session(campus); saved.loginExpired = true;
    const provider = new Provider({ request: async () => assert.fail('known expiry must ask for login directly') });
    await assert.rejects(provider.getAllTerms(saved), /教务会话已失效，请重新登录/);
  }
});

test('fallback term endpoints still verify deployments with different schemas', async () => {
  for (const campus of [Campus.BENBU, Campus.WEIHAI, Campus.SHENZHEN]) {
    const paths = [];
    const provider = new Provider({ request: async (_s, _cfg, endpoint) => {
      paths.push(endpoint);
      if (paths.length === 1) return response('', 404);
      return response(campus === Campus.SHENZHEN ? shenzhenTerms : terms('pageXnxq'));
    } });
    assert.equal(await provider.checkSessionStatus(session(campus)), Status.CONNECTED);
    assert.equal(paths.length, 2);
  }
});

test('missing usable credentials expire locally without making requests', async () => {
  const provider = new Provider({ request: async () => { assert.fail('no credential, no request'); } });
  const saved = session(Campus.WEIHAI);
  saved.webCookies.clear();
  saved.accessToken = 'legacy-token';
  assert.equal(await provider.checkSessionStatus(saved), Status.EXPIRED);
});

test('bounded verification returns unknown on timeout even if an old response later succeeds', async () => {
  let release;
  const provider = new Provider({ request: () => new Promise(resolve => { release = resolve; }) });
  const pending = provider.checkSessionStatus(session(Campus.BENBU), 5);
  assert.equal(await pending, Status.UNKNOWN);
  release(response(terms('xnxq')));
  assert.equal(await pending, Status.UNKNOWN);
});

test('session probes disable the underlying HTTP response cache', async () => {
  requests.length = 0;
  const saved = session(Campus.WEIHAI);
  const options = new EasApiClientOptions();
  options.useCache = false;
  await new EasApiClient().request(saved, easWebLoginConfigFor(saved.campus, saved.getStudentType()),
    '/kbcx/queryGrkb', options);
  assert.equal(requests[0].options.usingCache, false);
  assert.match(requests[0].options.header.Cookie, /JSESSIONID=synthetic-session/);
});

const { EasSessionStore } = load('feature/eas/EasSessionStore.ets');
function storedSessions(data = new Map()) {
  const state = new Map();
  global.AppStorage = { get: key => state.get(key), setOrCreate: (key, value) => state.set(key, value) };
  const store = new EasSessionStore();
  store.store = {
    get: async (key, fallback) => data.has(key) ? data.get(key) : fallback,
    put: async (key, value) => { data.set(key, value); },
    delete: async key => { data.delete(key); }, flush: async () => {}
  };
  return { store, data, state };
}

test('saved expiry persists across store reloads and does not erase the account, cookies or selected campus', async () => {
  const { store, data } = storedSessions();
  const saved = session(Campus.SHENZHEN); saved.name = 'Fixture';
  await store.save(saved);
  await store.save(session(Campus.BENBU));
  await store.markExpired(saved);
  const current = await storedSessions(data).store.load(Campus.SHENZHEN);
  assert.equal(current.loginExpired, true);
  assert.equal(current.name, 'Fixture');
  assert.equal(current.webCookies.get('JSESSIONID'), 'synthetic-session');
  assert.equal(current.isLogin(), true);
  assert.equal(await store.loadLastCampus(), Campus.BENBU);
  assert.equal((await store.load(Campus.BENBU)).loginExpired, false);
  const legacy = JSON.parse(saved.encode()); delete legacy.loginExpired;
  assert.equal(EasSession.decode(JSON.stringify(legacy)).loginExpired, false);
});

test('real request path marks only definite authentication failures for each campus', async () => {
  const previousStore = EasSessionStore.instance;
  const previousHttp = EasApiClient.doHttp;
  try {
    for (const campus of Object.values(Campus)) {
      for (const result of [response('', 401), response('{"code":"LOGIN_EXPIRED"}'),
        response('<form action="/loginCAS"><input type="password"></form>')]) {
        const { store } = storedSessions(); EasSessionStore.instance = store;
        const saved = session(campus); await store.save(saved);
        EasApiClient.doHttp = async () => result;
        assert.equal(await new EasApiClient().request(saved, easWebLoginConfigFor(campus, '1'),
          '/fixture-business', new EasApiClientOptions()), result);
        assert.equal((await store.load(campus)).loginExpired, true);
      }
    }
  } finally { EasApiClient.doHttp = previousHttp; EasSessionStore.instance = previousStore; }
});

test('Benbu term failure persists expiry, updates the session revision and displays the re-login message', async () => {
  const previousStore = EasSessionStore.instance;
  const previousHttp = EasApiClient.doHttp;
  const { EasUserMessages } = load('feature/eas/EasUserMessages.ets');
  try {
    const { store, state } = storedSessions(); EasSessionStore.instance = store;
    const saved = session(Campus.BENBU); saved.name = 'Fixture';
    await store.save(saved);
    const revision = state.get('hita_eas_session_revision');
    EasApiClient.doHttp = async () => response(benbuVpnVerify);
    const provider = new Provider(new EasApiClient());
    await assert.rejects(provider.getAllTerms(saved), error => {
      assert.equal(EasUserMessages.fromError(error.message, '稍后再试'), '教务登录已过期，请重新登录后重试');
      return true;
    });
    const persisted = await store.load(Campus.BENBU);
    assert.equal(persisted.loginExpired, true);
    assert.equal(persisted.name, 'Fixture');
    assert.equal(persisted.webCookies.get('JSESSIONID'), 'synthetic-session');
    assert.equal(state.get('hita_eas_session_revision'), revision + 1);
    assert.equal((await store.loadPreferred()).loginExpired, true);
    assert.equal(EasUserMessages.fromError('学期请求网络失败', '稍后再试'), '无法连接教务系统，请检查网络后重试');
  } finally { EasApiClient.doHttp = previousHttp; EasSessionStore.instance = previousStore; }
});

test('retry callbacks use the same auth decision and never treat ordinary redirects as expiry', async () => {
  const previousStore = EasSessionStore.instance;
  const previousHttp = EasApiClient.doHttp;
  try {
    for (const result of [response(benbuVpnShortcut), response(benbuVpnVerify), response('', 302),
      response('<a href="/loginCAS">教务首页</a>' + terms('xnxq'))]) {
      const { store } = storedSessions(); EasSessionStore.instance = store;
      const saved = session(Campus.BENBU); await store.save(saved);
      let retries = 0;
      const api = new EasApiClient();
      api.setReloginHandler(async () => { retries++; return false; });
      EasApiClient.doHttp = async () => result;
      await api.request(saved, easWebLoginConfigFor(saved.campus, '1'),
        '/kbcx/queryGrkb', new EasApiClientOptions());
      assert.equal(retries, isExpiredEasResponse(result) ? 1 : 0);
    }
  } finally { EasApiClient.doHttp = previousHttp; EasSessionStore.instance = previousStore; }
});

test('network and non-auth failures never mark an account expired; arbitrary success does not clear known expiry', async () => {
  const previousStore = EasSessionStore.instance;
  const previousHttp = EasApiClient.doHttp;
  try {
    for (const result of [response('', 0), response('maintenance', 503), response('Forbidden', 403),
      response('Not allowed', 405), response('rate limit', 429), response('unrecognized'),
      response('<a href="/loginCAS">退出登录</a>'+terms('xnxq'))]) {
      const { store } = storedSessions(); EasSessionStore.instance = store;
      const saved = session(Campus.WEIHAI); await store.save(saved);
      EasApiClient.doHttp = async () => result;
      await new EasApiClient().request(saved, easWebLoginConfigFor(saved.campus, '1'),
        '/fixture-business', new EasApiClientOptions());
      assert.equal((await store.load(saved.campus)).loginExpired, false);
    }
    const { store } = storedSessions(); EasSessionStore.instance = store;
    const saved = session(Campus.WEIHAI); await store.save(saved); await store.markExpired(saved);
    EasApiClient.doHttp = async () => response(terms('xnxq'));
    await new EasApiClient().request(saved, easWebLoginConfigFor(saved.campus, '1'),
      '/fixture-business', new EasApiClientOptions());
    assert.equal((await store.load(saved.campus)).loginExpired, true);
    await store.save(saved);
    assert.equal((await store.load(saved.campus)).loginExpired, false);
  } finally { EasApiClient.doHttp = previousHttp; EasSessionStore.instance = previousStore; }
});

test('late old request cannot expire a new login or recreate a logged-out session', async () => {
  const previousStore = EasSessionStore.instance;
  const previousHttp = EasApiClient.doHttp;
  try {
    const { store } = storedSessions(); EasSessionStore.instance = store;
    const saved = session(Campus.SHENZHEN); await store.save(saved);
    let release;
    EasApiClient.doHttp = () => new Promise(resolve => { release = resolve; });
    const pending = new EasApiClient().request(saved, easWebLoginConfigFor(saved.campus, '1'),
      '/fixture-business', new EasApiClientOptions());
    const renewed = session(saved.campus); await store.save(renewed);
    release(response('', 401)); await pending;
    assert.ok(renewed.sessionGeneration > saved.sessionGeneration);
    assert.equal((await store.load(saved.campus)).loginExpired, false);
    await store.clear(saved.campus); await store.markExpired(renewed);
    assert.equal(await store.load(saved.campus), undefined);
  } finally { EasApiClient.doHttp = previousHttp; EasSessionStore.instance = previousStore; }
});

const gatewayLogin = 'https://trust.hitsz.edu.cn/portal/shortcut.html?redirect=https%3A%2F%2Fjw-hitsz-edu-cn.hitsz.edu.cn%2F';
const redirect = (location, statusCode = 302) => ({ statusCode, body: '', location });

test('a Shenzhen redirect to the aTrust login entry is expiry; other redirects and a plain 405 are not', () => {
  for (const value of [redirect(gatewayLogin), redirect(gatewayLogin.replace('.cn/', '.cn:443/'), 303),
    redirect('https://trust.hitsz.edu.cn/controller/v1/public/verify?t=fixture', 307),
    redirect('https://TRUST.hitsz.edu.cn/passport/v1/auth/cas?x=1')]) {
    assert.equal(isExpiredEasResponse(value), true, value.location);
  }
  for (const value of [response('<html>405 Not Allowed</html>', 405), response('', 302),
    redirect('https://jw-hitsz-edu-cn.hitsz.edu.cn/authentication/main'),
    redirect('https://trust.hitsz.edu.cn/portal/'),
    redirect('https://trust.hitsz.edu.cn.evil.example/portal/shortcut.html'),
    redirect('http://trust.hitsz.edu.cn/portal/shortcut.html'),
    { statusCode: 200, body: terms('xnxq'), location: gatewayLogin }]) {
    assert.equal(isExpiredEasResponse(value), false, value.location ?? value.body);
  }
});

test('Shenzhen requests stop at the gateway login redirect and persist expiry instead of a 405', async () => {
  const previousStore = EasSessionStore.instance;
  const previousHttp = EasApiClient.doHttp;
  try {
    const { store } = storedSessions(); EasSessionStore.instance = store;
    const saved = session(Campus.SHENZHEN); await store.save(saved);
    const calls = [];
    EasApiClient.doHttp = async (url, method, header, body, timeout, useCache, follow) => {
      calls.push(follow);
      return follow === false ? redirect(gatewayLogin) : response('<html>405 Not Allowed</html>', 405);
    };
    const result = await new EasApiClient().request(saved, easWebLoginConfigFor(saved.campus, '1'),
      '/component/queryXnxq', new EasApiClientOptions());
    assert.equal(result.location, gatewayLogin);
    assert.deepEqual(calls, [false], 'the gateway redirect itself is the evidence');
    assert.equal((await store.load(saved.campus)).loginExpired, true);
  } finally { EasApiClient.doHttp = previousHttp; EasSessionStore.instance = previousStore; }
});

test('other Shenzhen redirects are still followed, and other campuses follow redirects as before', async () => {
  const previousStore = EasSessionStore.instance;
  const previousHttp = EasApiClient.doHttp;
  try {
    const { store } = storedSessions(); EasSessionStore.instance = store;
    for (const campus of Object.values(Campus)) {
      const saved = session(campus); await store.save(saved);
      const calls = [];
      EasApiClient.doHttp = async (url, method, header, body, timeout, useCache, follow) => {
        calls.push(follow);
        return follow === false ? redirect(EasCampusUrls.SHENZHEN_PROXY_BASE + '/Xsxk/query/1') :
          response('<html>405 Not Allowed</html>', 405);
      };
      const result = await new EasApiClient().request(saved, easWebLoginConfigFor(campus, '1'),
        '/fixture-business', new EasApiClientOptions());
      assert.equal(result.statusCode, 405);
      assert.deepEqual(calls, campus === Campus.SHENZHEN ? [false, true] : [true]);
      assert.equal((await store.load(campus)).loginExpired, false);
    }
  } finally { EasApiClient.doHttp = previousHttp; EasSessionStore.instance = previousStore; }
});

test('Shenzhen term reads report the gateway login redirect as an expired session', async () => {
  const saved = session(Campus.SHENZHEN);
  saved.webCookies.set('SESSION', 'synthetic-proxy-session');
  const provider = new Provider({ request: async () => redirect(gatewayLogin) });
  await assert.rejects(provider.getAllTerms(saved), /深圳教务会话已失效，请重新登录/);
  const plain = new Provider({ request: async () => response('<html>405 Not Allowed</html>', 405) });
  await assert.rejects(plain.getAllTerms(saved), /未获取到深圳学期列表/);
});

test('login and expiry writes are serialized so a fresh login always clears the old flag', async () => {
  for (const expiryFirst of [true, false]) {
    const { store } = storedSessions();
    const old = session(Campus.BENBU); await store.save(old);
    const fresh = session(Campus.BENBU);
    const actions = expiryFirst ? [store.markExpired(old), store.save(fresh)] :
      [store.save(fresh), store.markExpired(old)];
    await Promise.all(actions);
    const loaded = await store.load(old.campus);
    assert.equal(loaded.loginExpired, false);
    assert.equal(loaded.sessionGeneration, fresh.sessionGeneration);
  }
});
