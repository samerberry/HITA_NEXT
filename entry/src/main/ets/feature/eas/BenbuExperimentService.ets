import { EasApiClient, EasApiResponse, EasHttpMethod, EasUserAgentFallback } from './EasApiClient';
import { EasSession } from './EasSession';
import { EasCampusUrls } from './webLogin/EasWebLoginConfig';
import { EasCourseItem } from './model/EasModels';
import { BenbuExperimentParser } from './data/BenbuExperimentParser';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { url } from '@kit.ArkTS';

/** Auxiliary sessions belong to their own hosts, never overwrite the EAS JSESSIONID. */
export class BenbuExperimentService {
  static readonly EXPERIMENT_BASE: string = 'http://sjjx-hit-edu-cn.ivpn.hit.edu.cn:1080';

  static mergeCookies(target: Map<string, string>, raw: string): void {
    const parts: string[] = raw.split(/[;\r\n]|,(?=\s*[^\s;,=]+=)/);
    for (const part of parts) {
      const equal: number = part.indexOf('=');
      if (equal < 1) continue;
      const key: string = part.substring(0, equal).trim();
      if (/^(path|domain|expires|max-age|samesite|secure|httponly)$/i.test(key)) continue;
      target.set(key, part.substring(equal + 1).trim());
    }
  }

  private static headers(cookies: Map<string, string>): Map<string, string> {
    const headers: Map<string, string> = new Map<string, string>();
    headers.set('Cookie', EasSession.buildCookieHeader(cookies));
    headers.set('User-Agent', EasUserAgentFallback.value + ' (KHTML, like Gecko) Version/26.3.1 Safari/605.1.15');
    headers.set('Accept', 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');
    headers.set('Accept-Language', 'zh-CN,zh-Hans;q=0.9');
    headers.set('Upgrade-Insecure-Requests', '1');
    return headers;
  }

  /** Follow each SSO hop explicitly: API 23 does not provide a shared HTTP cookie jar. */
  private static async getWithCookies(target: string, session: EasSession,
    jars: Map<string, Map<string, string>>, timeoutMs: number): Promise<EasApiResponse> {
    const deadline: number = Date.now() + timeoutMs;
    for (let hop: number = 0; hop < 6; hop++) {
      const endpoint: url.URL = new url.URL(target);
      if ((endpoint.protocol !== 'http:' && endpoint.protocol !== 'https:') ||
        endpoint.username.length > 0 || endpoint.password.length > 0 ||
        !(endpoint.origin === EasCampusUrls.JWTS_BASE ||
        endpoint.hostname === 'ivpn.hit.edu.cn' || endpoint.hostname.endsWith('.ivpn.hit.edu.cn'))) {
        break;
      }
      let cookies: Map<string, string> | undefined = jars.get(endpoint.origin);
      if (cookies === undefined) {
        cookies = new Map<string, string>(session.webCookies);
        if (endpoint.origin !== EasCampusUrls.JWTS_BASE) cookies.delete('JSESSIONID');
        jars.set(endpoint.origin, cookies);
      }
      const remaining: number = deadline - Date.now();
      if (remaining <= 0) break;
      const response: EasApiResponse = await EasApiClient.doHttp(endpoint.toString(), EasHttpMethod.GET,
        BenbuExperimentService.headers(cookies), '', remaining, false, false);
      BenbuExperimentService.mergeCookies(cookies, response.cookies || '');
      if (![301, 302, 303, 307, 308].includes(response.statusCode)) return response;
      if (!response.location) break;
      target = new url.URL(response.location, endpoint).toString();
    }
    return new EasApiResponse();
  }

  static async getExperiments(session: EasSession, warnings: string[] = []): Promise<EasCourseItem[]> {
    // 优先使用登录阶段经 jwts 桥接捕获的 sjjx 会话：iVPN 网关已对该目标完成授权。
    if (EasSession.isNotBlank(EasSession.cookieValue(session.sjjxCookies, 'JSESSIONID'))) {
      try {
        const sjjxResponse: EasApiResponse = await EasApiClient.doHttp(
          BenbuExperimentService.EXPERIMENT_BASE + '/xskb/queryXszkb',
          EasHttpMethod.GET, BenbuExperimentService.headers(session.sjjxCookies), '', 20000, false);
        const bodyOk: boolean = sjjxResponse.statusCode === 200 &&
          /\bdataTable\b/i.test(sjjxResponse.body) && !/页面过期|请重新登录/.test(sjjxResponse.body);
        hilog.info(0x0000, 'HitaEasImport', 'experiment session query status=%{public}d len=%{public}d',
          sjjxResponse.statusCode, sjjxResponse.body.length);
        if (bodyOk) {
          const parsed: EasCourseItem[] = BenbuExperimentParser.parseHtml(sjjxResponse.body);
          if (parsed.length > 0) {
            hilog.info(0x0000, 'HitaEasImport', 'experiment session courses=%{public}d', parsed.length);
            return parsed;
          }
        }
      } catch (_) {
        hilog.warn(0x0000, 'HitaEasImport', 'experiment session request failed');
      }
    }
    const jars: Map<string, Map<string, string>> = new Map<string, Map<string, string>>();
    try {
      await BenbuExperimentService.getWithCookies(EasCampusUrls.JWTS_BASE + '/loginsysj/loginSygl',
        session, jars, 10000);
    } catch (_) {
      // Android still queries the schedule if the optional bridge fails.
      hilog.warn(0x0000, 'HitaEasImport', 'experiment SSO bridge failed; trying schedule');
    }
    try {
      const response: EasApiResponse = await BenbuExperimentService.getWithCookies(
        BenbuExperimentService.EXPERIMENT_BASE + '/xskb/queryXszkb', session, jars, 20000);
      // Android queries this endpoint without xnxq; it serves the experimental system's schedule.
      if (response.statusCode === 200 && /\bdataTable\b/i.test(response.body) &&
        !/页面过期|请重新登录/.test(response.body)) {
        const courses: EasCourseItem[] = BenbuExperimentParser.parseHtml(response.body);
        hilog.info(0x0000, 'HitaEasImport', 'experiment schedule status=%{public}d courses=%{public}d',
          response.statusCode, courses.length);
        return courses;
      }
      hilog.warn(0x0000, 'HitaEasImport', 'experiment schedule unavailable status=%{public}d', response.statusCode);
    } catch (_) {
      hilog.warn(0x0000, 'HitaEasImport', 'experiment request failed');
    }
    warnings.push('实验教学课表暂未读取成功，请稍后重新导入');
    return [];
  }

  static async getElectronicExperiments(session: EasSession, warnings: string[] = []): Promise<EasCourseItem[]> {
    if (!session.electronicExpToken.trim()) {
      hilog.warn(0x0000, 'HitaEasImport', 'electronic experiment token unavailable');
      warnings.push('未取得电子实验会话，相关实验课可能缺失，请重新登录教务后导入');
      return [];
    }
    try {
      const base: string = EasCampusUrls.EELABINFO_URL;
      const headers: Map<string, string> = BenbuExperimentService.headers(session.webCookies);
      headers.set('Accept', '*/*');
      headers.set('Content-Type', 'application/x-www-form-urlencoded');
      headers.set('Origin', base);
      headers.set('Referer', base + '/stu_ckkb.html');
      headers.set('X-Requested-With', 'XMLHttpRequest');
      headers.set('VcTchType', 'stu');
      headers.set('VcTchToken', session.electronicExpToken);
      const response: EasApiResponse = await EasApiClient.doHttp(base + '/api/stu/viewCKKB?sf_request_type=ajax',
        EasHttpMethod.POST, headers, '', 5000, false);
      const valid: boolean = response.statusCode === 200 &&
        BenbuExperimentParser.isElectronicResponse(response.body);
      const courses: EasCourseItem[] = valid ? BenbuExperimentParser.parseElectronic(response.body) : [];
      hilog.info(0x0000, 'HitaEasImport', 'electronic experiment status=%{public}d valid=%{public}s courses=%{public}d',
        response.statusCode, valid.toString(), courses.length);
      if (valid) return courses;
    } catch (_) {
      hilog.warn(0x0000, 'HitaEasImport', 'electronic experiment request failed');
    }
    warnings.push('电子实验课表暂未读取成功，请重新登录教务后导入');
    return [];
  }
}
