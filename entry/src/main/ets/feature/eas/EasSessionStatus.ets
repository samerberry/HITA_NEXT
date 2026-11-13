export interface EasSessionResponse {
  statusCode: number;
  body: string;
  /** 未跟随重定向时的 Location 头。 */
  location?: string;
}

export enum EasSessionStatus {
  SAVED = '已登录',
  CHECKING = '验证中',
  CONNECTED = '已连接',
  EXPIRED = '已过期',
  UNKNOWN = '无法验证'
}

/** The Benbu SDP gateway uses a variable-based browser redirect before its VPN login page. */
function isBenbuVerificationRedirect(html: string): boolean {
  const scripts: RegExp = /<script\b[^>]*>([\s\S]*?)<\/script\s*>/gi;
  let scriptMatch: RegExpExecArray | null = scripts.exec(html);
  while (scriptMatch !== null) {
    const script: string = scriptMatch[1].replace(/\/\*[\s\S]*?\*\//g, '')
      .replace(/^\s*\/\/[^\r\n]*/gm, '');
    const targets: RegExp =
      /\b(?:var|let|const)\s+([A-Za-z_$][\w$]*)\s*=\s*["']https:\/\/(?:ivpn|vpn)\.hit\.edu\.cn(?::443)?\/controller\/v1\/public\/verify(?:\?[^"']*)?["']/gi;
    let target: RegExpExecArray | null = targets.exec(script);
    while (target !== null) {
      const variable: string = target[1].replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      const redirect: RegExp = new RegExp('\\blocation\\s*\\.\\s*(?:replace|assign)\\s*\\(\\s*' +
        variable + '\\s*(?=[+),])');
      // A link or an unused URL declaration alone is not an authentication failure.
      if (redirect.test(script)) {
        return true;
      }
      target = targets.exec(script);
    }
    scriptMatch = scripts.exec(html);
  }
  return false;
}

/**
 * 深圳 aTrust 网关会话失效时，把业务请求重定向到自己的登录入口（门户 shortcut 页或
 * 准入校验）。跟随重定向后只剩 POST 到门户页的 405，所以必须在重定向这一跳上识别。
 */
export function isShenzhenGatewayLoginRedirect(response: EasSessionResponse): boolean {
  if (response.statusCode < 300 || response.statusCode >= 400 || response.location === undefined) {
    return false;
  }
  const target: RegExpExecArray | null =
    /^https:\/\/([^\/:?#]+)(?::443)?(\/[^?#]*)?/i.exec(response.location.trim());
  if (target === null || target[1].toLowerCase() !== 'trust.hitsz.edu.cn') {
    return false;
  }
  const path: string = (target[2] ?? '/').toLowerCase();
  return path === '/portal/shortcut.html' || path.startsWith('/controller/v1/public/verify') ||
    path.startsWith('/passport/');
}

/** A saved cookie is not proof of a live session; require an authentication failure from the server. */
export function isExpiredEasResponse(response: EasSessionResponse): boolean {
  return expiredEvidence(response).length > 0;
}

/**
 * A page that already shows the requested EAS content (a term list, a table or a form) is not an
 * authentication failure. The Benbu VPN may inject its loader and verification scripts into every
 * proxied page, so those scripts only count on a near-empty bootstrap page.
 */
function hasBusinessContent(markup: string): boolean {
  if (/<(?:select|table|form|iframe|frameset)\b/i.test(markup)) {
    return true;
  }
  const text: string = markup.replace(/<style\b[^>]*>[\s\S]*?<\/style\s*>/gi, '').replace(/<[^>]*>/g, ' ')
    .replace(/&nbsp;/gi, ' ').replace(/\s+/g, '');
  return text.length > 200;
}

/** Plain-language label for an evidence code, shown with the request path in the account sheet. */
export function describeExpiredEvidence(evidence: string): string {
  const rule: string = evidence.split(':')[0];
  if (rule === 'http-401') return '服务器返回 401';
  if (rule === 'gateway-redirect') return '跳转到 VPN 登录';
  if (rule === 'json-code' || rule === 'json-message') return '接口提示未登录';
  if (rule === 'vpn-verify-redirect') return 'VPN 要求重新验证';
  if (rule === 'vpn-shortcut-bootstrap') return 'VPN 返回登录引导页';
  if (rule === 'login-form') return '返回了登录表单';
  if (rule === 'login-redirect') return '页面跳转到登录页';
  if (rule === 'expired-message') return '页面提示登录失效';
  return rule.length > 0 ? rule : '登录失效';
}

/** Up to 100 characters of the matched text for logs, without query strings that may carry tickets. */
function evidenceSnippet(match: RegExpExecArray | null): string {
  if (match === null) return '';
  return match[0].replace(/\?[^"'\s<>]*/g, '?…').replace(/\s+/g, ' ').substring(0, 100);
}

/**
 * Names the authentication-failure evidence in a response, or returns '' when there is none.
 * Logged when a session is marked expired, so a misjudged page can be traced to its rule.
 */
export function expiredEvidence(response: EasSessionResponse): string {
  if (response.statusCode === 401) {
    return 'http-401';
  }
  if (isShenzhenGatewayLoginRedirect(response)) {
    return 'gateway-redirect';
  }
  if (response.statusCode === 0 || response.statusCode >= 500) {
    return '';
  }
  const expiredMessage: RegExp =
    /未登[录陆]|请(?:先|重新)登[录陆]|(?:登[录陆]|会话|身份认证)(?:状态)?(?:已)?(?:失效|过期|超时)|(?:session|token)\s+(?:has\s+)?(?:expired|invalid)|not\s+(?:logged|signed)\s+in/i;
  const body: string = response.body.trim();
  if (body.startsWith('{')) {
    try {
      const record: Record<string, Object> = JSON.parse(body) as Record<string, Object>;
      const code: string = String(record['code'] ?? record['status'] ?? record['statusCode'] ?? '');
      const message: string = String(record['msg'] ?? record['message'] ?? record['error'] ?? '');
      if (code === '401' || /^(?:UNAUTHORIZED|LOGIN_EXPIRED|NOT_LOGIN)$/i.test(code)) {
        return 'json-code: ' + code;
      }
      return expiredMessage.test(message) ? 'json-message: ' + evidenceSnippet(expiredMessage.exec(message)) : '';
    } catch (_) {
      return '';
    }
  }
  const html: string = body.replace(/<!--[\s\S]*?-->/g, '');
  const markup: string = html.replace(/<script\b[^>]*>[\s\S]*?<\/script\s*>/gi, '');
  const content: boolean = hasBusinessContent(markup);
  if (!content && isBenbuVerificationRedirect(html)) {
    return 'vpn-verify-redirect';
  }
  // Benbu's VPN returns this HTTP 200 bootstrap instead of the requested EAS page
  // when its authentication is unavailable. A generic loading page is not evidence.
  if (!content && /<script\b[^>]*\bsrc\s*=\s*["'][^"']*\/old\/jssdk\/shortcut_api\.js(?:[?"'])/i.test(html) &&
    /<script\b[^>]*\bsrc\s*=\s*["'][^"']*\/old\/shortcut_main\.js(?:[?"'])/i.test(html)) {
    return 'vpn-shortcut-bootstrap';
  }
  const passwordInput: RegExp = /<input\b[^>]*(?:type\s*=\s*["']?password\b|name\s*=\s*["']?(?:password|mm)\b)/i;
  const loginForm: RegExp = /<form\b[^>]*action\s*=\s*["'][^"']*(?:login|authentication\/require)/i;
  if (passwordInput.test(markup) || loginForm.test(markup)) {
    return 'login-form: ' + evidenceSnippet(passwordInput.exec(markup) ?? loginForm.exec(markup));
  }
  // Match a redirect, not an ordinary navigation link back to the login page.
  const assignment: RegExp = /(?:window|top|parent)?\.?location(?:\.href)?\s*=\s*["'][^"']*(?:login|authentication\/require|reauth)/i;
  const call: RegExp = /location\.(?:replace|assign)\(\s*["'][^"']*(?:login|authentication\/require|reauth)/i;
  const refresh: RegExp = /<meta\b[^>]*content\s*=\s*["'][^"']*url\s*=[^"']*(?:login|authentication\/require|reauth)/i;
  if (!content && (assignment.test(html) || call.test(html) || refresh.test(markup))) {
    return 'login-redirect: ' + evidenceSnippet(assignment.exec(html) ?? call.exec(html) ?? refresh.exec(markup));
  }
  const text: string = markup.replace(/<[^>]*>/g, ' ');
  return expiredMessage.test(text) ? 'expired-message: ' + evidenceSnippet(expiredMessage.exec(text)) : '';
}
