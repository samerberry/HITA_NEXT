import { EasApiClient, EasApiResponse, EasHttpMethod } from '../EasApiClient';
import { EasCampus } from '../EasSession';
import { EasCampusConfig, easWebLoginConfigFor, EasUserAgent } from './EasWebLoginConfig';

const CAMPUS_PROBE_TIMEOUT_MS: number = 2000;

export async function resolveEasLoginRoute(campus: EasCampus, studentType: string): Promise<EasCampusConfig> {
  const fallback: EasCampusConfig = easWebLoginConfigFor(campus, studentType);
  if (campus !== EasCampus.WEIHAI) return fallback;

  const direct: EasCampusConfig = easWebLoginConfigFor(campus, studentType, true);
  const headers: Map<string, string> = new Map<string, string>();
  if (studentType === '2') headers.set('User-Agent', EasUserAgent.SHENZHEN_DESKTOP);
  let timer: number = -1;
  try {
    const timeout = new Promise<EasApiResponse>((resolve) => {
      timer = setTimeout(() => resolve(new EasApiResponse()), CAMPUS_PROBE_TIMEOUT_MS);
    });
    // Probe the official entry point without account cookies or following redirects.
    const response: EasApiResponse = await Promise.race([
      EasApiClient.doHttp(direct.loginUrl, EasHttpMethod.GET, headers, '',
        CAMPUS_PROBE_TIMEOUT_MS, false, false),
      timeout
    ]);
    if (response.statusCode >= 300 && response.statusCode < 400) {
      const location: string = response.location.trim();
      const schoolRedirect: boolean = /^(?:https?:)?\/\/ids\.hit(?:wh)?\.edu\.cn(?::\d+)?\/authserver\//i.test(location);
      const localRedirect: boolean = /^\/(?![\/\\])/.test(location) ||
        location.startsWith(direct.dataBaseUrl + '/');
      if (schoolRedirect || localRedirect) return direct;
    }
    if (response.statusCode === 200 &&
      /\/authserver\/|<title[^>]*>[^<]*(?:统一身份认证|教务|研究生管理)|\/j_spring_security_check|\/xtgl\/login_slogin\.html/i.test(response.body)) {
      return direct;
    }
  } catch (_) {
    // The ordinary WebVPN entry is also used when a network probe cannot complete.
  } finally {
    if (timer >= 0) clearTimeout(timer);
  }
  return fallback;
}
