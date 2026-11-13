import { EasApiClient, EasApiClientOptions, EasApiResponse, EasHttpMethod } from '../eas/EasApiClient';
import { EasCampus, EasSession } from '../eas/EasSession';
import { isExpiredEasResponse } from '../eas/EasSessionStatus';
import { easWebLoginConfigFor } from '../eas/webLogin/EasWebLoginConfig';
import { EasTermItem } from '../eas/model/EasModels';
import { EasUserMessages } from '../eas/EasUserMessages';
import { CreditContext, CreditGroup, CreditGroupCourse, CreditCourseRecord, OfficialCreditProgress } from './CreditModels';
import { ShenzhenCreditParser as Parser } from './ShenzhenCreditParser';

const ROOT: string = '/cjgl/cjzhtjcx/cjcx/';
const REFERER: string = '/cjgl/grcjcx/cjxqList';
const EXPIRED: string = '教务会话已失效，请重新登录';
const CANCELLED: string = '学分查询已取消';
const MAX_PAGES: number = 50;
type RequestFields = Record<string, string | number | null>;

export function creditErrorMessage(message: string): string {
  const known: string[] = ['请先在“更多 → 教务账号”登录深圳教务', '教务系统未返回学号或入学年级',
    '教务系统未返回学籍标识', '当前成绩学期读取失败', '个人培养方案读取失败',
    '培养方案完成度读取失败，请稍后重试', '培养方案完成度解析失败，请稍后重试',
    '课组课程读取失败，请重试', '学分目标读取失败', '本地学分读取失败，请重试'];
  return known.includes(message) ? message : EasUserMessages.fromError(message, '学分查询失败，请检查网络后重试');
}

export class CreditService {
  private api: EasApiClient;

  constructor(api: EasApiClient = new EasApiClient()) { this.api = api; }

  private ensureActive(active: () => boolean): void {
    if (!active()) throw new Error(CANCELLED);
  }

  private async request(session: EasSession, path: string, fields: RequestFields, json: boolean,
    active: () => boolean, referer: string = REFERER): Promise<EasApiResponse> {
    this.ensureActive(active);
    if (session.loginExpired) throw new Error(EXPIRED);
    const options = new EasApiClientOptions();
    options.method = EasHttpMethod.POST;
    options.useCache = false;
    options.body = json ? JSON.stringify(fields) : Object.keys(fields).map((key: string) =>
      encodeURIComponent(key) + '=' + encodeURIComponent(String(fields[key] ?? ''))).join('&');
    options.extraHeaders.set('Content-Type', json ? 'application/json;charset=UTF-8' :
      'application/x-www-form-urlencoded; charset=UTF-8');
    options.extraHeaders.set('Accept', '*/*');
    options.extraHeaders.set('Accept-Language', 'zh-CN,zh;q=0.9');
    options.extraHeaders.set('Cache-Control', 'no-cache');
    options.extraHeaders.set('RoleCode', '01');
    options.extraHeaders.set('X-Requested-With', 'XMLHttpRequest');
    options.extraHeaders.set('Origin', session.webBaseUrl.replace(/\/+$/, ''));
    options.extraHeaders.set('Referer', EasApiClient.joinUrl(session.webBaseUrl, referer));
    const response = await this.api.request(session, easWebLoginConfigFor(session.campus, session.getStudentType()), path, options);
    this.ensureActive(active);
    // Authentication failures must propagate even when an optional detail fails.
    if (isExpiredEasResponse(response)) throw new Error(EXPIRED);
    return response;
  }

  private async optional(session: EasSession, path: string, fields: RequestFields, json: boolean,
    active: () => boolean): Promise<EasApiResponse | undefined> {
    try {
      const response = await this.request(session, path, fields, json, active);
      return response.statusCode >= 200 && response.statusCode < 300 ? response : undefined;
    } catch (error) {
      if (error instanceof Error && (error.message === EXPIRED || error.message === CANCELLED)) throw error;
      return undefined;
    }
  }

  async query(session: EasSession, term: EasTermItem | undefined,
    onProgress: (progress: OfficialCreditProgress) => void = () => {},
    active: () => boolean = () => true): Promise<OfficialCreditProgress> {
    this.ensureActive(active);
    if (session.campus !== EasCampus.SHENZHEN || !session.hasShenzhenWebSession()) {
      throw new Error('请先在“更多 → 教务账号”登录深圳教务');
    }
    const identityResponse = await this.request(session, '/UserManager/queryxsxx', {}, false, active, '/authentication/main');
    const identity = Parser.identity(identityResponse.statusCode === 200 ? identityResponse.body : '');
    const context = new CreditContext();
    context.studentNumber = identity.studentNumber || session.stuId || session.username;
    context.studentType = identity.studentType || session.getStudentType();
    context.grade = identity.grade || /(?:19|20)\d{2}/.exec(session.grade)?.[0] || '';
    context.recordId = identity.recordId;
    if (!context.studentNumber || !context.grade) throw new Error('教务系统未返回学号或入学年级');
    if (!context.recordId) {
      const lookup = await this.request(session, ROOT + 'getXs', { 'xjidorxh': context.studentNumber }, true, active);
      context.recordId = lookup.statusCode === 200 ? Parser.recordId(lookup.body) : '';
    }
    if (!context.recordId) throw new Error('教务系统未返回学籍标识');

    const termResponse = await this.request(session, ROOT + 'queryqxnxq?sf_request_type=ajax', {}, false, active);
    const currentTerm = term?.getCode() || (termResponse.statusCode === 200 ? Parser.currentTerm(termResponse.body) : '');
    if (!currentTerm) throw new Error('当前成绩学期读取失败');
    const planFields: RequestFields = { 'xh': context.studentNumber, 'pylx': context.studentType, 'falxdm': '1' };
    for (const endpoint of ['queryfahHljdx', 'queryfah']) {
      const response = await this.request(session, ROOT + endpoint + '?sf_request_type=ajax', planFields, false, active);
      context.planId = response.statusCode === 200 ? Parser.planId(response.body) : '';
      if (context.planId) break;
    }
    if (!context.planId) throw new Error('个人培养方案读取失败');

    const summaryResponse = await this.request(session, ROOT + 'queryBxkqk?sf_request_type=ajax', {
      'xjid': context.recordId, 'zyfxdm': null, 'pylx': context.studentType, 'fah': context.planId,
      'xh': context.studentNumber, 'nj': context.grade, 'jzxnxq': currentTerm
    }, true, active);
    if (summaryResponse.statusCode !== 200 && summaryResponse.statusCode !== 404) {
      throw new Error('培养方案完成度读取失败，请稍后重试');
    }
    const parsed = Parser.summary(summaryResponse.body);
    if (parsed === undefined && summaryResponse.statusCode === 200) {
      throw new Error('培养方案完成度解析失败，请稍后重试');
    }
    const progress = parsed ?? new OfficialCreditProgress();
    progress.term = currentTerm;
    progress.context = context;
    if (parsed === undefined) progress.notices.push('教务暂未提供汇总学分');
    else onProgress(progress);

    if (progress.categories.length === 0) {
      const categories = await this.optional(session, ROOT + 'queryXflbyq1?sf_request_type=ajax', {
        'xjid': context.recordId, 'zyfxdm': null, 'pylx': context.studentType, 'fah': context.planId, 'current': 1, 'pageSize': 200
      }, true, active);
      const items = Parser.categories(categories?.body ?? '');
      if (items === undefined) progress.notices.push('学分类别要求暂未获取，可刷新重试');
      else progress.categories = items;
    }
    const groups = await this.optional(session, ROOT + 'queryMkyq?sf_request_type=ajax', {
      'xjid': context.recordId, 'zyfxdm': null, 'pylx': context.studentType, 'fah': context.planId
    }, true, active);
    const groupItems = Parser.groups(groups?.body ?? '');
    if (groupItems === undefined) progress.notices.push('培养课组暂未获取，可刷新重试');
    else progress.groups = groupItems;
    onProgress(progress);

    const records = new Map<string, CreditCourseRecord>();
    let pages: number = 1;
    for (let page = 1; page <= pages; page++) {
      const response = await this.optional(session, '/cjgl/grcjcx/dyxwList?sf_request_type=ajax', {
        'pageNum': page, 'pageSize': 200, 'total': Parser.recordTotal(termResponse.body), 'xjid': context.recordId,
        'sfgld': '1', 'pxzd': '', 'pxfx': '', 'xn': '', 'xq': '', 'kcxz': '', 'kclb': '', 'key': '',
        'pylx': context.studentType, 'sffx': '', 'sfcxfxcj': '0', 'sfsjqx': '0'
      }, false, active);
      const rows = Parser.records(response?.body ?? '');
      if (rows === undefined) {
        progress.notices.push(records.size > 0 ? '部分课程成绩明细未获取，可刷新重试' : '课程成绩明细暂未获取，可刷新重试');
        break;
      }
      for (const item of rows) records.set(item.id, item);
      if (page === 1) {
        const totalPages = Parser.pageCount(response?.body ?? '');
        pages = Math.min(MAX_PAGES, totalPages);
        if (pages < totalPages) progress.notices.push('课程成绩明细较多，仅展示前 10000 条');
      }
    }
    progress.records = Array.from(records.values()).sort((a: CreditCourseRecord, b: CreditCourseRecord) =>
      b.term.localeCompare(a.term) || a.name.localeCompare(b.name));
    this.ensureActive(active);
    return progress;
  }

  async groupCourses(session: EasSession, context: CreditContext, group: CreditGroup,
    active: () => boolean = () => true): Promise<CreditGroupCourse[]> {
    const result = new Map<string, CreditGroupCourse>();
    let pages: number = 1;
    for (let page = 1; page <= pages; page++) {
      const response = await this.request(session, ROOT + 'queryFaKzkc?sf_request_type=ajax', {
        'current': page, 'pageSize': 200, 'xn': null, 'xq': null, 'yxdm': null, 'kzid': group.id, 'kzlx': '0',
        'kcxzdm': null, 'kclbdm': null, 'kzmc': group.name, 'kcmc': '', 'orderby': null, 'sxjx': null,
        'xjid': context.recordId, 'nj': context.grade, 'pylx': context.studentType, 'fah': context.planId, 'zyfxdm': null
      }, true, active);
      const items = response.statusCode === 200 ? Parser.groupCourses(response.body) : undefined;
      if (items === undefined) throw new Error('课组课程读取失败，请重试');
      for (const item of items) result.set(item.code || item.name, item);
      if (page === 1) {
        pages = Parser.pageCount(response.body);
        if (pages > MAX_PAGES) throw new Error('课组课程读取失败，请重试');
      }
    }
    return Array.from(result.values());
  }
}
