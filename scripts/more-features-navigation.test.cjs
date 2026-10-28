const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');
global.$r = name => ({ id: -1, type: 10001, params: [name] });

const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const EasCampus = { BENBU: 'BENBU', SHENZHEN: 'SHENZHEN', WEIHAI: 'WEIHAI' };

function campusPortals() {
  const mod = { exports: {} };
  const code = ts.transpileModule(read('feature/portal/CampusPortal.ets'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  new Function('require', 'module', 'exports', code)(() => ({ EasCampus }), mod, mod.exports);
  return mod.exports;
}

test('assistant, news and campus links are registered routes in More, after academic tools and settings', () => {
  const home = read('pages/Home.ets');
  const more = home.slice(home.indexOf('  tabMine()'), home.indexOf('  userCard()'));
  const academic = more.indexOf("this.moreSectionTitle('教务功能')");
  const settings = more.indexOf("this.moreSectionTitle('设置')");
  const extras = more.indexOf("this.moreSectionTitle('更多')");
  assert.ok(academic >= 0 && academic < settings && settings < extras);
  // 更多 is the last section; it runs to the end of the scroll content.
  const section = more.slice(extras, more.indexOf('Blank().height(this.dockPageInset()', extras));
  const routes = JSON.parse(fs.readFileSync(path.join(root, '../resources/base/profile/main_pages.json'))).src;
  for (const [page, label, symbol] of [
    ['AssistantPage', '助手', 'AI_message'], ['NewsPage', '资讯', 'doc_text'],
    ['PortalsPage', '常用入口', 'link']
  ]) {
    assert.ok(section.includes(`HitaListRow({ symbol: $r('sys.symbol.${symbol}'), title: '${label}'`));
    assert.ok(section.includes(`getRouter().pushUrl({ url: 'pages/${page}' })`));
    assert.ok(routes.includes(`pages/${page}`));
    const source = read(`pages/${page}.ets`);
    assert.match(source, /@Entry\s+@Component/);
    assert.match(source, /Row\(\) \{\s*HeaderBackButton\(\{/);
    assert.match(source, /getRouter\(\)\.back\(\)/);
    assert.doesNotMatch(source, /replaceUrl|\bTabs\(|\bTabContent\(|dockPageInset/);
  }
});

function deferred() {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return { promise, resolve };
}

// Exercise actual route controller methods without ArkUI builders or live services.
function pageClass(name, mocks = {}, moduleCache = new Map()) {
  let source = read(`pages/${name}.ets`);
  source = source.slice(0, source.indexOf('\n  build()')) + '\n}\n';
  source = source.replace(/^import lazy /gm, 'import ');
  source = source.replace(/^@(Entry|Component|Observed)\r?\n/gm, '')
    .replace(/@(State|StorageProp|Watch)(\([^)]*\))?\s*/g, '')
    .replace(`struct ${name}`, `export class ${name}`);
  const mod = { exports: {} };
  const timers = new Map();
  let timerId = 0;
  const ui = {
    modes: [], scrolls: [], routes: [], toasts: [], clipboard: [], stopped: 0, cleared: 0,
    getHostContext: () => ({}),
    setKeyboardAvoidMode: value => ui.modes.push(value),
    getFocusController: () => ({ clearFocus: () => { ui.cleared++; } }),
    getRouter: () => ({ pushUrl: route => {
      ui.routes.push(route);
      if (mocks.openFails) return Promise.reject(Error('route unavailable'));
    } }),
    getPromptAction: () => ({ showToast: options => ui.toasts.push(options.message) })
  };
  const settings = class {
    provider = 'deepseek';
    apiKey = '';
    hasCloudModel() { return false; }
  };
  const platform = spec => {
    if (spec.endsWith('/HitaDesign')) {
      const tokens = { exports: {} };
      const code = ts.transpileModule(read('common/theme/HitaDesign.ets'), {
        compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
      }).outputText;
      new Function('require', 'module', 'exports', code)(() => ({}), tokens, tokens.exports);
      return tokens.exports;
    }
    if (spec.endsWith('/EasSession')) return { EasCampus };
    if (spec.endsWith('/EasSessionStore')) return {
      EAS_SESSION_REVISION_KEY: 'hita_eas_session_revision',
      EasSessionStore: { getInstance: () => ({
        init: async () => {},
        loadLastCampus: mocks.loadLastCampus || (async () => undefined),
        loadPreferred: mocks.loadPreferred || (async () => undefined)
      }) }
    };
    if (spec.endsWith('/CampusPortal')) return campusPortals();
    if (spec === '@kit.BasicServicesKit') return { pasteboard: {
      MIMETYPE_TEXT_PLAIN: 'text/plain',
      createData: (mime, text) => ({ mime, text }),
      getSystemPasteboard: () => ({ setData: async data => {
        if (mocks.copyFails) throw Error('clipboard unavailable');
        ui.clipboard.push(data);
      } })
    } };
    if (spec.endsWith('/AssistantConversation')) {
      if (!moduleCache.has(spec)) {
        const state = { exports: {} };
        const code = ts.transpileModule(read('feature/assistant/AssistantConversation.ets')
          .replace(/^@Observed\r?\n/gm, ''), {
          compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
        }).outputText;
        new Function('require', 'module', 'exports', code)(platform, state, state.exports);
        moduleCache.set(spec, state.exports);
      }
      return moduleCache.get(spec);
    }
    if (spec === '@kit.ArkUI') return { KeyboardAvoidMode: { NONE: 'none', OFFSET: 'offset' } };
    if (spec.endsWith('/StatusBarInset')) return {
      STATUS_BAR_INSET_FALLBACK: 44, NAV_BAR_INSET_FALLBACK: 28, KEYBOARD_INSET_FALLBACK: 0
    };
    if (spec.endsWith('/AssistantService')) return {
      AssistantService: {
        welcome: () => ({ content: 'welcome', role: 'assistant' }),
        reply: mocks.reply
      },
      AssistantRole: { USER: 'user', ASSISTANT: 'assistant' },
      AssistantMessage: { of: (role, content) => ({ role, content }) }
    };
    if (spec.endsWith('/AssistantSettingsStore')) return {
      AssistantProvider: { DEEPSEEK: 'deepseek' }, AssistantSettings: settings,
      AssistantSettingsStore: { getInstance: () => ({
        init: async () => {}, load: async () => new settings()
      }) }
    };
    if (spec.endsWith('/NewsService')) {
      const service = { exports: {} };
      const code = ts.transpileModule(read('feature/news/NewsService.ets'), {
        compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
      }).outputText;
      new Function('require', 'module', 'exports', code)(platform, service, service.exports);
      return { NewsService: {
        CATEGORIES: service.exports.NewsService.CATEGORIES, fetchCategory: mocks.fetchCategory
      } };
    }
    return {};
  };
  const compiled = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  new Function('require', 'module', 'exports', 'Scroller', 'TextInputController', 'Edge',
    'setTimeout', 'clearTimeout', compiled)(
    platform, mod, mod.exports,
    class { scrollEdge(edge) { ui.scrolls.push(edge); } },
    class { stopEditing() { ui.stopped++; } },
    { Bottom: 'bottom', Top: 'top' },
    callback => { timers.set(++timerId, callback); return timerId; },
    id => timers.delete(id));
  const Page = mod.exports[name];
  Page.prototype.getUIContext = () => ui;
  return { Page, ui, timers, moduleCache };
}

test('assistant input follows the keyboard and reclaims the former dock space', () => {
  const { Page, ui, timers } = pageClass('AssistantPage');
  const page = new Page();
  assert.equal(page.inputBarBottom(), 28);
  page.navBarInset = 20;
  assert.equal(page.inputBarBottom(), 20);
  page.keyboardInset = 302;
  assert.equal(page.inputBarBottom(), 302);
  page.onPageShow();
  assert.equal(ui.modes.at(-1), 'none');
  assert.equal(timers.size, 1);
  page.onPageHide();
  assert.equal(ui.modes.at(-1), 'offset');
  assert.equal(timers.size, 0);
  assert.equal(ui.stopped, 2);
  assert.equal(ui.cleared, 1);
  page.scrollToLatest();
  assert.equal(timers.size, 0);
});

test('leaving and reopening assistant preserves messages and an in-flight reply without resending', async () => {
  const pending = deferred();
  let requests = 0;
  const { Page, moduleCache } = pageClass('AssistantPage', {
    reply: () => { requests++; return pending.promise; }
  });
  const first = new Page();
  const sending = first.send('明天有什么课');
  assert.equal(first.chat.sending, true);
  first.onPageHide();
  first.aboutToDisappear();
  // ArkUI evaluates an @Entry page again on pushUrl; only imported modules retain state.
  const { Page: ReopenedPage } = pageClass('AssistantPage', {}, moduleCache);
  const reopened = new ReopenedPage();
  assert.equal(reopened.chat.messages.at(-1).content, '明天有什么课');
  assert.equal(reopened.chat.sending, true);
  await reopened.send('重复请求');
  reopened.clearChat();
  assert.equal(requests, 1);
  assert.equal(reopened.chat.messages.length, 2);
  pending.resolve({ role: 'assistant', content: '课表回答' });
  await sending;
  assert.equal(reopened.chat.messages.at(-1).content, '课表回答');
  assert.equal(reopened.chat.sending, false);
  reopened.clearChat();
  assert.equal(reopened.chat.messages.length, 1);
});

test('assistant reply errors release the shared sending state after leaving', async () => {
  const { Page } = pageClass('AssistantPage', { reply: async () => { throw Error('offline'); } });
  const first = new Page();
  const sending = first.send('问题');
  first.aboutToDisappear();
  await sending;
  const reopened = new Page();
  assert.equal(reopened.chat.sending, false);
  assert.match(reopened.chat.messages.at(-1).content, /稍后再试/);
});

test('a late news response cannot update a page that was closed', async () => {
  const pending = deferred();
  const { Page } = pageClass('NewsPage', { fetchCategory: () => pending.promise });
  const page = new Page();
  const loading = page.reload();
  page.aboutToDisappear();
  pending.resolve({ ok: true, items: [{ url: 'https://example.invalid/article', title: 'Late article' }] });
  await loading;
  assert.deepEqual(page.items, []);
  assert.equal(page.page, 0);
});

test('news contains only the two news categories, with no campus links or portal tab', () => {
  const news = read('pages/NewsPage.ets');
  assert.doesNotMatch(news, /PORTAL_TAB|portalScroller|portalList|portalItems|常用入口|CampusPortal|NewsPortal/);
  assert.match(news, /ForEach\(NewsService\.CATEGORIES/);
  assert.match(news, /this\.newsList\(\)/);
  assert.match(news, /accessibilityText\('刷新'\)/);
  assert.match(news, /Text\('博客与通知'\)/);
  assert.doesNotMatch(news, /今日哈工大/);
  const service = read('feature/news/NewsService.ets');
  assert.deepEqual([...service.matchAll(/new NewsCategory\('([^']+)', '([^']+)'\)/g)]
    .map(match => [match[1], match[2]]), [['blog', '博客'], ['10', '通知']]);
  assert.doesNotMatch(service, /NewsPortal|PORTALS/);
});

test('news opens on blogs and refreshing or reopening preserves the correct category mapping', async () => {
  const requests = [];
  const { Page } = pageClass('NewsPage', {
    fetchCategory: async (id, page) => {
      requests.push([id, page]);
      return { ok: true, items: [], message: '', hasMore: false };
    }
  });
  const page = new Page();
  assert.equal(page.selected, 0);
  page.aboutToAppear();
  await page.reload();
  assert.deepEqual(requests, [['blog', 0], ['blog', 0]]);

  page.selectTab(1);
  await new Promise(resolve => setImmediate(resolve));
  await page.reload();
  assert.deepEqual(requests.slice(2), [['10', 0], ['10', 0]]);
  page.aboutToDisappear();

  const reopened = new Page();
  reopened.aboutToAppear();
  assert.equal(reopened.selected, 0);
  assert.deepEqual(requests.at(-1), ['blog', 0]);
});

test('notifications use the latest login campus on refresh and pin it while loading more', async () => {
  let selectedCampus;
  const requests = [];
  const { Page } = pageClass('NewsPage', {
    loadLastCampus: async () => selectedCampus,
    fetchCategory: async (id, page, campus) => {
      requests.push([id, page, campus]);
      return { ok: true, items: [{ url: `${campus}/${page}`, title: '通知' }], hasMore: true, message: '', sourceUrl: '' };
    }
  });
  const page = new Page();
  page.selected = 1;
  await page.reload();
  assert.deepEqual(requests.at(-1), ['10', 0, 'BENBU']);
  for (const campus of ['SHENZHEN', 'BENBU', 'WEIHAI']) {
    selectedCampus = campus;
    await page.reload();
    assert.deepEqual(requests.at(-1), ['10', 0, campus]);
    assert.deepEqual(page.items.map(value => value.url), [`${campus}/0`]);
    selectedCampus = 'different selection';
    await page.loadPage();
    assert.deepEqual(requests.at(-1), ['10', 1, campus]);
    assert.deepEqual(page.items.map(value => value.url), [`${campus}/0`, `${campus}/1`]);
  }
});

test('a slow campus read cannot start a notification request after switching back to blogs or closing', async () => {
  for (const action of ['selectTab', 'aboutToDisappear']) {
    const pending = deferred();
    const requests = [];
    const { Page } = pageClass('NewsPage', {
      loadLastCampus: () => pending.promise,
      fetchCategory: async (id, page, campus) => {
        requests.push(id);
        return { ok: true, items: [], hasMore: false, message: '', sourceUrl: '' };
      }
    });
    const page = new Page();
    page.selected = 1;
    const loading = page.reload();
    page[action](0);
    pending.resolve('SHENZHEN');
    await loading;
    assert.deepEqual(requests, action === 'selectTab' ? ['blog'] : []);
  }
});

test('a prior campus response cannot contaminate a refreshed campus list', async () => {
  const oldResponse = deferred();
  let campus = 'SHENZHEN';
  const { Page } = pageClass('NewsPage', {
    loadLastCampus: async () => campus,
    fetchCategory: async (id, page, selected) => selected === 'SHENZHEN' ? oldResponse.promise :
      { ok: true, items: [{ url: 'weihai' }], hasMore: false, message: '', sourceUrl: 'weihai-source' }
  });
  const page = new Page();
  page.selected = 1;
  const oldLoad = page.reload();
  await new Promise(resolve => setImmediate(resolve));
  campus = 'WEIHAI';
  await page.reload();
  oldResponse.resolve({ ok: true, items: [{ url: 'shenzhen' }], hasMore: true, message: '', sourceUrl: 'shenzhen-source' });
  await oldLoad;
  assert.deepEqual(page.items, [{ url: 'weihai' }]);
  assert.equal(page.sourceUrl, 'weihai-source');
  assert.equal(page.page, 1);
  assert.equal(page.loading, false);
});

test('returning from notice website authentication refreshes the campus list once', async () => {
  let requests = 0;
  const { Page, ui } = pageClass('NewsPage', {
    loadLastCampus: async () => 'SHENZHEN',
    fetchCategory: async () => {
      requests++;
      return { ok: false, items: [], hasMore: false, message: '需要认证', sourceUrl: 'http://info.hitsz.edu.cn/list.jsp' };
    }
  });
  const page = new Page();
  page.selected = 1;
  await page.reload();
  page.openSource();
  assert.deepEqual(ui.routes.at(-1), {
    url: 'pages/WebBrowserPage', params: { url: 'http://info.hitsz.edu.cn/list.jsp', title: '校区通知' }
  });
  page.onPageShow();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(requests, 2);
  page.onPageShow();
  assert.equal(requests, 2);
});

test('each campus has the four Android link groups and its own academic systems', () => {
  const { CampusPortal } = campusPortals();
  for (const [campus, name, sizes, undergraduate, postgraduate] of [
    ['BENBU', '本部', [5, 7, 2, 1], 'http://jwes.hit.edu.cn', 'http://jwts.hit.edu.cn'],
    ['SHENZHEN', '深圳', [6, 6, 4, 3], 'https://jw.hitsz.edu.cn/', 'https://lab.hitsz.edu.cn/'],
    ['WEIHAI', '威海', [7, 6, 6, 2], 'http://jwts.hitwh.edu.cn/', 'https://yjsgl.hitwh.edu.cn/']
  ]) {
    const groups = CampusPortal.groupsFor(campus);
    assert.equal(CampusPortal.campusName(campus), name);
    assert.deepEqual(groups.map(group => group.title), ['教学学习', '信息与事务', '网络与系统', '资源']);
    assert.deepEqual(groups.map(group => group.portals.length), sizes);
    assert.ok(groups[0].portals.some(portal => portal.url === undergraduate));
    assert.ok(groups[0].portals.some(portal => portal.url === postgraduate));
    const urls = groups.flatMap(group => group.portals.map(portal => portal.url));
    assert.equal(new Set(urls).size, urls.length);
    for (const group of groups) {
      for (const portal of group.portals) {
        assert.ok(portal.title.length && portal.icon);
        assert.ok(['http:', 'https:'].includes(new URL(portal.url).protocol));
      }
    }
  }
  const weihai = CampusPortal.groupsFor('WEIHAI');
  assert.ok(weihai[0].portals.some(portal => portal.url === 'https://y.cybzh.cn/'));
  assert.ok(weihai[3].portals.some(portal => portal.url === 'https://qqptr.top/'));
  assert.deepEqual(CampusPortal.groupsFor(undefined), []);
  assert.deepEqual(CampusPortal.groupsFor('invalid'), []);
  assert.equal(CampusPortal.campusName(undefined), '');
});

test('campus links display URLs and support mutually exclusive tap and long-press actions', async () => {
  const portals = read('pages/PortalsPage.ets');
  assert.match(portals, /ForEach\(this\.groups/);
  assert.match(portals, /ListItemGroup\(\{ header: this\.groupHeader\(group\.title\)/);
  assert.match(portals, /\(group: CampusPortalGroup\) => \(this\.campus \?\? ''\) \+ ':' \+ group\.title/);
  assert.match(portals, /ForEach\(group\.portals/);
  assert.match(portals, /Text\(portal\.url\)/);
  assert.match(portals, /GestureGroup\(GestureMode\.Exclusive,\s*LongPressGesture/);
  assert.match(portals, /LongPressGesture[^;]+this\.copy\(portal\)/);
  assert.match(portals, /TapGesture[^;]+this\.open\(portal\)/);
  assert.match(portals, /@StorageProp\(EAS_SESSION_REVISION_KEY\) @Watch\('onSessionChanged'\)/);
  assert.doesNotMatch(portals, /NewsService|fetchCategory|EasApiClient|@kit\.NetworkKit|Refresh\(/);
  const { CampusPortal } = campusPortals();
  const entries = Object.values(EasCampus).flatMap(campus =>
    CampusPortal.groupsFor(campus).flatMap(group => group.portals));
  const { Page, ui } = pageClass('PortalsPage');
  const page = new Page();
  for (const portal of entries) await page.open(portal);
  assert.deepEqual(ui.routes, entries.map(portal => ({
    url: 'pages/WebBrowserPage', params: { url: portal.url, title: portal.title }
  })));
  assert.deepEqual(ui.clipboard, []);
});

test('campus links follow the preferred local session even when expired, and clear after logout', async () => {
  let session;
  const { Page, ui } = pageClass('PortalsPage', { loadPreferred: async () => session });
  const page = new Page();
  page.aboutToAppear();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(page.loading, false);
  assert.deepEqual(page.groups, []);
  assert.equal(page.campus, undefined);

  for (const campus of Object.values(EasCampus)) {
    session = { campus, loginExpired: true };
    page.onSessionChanged();
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(page.campus, campus);
    assert.equal(page.groups.length, 4);
  }
  session = undefined;
  page.onSessionChanged();
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(page.groups, []);
  assert.equal(page.campus, undefined);
  assert.deepEqual(ui.routes, []);
});

test('returning from a campus website preserves scroll unless the account campus changed', async () => {
  let campus = 'WEIHAI';
  let reads = 0;
  const { Page, ui } = pageClass('PortalsPage', {
    loadPreferred: async () => { reads++; return { campus }; }
  });
  const page = new Page();
  page.aboutToAppear();
  page.onPageShow();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(reads, 1);
  ui.scrolls.length = 0;
  page.fadeOpacity = 0.8;
  page.onPageHide();
  page.onSessionChanged();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(reads, 1);
  page.onPageShow();
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(ui.scrolls, []);
  assert.equal(page.fadeOpacity, 0.8);
  page.onPageHide();
  campus = 'BENBU';
  page.onPageShow();
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(ui.scrolls, ['top']);
  assert.equal(page.fadeOpacity, 0);
  assert.equal(page.campus, 'BENBU');
});

test('slow local session reads cannot replace a newer campus or update a closed page', async () => {
  for (const closePage of [false, true]) {
    const pending = deferred();
    let firstRead = true;
    const { Page } = pageClass('PortalsPage', {
      loadPreferred: () => {
        if (firstRead) { firstRead = false; return pending.promise; }
        return Promise.resolve({ campus: 'WEIHAI' });
      }
    });
    const page = new Page();
    page.aboutToAppear();
    await new Promise(resolve => setImmediate(resolve));
    if (closePage) page.aboutToDisappear();
    else await page.reload();
    pending.resolve({ campus: 'BENBU' });
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(page.campus, closePage ? undefined : 'WEIHAI');
    assert.equal(page.groups.length, closePage ? 0 : 4);
  }
});

test('local session read failure leaves a usable empty page and a later login recovers', async () => {
  let fail = true;
  const { Page } = pageClass('PortalsPage', {
    loadPreferred: async () => {
      if (fail) throw Error('preferences unavailable');
      return { campus: 'SHENZHEN' };
    }
  });
  const page = new Page();
  page.aboutToAppear();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(page.loading, false);
  assert.deepEqual(page.groups, []);
  fail = false;
  page.onSessionChanged();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(page.campus, 'SHENZHEN');
});

test('copying a campus link retains the full URL and reports clipboard or browser failures accurately', async () => {
  const portal = { title: '实验室系统', url: 'http://openlab.hitwh.edu.cn/#/login?redirect=/index' };
  for (const options of [{}, { copyFails: true }, { openFails: true }]) {
    const { Page, ui } = pageClass('PortalsPage', options);
    const page = new Page();
    page.aboutToAppear();
    if (options.openFails) await page.open(portal);
    else await page.copy(portal);
    assert.deepEqual(ui.clipboard, options.copyFails ? [] : [{ mime: 'text/plain', text: portal.url }]);
    assert.deepEqual(ui.toasts, [options.copyFails ? '复制失败，请重试' : '已复制链接']);
    assert.equal(ui.routes.length, options.openFails ? 1 : 0);
  }
});

test('switching news categories resets scrolling and ignores stale responses', async () => {
  const pending = [];
  const { Page, ui } = pageClass('NewsPage', {
    fetchCategory: (id, page) => {
      const request = { id, page, ...deferred() };
      pending.push(request);
      return request.promise;
    }
  });
  const page = new Page();
  const original = page.reload();
  page.selectTab(1);
  page.selectTab(2);
  page.selectTab(-1);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(page.selected, 1);
  assert.deepEqual(pending.map(request => [request.id, request.page]), [['blog', 0], ['10', 0]]);
  assert.deepEqual(ui.scrolls, ['top']);
  pending[1].resolve({ ok: true, items: [{ url: 'notice', title: 'Notice' }] });
  await pending[1].promise;
  pending[0].resolve({ ok: true, items: [{ url: 'news', title: 'Old blog' }] });
  await original;
  assert.deepEqual(page.items.map(item => item.url), ['notice']);
  assert.equal(page.loading, false);
});

test('the complete blog list stops pagination while notifications still load subsequent pages', async () => {
  const requests = [];
  const { Page } = pageClass('NewsPage', {
    fetchCategory: async (id, page) => {
      requests.push([id, page]);
      return {
        ok: true, hasMore: id === '10' && page === 0, message: '',
        items: [{ url: `${id}/${page}`, title: 'Article' }]
      };
    }
  });
  const page = new Page();
  await page.reload();
  assert.equal(page.hasMore, false);
  page.selectTab(1);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(page.hasMore, true);
  await page.loadPage();
  assert.equal(page.hasMore, false);
  assert.deepEqual(requests, [['blog', 0], ['10', 0], ['10', 1]]);
  assert.deepEqual(page.items.map(item => item.url), ['10/0', '10/1']);
});
