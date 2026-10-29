const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const cache = new Map();
function load(file) {
  file = path.resolve(root, file);
  if (cache.has(file)) return cache.get(file).exports;
  const mod = { exports: {} };
  cache.set(file, mod);
  const compiled = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  new Function('require', 'module', 'exports', compiled)(name => name.startsWith('@kit.') ? {} :
    load(path.resolve(path.dirname(file), name + '.ets')), mod, mod.exports);
  return mod.exports;
}
const { AssistantService } = load('feature/assistant/AssistantService.ets');
const { EasTimetable } = load('common/model/timetable/TimetableModels.ets');
const term = Object.assign(new EasTimetable(), {
  startTime: new Date(2026, 7, 31).getTime(), endTime: new Date(2027, 0, 24).getTime() - 1
});

test('dates without a year land in the term, and dates that do not exist are not rolled over', () => {
  const december = new Date(2026, 11, 20, 10).getTime();
  assert.equal(AssistantService.resolveDay(term, '1月8日有什么课', december), new Date(2027, 0, 8).getTime());
  assert.equal(AssistantService.resolveDay(term, '9月1日', new Date(2027, 0, 5).getTime()), new Date(2026, 8, 1).getTime());
  assert.equal(AssistantService.resolveDay(term, '2月30日有什么课', december), undefined);
  assert.equal(AssistantService.resolveDay(term, '13月5日有什么课', december), undefined);
});

test('下一周 and 上一周 move a week like 下周 and 上周, and 下一周周三 is next Wednesday', () => {
  const now = new Date(2026, 9, 28, 10).getTime();
  assert.equal(AssistantService.resolveWeek(term, '下一周有什么课', now), AssistantService.resolveWeek(term, '下周有什么课', now));
  assert.equal(AssistantService.resolveWeek(term, '上一周的课', now), AssistantService.resolveWeek(term, '上周的课', now));
  assert.notEqual(AssistantService.resolveWeek(term, '下一周有什么课', now), AssistantService.resolveWeek(term, '本周有什么课', now));
  assert.equal(AssistantService.resolveDay(term, '下一周周三有什么课', now), AssistantService.resolveDay(term, '下周三有什么课', now));
});
