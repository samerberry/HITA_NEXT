const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = relative => fs.readFileSync(path.join(root, relative), 'utf8');

function dock({ model = 'Pura 80', deviceType = 'phone', capable = true,
  load = async () => ({ createXiaoyiAssistantBuilder: () => ({ builder() {} }) }) } = {}) {
  let source = read('feature/assistant/AssistantDockItem.ets');
  source = (source.slice(0, source.indexOf('\n  build()')) + '\n}')
    .replace('@Component', '').replace(/@(State|Prop)\s+/g, '')
    .replace('export struct', 'export class');
  const compiled = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const mod = { exports: {} }, loads = [], logs = [];
  new Function('require', 'module', 'exports', '$r', 'canIUse', compiled)(name => {
    if (name === '@kit.BasicServicesKit') return { deviceInfo: { productModel: model, deviceType, sdkApiVersion: 23 } };
    if (name === '@kit.PerformanceAnalysisKit') return { hilog: { warn: (...args) => logs.push(args) } };
    if (name === './XiaoyiAssistantEntry') { loads.push(name); return load(); }
    throw new Error('Unexpected runtime dependency: ' + name);
  }, mod, mod.exports, name => name, capability => {
    assert.equal(capability, 'SystemCapability.AI.Agent.AgentKit');
    return capable;
  });
  return { item: new mod.exports.AssistantDockItem(), loads, logs };
}

function deferred() {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return { promise, resolve };
}

test('the emulator never resolves AgentKit even when its syscap incorrectly reports support', async () => {
  for (const model of ['emulator', 'Emulator', 'HarmonyOS Emulator']) {
    const h = dock({ model, load: () => { throw new Error('agentKitHsp absent'); } });
    await h.item.aboutToAppear();
    assert.equal(h.item.nativeEntry, undefined);
    assert.deepEqual(h.loads, []); assert.deepEqual(h.logs, []);
  }
});

test('unsupported devices do not load the native module', async () => {
  for (const options of [{ capable: false }, { deviceType: '2in1' }, { deviceType: 'tv' }]) {
    const h = dock(options); await h.item.aboutToAppear();
    assert.deepEqual(h.loads, []); assert.equal(h.item.nativeEntry, undefined);
  }
});

test('supported API 23 phones and tablets keep the native builder without raising the minimum API', async () => {
  for (const deviceType of ['phone', 'tablet']) {
    const builder = { builder() {} };
    const h = dock({ deviceType, load: async () => ({ createXiaoyiAssistantBuilder: () => builder }) });
    assert.deepEqual(h.loads, [], 'importing the Dock itself must not resolve AgentKit');
    await h.item.aboutToAppear();
    assert.equal(h.item.nativeEntry, builder); assert.equal(h.loads.length, 1);
  }
});

test('module failures keep the fallback and never expose internal error data', async () => {
  const h = dock({ load: async () => { throw new Error('PRIVATE-INTERNAL-DATA'); } });
  await h.item.aboutToAppear();
  assert.equal(h.item.nativeEntry, undefined); assert.equal(h.logs.length, 1);
  assert.doesNotMatch(JSON.stringify(h.logs), /PRIVATE-INTERNAL-DATA/);
});

test('closing the Dock during loading prevents a late native component mount', async () => {
  const pending = deferred(); const h = dock({ load: () => pending.promise });
  const appeared = h.item.aboutToAppear();
  h.item.aboutToDisappear();
  let created = 0;
  pending.resolve({ createXiaoyiAssistantBuilder: () => { created++; return { builder() {} }; } });
  await appeared;
  assert.equal(created, 0); assert.equal(h.item.nativeEntry, undefined);
});

test('a previous load cannot replace the builder after the Dock reappears', async () => {
  const first = deferred(), second = deferred(); let count = 0;
  const h = dock({ load: () => count++ === 0 ? first.promise : second.promise });
  const before = h.item.aboutToAppear();
  // Start the first dynamic import before mounting the next generation.
  await Promise.resolve();
  h.item.aboutToDisappear();
  const after = h.item.aboutToAppear();
  const builder = { builder() {} };
  second.resolve({ createXiaoyiAssistantBuilder: () => builder }); await after;
  first.resolve({ createXiaoyiAssistantBuilder: () => { throw new Error('stale mount'); } }); await before;
  assert.equal(h.item.nativeEntry, builder); assert.deepEqual(h.logs, []);
});

test('the startup static import graph cannot reach the AgentKit system HSP', () => {
  const seen = new Set();
  function visit(relative) {
    const file = path.resolve(root, relative);
    if (seen.has(file)) return;
    seen.add(file);
    const text = fs.readFileSync(file, 'utf8');
    const source = ts.createSourceFile(file, text, ts.ScriptTarget.Latest, true);
    for (const node of source.statements) {
      if (!ts.isImportDeclaration(node) && !ts.isExportDeclaration(node)) continue;
      if (!node.moduleSpecifier || !ts.isStringLiteral(node.moduleSpecifier)) continue;
      const name = node.moduleSpecifier.text;
      assert.notEqual(name, '@kit.AgentFrameworkKit', 'startup dependency: ' + file);
      if (name.startsWith('.')) {
        const dependency = path.resolve(path.dirname(file), name + '.ets');
        if (fs.existsSync(dependency)) visit(dependency);
      }
    }
  }
  visit('pages/Home.ets'); visit('entryability/EntryAbility.ets');
  assert.ok(seen.has(path.join(root, 'feature/assistant/AssistantDockItem.ets')));
  assert.ok(!seen.has(path.join(root, 'feature/assistant/XiaoyiAssistantEntry.ets')));
});
