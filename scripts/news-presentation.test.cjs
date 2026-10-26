const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const EasCampus = { BENBU: 'BENBU', SHENZHEN: 'SHENZHEN', WEIHAI: 'WEIHAI' };

function load() {
  const code = ts.transpileModule(read('feature/news/NewsPresentation.ets'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const mod = { exports: {} };
  new Function('require', 'module', 'exports', code)(name => {
    if (name === '../eas/EasSession') return { EasCampus };
    if (name === './NewsService') return {};
    throw Error('Unexpected import: ' + name);
  }, mod, mod.exports);
  return mod.exports.NewsPresentation;
}
const P = load();
const item = (fields = {}) => ({ url: 'u', title: '', department: '', date: '', summary: '', tags: [], ...fields });
const now = new Date(2026, 9, 23, 14, 8).getTime();

test('dates read as today, yesterday, N days ago, then month-day or full date', () => {
  assert.equal(P.semanticDate('2026-10-23', now), '今天');
  assert.equal(P.semanticDate('2026-10-22', now), '昨天');
  assert.equal(P.semanticDate('2026-10-21', now), '前天');
  assert.equal(P.semanticDate('2026-10-17', now), '6天前');
  assert.equal(P.semanticDate('2026-10-16', now), '10月16日');
  assert.equal(P.semanticDate('2026-1-5', now), '1月5日');
  assert.equal(P.semanticDate('2025-12-30', now), '2025年12月30日');
  // Relative text from the site and impossible dates are shown as published.
  assert.equal(P.semanticDate('3小时前', now), '3小时前');
  assert.equal(P.semanticDate('2026-02-30', now), '2026-02-30');
  assert.equal(P.semanticDate('', now), '');
});

test('notice titles lose forward markers, leading bracket tags and the school prefix', () => {
  assert.deepEqual(P.cleanTitle('【心理健康教育】“沐浴书香”心理读书会招募公告'), ['“沐浴书香”心理读书会招募公告', '心理健康教育']);
  assert.deepEqual(P.cleanTitle('（转发）关于开展安全检查的通知'), ['关于开展安全检查的通知', '转发']);
  assert.deepEqual(P.cleanTitle('[通知] 期末考试安排'), ['期末考试安排', '通知']);
  assert.deepEqual(P.cleanTitle('哈尔滨工业大学（威海）2026年运动会通知'), ['2026年运动会通知', '']);
  // A bracket followed by too little text is itself the title.
  assert.deepEqual(P.cleanTitle('【重要通知】停电'), ['【重要通知】停电', '']);
  assert.deepEqual(P.cleanTitle('  普通   标题 '), ['普通 标题', '']);
});

test('avatar text drops institution suffixes and wraps four characters', () => {
  assert.equal(P.avatarText('教务处'), '教务');
  assert.equal(P.avatarText('学生工作部'), '学生');
  assert.equal(P.avatarText('计算机科学与技术学院'), '计算\n机科');
  assert.equal(P.avatarText('今日哈工大'), '今日\n哈工');
  // A leading Latin word stays whole on one line when it fits, never split across lines.
  assert.equal(P.avatarText('HOA 博客'), 'HOA');
  assert.equal(P.avatarText('HOA'), 'HOA');
  assert.equal(P.avatarText('justice'), 'JU');
  assert.equal(P.avatarText('AI 实验室'), 'AI');
  for (const source of ['HOA 博客', 'HOA', 'justice', 'AI 实验室', '教务处', 'X']) {
    assert.ok(!P.avatarText(source).includes('\n'), source);
  }
  assert.equal(P.avatarFontSize('HOA'), 13);
  assert.equal(P.avatarFontSize('教务'), 15);
  assert.equal(P.avatarFontSize('计算\n机科'), 11);
  assert.equal(P.avatarText('作者甲、作者乙'), '作者', 'only the first author is abbreviated');
  assert.equal(P.avatarText(''), '?');
});

test('avatar colours follow department keywords and stay stable for any other source', () => {
  assert.deepEqual(P.avatarColors('教务处'), P.avatarColors('研究生院教务办'));
  assert.notDeepEqual(P.avatarColors('教务处'), P.avatarColors('学生工作部'));
  assert.deepEqual(P.avatarColors('某个随机来源'), P.avatarColors('某个随机来源'));
  for (const source of ['HOA 博客', 'justice', '深圳校区', '']) {
    const colors = P.avatarColors(source);
    assert.equal(colors.length, 2);
    for (const color of colors) assert.match(color, /^#[0-9A-F]{6}$/);
  }
});

test('rows put the title first and the source on the secondary line', () => {
  const notice = P.row(item({ title: '【就业】秋季双选会通知', department: '学生工作部', date: '2026-10-22' }),
    false, EasCampus.BENBU, now);
  assert.equal(notice.title, '秋季双选会通知');
  assert.equal(notice.tag, '就业');
  assert.equal(notice.source, '学生工作部');
  assert.equal(notice.date, '昨天');
  assert.equal(notice.body, '');

  assert.equal(P.row(item({ title: '通知' }), false, EasCampus.WEIHAI, now).source, '威海校区');
  assert.equal(P.row(item({ title: '通知' }), false, EasCampus.SHENZHEN, now).source, '深圳校区');
  assert.equal(P.row(item({ title: '通知' }), false, EasCampus.BENBU, now).source, '今日哈工大');
  // A tag equal to the source adds nothing.
  assert.equal(P.row(item({ title: '【教务处】考试安排通知', department: '教务处' }), false, EasCampus.BENBU, now).tag, '');

  const blog = P.row(item({ title: 'MacBook 配置指北', department: 'HOA', summary: '如何正确使用一台 MacBook',
    tags: ['电脑设置', '效率工具'], date: '2026-09-14' }), true, EasCampus.BENBU, now);
  assert.equal(blog.title, 'MacBook 配置指北');
  assert.equal(blog.source, 'HOA 博客');
  assert.equal(blog.tag, '电脑设置');
  assert.equal(blog.body, '如何正确使用一台 MacBook');
  assert.equal(blog.date, '9月14日');
  // Blog titles are kept verbatim; the RSS fallback names the authors.
  const feed = P.row(item({ title: '【连载】第一章', department: 'justice', summary: '【连载】第一章' }), true,
    EasCampus.BENBU, now);
  assert.equal(feed.title, '【连载】第一章');
  assert.equal(feed.source, 'justice');
  assert.equal(feed.body, '', 'an excerpt that repeats the title is dropped');
});

test('news rows render the native reading hierarchy on one shared surface', () => {
  const page = read('pages/NewsPage.ets');
  const row = page.slice(page.indexOf('  newsRow(item: NewsItem, row: NewsRowModel, last: boolean)'));
  const title = row.indexOf('Text(row.title)');
  const source = row.indexOf('Span(row.source)');
  const body = row.indexOf('Text(row.body)');
  assert.ok(row.indexOf('Text(row.avatarText)') >= 0 && title > 0 && source > title && body > source,
    'avatar, then title, then source, then excerpt');
  assert.match(row.slice(title, source), /fontWeight\(FontWeight\.Medium\)[\s\S]*Text\(row\.date\)/);
  assert.match(row, /Span\(row\.tag\)[\s\S]*textBackgroundStyle/);
  assert.match(row, /if \(!last\) \{\s*Divider\(\)/);
  assert.match(page, /this\.newsRow\(item, this\.rowModel\(item\), index === this\.items\.length - 1\)/);
  assert.doesNotMatch(row, /this\.rowModel\(item\)/, 'each row computes its model once');
});
