/**
 * EasWebLoginProbe.ets — URL/页面/会话判定谓词集（纯函数，与平台无关，可单测回归）。
 *
 * 判定规则参考 HITA Android 的 WebLoginSuccessPolicy、ShenzhenWebAutoLogin
 * 和 WebViewLoginActivity，并适配鸿蒙端的 Cookie 采集流程。
 */
import { EasCampus } from '../EasSession';
import { EasCampusUrls } from './EasWebLoginConfig';

/** 威海 webvpn ticket Cookie key 前缀（WEIHAI_TICKET_COOKIE_PREFIX，L234）。 */
export const WEIHAI_TICKET_COOKIE_PREFIX: string = 'wengine_vpn_ticket';

// ---------------------------------------------------------------------------
// URL 基础工具（ArkTS 无 java.net.URI；手写 host/path 提取）
// ---------------------------------------------------------------------------

export function isBlank(s: string | undefined): boolean {
  return s === undefined || s === null || s.trim().length === 0;
}

function cleanedUrl(url: string): string {
  let u: string = url;
  const h: number = u.indexOf('#');
  if (h >= 0) {
    u = u.substring(0, h);
  }
  const q: number = u.indexOf('?');
  if (q >= 0) {
    u = u.substring(0, q);
  }
  return u;
}

/** 取 host（小写）；解析失败返回 ''。 */
export function hostOf(url: string): string {
  const u: string = cleanedUrl(url);
  const m: RegExpExecArray | null = /^[a-zA-Z][a-zA-Z0-9+.-]*:\/\/([^\/:?#]+)/.exec(u);
  return m === null ? '' : m[1].toLowerCase();
}

/** 取 path（小写，含首 '/'，不含 query/fragment）；根路径返回 ''。 */
export function pathOf(url: string): string {
  const u: string = cleanedUrl(url);
  const m: RegExpExecArray | null = /^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//.exec(u);
  if (m === null) {
    return u.toLowerCase();
  }
  const rest: string = u.substring(m[0].length);
  const slash: number = rest.indexOf('/');
  if (slash < 0) {
    return '';
  }
  return rest.substring(slash).toLowerCase();
}

function trimEndSlash(s: string): string {
  return s.replace(/\/+$/, '');
}

function containsIgnoreCase(haystack: string, needle: string): boolean {
  return haystack.toLowerCase().indexOf(needle.toLowerCase()) >= 0;
}

function equalsIgnoreCase(a: string, b: string): boolean {
  if (a === undefined || b === undefined) {
    return false;
  }
  return a.toLowerCase() === b.toLowerCase();
}

// ---------------------------------------------------------------------------
// 会话判定
// ---------------------------------------------------------------------------

/**
 * 深圳 Web 会话成立：
 * `(!js.isBlank() && !route.isBlank()) || !session.isBlank()`
 * —— 直连会话需要 JSESSIONID + route；代理会话可由非空 SESSION 单独成立。
 */
export function hasShenzhenWebSessionCookies(cookies: Map<string, string>): boolean {
  const js: string = cookies.has('JSESSIONID') ? (cookies.get('JSESSIONID') as string) : '';
  const route: string = cookies.has('route') ? (cookies.get('route') as string) : '';
  const session: string = cookies.has('SESSION') ? (cookies.get('SESSION') as string) : '';
  return (!isBlank(js) && !isBlank(route)) || !isBlank(session);
}

/** 深圳 Cookie 探针 URL 序列（WebLoginSuccessPolicy.shenzhenCookieProbeUrls，8 个）。 */
export function shenzhenCookieProbeUrls(proxyBaseUrl: string, directBaseUrl: string): string[] {
  const paths: string[] = ['/authentication/main', '/student_index', '/user/me', '/'];
  const seenBases: Set<string> = new Set<string>();
  const bases: string[] = [];
  const raw: string[] = [proxyBaseUrl, directBaseUrl];
  for (let i = 0; i < raw.length; i++) {
    const norm: string = trimEndSlash(raw[i]).toLowerCase();
    if (!seenBases.has(norm)) {
      seenBases.add(norm);
      bases.push(raw[i]);
    }
  }
  const out: string[] = [];
  for (let i = 0; i < bases.length; i++) {
    const base: string = trimEndSlash(bases[i]);
    for (let j = 0; j < paths.length; j++) {
      out.push(base + paths[j]);
    }
  }
  return out;
}

/**
 * 深圳实际数据基址选择（shenzhenWebBaseUrl L431-449）：当前 host 与 directBase host
 * 忽略大小写相等 → direct（trimEnd '/'）；否则 proxy（trimEnd '/'）。
 */
export function shenzhenWebBaseUrl(host: string, proxyBaseUrl: string, directBaseUrl: string): string {
  const directHost: string = hostOf(directBaseUrl);
  if (directHost.length > 0 && equalsIgnoreCase(host, directHost)) {
    return trimEndSlash(directBaseUrl);
  }
  return trimEndSlash(proxyBaseUrl);
}

// ---------------------------------------------------------------------------
// Cookie header 解析 / URL jsessionid
// ---------------------------------------------------------------------------

/**
 * parseCookies（L3483-3592）：";" 切分 → 每段 trim → 首个 "=" 拆 k/v；空段/无 "=" /空 key 跳过。
 * 注意：不识别 Cookie 属性（Expires/Path 等会并入 value）。
 */
export function parseCookiesHeader(header: string): Map<string, string> {
  const out: Map<string, string> = new Map<string, string>();
  if (header === undefined || header === null || isBlank(header)) {
    return out;
  }
  const parts: string[] = header.split(';');
  for (let i = 0; i < parts.length; i++) {
    const seg: string = parts[i].trim();
    if (seg.length === 0) {
      continue;
    }
    const eq: number = seg.indexOf('=');
    if (eq <= 0) {
      continue;
    }
    const k: string = seg.substring(0, eq).trim();
    const v: string = seg.substring(eq + 1).trim();
    if (k.length > 0) {
      out.set(k, v);
    }
  }
  return out;
}

/**
 * extractJsessionidFromUrl（L1488-1512）：依次 `;jsessionid=([^;&?]*)`、`[?&]jsessionid=([^;&]*)`
 * （均 IGNORE_CASE，首个命中即返回捕获组 1）；未命中返回 ''。
 */
export function extractJsessionidFromUrl(url: string): string {
  const m1: RegExpExecArray | null = /;jsessionid=([^;&?]*)/i.exec(url);
  if (m1 !== null && m1[1] !== undefined) {
    return m1[1];
  }
  const m2: RegExpExecArray | null = /[?&]jsessionid=([^;&]*)/i.exec(url);
  if (m2 !== null && m2[1] !== undefined) {
    return m2[1];
  }
  return '';
}

/** hasUrlJsession（L2428-2446）：URL 任意位置含 ";jsessionid=" 或 "jsessionid="（忽略大小写）。 */
export function hasUrlJsession(url: string): boolean {
  return containsIgnoreCase(url, ';jsessionid=') || containsIgnoreCase(url, 'jsessionid=');
}

/** hasWeihaiVpnTicket（L2452-2489）：任一 key startsWith 或 contains "wengine_vpn_ticket"（忽略大小写）。 */
export function hasWeihaiVpnTicket(cookies: Map<string, string>): boolean {
  let found: boolean = false;
  cookies.forEach((value: string, key: string) => {
    if (!found && (key.toLowerCase().startsWith(WEIHAI_TICKET_COOKIE_PREFIX) ||
      key.toLowerCase().indexOf(WEIHAI_TICKET_COOKIE_PREFIX) >= 0)) {
      found = true;
    }
  });
  return found;
}

/**
 * 三校区“必选 Cookie”判定（hasRequiredCookies L2339-2426 逐字规则，供完成判定复用）。
 * @param cookies 已合并 Cookie Map
 * @param url 当前页 URL（仅 BENBU 用）
 * @param campus 校区
 * @param studentType "1"|"2"
 */
export function hasRequiredCookiesFor(cookies: Map<string, string>, url: string,
  campus: EasCampus, studentType: string): boolean {
  if (campus === EasCampus.SHENZHEN) {
    return hasShenzhenWebSessionCookies(cookies);
  }
  if (campus === EasCampus.WEIHAI) {
    return hasWeihaiVpnTicket(cookies) && cookies.has('JSESSIONID');
  }
  // BENBU
  if (studentType === '2') {
    // 研究生：sdp_user_token 非空 且 (map 有非空 JSESSIONID 或 url 带 jsessionid)
    const sdp: string = cookies.has('sdp_user_token') ? (cookies.get('sdp_user_token') as string) : '';
    if (isBlank(sdp)) {
      return false;
    }
    const js: string | undefined = cookies.get('JSESSIONID');
    if (js !== undefined && js !== null && !isBlank(js)) {
      return true;
    }
    return hasUrlJsession(url);
  }
  // 本科生：(JSESSIONID 在 map 或在 url) 且 map 含 HIT（值空白也算 containsKey）
  const hasJs: boolean = cookies.has('JSESSIONID') || hasUrlJsession(url);
  return hasJs && cookies.has('HIT');
}

// ---------------------------------------------------------------------------
// “已认证页面/页面类别”判定（WebLoginSuccessPolicy / Activity §A 语义）
// ---------------------------------------------------------------------------

/** 深圳：host∈{jw.hitsz.edu.cn, jw-hitsz-edu-cn.hitsz.edu.cn}，path 不含 login/authserver/
 * authentication/require，且 (path 空或'/'或含 authentication/main|student_index|user/me|
 * xszykb|xsxk) 且具深圳 Web 会话 Cookie（L46-158）。 */
export function isShenzhenAuthenticatedPage(url: string, cookies: Map<string, string>): boolean {
  const host: string = hostOf(url);
  if (host !== 'jw.hitsz.edu.cn' && host !== 'jw-hitsz-edu-cn.hitsz.edu.cn') {
    return false;
  }
  const path: string = pathOf(url);
  if (path.indexOf('login') >= 0 || path.indexOf('authserver') >= 0 ||
    path.indexOf('authentication/require') >= 0) {
    return false;
  }
  const authedPath: boolean = path.length === 0 || path === '/' ||
    path.indexOf('authentication/main') >= 0 || path.indexOf('student_index') >= 0 ||
    path.indexOf('user/me') >= 0 || path.indexOf('xszykb') >= 0 || path.indexOf('xsxk') >= 0;
  return authedPath && hasShenzhenWebSessionCookies(cookies);
}

/**
 * 威海成功页（L164-317）：path 含 /http/ 或 kbcx|cjcx|kjscx|query|index（成功路径集合），
 * 且非登录页（logincas、endsWith /login、/login/），且含 wengine_vpn_ticket* key 且 JSESSIONID 非空。
 */
export function isWeihaiAuthenticatedPage(url: string, cookies: Map<string, string>): boolean {
  if (hostOf(url) !== 'webvpn.hitwh.edu.cn') {
    return false;
  }
  const path: string = pathOf(url);
  const pathOk: boolean = path.indexOf('/http/') >= 0 || path.indexOf('kbcx') >= 0 ||
    path.indexOf('cjcx') >= 0 || path.indexOf('kjscx') >= 0 || path.indexOf('query') >= 0 ||
    path.indexOf('index') >= 0;
  const loginish: boolean = path.indexOf('logincas') >= 0 || path.endsWith('/login') ||
    path.indexOf('/login/') >= 0 || path.indexOf('authserver') >= 0 || path.indexOf('reauth') >= 0;
  if (!pathOk || loginish) {
    return false;
  }
  if (!hasWeihaiVpnTicket(cookies)) {
    return false;
  }
  const js: string | undefined = cookies.get('JSESSIONID');
  return js !== undefined && js !== null && !isBlank(js);
}

/** isAuthenticationPage L2586-2595：CAS 登录页 = path 含 "/authserver/login"（忽略大小写）。 */
export function isAuthenticationPage(url: string): boolean {
  return containsIgnoreCase(pathOf(url), '/authserver/login');
}

/** isMfaPage L2761-2769：path 含 "/authserver/reAuthCheck/"（忽略大小写）。 */
export function isMfaPage(url: string): boolean {
  return containsIgnoreCase(pathOf(url), '/authserver/reauthcheck/');
}

/** 静默续期停在这些页面即放弃：需要用户输入账号密码或完成二次认证。 */
export function isCredentialPromptPage(url: string): boolean {
  return isAuthenticationPage(url) || isMfaPage(url);
}

/**
 * 静默续期不把这些页面上的登录表单当作需要用户介入：深圳教务入口自带本地账号表单，
 * 控制器会点击“统一身份认证登录”；本部实验教学与电子实验系统只是登录后的可选会话。
 */
export function ignoresLoginFormDuringRenewal(url: string): boolean {
  const host: string = hostOf(url);
  return host === hostOf(EasCampusUrls.SHENZHEN_DIRECT_BASE) || isShenzhenProxyJwPage(url) ||
    host === hostOf(EasCampusUrls.SJJX_BASE) || host === hostOf(EasCampusUrls.EELABINFO_URL);
}

/** Only the configured EAS host may supply a Benbu session, not CAS or a portal. */
export function isBenbuEasPage(url: string, studentType: string): boolean {
  const base: string = studentType === '2' ? EasCampusUrls.GRADUATE_BASE : EasCampusUrls.JWTS_BASE;
  const path: string = pathOf(url);
  return hostOf(url) === hostOf(base) && path.indexOf('authserver') < 0 &&
    path.indexOf('reauth') < 0 && path.indexOf('logout') < 0;
}

/** isShenzhenProxyJwPage L2839-2843：host == jw-hitsz-edu-cn.hitsz.edu.cn（忽略大小写）。 */
export function isShenzhenProxyJwPage(url: string): boolean {
  return equalsIgnoreCase(hostOf(url), hostOf(EasCampusUrls.SHENZHEN_PROXY_BASE));
}

/** isJwtsPage L2689-2759：WEIHAI 恒 false；host 含 jwts 或(研究生且 host 含 yjsgl)，且 url/path 小写含 logincas 或 login。 */
export function isJwtsPage(url: string, campus: EasCampus, studentType: string): boolean {
  if (campus === EasCampus.WEIHAI) {
    return false;
  }
  const host: string = hostOf(url);
  const lower: string = url.toLowerCase();
  const hostOk: boolean = host.indexOf('jwts') >= 0 || (studentType === '2' && host.indexOf('yjsgl') >= 0);
  if (!hostOk) {
    return false;
  }
  return lower.indexOf('logincas') >= 0 || lower.indexOf('login') >= 0;
}

/** isPortalHomePage L2771-2837：见各校区规则（路径比较前 trimEnd '/'）。 */
export function isPortalHomePage(url: string, campus: EasCampus): boolean {
  const host: string = hostOf(url);
  const path: string = trimEndSlash(pathOf(url));
  const lowerUrl: string = url.toLowerCase();

  if (campus === EasCampus.SHENZHEN) {
    // 1. 代理首页：https://jw-hitsz-edu-cn.hitsz.edu.cn/
    const isProxyBase: boolean = equalsIgnoreCase(trimEndSlash(cleanedUrl(url)),
      trimEndSlash(cleanedUrl(EasCampusUrls.SHENZHEN_PROXY_BASE)));
    // 2. aTrust 门户首页：host 为 trust.hitsz.edu.cn，且处于登录成功后的门户页（非 shortcut、非 login、非 authserver）
    const isTrustPortal: boolean = (host === 'trust.hitsz.edu.cn') &&
      (path.length === 0 || path === '/portal' || path.startsWith('/portal/')) &&
      lowerUrl.indexOf('/portal/shortcut') < 0 &&
      lowerUrl.indexOf('/login') < 0 &&
      lowerUrl.indexOf('authserver') < 0;
    return isProxyBase || isTrustPortal;
  }
  if (campus === EasCampus.WEIHAI) {
    // 威海 WebVPN 门户首页：host 为 webvpn.hitwh.edu.cn，认证成功后的门户页
    const isWeihaiHost: boolean = (host === 'webvpn.hitwh.edu.cn');
    const isLoginPath: boolean = path === '/login' || path.startsWith('/login/') ||
      lowerUrl.indexOf('authserver') >= 0 || lowerUrl.indexOf('logincas') >= 0;
    const hasPortalIndicator: boolean = path.startsWith('/portal') ||
      lowerUrl.indexOf('#/portal') >= 0 || lowerUrl.indexOf('#/') >= 0;
    // Android WebViewLoginActivity 将根路径也视为门户，并在 CAS 返回根路径时
    // 再次打开 WEIHAI_JWTS；否则认证成功后会停在根页面。
    const isRoot: boolean = path.length === 0 || path === '/';
    return isWeihaiHost && !isLoginPath && (isRoot || hasPortalIndicator);
  }
  // BENBU
  return host === 'i-hit-edu-cn.ivpn.hit.edu.cn' && (path === '/portal/home' || path === '/portal');
}

/** isTrustPortalPage L3015-3033：host==trust.hitsz.edu.cn 且 path startsWith /portal。 */
export function isTrustPortalPage(url: string): boolean {
  return hostOf(url) === 'trust.hitsz.edu.cn' && pathOf(url).startsWith('/portal');
}

/** isIvpnRedirectPage L2676-2687：仅 BENBU，且 host 精确等于 "ivpn.hit.edu.cn"（大小写敏感）。 */
export function isIvpnRedirectPage(url: string, campus: EasCampus): boolean {
  if (campus !== EasCampus.BENBU) {
    return false;
  }
  return hostOf(url) === 'ivpn.hit.edu.cn';
}

// ---------------------------------------------------------------------------
// 深圳推进辅助（ShenzhenWebAutoLogin）
// ---------------------------------------------------------------------------

/** normalizeStudentType：trim 后为 "2" 保持，其余一律 "1"。 */
export function normalizeStudentType(raw: string | undefined): string {
  if (raw !== undefined && raw !== null && raw.trim() === '2') {
    return '2';
  }
  return '1';
}

/** isProxyRoot：去 query/fragment/尾 '/' 后与 proxyBase 相等。 */
export function isProxyRoot(url: string, proxyBaseUrl: string): boolean {
  return trimEndSlash(cleanedUrl(url)) === trimEndSlash(cleanedUrl(proxyBaseUrl));
}

/**
 * reauthenticationUrl：
 * 当前 host 与 direct 相同 且 path 含 /authentication/require → direct/cas；
 * 否则当前 host 与 proxy 相同 且 path 含 /session/invalid → proxy/cas；否则 ''。
 */
export function reauthenticationUrl(currentUrl: string, directBaseUrl: string,
  proxyBaseUrl: string): string {
  const curHost: string = hostOf(currentUrl);
  const path: string = pathOf(currentUrl);
  if (curHost.length > 0 && equalsIgnoreCase(curHost, hostOf(directBaseUrl)) &&
    path.indexOf('/authentication/require') >= 0) {
    return trimEndSlash(directBaseUrl) + '/cas';
  }
  if (curHost.length > 0 && equalsIgnoreCase(curHost, hostOf(proxyBaseUrl)) &&
    path.indexOf('/session/invalid') >= 0) {
    return trimEndSlash(proxyBaseUrl) + '/cas';
  }
  return '';
}

// ---------------------------------------------------------------------------
// 页面类型综合判定（状态机用；isSuccessPage L2845-3013 语义 + MFA/门户细类）
// ---------------------------------------------------------------------------

export enum EasPageKind {
  UNKNOWN = 'UNKNOWN',
  LOGIN = 'LOGIN',                 // 统一认证登录页
  IVPN_REDIRECT = 'IVPN_REDIRECT', // 本部 ivpn 中转
  PORTAL_HOME = 'PORTAL_HOME',     // 门户首页
  JWTS = 'JWTS',                   // jwts/yjsgl 目标系统
  MFA = 'MFA',                     // 二次认证
  TRUST_PORTAL = 'TRUST_PORTAL',   // aTrust 强门户
  SZ_PROXY_JW = 'SZ_PROXY_JW',     // 深圳代理 jw 页
  SUCCESS = 'SUCCESS'              // 已认证成功页
}

/**
 * 成功页判定（isSuccessPage L2845-3013）：
 *  - SHENZHEN：isShenzhenAuthenticatedPage(url, cookies)
 *  - WEIHAI：isWeihaiAuthenticatedPage(url, cookies)
 *  - BENBU：仅接受对应培养层次的教务域名；本科仍需由控制器验证课表接口。
 */
export function isSuccessPageFor(url: string, cookies: Map<string, string>, campus: EasCampus,
  studentType: string): boolean {
  if (isAuthenticationPage(url) || isMfaPage(url)) {
    return false;
  }
  if (campus === EasCampus.SHENZHEN) {
    return isShenzhenAuthenticatedPage(url, cookies);
  }
  if (campus === EasCampus.WEIHAI) {
    return isWeihaiAuthenticatedPage(url, cookies);
  }
  if (!isBenbuEasPage(url, studentType)) {
    return false;
  }
  const path: string = pathOf(url);
  if (studentType === '2') {
    return path.indexOf('/xs/index') >= 0 &&
      hasRequiredCookiesFor(cookies, url, campus, studentType);
  }
  return path.indexOf('login') < 0 && hasRequiredCookiesFor(cookies, url, campus, studentType);
}

/** 综合页面归类（优先级：MFA > SUCCESS > 门户/中转细类 > UNKNOWN）。 */
export function classifyPage(url: string, cookies: Map<string, string>, campus: EasCampus,
  studentType: string): EasPageKind {
  if (isMfaPage(url)) {
    return EasPageKind.MFA;
  }
  if (isSuccessPageFor(url, cookies, campus, studentType)) {
    return EasPageKind.SUCCESS;
  }
  if (campus === EasCampus.SHENZHEN) {
    if (isShenzhenProxyJwPage(url)) {
      return EasPageKind.SZ_PROXY_JW;
    }
    if (isTrustPortalPage(url)) {
      return EasPageKind.TRUST_PORTAL;
    }
    if (isPortalHomePage(url, campus)) {
      return EasPageKind.PORTAL_HOME;
    }
    return EasPageKind.UNKNOWN;
  }
  if (campus === EasCampus.WEIHAI) {
    if (isPortalHomePage(url, campus)) {
      return EasPageKind.PORTAL_HOME;
    }
    return EasPageKind.UNKNOWN;
  }
  // BENBU
  if (isIvpnRedirectPage(url, campus)) {
    return EasPageKind.IVPN_REDIRECT;
  }
  if (isJwtsPage(url, campus, studentType)) {
    return EasPageKind.JWTS;
  }
  if (isPortalHomePage(url, campus)) {
    return EasPageKind.PORTAL_HOME;
  }
  return EasPageKind.UNKNOWN;
}
