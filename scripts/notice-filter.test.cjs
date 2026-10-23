const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const root = path.resolve(__dirname, '../entry/src/main/ets');
let deviceVersionCode = 0;
let httpResult = { responseCode: 200, result: '' };
const stored = new Map();

function load(file) {
  file = path.resolve(root, file);
  const mod = { exports: {} };
  const req = name => {
    if (name === '@kit.AbilityKit') {
      return {
        bundleManager: {
          BundleFlag: { GET_BUNDLE_INFO_DEFAULT: 0 },
          getBundleInfoForSelfSync: () => ({ versionName: '0.4.0', versionCode: deviceVersionCode })
        },
        common: {}
      };
    }
    if (name === '@kit.NetworkKit') {
      return { http: {
        createHttp: () => ({ request: async () => httpResult, destroy() {} }),
        RequestMethod: { GET: 'GET', POST: 'POST' },
        HttpDataType: { STRING: 'STRING' }
      } };
    }
    if (name === '@kit.ArkData') {
      return { preferences: {
        getPreferences: async () => ({
          get: async (key, def) => (stored.has(key) ? stored.get(key) : def),
          put: async (key, value) => { stored.set(key, value); },
          flush: async () => {}
        })
      } };
    }
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

const { AppNoticeCenter, AppNotice } = load('feature/notice/AppNoticeCenter.ets');

const notice = fields => {
  const n = new AppNotice();
  n.id = fields.id || 'test-notice';
  if ('severity' in fields) n.severity = fields.severity;
  if ('minAppVersion' in fields) n.minAppVersion = fields.minAppVersion;
  if ('maxAppVersion' in fields) n.maxAppVersion = fields.maxAppVersion;
  if ('affectedMinVersion' in fields) n.affectedMinVersion = fields.affectedMinVersion;
  if ('affectedMaxVersion' in fields) n.affectedMaxVersion = fields.affectedMaxVersion;
  return n;
};
const shown = n => AppNoticeCenter.activeNotices([n]).length === 1;

test('无版本限制的公告对所有版本可见', () => {
  deviceVersionCode = 2001000;
  assert.ok(shown(notice({})));
  deviceVersionCode = 4000000;
  assert.ok(shown(notice({})));
});

test('min_app_version 作为可见下限', () => {
  const n = notice({ minAppVersion: 4000000 });
  deviceVersionCode = 3002000;
  assert.ok(!shown(n));
  deviceVersionCode = 4000000;
  assert.ok(shown(n));
});

test('max_app_version 作为可见上限', () => {
  const n = notice({ maxAppVersion: 3999999 });
  deviceVersionCode = 3002000;
  assert.ok(shown(n));
  deviceVersionCode = 4000000;
  assert.ok(!shown(n));
});

test('min/max 组合表达版本区间', () => {
  const n = notice({ minAppVersion: 3000000, maxAppVersion: 3002999 });
  deviceVersionCode = 2001000;
  assert.ok(!shown(n));
  deviceVersionCode = 3002000;
  assert.ok(shown(n));
  deviceVersionCode = 4000000;
  assert.ok(!shown(n));
});

test('affected_min/max 同样参与过滤', () => {
  const n = notice({ affectedMinVersion: 3002000, affectedMaxVersion: 3999999 });
  deviceVersionCode = 3000000;
  assert.ok(!shown(n));
  deviceVersionCode = 3002000;
  assert.ok(shown(n));
  deviceVersionCode = 4000000;
  assert.ok(!shown(n));
});

test('critical 公告排在普通公告前面', () => {
  deviceVersionCode = 4000000;
  const info = notice({ id: 'info-one', severity: 'info' });
  const crit = notice({ id: 'crit-one', severity: 'critical' });
  const out = AppNoticeCenter.activeNotices([info, crit]);
  assert.equal(out[0].id, 'crit-one');
});

test('解析 JSON 的 snake_case 上下限字段并回落缓存', async () => {
  deviceVersionCode = 3002000;
  httpResult = { responseCode: 200, result: JSON.stringify({ notices: [
    {
      id: 'range-notice', kind: 'service', severity: 'info', title: 't', body: 'b',
      min_app_version: 3002000, max_app_version: 3999999,
      affected_min_version: -1, affected_max_version: -1,
      starts_at: -1, ends_at: -1
    }
  ] }) };
  const fetched = await AppNoticeCenter.fetch({});
  assert.equal(fetched.length, 1);
  assert.equal(fetched[0].minAppVersion, 3002000);
  assert.equal(fetched[0].maxAppVersion, 3999999);
  assert.equal(AppNoticeCenter.activeNotices(fetched).length, 1);

  const cached = await AppNoticeCenter.cachedNotices({});
  assert.equal(cached.length, 1);
  assert.equal(cached[0].minAppVersion, 3002000);
  assert.equal(cached[0].maxAppVersion, 3999999);
  assert.equal(AppNoticeCenter.activeNotices(cached).length, 1);

  deviceVersionCode = 4000000;
  assert.equal(AppNoticeCenter.activeNotices(cached).length, 0);
});
