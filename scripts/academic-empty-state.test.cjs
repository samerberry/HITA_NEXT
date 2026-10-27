const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '../entry/src/main/ets/pages');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');

function emptyBranch(source, condition) {
  const start = source.indexOf(`} else if (${condition}) {`);
  assert.ok(start >= 0, 'empty-state branch must remain separate from loading and errors');
  const end = source.indexOf('\n      } else {', start);
  assert.ok(end > start, 'data list must remain separate from the empty state');
  return source.slice(start, end);
}

const cases = [
  ['ExamPage.ets', '!this.loadError && this.exams.length === 0 && this.remoteExams.length === 0']
];

for (const [file, condition] of cases) {
  test(`${file}: empty content is centered below the header and above the gesture inset`, () => {
    const source = read(file);
    const empty = emptyBranch(source, condition);
    assert.match(source, /@StorageProp\('hita_nav_bar_vp'\) navBarInset: number = NAV_BAR_INSET_FALLBACK/);
    assert.match(empty, /\}\s*\.width\('100%'\)\s*\.height\('100%'\)\s*\.padding\(\{\s*left: 32, right: 32, top: HEADER_HEIGHT, bottom: this\.navBarInset\s*\}\)\s*\.justifyContent\(FlexAlign\.Center\)\s*\.alignItems\(HorizontalAlign\.Center\)/);
    assert.doesNotMatch(empty, /\.margin\(\{ top: HEADER_HEIGHT/);
    assert.doesNotMatch(empty, /Text\('\u25c9'\)|Circle\(|LoadingProgress\(|SymbolGlyph\(|Image\(/);
    assert.ok((empty.match(/\.width\('100%'\)\s*\.textAlign\(TextAlign\.Center\)/g) ?? []).length >= 2,
      'title and wrapping subtitle both need centered text');
  });
}

test('empty states keep loading and text hints without login or add buttons', () => {
  const exam = read('ExamPage.ets');
  const score = read('ScorePage.ets');
  const examEmpty = emptyBranch(exam, cases[0][1]);
  assert.doesNotMatch(examEmpty, /Button\(|\.onClick\(|openAddExam|\.margin\(\{\s*bottom:/);
  assert.match(exam, /HeaderActionButton\(\{ label: '\u6dfb\u52a0',[\s\S]*?this\.openAddExam\(\)/);
  assert.equal((exam.match(/this\.openAddExam\(\)/g) ?? []).length, 1);
  const hint = /Text\((this\.queryMsg[\s\S]*?)\)\s*\.fontSize/.exec(examEmpty);
  assert.ok(hint, 'the empty state must display the query message');
  const text = new Function(`return (${hint[1]});`);
  assert.equal(text.call({ queryMsg: 'Query failed', hasSession: true }), 'Query failed');
  for (const hasSession of [false, true]) {
    assert.ok(text.call({ queryMsg: '', hasSession }).length > 0, 'no message still needs a readable fallback');
  }
  assert.match(examEmpty.slice(hint.index), /\.width\('100%'\)\s*\.textAlign\(TextAlign\.Center\)/);
  assert.match(exam, /if \(this\.preparingQuery \|\| this\.querying \|\|\s*\(this\.loading && this\.exams\.length === 0 && this\.remoteExams\.length === 0\)\) \{\s*Column\([^)]*\) \{\s*LoadingProgress\(\)/);
  // Score statistics stay visible for a successful empty transcript; errors have their own retry state.
  assert.match(score, /if \(this\.loading\) \{\s*Column\([^)]*\) \{\s*LoadingProgress\(\)/);
  assert.match(score, /else if \(this\.errorText\) \{/);
  assert.match(score, /else if \(this\.queried\) \{[\s\S]*?this\.statisticsCard\(\)[\s\S]*?if \(this\.scores\.length === 0\)/);
});
