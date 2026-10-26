const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const root = path.resolve(__dirname, '../entry/src/main');
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
global.$r = name => ({ id: -1, type: 20000, params: [name] });

function loadContent() {
  const code = ts.transpileModule(read('ets/feature/about/AboutContent.ets'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const mod = { exports: {} };
  new Function('require', 'module', 'exports', code)(() => ({}), mod, mod.exports);
  return mod.exports.AboutContent;
}

test('More lists 教务功能, then 设置, then 更多 with notices and about at the end', () => {
  const home = read('ets/pages/Home.ets');
  const more = home.slice(home.indexOf('  tabMine()'), home.indexOf('  userCard()'));
  const order = ['课表工具', '教务功能', '设置', '更多'].map(title => more.indexOf(`moreSectionTitle('${title}')`));
  assert.ok(order.every(index => index >= 0), 'every section exists');
  assert.deepEqual([...order].sort((a, b) => a - b), order, 'sections appear in order');

  const settings = more.slice(order[2], order[3]);
  assert.match(settings, /this\.classReminderSettings\(\)/);
  assert.match(settings, /this\.appearanceSettings\(\)/);
  assert.doesNotMatch(settings, /'公告'|'关于'/);

  const tail = more.slice(order[3]);
  const notice = tail.indexOf("'公告'");
  const about = tail.indexOf("'关于'");
  assert.ok(notice > 0 && about > notice, 'about follows notices');
  assert.match(tail.slice(notice), /url: 'pages\/NoticesPage'/);
  assert.match(tail.slice(about), /url: 'pages\/AppAboutPage'/);
});

test('about and privacy pages are registered and linked', () => {
  const routes = JSON.parse(read('resources/base/profile/main_pages.json')).src;
  assert.ok(routes.includes('pages/AppAboutPage'));
  assert.ok(routes.includes('pages/PrivacyPolicyPage'));
  const about = read('ets/pages/AppAboutPage.ets');
  for (const title of ['制作者', '鸣谢']) assert.match(about, new RegExp(`sectionTitle\\('${title}'\\)`));
  // The policy is reached from the button under the app name; there is no separate section.
  assert.doesNotMatch(about, /sectionTitle\('隐私'\)/);
  assert.match(about, /url: 'pages\/PrivacyPolicyPage'/);
  assert.match(about, /url: 'pages\/WebBrowserPage'/);
  const home = read('ets/pages/Home.ets');
  assert.match(home, /'关于',\s*'关于HITA NEXT'/);
});

test('about lists the three contributors in order with real names, GitHub nicknames and avatars', () => {
  const content = loadContent();
  const people = content.contributors();
  assert.deepEqual(people.map(person => [person.name, person.github]),
    [['蒋国贤', 'samerberry'], ['刘震宇', 'sofa1145'], ['肖丁荣', 'xdInternet']]);
  for (const person of people) {
    assert.equal(person.url, 'https://github.com/' + person.github);
    const media = person.avatar.params[0].replace('app.media.', '');
    const file = path.join(root, 'resources/base/media', media + '.png');
    assert.ok(fs.existsSync(file), file);
    assert.equal(fs.readFileSync(file).subarray(1, 4).toString(), 'PNG', file);
  }
  const about = read('ets/pages/AppAboutPage.ets');
  const row = about.slice(about.indexOf('  contributorRow('), about.indexOf('  creditRow('));
  assert.match(row, /Image\(person\.avatar\)/);
  assert.match(row, /Text\(person\.name\)[\s\S]*Text\(person\.github\)/);
  assert.doesNotMatch(row, /person\.role|person\.initial/);
});

test('credits keep the three source projects only', () => {
  const content = loadContent();
  assert.deepEqual(content.projectCredits().map(credit => credit.url), [
    'https://github.com/StupidTrees/HITA_X', 'https://github.com/HIT-A/HITA_Android',
    'https://github.com/HIT-A/HITA-Aura']);
  assert.doesNotMatch(read('ets/pages/AppAboutPage.ets'), /HITA_TEAM|HITA Android 开发者/);
});

test('privacy policy text mirrors the hosted agreement and links to it', () => {
  const content = loadContent();
  assert.match(content.PRIVACY_POLICY_URL, /agreementId=2056866492535841728$/);
  assert.equal(content.POLICY_TITLE, '关于HITA NEXT与隐私的声明');
  assert.equal(content.CONTACT_EMAIL, 'jiangguoxian0313@outlook.com');
  assert.deepEqual(content.policy().map(section => section.title), [
    '1. 我们如何收集和使用您的个人信息', '2. 设备权限调用', '3. 管理您的个人信息',
    '4. 信息存储地点及期限', '5. 如何联系我们']);
  const text = content.policyIntro().join('\n') + content.policy().map(s => s.items.join('\n')).join('\n');
  assert.match(text, /HITA NEXT 是由 蒋国贤/);
  assert.match(text, /导出至手机日历/);
  assert.match(text, /邮箱：jiangguoxian0313@outlook\.com/);
  assert.doesNotMatch(text, /undefined/, 'empty template fields from the hosted page are not copied');
  const page = read('ets/pages/PrivacyPolicyPage.ets');
  assert.match(page, /AboutContent\.PRIVACY_POLICY_URL/);
  assert.match(page, /AboutContent\.POLICY_EFFECTIVE/);
});
