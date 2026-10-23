/**
 * static-checks.cjs — HitaNEXT 静态一致性自检（Node，无依赖）。
 *
 * 运行：node scripts/static-checks.cjs   （0=全过，非0=有问题，逐条打印）
 * 检查：
 *  1) 相对 import：文件存在性 + 目标 export 符号匹配（*限 ets/ts*）
 *  2) 路由三方一致：main_pages.json ↔ pages/@Entry ↔ router.pushUrl
 *  3) 资源引用：app.json5/module.json5 的 $media/$string/$color/$profile 可解析
 * 说明：基于简单正则，非 ArkTS 编译器；结论供 DevEco 打开前快速回归。
 */
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const ETS = path.join(ROOT, 'entry/src/main/ets');
const PAGES_JSON = path.join(ROOT, 'entry/src/main/resources/base/profile/main_pages.json');

function walk(dir, ext, out = []) {
  if (!fs.existsSync(dir)) return out;
  for (const f of fs.readdirSync(dir)) {
    const p = path.join(dir, f);
    const st = fs.statSync(p);
    if (st.isDirectory()) walk(p, ext, out);
    else if (f.endsWith(ext)) out.push(p);
  }
  return out;
}

const problems = [];
const files = walk(ETS, '.ets').concat(walk(ETS, '.ts'));

// ---- 1) imports/exports ----
const expRe = /export\s+(?:class|const|function|enum|interface|struct|type|abstract\s+class)\s+([A-Za-z0-9_$]+)/g;
const reEx = /export\s*\{([^}]*)\}/g;
const imRe = /import\s*\{([^}]*)\}\s*from\s*['"]([^'"]+)['"]/g;
const exportCache = new Map();
for (const f of files) {
  const src = fs.readFileSync(f, 'utf8');
  const names = new Set();
  let m;
  expRe.lastIndex = 0; while ((m = expRe.exec(src))) names.add(m[1]);
  reEx.lastIndex = 0; while ((m = reEx.exec(src))) for (const part of m[1].split(',')) { const n = part.trim().split(/\s+as\s+/)[0].trim(); if (n) names.add(n); }
  exportCache.set(f, names);
}
for (const f of files) {
  const src = fs.readFileSync(f, 'utf8');
  imRe.lastIndex = 0;
  let m;
  while ((m = imRe.exec(src))) {
    const spec = m[2];
    if (!spec.startsWith('.')) continue;
    const rel = path.resolve(path.dirname(f), spec);
    const target = [rel, rel + '.ets', rel + '.ts'].find((c) => fs.existsSync(c));
    if (!target) { problems.push('[import] 文件缺失 ' + f.replace(ETS, '') + ' -> ' + spec); continue; }
    const exps = exportCache.get(target) || new Set();
    for (const part of m[1].split(',')) {
      const nm = part.trim().split(/\s+as\s+/)[0].trim();
      if (!nm || nm === 'default') continue;
      if (!exps.has(nm)) problems.push('[import] 未导出 ' + nm + '（' + spec + '，使用者 ' + f.replace(ETS, '') + '）');
    }
  }
}

// ---- 2) routes ----
if (fs.existsSync(PAGES_JSON)) {
  const routes = JSON.parse(fs.readFileSync(PAGES_JSON, 'utf8')).src;
  for (const r of routes) {
    const p = path.join(ETS, r + '.ets');
    if (!fs.existsSync(p)) { problems.push('[route] 注册页文件缺失 ' + r); continue; }
    if (!/@Entry/.test(fs.readFileSync(p, 'utf8'))) problems.push('[route] 非 @Entry ' + r);
  }
  const pushRe = /pushUrl\s*\(\s*\{\s*url:\s*'pages\/([A-Za-z0-9_]+)'/g;
  for (const f of walk(ETS, '.ets')) {
    const src = fs.readFileSync(f, 'utf8');
    let m;
    while ((m = pushRe.exec(src))) if (!routes.includes('pages/' + m[1])) problems.push('[route] 未注册跳转 pages/' + m[1] + '（' + f.replace(ETS, '') + '）');
  }
  const pagesDir = path.join(ETS, 'pages');
  for (const f of fs.readdirSync(pagesDir)) {
    if (f.endsWith('.ets') && !routes.includes('pages/' + f.replace(/\.ets$/, ''))) problems.push('[route] 孤儿页面 pages/' + f);
  }
} else {
  problems.push('[route] 找不到 ' + PAGES_JSON);
}

// ---- 3) resources ----
function jsonOf(p) { try { return JSON.parse(fs.readFileSync(p, 'utf8').replace(/'/g, '"')); } catch (e) { return null; } }
function refsOf(o) {
  const out = [];
  const re = /\$(media|string|color|profile):([A-Za-z0-9_]+)/g;
  const s = JSON.stringify(o);
  let m;
  while ((m = re.exec(s))) out.push([m[1], m[2]]);
  return out;
}
for (const f of ['AppScope/app.json5', 'entry/src/main/module.json5']) {
  const p = path.join(ROOT, f);
  if (!fs.existsSync(p)) { problems.push('[res] 缺失 ' + f); continue; }
  const o = jsonOf(p);
  if (!o) { problems.push('[res] 解析失败 ' + f); continue; }
  const isApp = f.startsWith('AppScope');
  for (const [kind, name] of refsOf(o)) {
    if (kind === 'media') {
      const dir = path.join(ROOT, (isApp ? 'AppScope' : 'entry/src/main') + '/resources/base/media');
      if (!fs.existsSync(path.join(dir, name + '.png')) && !fs.existsSync(path.join(dir, name + '.json'))) problems.push('[res] media 缺失 ' + name);
    } else if (kind === 'string' || kind === 'color') {
      const dir = path.join(ROOT, (isApp ? 'AppScope' : 'entry/src/main') + '/resources/base/element');
      const j = jsonOf(path.join(dir, kind + '.json'));
      const arr = j ? j[kind] : null;
      if (!arr || !arr.some((x) => x && x.name === name)) problems.push('[res] ' + kind + ' 缺失 ' + name);
    } else if (kind === 'profile') {
      const dir = path.join(ROOT, 'entry/src/main/resources/base/profile');
      if (!fs.existsSync(path.join(dir, name + '.json'))) problems.push('[res] profile 缺失 ' + name);
    }
  }
}

if (problems.length === 0) {
  console.log('STATIC CHECKS ALL OK  (files=' + files.length + ', routes=' +
    (fs.existsSync(PAGES_JSON) ? JSON.parse(fs.readFileSync(PAGES_JSON, 'utf8')).src.length : '?') + ')');
  process.exit(0);
}
console.log('STATIC CHECKS PROBLEMS=' + problems.length);
for (const p of problems) console.log('  ' + p);
process.exit(1);
