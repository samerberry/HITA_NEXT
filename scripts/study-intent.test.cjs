const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');

function harness() {
  const state = { writes: 0, opened: [], permission: true, finishCalls: [], failQuery: false, queryCalls: [],
    operation: { id: 'operation', status: 'pending', kind: 'create', task: { title: '概率论作业', remindAt: 0 } } };
  const cache = new Map();
  class StudyInputError extends Error {}
  const service = {
    text: (params, key) => params[key] ?? '',
    query: async (_ctx, params) => {
      state.queryCalls.push(params);
      if (state.failQuery) throw Error('private SQL path');
      return { status: 'success', records: [] };
    },
    prepare: async (_ctx, kind) => ({ status: 'needs_confirmation', kind, operationId: 'operation' }),
    operation: async () => ({ ...state.operation, task: { ...state.operation.task } }),
    operationView: op => ({ status: op.status === 'pending' ? 'needs_confirmation' : op.status, operationId: op.id }),
    finish: async (_ctx, id, confirm) => {
      state.finishCalls.push([id, confirm]);
      state.operation.status = confirm ? 'saved' : 'cancelled';
      state.writes += Number(confirm);
      return { ...state.operation };
    }
  };
  function load(file) {
    file = path.resolve(root, file);
    if (cache.has(file)) return cache.get(file).exports;
    const mod = { exports: {} }; cache.set(file, mod);
    let source = fs.readFileSync(file, 'utf8');
    if (file.endsWith('StudyOperationConfirmPage.ets')) {
      source = source.slice(0, source.indexOf('\n  @Builder')) + '\n}\n';
      source = source.replace(/^@(Entry|Component)\r?\n/gm, '')
        .replace(/@(State|StorageProp|Watch)(\([^)]*\))?\s*/g, '')
        .replace('struct StudyOperationConfirmPage', 'export class StudyOperationConfirmPage');
    }
    const compiled = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText;
    new Function('require', 'module', 'exports', compiled)(name => {
      if (name.endsWith('/StudyAssistantService')) return { StudyAssistantService: service, StudyInputError };
      if (name.endsWith('/ClassReminderScheduler')) return { ClassReminderScheduler: { requestNotification: async () => {
        state.onPermission?.(); return state.permission;
      } } };
      if (name === '@kit.AbilityKit') return { InsightIntentExecutor: class {} };
      if (name === '@kit.PerformanceAnalysisKit') return { hilog: { info() {}, error() {} } };
      if (name.startsWith('@kit.') || name.includes('/theme/') || name.includes('/components/')) return {};
      return load(path.resolve(path.dirname(file), name + '.ets'));
    }, mod, mod.exports);
    return mod.exports;
  }
  const { TimetableExecutionContext: context } = load('feature/assistant/TimetableExecutionContext.ets');
  context.attach({}, Promise.resolve());
  context.current().setStudyOpener(async id => state.opened.push(id));
  const Executor = load('entryability/StudyIntentExecutor.ets').default;
  const Page = load('pages/StudyOperationConfirmPage.ets').StudyOperationConfirmPage;
  const page = () => {
    const p = new Page(); p.active = true; p.busy = false;
    p.operationId = 'operation'; p.operation = { ...state.operation, task: { ...state.operation.task } };
    p.getUIContext = () => ({ getHostContext: () => ({}) }); return p;
  };
  return { state, context, executor: new Executor(), page, data: response => JSON.parse(response.result.data) };
}

test('background tools only read/prepare and cannot open or commit a confirmation, even with a forged confirm flag', async () => {
  const h = harness();
  for (const name of ['StudyQuery', 'PrepareHomework', 'PrepareTaskCompletion', 'LearningOperation']) {
    const response = await h.executor.onExecuteInUIAbilityBackgroundMode(name, { action: 'tasks', confirm: true });
    assert.equal(response.code, 0);
  }
  assert.equal(h.state.writes, 0); assert.deepEqual(h.state.opened, []);
  assert.equal((await h.executor.onExecuteInUIAbilityBackgroundMode('ConfirmLearningOperation', {})).code, 4);
  assert.equal((await h.executor.onExecuteInUIAbilityForegroundMode('PrepareHomework', {}, {})).code, 4);
});

test('foreground confirmation returns pending rather than success and status query reflects only a later actual save', async () => {
  const h = harness();
  const response = await h.executor.onExecuteInUIAbilityForegroundMode('ConfirmLearningOperation', { operationId: 'operation' }, {});
  assert.equal(h.data(response).status, 'needs_confirmation'); assert.deepEqual(h.state.opened, ['operation']);
  assert.equal(h.state.writes, 0);
  await h.page().finish(true);
  assert.equal(h.data(await h.executor.onExecuteInUIAbilityBackgroundMode('LearningOperation', { operationId: 'operation' })).status, 'saved');
  assert.equal(h.state.writes, 1);
});

test('read/startup failures do not become no homework and do not leak internal paths', async () => {
  const h = harness(); h.state.failQuery = true;
  const response = await h.executor.onExecuteInUIAbilityBackgroundMode('StudyQuery', { action: 'tasks' });
  assert.equal(response.code, 3); assert.equal(h.data(response).status, 'error');
  assert.doesNotMatch(response.result.data, /private SQL path/);
  const pending = Promise.withResolvers(); h.context.attach({}, pending.promise);
  const request = h.executor.onExecuteInUIAbilityBackgroundMode('StudyQuery', { action: 'courses' });
  h.context.attach({}, Promise.resolve()); pending.resolve();
  assert.equal((await request).code, 3); assert.equal(h.state.queryCalls.length, 1);
});

test('confirmation waits for cold-start content and cannot use a detached UIAbility context', async () => {
  const h = harness(); h.context.attach({}, Promise.resolve()); const execution = h.context.current();
  const pending = execution.openStudyConfirmation('later');
  execution.setStudyOpener(async id => h.state.opened.push(id));
  await pending; assert.deepEqual(h.state.opened, ['later']);
  h.context.attach({}, Promise.resolve());
  await assert.rejects(execution.openStudyConfirmation('old'), /重新启动/);
});

test('notification refusal and a replaced preview during permission request never commit a hidden draft', async () => {
  const h = harness(); h.state.operation.task.remindAt = Date.now() + 60000;
  h.state.permission = false; let p = h.page(); await p.finish(true);
  assert.equal(h.state.writes, 0); assert.match(p.message, /通知/); assert.equal(p.busy, false);
  h.state.permission = true; p = h.page();
  h.state.onPermission = () => { p.generation++; p.operationId = 'replacement'; };
  await p.finish(true); assert.equal(h.state.writes, 0);
});

test('cancel commits only a cancelled receipt and double taps cannot save a task twice', async () => {
  const h = harness(); let p = h.page(); await p.finish(false);
  assert.equal(h.state.writes, 0); assert.equal(p.operation.status, 'cancelled');
  h.state.operation.status = 'pending'; p = h.page();
  await Promise.all([p.finish(true), p.finish(true)]);
  assert.equal(h.state.writes, 1); assert.equal(p.operation.status, 'saved');
});
