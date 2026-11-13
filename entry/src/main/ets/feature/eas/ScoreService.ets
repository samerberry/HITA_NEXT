import { EasCampus, EasSession } from './EasSession';
import { EasApiClient, EasApiClientOptions, EasApiResponse, EasHttpMethod } from './EasApiClient';
import { EasCourseScoreItem, EasTermItem } from './model/EasModels';
import { EasCampusUrls, easWebLoginConfigFor } from './webLogin/EasWebLoginConfig';
import { isExpiredEasResponse } from './EasSessionStatus';
import { parseShenzhenWebScores } from './data/ShenzhenWebScores';
import { ScoreTestType, OfficialScoreSummary, legacyScoreRequest, parseLegacyScores,
  parseOfficialLegacySummary, parseOfficialShenzhenSummary } from './data/ScoreData';

export class ScoreQueryResult {
  items: EasCourseScoreItem[] = [];
  summary: OfficialScoreSummary = new OfficialScoreSummary();
  summaryMessage: string = '';
}

interface ShenzhenScoreBody {
  xn: string;
  xq: string;
  kcmc: string | null;
  pylx: string;
  current: number;
  pageSize: number;
  cxbj?: string;
  xscjlb?: string | null;
  sffx?: string | null;
}

export class ScoreService {
  private api: EasApiClient = new EasApiClient();

  async query(session: EasSession, term: EasTermItem, type: ScoreTestType): Promise<ScoreQueryResult> {
    if (session.campus !== EasCampus.SHENZHEN && session.getStudentType() === '2') {
      throw new Error('该校区研究生成绩接口暂未接入，请到教务网站查询');
    }
    const result = new ScoreQueryResult();
    if (session.campus === EasCampus.SHENZHEN) {
      const midterm = type === ScoreTestType.MIDTERM;
      const body: ShenzhenScoreBody = {
        xn: term.yearCode, xq: term.termCode, kcmc: midterm ? '' : null,
        pylx: session.getStudentType(), current: 1, pageSize: 1000
      };
      if (!midterm) { body.cxbj = '-1'; body.xscjlb = null; body.sffx = null; }
      const response = await this.request(session, midterm ? '/cjgl/grcjcx/qzcjcx' : '/cjgl/grcjcx/grcjcx', JSON.stringify(body));
      const parsed = parseShenzhenWebScores(response.body, term);
      if (parsed === undefined || (parsed.code !== 0 && parsed.code !== 200)) throw new Error('成绩响应解析失败，请稍后重试');
      // An arbitrary successful JSON object must not become an empty transcript.
      const root = JSON.parse(response.body) as Record<string, Object>;
      const content = root['content'] as Record<string, Object>;
      if (!content || !Array.isArray(content['list'])) throw new Error('教务未返回有效成绩列表，请稍后重试');
      result.items = parsed.list;
    } else {
      const spec = legacyScoreRequest(session.campus, term, type);
      const pairs: string[] = [];
      spec.fields.forEach((value: string, key: string) => pairs.push(encodeURIComponent(key) + '=' + encodeURIComponent(value)));
      const response = await this.request(session, spec.path, pairs.join('&'));
      const items = parseLegacyScores(response.body, term);
      if (items === undefined) throw new Error('未识别到成绩表，请确认教务登录状态后重试');
      result.items = items;
    }
    try {
      if (session.campus === EasCampus.SHENZHEN) {
        const response = await this.request(session, '/cjgl/grcjcx/getgpa', JSON.stringify({
          xn: term.yearCode, xq: term.termCode, pylx: session.getStudentType()
        }));
        result.summary = parseOfficialShenzhenSummary(response.body);
      } else {
        const response = await this.request(session, '/xfj/queryListXfj');
        result.summary = parseOfficialLegacySummary(response.body);
      }
      if (!result.summary.available()) result.summaryMessage = '教务未提供官方统计';
    } catch (_) {
      result.summaryMessage = '成绩已获取，官方统计暂不可用，可稍后刷新重试';
    }
    return result;
  }

  private async request(session: EasSession, path: string, body?: string): Promise<EasApiResponse> {
    const options = new EasApiClientOptions();
    options.method = body === undefined ? EasHttpMethod.GET : EasHttpMethod.POST;
    options.body = body ?? '';
    options.useCache = false;
    options.timeoutMs = 20000;
    const shenzhen = session.campus === EasCampus.SHENZHEN;
    options.extraHeaders.set('Content-Type', shenzhen ? 'application/json;charset=UTF-8' : 'application/x-www-form-urlencoded;charset=UTF-8');
    options.extraHeaders.set('Accept', shenzhen ? 'application/json' : 'text/html');
    if (shenzhen) {
      options.extraHeaders.set('RoleCode', '01');
      options.extraHeaders.set('X-Requested-With', 'XMLHttpRequest');
      options.extraHeaders.set('Referer', EasApiClient.joinUrl(session.webBaseUrl, '/cjgl/grcjcx'));
    } else if (session.campus === EasCampus.WEIHAI) {
      options.extraHeaders.set('Origin', EasCampusUrls.WEIHAI_BASE);
      options.extraHeaders.set('Referer', EasApiClient.joinUrl(EasCampusUrls.WEIHAI_EAS_PREFIX, path));
    }
    const response = await this.api.request(session, easWebLoginConfigFor(session.campus, session.getStudentType()), path, options);
    if (isExpiredEasResponse(response)) throw new Error('教务会话已过期，请在“更多”的教务账号中重新登录');
    if (response.statusCode < 200 || response.statusCode >= 300) throw new Error('成绩查询失败，请检查网络或稍后重试');
    return response;
  }
}
