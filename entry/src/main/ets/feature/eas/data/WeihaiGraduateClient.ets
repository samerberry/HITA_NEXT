import { EasApiClient, EasApiClientOptions, EasApiResponse, EasHttpMethod } from '../EasApiClient';
import { EasSession } from '../EasSession';
import { isExpiredEasResponse } from '../EasSessionStatus';
import { easWebLoginConfigFor, EasUserAgent } from '../webLogin/EasWebLoginConfig';

export class WeihaiGraduateClient {
  private readonly api: EasApiClient;

  constructor(api: EasApiClient) {
    this.api = api;
  }

  async request(session: EasSession, path: string, body: string = '',
    referer: string = '/authentication/main', method: EasHttpMethod = EasHttpMethod.POST,
    json: boolean = false): Promise<string> {
    const options: EasApiClientOptions = new EasApiClientOptions();
    options.method = method;
    options.body = body;
    options.useCache = false;
    options.followRedirects = false;
    options.weihaiRefererPath = referer;
    options.extraHeaders.set('RoleCode', '02');
    options.extraHeaders.set('User-Agent', EasUserAgent.SHENZHEN_DESKTOP);
    options.extraHeaders.set('X-Requested-With', 'XMLHttpRequest');
    if (method === EasHttpMethod.POST) {
      options.extraHeaders.set('Content-Type', json ? 'application/json; charset=UTF-8' :
        'application/x-www-form-urlencoded; charset=UTF-8');
    }
    const response: EasApiResponse = await this.api.request(session,
      easWebLoginConfigFor(session.campus, session.getStudentType()), path, options);
    if (isExpiredEasResponse(response)) throw new Error('威海研究生教务会话已失效，请重新登录');
    if (response.statusCode === 0) throw new Error('无法连接威海研究生教务，请检查网络后重试');
    if (response.statusCode < 200 || response.statusCode >= 300) throw new Error('威海研究生教务暂时无法提供查询');
    return response.body;
  }

  static form(fields: Map<string, string>): string {
    const pairs: string[] = [];
    fields.forEach((value: string, key: string) => pairs.push(encodeURIComponent(key) + '=' + encodeURIComponent(value)));
    return pairs.join('&');
  }
}
