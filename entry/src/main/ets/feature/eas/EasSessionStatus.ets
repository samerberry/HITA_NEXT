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
      /\b(?:var|let|const)\s+([A-Za-z_$][\w$]*)\s*=\s*["']https:\/\/ivpn\.hit\.edu\.cn(?::443)?\/controller\/v1\/public\/verify(?:\?[^"']*)?["']/gi;
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
  if (response.statusCode === 401 || isShenzhenGatewayLoginRedirect(response)) {
    return true;
  }
  if (response.statusCode === 0 || response.statusCode >= 500) {
    return false;
  }
  const expiredMessage: RegExp =
    /未登[录陆]|请(?:先|重新)登[录陆]|(?:登[录陆]|会话|身份认证)(?:状态)?(?:已)?(?:失效|过期|超时)|(?:session|token)\s+(?:has\s+)?(?:expired|invalid)|not\s+(?:logged|signed)\s+in/i;
  const body: string = response.body.trim();
  if (body.startsWith('{')) {
    try {
      const record: Record<string, Object> = JSON.parse(body) as Record<string, Object>;
      const code: string = String(record['code'] ?? record['status'] ?? record['statusCode'] ?? '');
      const message: string = String(record['msg'] ?? record['message'] ?? record['error'] ?? '');
      return code === '401' || /^(?:UNAUTHORIZED|LOGIN_EXPIRED|NOT_LOGIN)$/i.test(code) ||
        expiredMessage.test(message);
    } catch (_) {
      return false;
    }
  }
  const html: string = body.replace(/<!--[\s\S]*?-->/g, '');
  if (isBenbuVerificationRedirect(html)) {
    return true;
  }
  // Benbu's VPN returns this HTTP 200 bootstrap instead of the requested EAS page
  // when its authentication is unavailable. A generic loading page is not evidence.
  if (/<script\b[^>]*\bsrc\s*=\s*["'][^"']*\/old\/jssdk\/shortcut_api\.js(?:[?"'])/i.test(html) &&
    /<script\b[^>]*\bsrc\s*=\s*["'][^"']*\/old\/shortcut_main\.js(?:[?"'])/i.test(html)) {
    return true;
  }
  const markup: string = html.replace(/<script\b[^>]*>[\s\S]*?<\/script\s*>/gi, '');
  if (/<input\b[^>]*(?:type\s*=\s*["']?password\b|name\s*=\s*["']?(?:password|mm)\b)/i.test(markup) ||
    /<form\b[^>]*action\s*=\s*["'][^"']*(?:login|authentication\/require)/i.test(markup)) {
    return true;
  }
  // Match a redirect, not an ordinary navigation link back to the login page.
  if (/(?:window|top|parent)?\.?location(?:\.href)?\s*=\s*["'][^"']*(?:login|authentication\/require|reauth)/i.test(html) ||
    /location\.(?:replace|assign)\(\s*["'][^"']*(?:login|authentication\/require|reauth)/i.test(html) ||
    /<meta\b[^>]*content\s*=\s*["'][^"']*url\s*=[^"']*(?:login|authentication\/require|reauth)/i.test(markup)) {
    return true;
  }
  return expiredMessage.test(markup.replace(/<[^>]*>/g, ' '));
}
