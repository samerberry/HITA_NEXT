/**
 * EasApiClient.ets — 教务数据 HTTP 客户端：Cookie 注入与会话失效判定。
 *
 * 校区数据端点形态：
 *  - 深圳：JSON（ParsedShenzhenWebScores: code/msg/content.list[] …）
 *  - 威海：webvpn 编码前缀下的端点（kjscx/queryJxlListBySjid、cjcx/queryQmcj …），带 JSESSIONID
 *  - 本部：ivpn 内网域名 + CAS 会话（HIT / JSESSIONID）
 * 请求路径由 EasDataProvider 配置。
 */
import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { EasCampusConfig, EasCampusUrls, EasUserAgent } from './webLogin/EasWebLoginConfig';
import { EasCampus, EasSession } from './EasSession';
import { EasSessionStore } from './EasSessionStore';
import { EasSessionResponse, isExpiredEasResponse, isShenzhenGatewayLoginRedirect } from './EasSessionStatus';

const TAG: string = 'HitaEasApi';
const DOMAIN: number = 0x0000;

export enum EasHttpMethod {
  GET = 'GET',
  POST = 'POST'
}

export class EasApiResponse implements EasSessionResponse {
  statusCode: number = 0;
  body: string = '';
  cookies: string = '';
  location: string = '';
}

export class EasApiClientOptions {
  method: EasHttpMethod = EasHttpMethod.GET;
  /** POST body（JSON 字符串或表单串）。 */
  body: string = '';
  /** 追加请求头。 */
  extraHeaders: Map<string, string> = new Map<string, string>();
  /** 超时 ms。 */
  timeoutMs: number = 20000;
  /** Session probes must reach the server rather than reuse a cached business page. */
  useCache: boolean = true;
  /** 是否跟随重定向（http 模块默认跟随，保留开关以便抓包期关闭）。 */
  followRedirects: boolean = true;
}

/**
 * 失效重登回调：返回 true 表示已把新一代会话凭据写回传入的 session（调用方重试一次），
 * false 表示放弃，由调用方标记过期。对应 sessionGeneration +1 的重登协议。
 */
export type EasReloginHandler = (session: EasSession, reason: string) => Promise<boolean>;

export class EasApiClient {
  /** 应用启动后由静默续期服务注册；未注册时认证失效直接标记过期。 */
  private static defaultReloginHandler: EasReloginHandler | undefined = undefined;
  private reloginHandler: EasReloginHandler | undefined = undefined;

  static setDefaultReloginHandler(handler: EasReloginHandler | undefined): void {
    EasApiClient.defaultReloginHandler = handler;
  }

  setReloginHandler(handler: EasReloginHandler): void {
    this.reloginHandler = handler;
  }

  /**
   * 发起数据请求：合并校区 Cookie 到请求头，遇到明确的认证失效响应
   * 先尝试重登并重试一次，仍失效才标记过期。
   */
  async request(session: EasSession, cfg: EasCampusConfig, path: string,
    options: EasApiClientOptions): Promise<EasApiResponse> {
    const attempts: number = 2;
    for (let i = 0; i < attempts; i++) {
      // 重登可能换到深圳另一数据基址，每次尝试都按当前会话取地址。
      const url: string = EasApiClient.joinUrl(this.dataBaseUrl(session, cfg), path);
      const header: Map<string, string> = new Map<string, string>();
      options.extraHeaders.forEach((value: string, key: string) => {
        header.set(key, value);
      });
      const cookieHeader: string = EasSession.buildCookieHeader(session.webCookies);
      if (cookieHeader.length > 0) {
        header.set('Cookie', cookieHeader);
      }
      if (!header.has('User-Agent')) {
        header.set('User-Agent', this.userAgentFor(session, cfg));
      }
      // Keep the endpoint-specific Accept header.  Weihai returns HTML pages
      // for terms and the timetable; overriding it with JSON makes WebVPN
      // occasionally return the login shell instead of the business page.
      if (!header.has('Accept')) {
        header.set('Accept', 'application/json, text/plain, */*');
      }
      if (options.body.length > 0) {
        if (!header.has('Content-Type')) {
          header.set('Content-Type', 'application/x-www-form-urlencoded; charset=UTF-8');
        }
      }
      // 重登后的重试不能读缓存，否则可能拿回刚才那张失效页，把新会话又标成过期。
      const useCache: boolean = options.useCache && i === 0;
      // 深圳 aTrust 网关失效时的重定向只能在第一跳识别；其他重定向照常跟随。
      const gatewayChecked: boolean = session.campus === EasCampus.SHENZHEN;
      let resp: EasApiResponse = await EasApiClient.doHttp(url, options.method, header, options.body,
        options.timeoutMs, useCache, options.followRedirects && !gatewayChecked);
      if (gatewayChecked && resp.statusCode >= 300 && resp.statusCode < 400) {
        const gatewayLogin: boolean = isShenzhenGatewayLoginRedirect(resp);
        hilog.info(DOMAIN, TAG, 'Shenzhen redirect status=%{public}d gatewayLogin=%{public}s target=%{public}s',
          resp.statusCode, String(gatewayLogin), EasApiClient.redirectTarget(resp.location));
        if (!gatewayLogin && options.followRedirects) {
          resp = await EasApiClient.doHttp(url, options.method, header, options.body,
            options.timeoutMs, useCache, true);
        }
      }
      if (isExpiredEasResponse(resp)) {
        const relogin: EasReloginHandler | undefined = this.reloginHandler ?? EasApiClient.defaultReloginHandler;
        if (relogin !== undefined && i + 1 < attempts && await relogin(session, 'session invalid on ' + path)) {
          continue; // 重登成功后用新凭据重试一次
        }
        await EasSessionStore.getInstance().markExpired(session);
      }
      return resp;
    }
    return new EasApiResponse(); // 理论不可达
  }

  /** 数据基址：深圳用 webBaseUrl；威海用 webvpn 前缀；本部按培养层次选 jwts/yjsgl 域。 */
  private dataBaseUrl(session: EasSession, cfg: EasCampusConfig): string {
    if (session.campus.toString() === 'SHENZHEN' && session.webBaseUrl.length > 0) {
      return session.webBaseUrl;
    }
    if (session.campus.toString() === 'WEIHAI') {
      return EasCampusUrls.WEIHAI_EAS_PREFIX;
    }
    if (session.getStudentType() === '2') {
      return EasCampusUrls.GRADUATE_BASE;
    }
    return EasCampusUrls.JWTS_BASE;
  }

  private userAgentFor(session: EasSession, cfg: EasCampusConfig): string {
    // Android EASWebSource 对新版深圳 Web 接口固定使用桌面 UA；旧校区
    // 沿用移动 UA 以兼容旧教务页面。
    if (session.campus.toString() === 'SHENZHEN') {
      return EasUserAgent.SHENZHEN_DESKTOP;
    }
    return EasUserAgentFallback.value;
  }

  /** 只记录重定向目标的主机和路径，不记录可能带票据的查询串。 */
  private static redirectTarget(location: string): string {
    const end: number = location.search(/[?#]/);
    return end >= 0 ? location.substring(0, end) : location;
  }

  static joinUrl(base: string, path: string): string {
    if (path.length === 0) {
      return base;
    }
    if (path.indexOf('http://') === 0 || path.indexOf('https://') === 0) {
      return path;
    }
    return base.replace(/\/+$/, '') + '/' + path.replace(/^\/+/, '');
  }

  static async doHttp(url: string, method: EasHttpMethod, header: Map<string, string>, body: string,
    timeoutMs: number, useCache: boolean = true, followRedirects: boolean = true): Promise<EasApiResponse> {
    const httpRequest: http.HttpRequest = http.createHttp();
    const opts: http.HttpRequestOptions = {
      method: method === EasHttpMethod.POST ? http.RequestMethod.POST : http.RequestMethod.GET,
      header: EasApiClient.headerToObject(header),
      connectTimeout: timeoutMs,
      readTimeout: timeoutMs,
      usingCache: useCache,
      expectDataType: http.HttpDataType.STRING
    };
    if (body.length > 0) {
      opts.extraData = body;
    }
    if (!followRedirects) opts.maxRedirects = 0;
    try {
      const resp: http.HttpResponse = await httpRequest.request(url, opts);
      const out: EasApiResponse = new EasApiResponse();
      out.statusCode = resp.responseCode;
      out.body = resp.result === undefined ? '' : String(resp.result);
      out.cookies = resp.cookies || EasApiClient.responseHeader(resp.header, 'set-cookie');
      out.location = EasApiClient.responseHeader(resp.header, 'location');
      return out;
    } catch (e) {
      const out: EasApiResponse = new EasApiResponse();
      out.statusCode = 0;
      out.body = '';
      return out;
    } finally {
      httpRequest.destroy();
    }
  }

  private static responseHeader(header: Object, name: string): string {
    if (header === undefined || header === null) return '';
    const fields: Record<string, string | string[]> = header as Record<string, string | string[]>;
    for (const key of Object.keys(fields)) {
      if (key.toLowerCase() !== name) continue;
      const value: string | string[] = fields[key];
      return Array.isArray(value) ? (value as string[]).join('\n') : String(value);
    }
    return '';
  }

  private static headerToObject(header: Map<string, string>): Object {
    const o: Record<string, string> = {};
    header.forEach((value: string, key: string) => {
      o[key] = value;
    });
    return o;
  }
}

/** UA 回退常量（避免与 config 循环依赖的临时归属，后续并入 EasWebLoginConfig）。 */
export class EasUserAgentFallback {
  static readonly value: string =
    // Android's legacy Weihai/Benbu source deliberately uses a desktop UA;
    // the old EAS renders a different mobile shell that the HTML parser cannot
    // use for terms and timetable pages.
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15';
}
