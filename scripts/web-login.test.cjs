const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');
global.$r = name => ({ id: -1, type: 10001, params: [name] });

const root = path.resolve(__dirname, '../entry/src/main/ets');
const flush = async () => { for (let i = 0; i < 60; i++) await Promise.resolve(); };
function setup(apiVersion = 26) {
  const timers = new Map();
  const cache = new Map();
  const state = { now: 10000, syncReads: 0, reads: 0, cookie: '', navigations: [],
    finished: [], errors: [], scripts: [], progress: [], requests: 0, exchanges: 0,
    resetCookies: 0, resetStorage: 0, allReads: 0 };
  let timerId = 0;
  const setTimer = (callback, delay) => {
    const id = ++timerId;
    timers.set(id, { callback, time: state.now + delay });
    return id;
  };
  const clearTimer = id => timers.delete(id);
  const clock = class extends Date { static now() { return state.now; } };
  const web = {
    getUserAgent: () => 'test UA', setCustomUserAgent() {},
    loadUrl: url => state.navigations.push(url), refresh() {}, stop() {}, removeCache() {},
    runJavaScript: async script => { state.scripts.push(script); return 'false'; },
    accessBackward: () => false,
    getUrl: () => state.currentUrl ?? ''
  };
  const webview = {
    WebviewController: class {
      constructor() { return web; }
      static addIntelligentTrackingPreventionBypassingList() {}
    },
    WebCookieManager: {
      fetchAllCookies: () => {
        state.allReads++;
        return state.fetchAllCookies ? state.fetchAllCookies() : Promise.resolve([]);
      },
      fetchCookieSync: () => { state.syncReads++; return state.cookie; },
      fetchCookie: (...args) => {
        state.reads++;
        return state.fetchCookie ? state.fetchCookie(...args) : Promise.resolve(state.cookie);
      },
      clearAllCookies: async () => {
        state.resetCookies++;
        if (state.clearCookies) await state.clearCookies();
        state.cookie = '';
      },
      putAcceptCookieEnabled() {}, putAcceptThirdPartyCookieEnabled() {},
      isThirdPartyCookieAllowed: () => true
    },
    WebStorage: { deleteAllData: () => state.resetStorage++ }
  };
  const http = {
    RequestMethod: { GET: 'GET' }, HttpDataType: { STRING: 'STRING' },
    createHttp: () => ({
      request: (url, options) => {
        state.requests++;
        if (url.includes('jwts-hit-edu-cn.vpn.hit.edu.cn') && url.includes('/kbcx/queryGrkb')) {
          state.benbuRequests = (state.benbuRequests ?? 0) + 1;
          state.benbuRequest = { url, options };
          if (state.benbuResponse) return state.benbuResponse();
        }
        if (url.includes('/wengine-vpn/cookie')) {
          state.exchanges++;
          return state.httpResponse ? state.httpResponse() :
            Promise.resolve({ responseCode: 200, result: 'JSESSIONID=inner-session' });
        }
        return Promise.resolve({
          responseCode: state.verificationStatus ?? 200,
          result: state.verificationBody ?? '<select name="xnxq"><option value="2026-20271">2026秋季</option></select>'
        });
      }, destroy() {}
    })
  };
  function load(file) {
    file = path.resolve(root, file);
    if (cache.has(file)) return cache.get(file).exports;
    let source = fs.readFileSync(file, 'utf8');
    if (file.endsWith('EasLoginPage.ets')) {
      source = source.slice(0, source.indexOf('\n  build()')) + '\n}';
      source = source.replace(/^@Component\r?\n/gm, '')
        .replace(/@(State|Prop|StorageProp)(\([^)]*\))?\s+/g, '')
        .replace('export struct ', 'export class ');
    }
    const mod = { exports: {} };
    cache.set(file, mod);
    const localRequire = name => {
      if (name === '@kit.ArkWeb') return { webview };
      if (name === '@kit.NetworkKit') return { http };
      if (name === '@kit.BasicServicesKit') return { deviceInfo: { apiAvailable: () => apiVersion >= 26, sdkApiVersion: apiVersion } };
      if (name === '@kit.PerformanceAnalysisKit') return { hilog: { info() {}, warn() {}, error() {} } };
      if (name.startsWith('@kit.')) return {};
      assert.ok(name.startsWith('.'), name);
      return load(path.resolve(path.dirname(file), name + '.ets'));
    };
    const output = ts.transpileModule(source, {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
    }).outputText;
    new Function('require', 'module', 'exports', 'setTimeout', 'clearTimeout', 'Date', output)(
      localRequire, mod, mod.exports, setTimer, clearTimer, clock);
    return mod.exports;
  }
  const { EasWebLoginController } = load('feature/eas/webLogin/EasWebLoginController.ets');
  const { EasCampusUrls: urls } = load('feature/eas/webLogin/EasWebLoginConfig.ets');
  const ctrl = new EasWebLoginController();
  ctrl.attachWeb(web);
  ctrl.onFinished = session => state.finished.push(session);
  ctrl.onError = text => { if (text) state.errors.push(text); };
  ctrl.onProgress = value => state.progress.push(value);
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
  async function page(url) {
    ctrl.notifyPageBegin(url);
    ctrl.notifyPageEnd(url);
    await flush();
  }
  return { ctrl, state, web, urls, tick, page, load, timers };
}

test('Benbu undergraduate login and cookie probes use the new VPN EAS address', () => {
  const h = setup();
  const { easWebLoginConfigFor } = h.load('feature/eas/webLogin/EasWebLoginConfig.ets');
  const cfg = easWebLoginConfigFor('BENBU', '1');
  const base = 'http://jwts-hit-edu-cn.vpn.hit.edu.cn:1080';
  assert.equal(cfg.loginUrl, base + '/loginCAS');
  assert.equal(cfg.jwtsUrl, cfg.loginUrl);
  assert.ok(cfg.cookieProbeUrls.includes(base + '/kbcx/queryGrkb'));
  assert.ok(cfg.cookieDomains.includes('jwts-hit-edu-cn.vpn.hit.edu.cn'));
  assert.equal(easWebLoginConfigFor('BENBU', '2').loginUrl, h.urls.BENBU_LOGIN);
  for (const key of ['BENBU_BASE', 'GRADUATE_BASE', 'EELABINFO_URL', 'SJJX_BASE']) {
    assert.ok(new URL(h.urls[key]).hostname.endsWith('.vpn.hit.edu.cn'), key);
  }
  for (const type of ['1', '2']) {
    const campusConfig = easWebLoginConfigFor('BENBU', type);
    for (const url of [campusConfig.loginUrl, campusConfig.jwtsUrl, ...campusConfig.cookieProbeUrls]) {
      assert.ok(new URL(url).hostname.endsWith('.vpn.hit.edu.cn'), url);
    }
    assert.ok(campusConfig.cookieDomains.every(host => host.endsWith('.vpn.hit.edu.cn')));
  }
});

test('Benbu recognizes the new VPN gateway without accepting lookalike or other-campus hosts', () => {
  const h = setup();
  const { isIvpnRedirectPage } = h.load('feature/eas/webLogin/EasWebLoginProbe.ets');
  for (const host of ['vpn.hit.edu.cn', 'ivpn.hit.edu.cn']) {
    assert.equal(isIvpnRedirectPage('https://' + host + '/login', 'BENBU'), true);
    assert.equal(isIvpnRedirectPage('https://' + host + '/login', 'WEIHAI'), false);
    assert.equal(isIvpnRedirectPage('https://' + host + '.evil.example/login', 'BENBU'), false);
  }
});

test('returning from authentication to the portal opens EAS again instead of keeping the old navigation latch', async () => {
  const { ctrl, state, urls, page } = setup();
  ctrl.start('WEIHAI', '1');
  await page(urls.WEIHAI_LOGIN);
  await page('https://ids.hitwh.edu.cn/authserver/login');
  await page(urls.WEIHAI_LOGIN);
  assert.equal(state.navigations.filter(url => url === urls.WEIHAI_JWTS).length, 2);
  ctrl.stop();
});

test('stale cookies on a login intermediary cannot finish authentication', async () => {
  const { ctrl, state, urls, page, tick } = setup();
  state.cookie = 'wengine_vpn_ticket_test=old-ticket; JSESSIONID=old-session';
  state.verificationStatus = 401;
  ctrl.start('WEIHAI', '1');
  await page(urls.WEIHAI_JWTS);
  await tick(600);
  assert.equal(state.finished.length, 0);
  assert.equal(state.exchanges, 1);
  ctrl.stop();
});

test('cookie probes never use synchronous reads on the UI thread', async () => {
  const { ctrl, state, urls, page } = setup();
  ctrl.start('WEIHAI', '1');
  await page(urls.WEIHAI_EAS_PREFIX + '/kbcx/queryGrkb');
  assert.equal(state.syncReads, 0);
  assert.ok(state.reads > 0);
  ctrl.stop();
});

test('verification has no native overlay, code field or scripted send/submit bridge', () => {
  const login = fs.readFileSync(path.join(root, 'feature/eas/webLogin/EasLoginPage.ets'), 'utf8');
  const controller = fs.readFileSync(path.join(root, 'feature/eas/webLogin/EasWebLoginController.ets'), 'utf8');
  assert.doesNotMatch(login, /EasMfa|mfaState|mfaInput|mfaBusy|TextInput\s*\(/);
  assert.doesNotMatch(controller, /EasWebMfaBridge|scheduleMfaDetection|submitMfaInput|sendMfaCode|switchMfaMethod/);
  assert.equal(fs.existsSync(path.join(root, 'feature/eas/webLogin/EasWebMfaBridge.ets')), false);
  assert.match(login, /\.javaScriptAccess\(true\)/);
  assert.match(login, /\.onPageEnd\(/);
  assert.match(login, /\.onLoadFinished\(/);
});

for (const api of [23, 26]) {
  for (const campus of ['BENBU', 'WEIHAI', 'SHENZHEN']) {
    test(`${campus} API ${api}: verification stays in the webpage and its successful redirect completes login`, async () => {
      const h = setup(api);
      const { ctrl, state, urls, page, tick } = h;
      const authBase = campus === 'BENBU' ? 'https://ids.hit.edu.cn' :
        campus === 'WEIHAI' ? 'https://webvpn.hitwh.edu.cn' : 'https://authserver.hitsz.edu.cn';
      const easBase = campus === 'BENBU' ? urls.JWTS_BASE :
        campus === 'WEIHAI' ? urls.WEIHAI_EAS_PREFIX : urls.SHENZHEN_PROXY_BASE;
      state.cookie = 'JSESSIONID=stale; route=old-route; HIT=old; wengine_vpn_ticket_test=old';
      ctrl.start(campus, '1');
      for (const base of [authBase, easBase]) {
        await page(base + '/authserver/login');
        await page(base + '/authserver/reAuthCheck/index');
        // A failed code / changed verification method can reload the same page.
        await page(base + '/authserver/reAuthCheck/index');
      }
      ctrl.notifyProgress(100);
      await tick(65000);
      assert.equal(state.finished.length, 0);
      assert.equal(state.requests, 0);
      assert.equal(state.reads, 0);
      assert.deepEqual(state.navigations, []);
      assert.deepEqual(state.errors, []);
      assert.equal(state.progress.at(-1), 100);
      // Shenzhen keeps only its existing mobile viewport fix, not form interception.
      for (const script of state.scripts) {
        assert.match(script, /hita-mfa-viewport-fix/);
        assert.doesNotMatch(script, /\.click\(|\.value\s*=|reAuthParams|querySelector.*input/);
      }

      state.cookie = 'JSESSIONID=current; route=current-route; HIT=gateway; wengine_vpn_ticket_test=ticket';
      const destination = campus === 'BENBU' ? urls.BENBU_JWTS :
        campus === 'WEIHAI' ? urls.WEIHAI_JWTS : urls.SHENZHEN_DIRECT_BASE + '/student_index';
      await page(destination);
      if (campus === 'BENBU') await completeSjjxPage(h);
      await tick(10001);
      assert.equal(state.finished.length, 1);
      assert.equal(state.finished[0].isLogin(), true);
      assert.deepEqual(state.errors, []);
      ctrl.stop();
    });
  }
}

test('loading a verification page dismisses the loading cover without a second native prompt', async () => {
  const h = setup();
  const page = loginPage(h);
  const url = 'https://webvpn.hitwh.edu.cn/authserver/reAuthCheck/index';
  page.watchPageLoad(url);
  assert.equal(page.webReady, false);
  page.pageEnded(url);
  await h.tick(20000);
  assert.equal(page.webReady, true);
  assert.equal(page.errorText, '');
  assert.equal(page.pageLoadTimer, -1);
  assert.equal(h.state.scripts.length, 0);
  page.aboutToDisappear();
});

test('authentication/portal redirect loops stop with a recovery message', async () => {
  const { ctrl, state, urls, page } = setup();
  ctrl.start('WEIHAI', '1');
  for (let i = 0; i < 5; i++) {
    await page('https://ids.hitwh.edu.cn/authserver/login');
    await page(urls.WEIHAI_LOGIN);
  }
  assert.equal(state.navigations.length, 3);
  assert.ok(state.errors.some(error => error.includes('重置')));
  ctrl.stop();
});

test('duplicate page-end events run one cookie exchange and finish once', async () => {
  const { ctrl, state, urls } = setup();
  state.cookie = 'wengine_vpn_ticket_test=ticket; JSESSIONID=session';
  ctrl.start('WEIHAI', '1');
  const url = urls.WEIHAI_EAS_PREFIX + '/kbcx/queryGrkb';
  ctrl.notifyPageBegin(url);
  ctrl.notifyPageEnd(url);
  ctrl.notifyPageEnd(url);
  await flush();
  assert.equal(state.exchanges, 1);
  assert.equal(state.requests, 2);
  assert.equal(state.finished.length, 1);
});

test('slow cookie reads do not block cancellation or finish a later login', async () => {
  const { ctrl, state, urls, tick } = setup();
  const pending = [];
  state.fetchCookie = () => new Promise(resolve => pending.push(resolve));
  ctrl.start('WEIHAI', '1');
  const url = urls.WEIHAI_EAS_PREFIX + '/index';
  ctrl.notifyPageBegin(url);
  ctrl.notifyPageEnd(url);
  assert.ok(pending.length > 0);
  ctrl.stop();
  ctrl.start('BENBU', '1');
  pending.forEach(resolve => resolve('wengine_vpn_ticket_test=ticket; JSESSIONID=old'));
  await tick(4000);
  assert.equal(state.finished.length, 0);
  assert.equal(state.requests, 0);
  assert.equal(state.syncReads, 0);
  ctrl.stop();
});

test('Weihai VPN-only browser cookies exchange the server-side session before validating EAS', async () => {
  const { ctrl, state, urls, page } = setup();
  state.cookie = 'wengine_vpn_ticket_test=ticket';
  ctrl.start('WEIHAI', '1');
  await page(urls.WEIHAI_JWTS);
  assert.equal(state.exchanges, 1);
  assert.equal(state.requests, 2);
  assert.equal(state.finished.length, 1);
  assert.equal(state.finished[0].webCookies.get('JSESSIONID'), 'inner-session');
});

test('quoted cookie responses are decoded and a verified VPN-only session remains usable', async () => {
  for (const result of ['"JSESSIONID=quoted-session"', '']) {
    const { ctrl, state, urls, page } = setup();
    state.cookie = 'wengine_vpn_ticket_test=ticket';
    state.httpResponse = async () => ({ responseCode: 200, result });
    ctrl.start('WEIHAI', '1');
    await page(urls.WEIHAI_JWTS);
    assert.equal(state.finished.length, 1);
    assert.equal(state.finished[0].isLogin(), true);
    if (result) assert.equal(state.finished[0].webCookies.get('JSESSIONID'), 'quoted-session');
  }
});

test('gateway success or stale inner cookies without an authenticated timetable never finishes login', async () => {
  const { ctrl, state, urls, page, tick } = setup();
  state.cookie = 'wengine_vpn_ticket_test=ticket';
  state.verificationBody = '<form action="/login"><input name="password"></form>';
  ctrl.start('WEIHAI', '1');
  await page(urls.WEIHAI_JWTS);
  await tick(4000);
  assert.equal(state.exchanges, 3);
  assert.equal(state.finished.length, 0);
  assert.ok(state.errors.some(error => error.includes('教务会话尚未就绪')));
  ctrl.stop();
});

test('never-settling cookie and JavaScript operations time out asynchronously', async () => {
  const { state, load, web, tick } = setup();
  state.fetchCookie = () => new Promise(() => {});
  web.runJavaScript = () => new Promise(() => {});
  const { EasWebLoginController } = load('feature/eas/webLogin/EasWebLoginController.ets');
  const cookie = EasWebLoginController.tryFetchCookie('https://webvpn.hitwh.edu.cn/');
  const script = EasWebLoginController.runJs(web, 'test');
  await tick(5000);
  assert.equal(await cookie, '');
  assert.equal(await script, '');
  assert.equal(state.syncReads, 0);
});

test('late cookie exchange responses cannot complete a cancelled or restarted login', async () => {
  const { ctrl, state, urls, page } = setup();
  state.cookie = 'wengine_vpn_ticket_test=ticket; JSESSIONID=session';
  let resolve;
  state.httpResponse = () => new Promise(done => { resolve = done; });
  ctrl.start('WEIHAI', '1');
  await page(urls.WEIHAI_EAS_PREFIX + '/index');
  assert.equal(state.requests, 1);
  ctrl.stop();
  ctrl.start('SHENZHEN', '1');
  resolve({ responseCode: 200, result: 'JSESSIONID=old-inner' });
  await flush();
  assert.equal(state.finished.length, 0);
  ctrl.stop();
});

test('the active EAS host takes precedence over stale cookies from another probe URL', async () => {
  const { ctrl, state, urls, page } = setup();
  state.fetchCookie = url => Promise.resolve(url.startsWith(urls.SHENZHEN_DIRECT_BASE) ?
    'JSESSIONID=current; route=current-route' : 'JSESSIONID=stale; route=stale-route');
  ctrl.start('SHENZHEN', '1');
  await page(urls.SHENZHEN_DIRECT_BASE + '/student_index');
  assert.equal(state.finished.length, 1);
  assert.equal(state.finished[0].webCookies.get('JSESSIONID'), 'current');
});

test('Weihai reauthentication and unrelated sites cannot be success pages even with old cookies', () => {
  const { load, urls } = setup();
  const { isWeihaiAuthenticatedPage, logUrl } = load('feature/eas/webLogin/EasWebLoginProbe.ets');
  assert.equal(logUrl('http://jwts-hit-edu-cn.vpn.hit.edu.cn:1080/loginCAS;jsessionid=abc?ticket=ST-1#top'),
    'http://jwts-hit-edu-cn.vpn.hit.edu.cn:1080/loginCAS', 'logs never carry tickets or session ids');
  const cookies = new Map([['wengine_vpn_ticket_test', 'ticket'], ['JSESSIONID', 'session']]);
  for (const url of [urls.WEIHAI_JWTS, urls.WEIHAI_EAS_PREFIX + '/reAuth',
    'https://other.example/index', 'https://webvpn.hitwh.edu.cn/authserver/reAuthCheck/index']) {
    assert.equal(isWeihaiAuthenticatedPage(url, cookies), false, url);
  }
  assert.equal(isWeihaiAuthenticatedPage(urls.WEIHAI_EAS_PREFIX + '/index', cookies), true);
});

function loginPage(harness) {
  const { EasLoginPage } = harness.load('feature/eas/webLogin/EasLoginPage.ets');
  const page = new EasLoginPage();
  page.getUIContext = () => ({ getPromptAction: () => ({
    showDialog: async () => ({ index: 0 })
  }) });
  page.campusCode = 'WEIHAI';
  page.aboutToAppear();
  return page;
}

test('a page that never finishes loading releases the overlay and offers recovery', async () => {
  const h = setup();
  const page = loginPage(h);
  page.watchPageLoad(h.urls.WEIHAI_LOGIN);
  await h.tick(20000);
  assert.equal(page.webReady, true);
  assert.match(page.errorText, /重置/);
  page.aboutToDisappear();
  assert.equal(h.timers.size, 0);
});

test('recovery waits for a blank page before clearing only Web storage and restarting login', async () => {
  const h = setup();
  const page = loginPage(h);
  page.beginRecovery();
  assert.equal(h.state.resetCookies, 0);
  assert.equal(h.state.navigations.at(-1), 'about:blank');
  page.pageEnded(h.urls.WEIHAI_LOGIN);
  assert.equal(h.state.resetCookies, 0);
  page.pageEnded('about:blank');
  await flush();
  assert.equal(h.state.resetCookies, 1);
  assert.equal(h.state.resetStorage, 1);
  assert.equal(h.state.navigations.at(-1), h.urls.WEIHAI_LOGIN);
  assert.equal(page.recoveryBusy, false);
  const source = fs.readFileSync(path.join(root, 'feature/eas/webLogin/EasLoginPage.ets'), 'utf8');
  const reset = source.slice(source.indexOf('  private beginRecovery'), source.indexOf('  private updateWebNavigation'));
  assert.doesNotMatch(reset, /RdbHelper|\.clear\(|\.delete\(|EasSessionStore|preferences/);
  page.aboutToDisappear();
});

test('reset completion after cancelling the login window cannot reopen it', async () => {
  const h = setup();
  let resolve;
  h.state.clearCookies = () => new Promise(done => { resolve = done; });
  const page = loginPage(h);
  page.beginRecovery();
  page.pageEnded('about:blank');
  page.cancelLogin();
  resolve();
  await flush();
  assert.deepEqual(h.state.navigations, ['about:blank']);
  assert.equal(h.state.resetStorage, 0);
  assert.equal(h.timers.size, 0);
});

test('a hung reset times out without leaving the login window busy forever', async () => {
  const h = setup();
  h.state.clearCookies = () => new Promise(() => {});
  const page = loginPage(h);
  page.beginRecovery();
  page.pageEnded('about:blank');
  await h.tick(15000);
  assert.equal(page.recoveryBusy, false);
  assert.equal(page.webReady, true);
  assert.match(page.errorText, /超时/);
  page.aboutToDisappear();
});

function storedCookie(overrides = {}) {
  return { name: 'JSESSIONID', value: 'session', domain: 'jwts.hit.edu.cn', path: '/',
    isSessionCookie: true, isSecure: true, isHttpOnly: true, expiresDate: '', samesitePolicy: 0, ...overrides };
}

test('API 23 supplements URL-scoped cookies without replacing the authoritative session', async () => {
  const h = setup(23);
  const { EasWebLoginController } = h.load('feature/eas/webLogin/EasWebLoginController.ets');
  const calls = [];
  h.state.fetchCookie = (...args) => { calls.push(args); return Promise.resolve('JSESSIONID=current'); };
  h.state.fetchAllCookies = async () => [storedCookie({ value: 'stale' }), storedCookie({ name: 'ticket', value: 'extra' })];
  assert.equal(await EasWebLoginController.tryFetchCookieWithPartitioned('https://jwts.hit.edu.cn/index'),
    'JSESSIONID=current; ticket=extra');
  assert.deepEqual(calls, [['https://jwts.hit.edu.cn/index']]);
  assert.equal(h.state.allReads, 1);
  assert.equal(h.state.syncReads, 0);
  assert.equal(h.timers.size, 0);
});

test('API 26 keeps partition-aware native reads and never enumerates the old cookie store', async () => {
  const h = setup(26);
  const { EasWebLoginController } = h.load('feature/eas/webLogin/EasWebLoginController.ets');
  const calls = [];
  h.state.fetchCookie = (...args) => { calls.push(args); return Promise.resolve(args.length === 3 ? 'ticket=partitioned' : 'sid=normal'); };
  assert.equal(await EasWebLoginController.tryFetchCookieWithPartitioned('https://jwts.hit.edu.cn/'), 'sid=normal; ticket=partitioned');
  assert.deepEqual(calls, [['https://jwts.hit.edu.cn/'], ['https://jwts.hit.edu.cn/', false, true]]);
  assert.equal(h.state.allReads, 0);
});

test('legacy cookie selection respects domain, path case, Secure, expiry and ambiguous partition values', () => {
  const { LegacyCookieReader } = setup(23).load('feature/eas/webLogin/LegacyCookieReader.ets');
  const cookies = [
    storedCookie({ name: 'good', path: '/EAS' }),
    storedCookie({ name: 'httpOnly' }),
    storedCookie({ name: 'parent', domain: '.hit.edu.cn' }),
    storedCookie({ name: 'other', domain: 'evilhit.edu.cn' }),
    storedCookie({ name: 'hostOnly', domain: 'hit.edu.cn' }),
    storedCookie({ name: 'wrongCase', path: '/eas' }),
    storedCookie({ name: 'prefix', path: '/EA' }),
    storedCookie({ name: 'expired', isSessionCookie: false, expiresDate: '1970-01-01T00:00:01Z' }),
    storedCookie({ name: 'badExpiry', isSessionCookie: false, expiresDate: 'bad' }),
    storedCookie({ name: 'conflict', value: 'partition-a' }),
    storedCookie({ name: 'conflict', value: 'partition-b' }),
    storedCookie({ name: 'injected', value: 'value; another=bad' })
  ];
  assert.equal(LegacyCookieReader.select(cookies, 'https://jwts.hit.edu.cn/EAS/index', 10000),
    'good=session; httpOnly=session; parent=session');
  assert.equal(LegacyCookieReader.select(cookies, 'http://jwts.hit.edu.cn/EAS/index', 10000), '');
});

test('API 23 supplement stays on the active first-party host and times out without losing normal cookies', async () => {
  const h = setup(23);
  const { EasWebLoginController } = h.load('feature/eas/webLogin/EasWebLoginController.ets');
  h.state.cookie = 'sid=normal';
  assert.equal(await EasWebLoginController.tryFetchCookieWithPartitioned('https://jwts.hit.edu.cn/', 'https://ids.hit.edu.cn/'), 'sid=normal');
  assert.equal(h.state.allReads, 0);
  h.state.fetchAllCookies = () => new Promise(() => {});
  const pending = EasWebLoginController.tryFetchCookieWithPartitioned('https://jwts.hit.edu.cn/');
  await h.tick(3000);
  assert.equal(await pending, 'sid=normal');
  assert.equal(h.timers.size, 0);
  h.state.fetchAllCookies = async () => [storedCookie()];
  assert.equal(await EasWebLoginController.tryFetchCookieWithPartitioned('https://jwts.hit.edu.cn/'), 'sid=normal; JSESSIONID=session');
});

test('Benbu loginCAS can finish after the timetable endpoint verifies the current session', async () => {
  for (const api of [23, 26]) {
    const h = setup(api);
    h.state.cookie = 'JSESSIONID=current; HIT=gateway';
    h.ctrl.start('BENBU', '1');
    await h.page(h.urls.BENBU_JWTS);
    assert.equal(h.state.benbuRequests, 1);
    assert.equal(h.state.benbuRequest.url, 'http://jwts-hit-edu-cn.vpn.hit.edu.cn:1080/kbcx/queryGrkb');
    assert.equal(h.state.navigations.at(-1), h.urls.JWTS_BASE + '/loginsysj/loginSygl');
    await completeSjjxPage(h);
    assert.ok(h.state.navigations.some(url => url.startsWith(h.urls.EELABINFO_URL)));
    await h.tick(10001);
    assert.equal(h.state.finished.length, 1);
    assert.equal(h.state.finished[0].webCookies.get('JSESSIONID'), 'current');
    assert.equal(h.state.finished[0].getStudentType(), '1');
  }
});

test('Benbu delayed cookies on a non-login EAS page are retried even without auto-open', async () => {
  const h = setup();
  h.ctrl.start('BENBU', '1');
  await h.page(h.urls.JWTS_BASE + '/xs/main');
  h.state.cookie = 'JSESSIONID=late; HIT=gateway';
  await h.tick(600);
  assert.equal(h.state.benbuRequests, 1);
  await completeSjjxPage(h);
  await h.tick(10001);
  assert.equal(h.state.finished.length, 1);
});

test('Benbu verification can use a path-scoped JSESSIONID without a readable HIT cookie', async () => {
  const h = setup(23);
  h.state.fetchCookie = url => Promise.resolve(url.endsWith('/kbcx/queryGrkb') ? 'JSESSIONID=path-session' : '');
  h.ctrl.start('BENBU', '1');
  await h.page(h.urls.JWTS_BASE + '/index');
  assert.equal(h.state.benbuRequests, 1);
  assert.match(h.state.benbuRequest.options.header.Cookie, /JSESSIONID=path-session/);
  await completeSjjxPage(h);
  await h.tick(10001);
  assert.equal(h.state.finished.length, 1);
});

test('Benbu gateway or stale cookies without authenticated timetable data cannot finish', async () => {
  for (const response of [
    { responseCode: 200, result: '<html>统一认证登录</html>' },
    { responseCode: 401, result: '<select name="xnxq"><option value="2026-20271">秋季</option></select>' },
    { responseCode: 200, result: '<form><input type="password"><select name="xnxq"><option value="2026-20271">秋季</option></select></form>' }
  ]) {
    const h = setup();
    h.state.cookie = 'JSESSIONID=stale; HIT=stale';
    h.state.benbuResponse = async () => response;
    h.ctrl.start('BENBU', '1');
    await h.page(h.urls.JWTS_BASE + '/index');
    await h.tick(20000);
    assert.equal(h.state.finished.length, 0);
    assert.equal(h.state.navigations.length, 0);
    assert.equal(h.state.benbuRequests, 3);
    assert.ok(h.state.errors.some(error => error.includes('本部教务')));
  }
});

test('Benbu duplicate page completion does not run concurrent verification', async () => {
  const h = setup();
  let release;
  h.state.cookie = 'JSESSIONID=current; HIT=gateway';
  h.state.benbuResponse = () => new Promise(resolve => { release = resolve; });
  h.ctrl.start('BENBU', '1');
  await h.page(h.urls.BENBU_JWTS);
  h.ctrl.notifyPageEnd(h.urls.BENBU_JWTS);
  await flush();
  assert.equal(h.state.benbuRequests, 1);
  release({ responseCode: 200, result: '<select name="pageXnxq"><option value="2026-20271">秋季</option></select>' });
  await flush();
  await completeSjjxPage(h);
  await h.tick(10001);
  assert.equal(h.state.finished.length, 1);
});

test('Benbu verification timeout stays bounded and late results cannot finish a restarted login', async () => {
  const h = setup();
  let release;
  h.state.cookie = 'JSESSIONID=current; HIT=gateway';
  h.state.benbuResponse = () => new Promise(resolve => { release = resolve; });
  h.ctrl.start('BENBU', '1');
  await h.page(h.urls.BENBU_JWTS);
  await h.tick(32000);
  assert.equal(h.state.finished.length, 0);
  assert.equal(h.state.benbuRequests, 3);
  assert.ok(h.state.errors.length > 0);
  h.ctrl.stop();
  h.ctrl.start('BENBU', '1');
  release({ responseCode: 200, result: '<select name="xnxq"><option value="2026-20271">秋季</option></select>' });
  await flush();
  assert.equal(h.state.finished.length, 0);
  assert.equal(h.state.navigations.length, 0);
  h.ctrl.stop();
});

test('Benbu authentication, unrelated hosts and graduate pages never use undergraduate verification', async () => {
  for (const [type, url] of [
    ['1', 'https://ids.hit.edu.cn/authserver/login'],
    ['1', 'http://jwts-hit-edu-cn.vpn.hit.edu.cn:1080/authserver/reAuthCheck/'],
    ['1', 'https://jwts-hit-edu-cn.vpn.hit.edu.cn.evil.example/index'],
    ['1', 'http://jwts-hit-edu-cn.ivpn.hit.edu.cn:1080/index'],
    ['1', 'https://unrelated.hit.edu.cn/index'],
    ['2', 'http://yjsgl-hit-edu-cn.vpn.hit.edu.cn:1080/xs/index']
  ]) {
    const h = setup();
    h.state.cookie = 'JSESSIONID=stale; HIT=stale';
    h.ctrl.start('BENBU', type);
    await h.page(url);
    await h.tick(16000);
    assert.equal(h.state.benbuRequests ?? 0, 0, url);
    assert.equal(h.state.finished.length, 0, url);
    h.ctrl.stop();
  }
});

test('Benbu main-frame completion accepts a verified current URL after in-page navigation only', async () => {
  const h = setup();
  const { EasLoginPage } = h.load('feature/eas/webLogin/EasLoginPage.ets');
  const page = new EasLoginPage();
  page.campusCode = 'BENBU';
  page.aboutToAppear();
  const completed = [];
  page.loginController.notifyPageEnd = url => completed.push(url);
  page.watchPageLoad(h.urls.BENBU_JWTS);
  h.state.currentUrl = h.urls.JWTS_BASE + '/index#/home';
  page.pageLoadFinished(h.state.currentUrl);
  assert.deepEqual(completed, [h.state.currentUrl]);
  assert.equal(page.webReady, true);
  page.pageLoadFinished(h.urls.BENBU_JWTS);
  assert.equal(completed.length, 1);
  page.aboutToDisappear();
  page.pageLoadFinished(h.state.currentUrl);
  assert.equal(completed.length, 1);
});

test('Benbu login resumes after a failed probe when a new authenticated page arrives', async () => {
  const h = setup();
  h.state.cookie = 'JSESSIONID=stale; HIT=gateway';
  h.state.benbuResponse = async () => ({ responseCode: 200, result: 'login required' });
  h.ctrl.start('BENBU', '1');
  await h.page(h.urls.BENBU_JWTS);
  await h.tick(2000);
  assert.equal(h.state.benbuRequests, 3);
  h.state.cookie = 'JSESSIONID=new; HIT=gateway';
  h.state.benbuResponse = async () => ({
    responseCode: 200, result: '<select name="xnxq"><option value="2026-20271">秋季</option></select>'
  });
  await h.page(h.urls.JWTS_BASE + '/index');
  await completeSjjxPage(h);
  await h.tick(10001);
  assert.equal(h.state.finished.length, 1);
  assert.equal(h.state.finished[0].webCookies.get('JSESSIONID'), 'new');
});

test('Benbu completed verification cannot finish after navigation back to CAS', async () => {
  const h = setup();
  let release;
  h.state.cookie = 'JSESSIONID=current; HIT=gateway';
  h.state.benbuResponse = () => new Promise(resolve => { release = resolve; });
  h.ctrl.start('BENBU', '1');
  await h.page(h.urls.BENBU_JWTS);
  await h.page('https://ids.hit.edu.cn/authserver/login');
  release({ responseCode: 200, result: '<select name="xnxq"><option value="2026-20271">秋季</option></select>' });
  await h.tick(12000);
  assert.equal(h.state.finished.length, 0);
  assert.equal(h.state.navigations.length, 0);
  h.ctrl.stop();
});

test('Benbu graduate final page retries late cookies without entering undergraduate token flow', async () => {
  const h = setup();
  h.ctrl.start('BENBU', '2');
  await h.page(h.urls.GRADUATE_BASE + '/xs/index');
  h.state.cookie = 'JSESSIONID=graduate; sdp_user_token=graduate-token';
  await h.tick(600);
  assert.equal(h.state.finished.length, 1);
  assert.equal(h.state.finished[0].getStudentType(), '2');
  assert.equal(h.state.benbuRequests ?? 0, 0);
  assert.equal(h.state.navigations.length, 0);
});

test('Benbu successful EAS login survives optional laboratory navigation errors', async () => {
  const h = setup();
  h.state.cookie = 'JSESSIONID=current; HIT=gateway';
  h.web.loadUrl = () => { throw Error('optional laboratory site failed'); };
  h.ctrl.start('BENBU', '1');
  await h.page(h.urls.BENBU_JWTS);
  assert.equal(h.state.finished.length, 1);
  assert.equal(h.state.finished[0].electronicExpToken, '');
});

async function completeSjjxPage(h) {
  await h.page(h.urls.SJJX_BASE + '/to-welcome');
  await h.tick(1000);
}

async function enterSjjx(h, cookie = 'JSESSIONID=lab; HIT=gateway') {
  h.state.cookie = 'JSESSIONID=teaching; HIT=gateway';
  h.ctrl.start('BENBU', '1');
  await h.page(h.urls.BENBU_JWTS);
  assert.equal(h.state.navigations.at(-1), h.urls.JWTS_BASE + '/loginsysj/loginSygl');
  h.state.cookie = cookie;
  await h.page(h.urls.SJJX_BASE + '/to-welcome');
}

test('Benbu WebView bridge saves a separate experiment session and supports repeated login', async () => {
  for (const api of [23, 26]) {
    const h = setup(api);
    for (const value of ['first-lab', 'second-lab']) {
      await enterSjjx(h, 'JSESSIONID=' + value + '; HIT=gateway');
      await h.tick(1000);
      assert.equal(h.state.navigations.at(-1), h.urls.EELABINFO_URL + '/api/cas/loginSuccess');
      await h.tick(10001);
      const s = h.state.finished.at(-1);
      assert.equal(s.webCookies.get('JSESSIONID'), 'teaching');
      assert.equal(s.sjjxCookies.get('JSESSIONID'), value);
      const { EasSession } = h.load('feature/eas/EasSession.ets');
      assert.equal(EasSession.decode(s.encode()).sjjxCookies.get('JSESSIONID'), value);
    }
    assert.equal(h.state.finished.length, 2);
  }
});

test('stopping the experiment bridge cancels its navigation and cookie timers', async () => {
  const h = setup();
  await enterSjjx(h);
  h.ctrl.stop();
  assert.equal(h.timers.size, 0);
  await h.tick(30000);
  assert.equal(h.state.finished.length, 0);
  assert.equal(h.state.navigations.some(url => url.startsWith(h.urls.EELABINFO_URL)), false);
});

test('a late experiment cookie read cannot alter a restarted login', async () => {
  const h = setup();
  await enterSjjx(h);
  let release;
  h.state.fetchCookie = () => new Promise(resolve => { release = resolve; });
  await h.tick(1000);
  assert.equal(typeof release, 'function');
  h.ctrl.start('WEIHAI', '1');
  const navigationCount = h.state.navigations.length;
  release('JSESSIONID=old-lab; HIT=old-gateway');
  await flush();
  assert.equal(h.state.navigations.length, navigationCount);
  assert.equal(h.ctrl.pendingSjjxCookies.size, 0);
  assert.equal(h.state.finished.length, 0);
  h.ctrl.stop();
});

test('experiment cookies are not reused when another campus logs in', async () => {
  const h = setup();
  await enterSjjx(h);
  await h.tick(11001);
  assert.equal(h.state.finished.length, 1);
  h.state.cookie = 'wengine_vpn_ticket_test=ticket; JSESSIONID=weihai';
  h.ctrl.start('WEIHAI', '1');
  await h.page(h.urls.WEIHAI_JWTS);
  await h.tick(10001);
  assert.equal(h.state.finished.length, 2);
  assert.equal(h.state.finished[1].sjjxCookies.size, 0);
});

test('a stalled experiment bridge remains optional and completes the verified teaching login', async () => {
  const h = setup();
  h.state.cookie = 'JSESSIONID=teaching; HIT=gateway';
  h.ctrl.start('BENBU', '1');
  await h.page(h.urls.BENBU_JWTS);
  await h.tick(4000);
  assert.equal(h.state.navigations.at(-1), h.urls.EELABINFO_URL + '/api/cas/loginSuccess');
  await h.tick(4001);
  assert.equal(h.state.finished.length, 1);
  assert.equal(h.state.finished[0].webCookies.get('JSESSIONID'), 'teaching');
  assert.equal(h.state.finished[0].sjjxCookies.size, 0);
});

test('an experiment cookie read arriving after the bridge timeout cannot change its result', async () => {
  const h = setup();
  h.state.cookie = 'JSESSIONID=teaching; HIT=gateway';
  h.ctrl.start('BENBU', '1');
  await h.page(h.urls.BENBU_JWTS);
  await h.tick(2900);
  let release;
  h.state.fetchCookie = () => new Promise(resolve => { release = resolve; });
  await h.page(h.urls.SJJX_BASE + '/to-welcome');
  await h.tick(1000);
  await h.tick(100);
  assert.equal(h.state.navigations.at(-1), h.urls.EELABINFO_URL + '/api/cas/loginSuccess');
  release('JSESSIONID=too-late');
  await flush();
  await h.tick(10001);
  assert.equal(h.state.finished.length, 1);
  assert.equal(h.state.finished[0].sjjxCookies.size, 0);
});

test('optional experiment page completion works even when ArkWeb omits page begin', async () => {
  const h = setup();
  h.state.cookie = 'JSESSIONID=teaching';
  h.ctrl.start('BENBU', '1');
  await h.page(h.urls.BENBU_JWTS);
  h.state.cookie = 'JSESSIONID=lab';
  await h.ctrl.notifyPageEnd(h.urls.SJJX_BASE + '/to-welcome');
  await h.tick(1000);
  assert.equal(h.ctrl.pendingSjjxCookies.get('JSESSIONID'), 'lab');
  await h.tick(7000);
  assert.equal(h.state.finished.length, 1);
  assert.equal(h.state.finished[0].webCookies.get('JSESSIONID'), 'teaching');
});

test('optional experiment authentication redirects finish the verified main session immediately', async () => {
  for (const target of ['https://ids.hit.edu.cn/authserver/login', 'https://vpn.hit.edu.cn/portal/']) {
    const h = setup();
    await enterSjjx(h);
    h.ctrl.notifyPageBegin(target);
    assert.equal(h.state.finished.length, 1);
    assert.equal(h.state.finished[0].webCookies.get('JSESSIONID'), 'teaching');
    assert.equal(h.timers.size, 0);
  }
});

test('only optional main-frame errors complete login, never resource or unverified authentication errors', async () => {
  const h = setup();
  h.ctrl.start('BENBU', '1');
  assert.equal(h.ctrl.notifyLoadError('authentication unavailable', true), false);
  assert.equal(h.state.finished.length, 0);
  await enterSjjx(h);
  assert.equal(h.ctrl.notifyLoadError('image unavailable', false), false);
  assert.equal(h.state.finished.length, 0);
  assert.equal(h.ctrl.notifyLoadError('laboratory unavailable', true), true);
  assert.equal(h.state.finished.length, 1);
  assert.equal(h.state.finished[0].webCookies.get('JSESSIONID'), 'teaching');
  await h.tick(30000);
  assert.equal(h.state.finished.length, 1);
});

test('a stalled electronic token request cannot extend the shared experiment deadline or finish twice', async () => {
  const h = setup();
  await enterSjjx(h);
  await h.tick(1000);
  let release;
  h.ctrl.fetchEelabToken = () => new Promise(resolve => { release = resolve; });
  await h.page(h.urls.EELABINFO_URL + '/login.html?t=suc');
  await h.tick(1000);
  assert.equal(typeof release, 'function');
  await h.tick(6000);
  assert.equal(h.state.finished.length, 1);
  assert.equal(h.state.finished[0].sjjxCookies.get('JSESSIONID'), 'lab');
  assert.equal(h.state.finished[0].electronicExpToken, '');
  release('late-token');
  await flush();
  assert.equal(h.state.finished.length, 1);
  assert.equal(h.state.finished[0].electronicExpToken, '');
});
