/**
 * EasDataProvider.ets - legacy EAS data access used by the timetable importer.
 *
 * Benbu/Weihai undergraduate endpoints mirror Android HITA:
 * GET /cjcx/queryQmcj, GET /kbcx/queryGrkb, POST /kbcx/queryGrkb.
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { EasCampus, EasSession } from './EasSession';
import { EasApiClient, EasApiClientOptions, EasApiResponse, EasHttpMethod } from './EasApiClient';
import { EasSessionStatus, isExpiredEasResponse } from './EasSessionStatus';
import { EasCourseItem, EasCourseScoreItem, EasExamItem, EasTermItem } from './model/EasModels';
import { EasTimePeriodInDay } from '../../common/model/timetable/TimetableModels';
import { easWebLoginConfigFor, EasCampusConfig, EasCampusUrls } from './webLogin/EasWebLoginConfig';
import { EasLegacyTimetableParser } from './data/EasLegacyTimetableParser';
import { BenbuExperimentService } from './BenbuExperimentService';
import { EasAcademicCalendar } from './data/EasAcademicCalendar';
import { EasLegacyCourseCatalogParser, LegacyCourseAttributes } from './data/EasLegacyCourseCatalogParser';
import { ParsedShenzhenWebScores, parseShenzhenWebScores } from './data/ShenzhenWebScores';
import { ParsedShenzhenWebExams, parseShenzhenWebExams } from './data/ShenzhenWebExams';
import { ExamSchedule } from './ExamSchedule';
import { LegacyWebExams } from './data/LegacyWebExams';
import {
  parseShenzhenWebSelectedSubjects,
  parseShenzhenWebTerms,
  parseShenzhenWebTimetable,
  ShenzhenSubjectMeta,
  parseShenzhenWebScheduleStructure
} from './data/ShenzhenWebTimetableParser';

const DOMAIN: number = 0x0000;
const TAG: string = 'HitaEasImport';

export class EasShenzhenEndpoints {
  /** 新版深圳 Web 教务接口（Android EASWebSource.kt 同源）。 */
  static termsPath: string = '/component/queryXnxq';
  static timetablePath: string = '/xszykb/queryxszykbzong';
  static selectedSubjectsPath: string = '/Xsxk/queryYxkc?sf_request_type=ajax';
  static scheduleStructurePath: string = '/component/queryKbjg';
  static weekDatesPath: string = '/component/queryRlZcSj';
  static scoresPath: string = '/cjgl/grcjcx/grcjcx';
  /** 与 Android getShenzhenWebExamItems 使用同一网页接口。 */
  static examsPath: string = '/kscxtj/queryXsksByxhList';
}

export class EasWeihaiEndpoints {
  static examsPath: string = '/kscx/queryKcForXs';
  static termsPath: string = '/kbcx/queryGrkb';
  static scoreTermsPath: string = '/cjcx/queryQmcj';
  static timetableTermsPath: string = '/kbcx/queryGrkb';
  static timetablePath: string = '/kbcx/queryGrkb';
  static calendarPath: string = '/xlcx/queryXlcx';
  static scoresPath: string = '';
}

export class EasBenbuEndpoints {
  static examsPath: string = '/kscx/queryKcForXs1';
  static termsPath: string = '/kbcx/queryGrkb';
  static scoreTermsPath: string = '/cjcx/queryQmcj';
  static timetableTermsPath: string = '/kbcx/queryGrkb';
  static timetablePath: string = '/kbcx/queryGrkb';
  static calendarPath: string = '/xlcx/queryXlcx';
  static scoresPath: string = '';
}

/** 本部/威海共用的课程属性表页面（两校区传统教务路径一致）。 */
export class EasLegacyCatalogEndpoints {
  static executionPlanPath: string = '/zxjh/queryZxkc';
  static finalScoresPath: string = '/cjcx/queryQmcj';
}

/** 课程属性和仅供后台日志使用的读取诊断。 */
export class LegacyCatalogFetch {
  rows: LegacyCourseAttributes[] = [];
  diag: string = '';
}

export class EasScoresResult {
  code: number = 0;
  msg: string = '';
  items: EasCourseScoreItem[] = [];
  ok: boolean = false;
}

export class EasExamQueryResult {
  items: EasExamItem[] = [];
  failedTypes: string[] = [];
}

export class EasDataProvider {
  private api: EasApiClient;
  readonly importWarnings: string[] = [];

  constructor(api: EasApiClient) {
    this.api = api;
  }

  async checkSessionStatus(session: EasSession, timeoutMs: number = 10000): Promise<EasSessionStatus> {
    if (EasSession.buildCookieHeader(session.webCookies).length === 0) {
      return EasSessionStatus.EXPIRED;
    }
    let timer: number = -1;
    try {
      return await Promise.race([
        this.querySessionStatus(session, Math.min(timeoutMs, 6000)),
        new Promise<EasSessionStatus>((resolve) => {
          timer = setTimeout(() => resolve(EasSessionStatus.UNKNOWN), timeoutMs);
        })
      ]);
    } catch (_) {
      return EasSessionStatus.UNKNOWN;
    } finally {
      if (timer !== -1) {
        clearTimeout(timer);
      }
    }
  }

  private async querySessionStatus(session: EasSession, timeoutMs: number): Promise<EasSessionStatus> {
    if (session.campus === EasCampus.BENBU && session.getStudentType() === '2') {
      // The graduate portal has a separate schema; do not claim its cookie is valid without verification.
      const response: EasApiResponse = await this.getHtml(session, '/xs/index', timeoutMs, false);
      return isExpiredEasResponse(response) ? EasSessionStatus.EXPIRED : EasSessionStatus.UNKNOWN;
    }
    const shenzhen: boolean = session.campus === EasCampus.SHENZHEN;
    if (shenzhen && session.webBaseUrl.length === 0) {
      return EasSessionStatus.UNKNOWN;
    }
    const paths: string[] = shenzhen ?
      [EasShenzhenEndpoints.termsPath, '/component/queryxnxqdata'] :
      [EasDataProvider.timetableTermsPathOf(session), EasDataProvider.scoreTermsPathOf(session)];
    for (let i: number = 0; i < paths.length; i++) {
      let response: EasApiResponse;
      if (shenzhen) {
        const options: EasApiClientOptions = EasDataProvider.shenzhenFormOptions(session, '', timeoutMs,
          i === 0 ? '/Xsxk/query/1' : '/authentication/main');
        options.useCache = false;
        options.extraHeaders.set('Cache-Control', 'no-cache');
        response = await this.api.request(session,
          easWebLoginConfigFor(session.campus, session.getStudentType()), paths[i], options);
      } else {
        response = await this.getHtml(session, paths[i], timeoutMs, false);
      }
      if (isExpiredEasResponse(response)) {
        return EasSessionStatus.EXPIRED;
      }
      if (EasDataProvider.isHttpOk(response)) {
        const terms: EasTermItem[] = shenzhen ? parseShenzhenWebTerms(response.body) :
          EasLegacyTimetableParser.parseTermsBySelect(response.body, i === 0 ? 'xnxq' : 'pageXnxq');
        if (terms.length > 0) {
          return EasSessionStatus.CONNECTED;
        }
      } else if (response.statusCode !== 404) {
        return EasSessionStatus.UNKNOWN;
      }
    }
    return EasSessionStatus.UNKNOWN;
  }

  async getAllTerms(session: EasSession): Promise<EasTermItem[]> {
    if (session.loginExpired) {
      throw new Error('教务会话已失效，请重新登录');
    }
    if (session.campus === EasCampus.SHENZHEN) {
      return await this.getShenzhenTerms(session);
    }
    if (session.campus === EasCampus.BENBU && session.getStudentType() === '2') {
      throw new Error('本部研究生课表接口暂未接入');
    }

    const scorePath: string = EasDataProvider.scoreTermsPathOf(session);
    const timetablePath: string = EasDataProvider.timetableTermsPathOf(session);
    const scoreResp: EasApiResponse = await this.getHtml(session, scorePath, 20000, false);
    hilog.info(DOMAIN, TAG, 'terms score path=%{public}s status=%{public}d len=%{public}d',
      scorePath, scoreResp.statusCode, scoreResp.body.length);
    if (isExpiredEasResponse(scoreResp)) {
      throw new Error('教务会话已失效，请重新登录');
    }
    const timetableResp: EasApiResponse = await this.getHtml(session, timetablePath, 20000, false);
    hilog.info(DOMAIN, TAG, 'terms timetable path=%{public}s status=%{public}d len=%{public}d',
      timetablePath, timetableResp.statusCode, timetableResp.body.length);
    if (isExpiredEasResponse(timetableResp)) {
      throw new Error('教务会话已失效，请重新登录');
    }

    const scoreTerms: EasTermItem[] = EasDataProvider.isHttpOk(scoreResp) ?
      EasLegacyTimetableParser.parseTermsBySelect(scoreResp.body, 'pageXnxq') : [];
    const timetableTerms: EasTermItem[] = EasDataProvider.isHttpOk(timetableResp) ?
      EasLegacyTimetableParser.parseTermsBySelect(timetableResp.body, 'xnxq') : [];
    const terms: EasTermItem[] = EasDataProvider.mergeTerms(scoreTerms, timetableTerms);
    hilog.info(DOMAIN, TAG, 'terms parsed score=%{public}d timetable=%{public}d merged=%{public}d',
      scoreTerms.length, timetableTerms.length, terms.length);
    if (terms.length === 0) {
      if (scoreResp.statusCode === 0 || timetableResp.statusCode === 0) {
        throw new Error('学期请求网络失败');
      }
      throw new Error('未获取到学期列表');
    }
    return terms;
  }

  /** Read week-one Monday from the calendar, not from course/score term selectors. */
  async getStartDate(session: EasSession, term: EasTermItem): Promise<number | undefined> {
    let resp: EasApiResponse;
    if (session.campus === EasCampus.SHENZHEN) {
      const cfg = easWebLoginConfigFor(session.campus, session.getStudentType());
      const body: string = 'xn=' + encodeURIComponent(term.yearCode) +
        '&xq=' + encodeURIComponent(term.termCode) + '&djz=1';
      resp = await this.api.request(session, cfg, EasShenzhenEndpoints.weekDatesPath,
        EasDataProvider.shenzhenFormOptions(session, body, 20000, '/Xsxk/query/1'));
    } else {
      const path: string = session.campus === EasCampus.WEIHAI ?
        EasWeihaiEndpoints.calendarPath : EasBenbuEndpoints.calendarPath;
      const fields: Map<string, string> = new Map<string, string>();
      fields.set('xnxq', term.getCode());
      resp = await this.postForm(session, path, fields, 20000);
    }
    if (resp.statusCode === 401 || resp.statusCode === 403 || isExpiredEasResponse(resp) ||
      EasDataProvider.isLoginResponse(resp.body)) {
      throw new Error('教务会话已失效，请重新登录');
    }
    const date: number | undefined = !EasDataProvider.isHttpOk(resp) ? undefined :
      session.campus === EasCampus.SHENZHEN ? EasAcademicCalendar.parseShenzhenJson(resp.body, term) :
        EasAcademicCalendar.parseLegacyHtml(resp.body, term);
    hilog.info(DOMAIN, TAG, 'calendar campus=%{public}s term=%{public}s status=%{public}d start=%{public}s',
      session.campus.toString(), term.getCode(), resp.statusCode,
      date === undefined ? 'unavailable' : new Date(date).toDateString());
    return date;
  }

  async getTimetableOfTerm(session: EasSession, term: EasTermItem): Promise<EasCourseItem[]> {
    this.importWarnings.length = 0;
    if (session.campus === EasCampus.SHENZHEN) {
      return await this.getShenzhenTimetable(session, term);
    }
    if (session.campus === EasCampus.BENBU && session.getStudentType() === '2') {
      throw new Error('本部研究生课表接口暂未接入');
    }

    const path: string = EasDataProvider.timetablePathOf(session);
    const opts: EasApiClientOptions = new EasApiClientOptions();
    opts.method = EasHttpMethod.POST;
    opts.timeoutMs = 25000;
    opts.body = 'fhlj=' + encodeURIComponent('kbcx/queryGrkb') + '&xnxq=' + encodeURIComponent(term.getCode());
    opts.extraHeaders.set('Content-Type', 'application/x-www-form-urlencoded; charset=UTF-8');
    opts.extraHeaders.set('Accept', 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');
    opts.extraHeaders.set('Accept-Language', 'zh-CN,zh-Hans;q=0.9');
    if (session.campus === EasCampus.WEIHAI) {
      opts.extraHeaders.set('Origin', EasCampusUrls.WEIHAI_BASE);
      opts.extraHeaders.set('Referer', EasApiClient.joinUrl(EasCampusUrls.WEIHAI_EAS_PREFIX, path));
    }
    const cfg = easWebLoginConfigFor(session.campus, session.getStudentType());
    const resp: EasApiResponse = await this.api.request(session, cfg, path, opts);

    hilog.info(DOMAIN, TAG, 'timetable term=%{public}s path=%{public}s status=%{public}d len=%{public}d',
      term.getCode(), path, resp.statusCode, resp.body.length);
    if (resp.statusCode === 0) {
      throw new Error('课表请求网络失败');
    }
    if (!EasDataProvider.isHttpOk(resp)) {
      throw new Error('课表请求失败 HTTP ' + resp.statusCode.toString());
    }
    if (EasDataProvider.isLoginResponse(resp.body)) {
      throw new Error('教务会话已失效，请重新登录');
    }
    if (resp.body.indexOf('addlist_01') < 0) {
      if (resp.body.indexOf('name="xnxq"') >= 0 || resp.body.indexOf("name='xnxq'") >= 0) {
        throw new Error('课表页返回异常，未找到课表表格');
      }
      throw new Error('返回的不是课表页，请重新登录后再试');
    }

    const courses: EasCourseItem[] = EasLegacyTimetableParser.parseScheduleHtml(resp.body);
    if (session.campus === EasCampus.BENBU) {
      courses.push(...await BenbuExperimentService.getExperiments(session, this.importWarnings));
      courses.push(...await BenbuExperimentService.getElectronicExperiments(session, this.importWarnings));
    }
    hilog.info(DOMAIN, TAG, 'timetable parsed term=%{public}s courses=%{public}d',
      term.getCode(), courses.length);
    if (courses.length === 0) {
      throw new Error('课表解析为空，请检查该学期是否已有课表');
    }
    return courses;
  }

  /**
   * 本部/威海：课表 HTML 不含课程性质、学分与“是否考试课”，从执行计划和期末成绩
   * 两张表补读。尽力而为：任何一步失败都只返回已拿到的部分，不影响课表导入；
   * diag 记录每张表实际读到的行数或失败原因。
   */
  async getLegacyCourseAttributes(session: EasSession, term: EasTermItem): Promise<LegacyCatalogFetch> {
    const out: LegacyCatalogFetch = new LegacyCatalogFetch();
    if (session.campus === EasCampus.SHENZHEN) {
      return out;
    }
    const planOverrides: Map<string, string> = new Map<string, string>();
    planOverrides.set('pageNo', '1');
    planOverrides.set('pageSize', '1000');
    const plan: LegacyCatalogFetch = await this.fetchLegacyCourseTable(session,
      EasLegacyCatalogEndpoints.executionPlanPath, 'pageSize', planOverrides);
    const scoreOverrides: Map<string, string> = new Map<string, string>();
    scoreOverrides.set('pageXnxq', term.getCode());
    scoreOverrides.set('pageBkcxbj', '0');
    scoreOverrides.set('pageSfjg', '');
    scoreOverrides.set('pageKcmc', '');
    const scores: LegacyCatalogFetch = await this.fetchLegacyCourseTable(session,
      EasLegacyCatalogEndpoints.finalScoresPath, 'pageXnxq', scoreOverrides);
    out.rows = scores.rows.concat(plan.rows);
    out.diag = '计划' + plan.diag + '/成绩' + scores.diag;
    hilog.info(DOMAIN, TAG, 'legacy course attributes plan=%{public}s scores=%{public}s',
      plan.diag, scores.diag);
    return out;
  }

  private async fetchLegacyCourseTable(session: EasSession, path: string, formMarker: string,
    overrides: Map<string, string>): Promise<LegacyCatalogFetch> {
    const out: LegacyCatalogFetch = new LegacyCatalogFetch();
    try {
      const page: EasApiResponse = await this.getHtml(session, path, 12000);
      if (!EasDataProvider.isHttpOk(page)) {
        out.diag = 'HTTP' + page.statusCode.toString();
        hilog.warn(DOMAIN, TAG, 'legacy catalog GET path=%{public}s status=%{public}d', path, page.statusCode);
        return out;
      }
      if (EasDataProvider.isLoginResponse(page.body)) {
        out.diag = '会话失效';
        return out;
      }
      let rows: LegacyCourseAttributes[] = EasLegacyCourseCatalogParser.parseTables(page.body);
      const fields: Map<string, string> | undefined =
        EasLegacyCourseCatalogParser.parseFormFields(page.body, formMarker);
      if (fields !== undefined) {
        overrides.forEach((value: string, key: string) => {
          fields.set(key, value);
        });
        hilog.info(DOMAIN, TAG, 'legacy catalog POST path=%{public}s fields=%{public}d', path, fields.size);
        const posted: EasApiResponse = await this.postForm(session, path, fields, 15000);
        const postedRows: LegacyCourseAttributes[] = EasDataProvider.isLegacyCatalogPage(posted) ?
          EasLegacyCourseCatalogParser.parseTables(posted.body) : [];
        if (postedRows.length > rows.length) {
          rows = postedRows;
        }
      }
      if (rows.length === 0) {
        // 页面上找不到完整表单（或表单不含查询控件）时，按文档参数直接 POST 一次。
        hilog.warn(DOMAIN, TAG, 'legacy catalog direct POST path=%{public}s overrides=%{public}d',
          path, overrides.size);
        const direct: EasApiResponse = await this.postForm(session, path, overrides, 15000);
        const directRows: LegacyCourseAttributes[] = EasDataProvider.isLegacyCatalogPage(direct) ?
          EasLegacyCourseCatalogParser.parseTables(direct.body) : [];
        if (directRows.length > rows.length) {
          rows = directRows;
        }
      }
      out.rows = rows;
      out.diag = rows.length.toString() + '条';
      return out;
    } catch (e) {
      const text: string = e instanceof Error ? e.message : String(e);
      out.diag = text.length > 0 && text.length <= 12 ? text : '读取异常';
      hilog.warn(DOMAIN, TAG, 'legacy catalog failed path=%{public}s %{public}s', path, text);
      return out;
    }
  }

  /** 菜单里常带 loginCAS 链接；出现课程表头时按业务页处理。 */
  private static isLegacyCatalogPage(resp: EasApiResponse): boolean {
    if (!EasDataProvider.isHttpOk(resp)) {
      return false;
    }
    return resp.body.indexOf('课程名称') >= 0 || !EasDataProvider.isLoginResponse(resp.body);
  }

  private async postForm(session: EasSession, path: string, fields: Map<string, string>,
    timeoutMs: number): Promise<EasApiResponse> {
    const parts: string[] = [];
    fields.forEach((value: string, key: string) => {
      parts.push(encodeURIComponent(key) + '=' + encodeURIComponent(value));
    });
    const opts: EasApiClientOptions = new EasApiClientOptions();
    opts.method = EasHttpMethod.POST;
    opts.timeoutMs = timeoutMs;
    opts.body = parts.join('&');
    opts.extraHeaders.set('Content-Type', 'application/x-www-form-urlencoded; charset=UTF-8');
    opts.extraHeaders.set('Accept', 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');
    opts.extraHeaders.set('Accept-Language', 'zh-CN,zh-Hans;q=0.9');
    if (session.campus === EasCampus.WEIHAI) {
      opts.extraHeaders.set('Origin', EasCampusUrls.WEIHAI_BASE);
      opts.extraHeaders.set('Referer', EasApiClient.joinUrl(EasCampusUrls.WEIHAI_EAS_PREFIX, path));
    }
    const cfg = easWebLoginConfigFor(session.campus, session.getStudentType());
    return await this.api.request(session, cfg, path, opts);
  }

  private async getHtml(session: EasSession, path: string, timeoutMs: number = 20000,
    useCache: boolean = true): Promise<EasApiResponse> {
    const opts: EasApiClientOptions = new EasApiClientOptions();
    opts.method = EasHttpMethod.GET;
    opts.timeoutMs = timeoutMs;
    opts.useCache = useCache;
    if (!useCache) {
      opts.extraHeaders.set('Cache-Control', 'no-cache');
    }
    opts.extraHeaders.set('Accept', 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');
    opts.extraHeaders.set('Accept-Language', 'zh-CN,zh-Hans;q=0.9');
    if (session.campus === EasCampus.WEIHAI) {
      opts.extraHeaders.set('Origin', EasCampusUrls.WEIHAI_BASE);
      opts.extraHeaders.set('Referer', EasApiClient.joinUrl(EasCampusUrls.WEIHAI_EAS_PREFIX, path));
    }
    const cfg = easWebLoginConfigFor(session.campus, session.getStudentType());
    return await this.api.request(session, cfg, path, opts);
  }

  /** 深圳新版 Web 端点：学期列表 + 课程选择学期校准。 */
  private async getShenzhenTerms(session: EasSession): Promise<EasTermItem[]> {
    if (!session.hasShenzhenWebSession()) {
      throw new Error('深圳教务会话已失效，请重新登录');
    }
    const cfg = easWebLoginConfigFor(session.campus, session.getStudentType());
    const paths: string[] = [EasShenzhenEndpoints.termsPath, '/component/queryxnxqdata'];
    let terms: EasTermItem[] = [];
    for (let i = 0; i < paths.length; i++) {
      const refererPath: string = paths[i] === EasShenzhenEndpoints.termsPath ? '/Xsxk/query/1' : '/authentication/main';
      const opts: EasApiClientOptions = EasDataProvider.shenzhenFormOptions(
        session, EasDataProvider.shenzhenTermBody(session), 20000, refererPath);
      const resp: EasApiResponse = await this.api.request(session, cfg, paths[i], opts);
      hilog.info(DOMAIN, TAG, 'shenzhen terms path=%{public}s status=%{public}d len=%{public}d',
        paths[i], resp.statusCode, resp.body.length);
      if (resp.statusCode === 401 || resp.statusCode === 403 || isExpiredEasResponse(resp) ||
        EasDataProvider.isLoginResponse(resp.body)) {
        throw new Error('深圳教务会话已失效，请重新登录');
      }
      if (EasDataProvider.isHttpOk(resp)) {
        terms = parseShenzhenWebTerms(resp.body);
      }
      if (terms.length > 0) {
        break;
      }
    }
    if (terms.length === 0) {
      throw new Error('未获取到深圳学期列表');
    }

    // Android 端还会调用 queryXkdqXnxq 校准“选课当前学期”；失败时不阻断课表导入。
    try {
      const selectOpts: EasApiClientOptions = EasDataProvider.shenzhenFormOptions(
        session, 'p_pylx=' + encodeURIComponent(session.getStudentType()), 10000, '/Xsxk/query/1');
      const selectResp: EasApiResponse = await this.api.request(session, cfg,
        '/Xsxk/queryXkdqXnxq', selectOpts);
      const selectedId: string = EasDataProvider.extractShenzhenSelectionTermId(selectResp.body);
      if (selectedId.length > 0) {
        for (let i = 0; i < terms.length; i++) {
          terms[i].isCurrent = terms[i].getCode() === selectedId ||
            (terms[i].yearCode + '-' + terms[i].termCode) === selectedId;
        }
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'shenzhen current term probe failed %{public}s', String(e));
    }
    terms.sort((a: EasTermItem, b: EasTermItem): number => {
      if (a.isCurrent !== b.isCurrent) {
        return a.isCurrent ? -1 : 1;
      }
      return (b.yearCode + b.termCode).localeCompare(a.yearCode + a.termCode);
    });
    return terms;
  }

  /** 深圳新版 Web 端点：读取已选课程元数据，再读取个人总课表。 */
  private async getShenzhenTimetable(session: EasSession, term: EasTermItem): Promise<EasCourseItem[]> {
    if (!session.hasShenzhenWebSession()) {
      throw new Error('深圳教务会话已失效，请重新登录');
    }
    const cfg = easWebLoginConfigFor(session.campus, session.getStudentType());
    let subjects: ShenzhenSubjectMeta[] = [];
    try {
      const subjectOpts: EasApiClientOptions = EasDataProvider.shenzhenFormOptions(
        session, EasDataProvider.shenzhenSelectionBody(session, term), 30000);
      const subjectResp: EasApiResponse = await this.api.request(session, cfg,
        EasShenzhenEndpoints.selectedSubjectsPath, subjectOpts);
      if (subjectResp.statusCode === 401 || subjectResp.statusCode === 403 || isExpiredEasResponse(subjectResp) ||
        EasDataProvider.isLoginResponse(subjectResp.body)) {
        throw new Error('深圳教务会话已失效，请重新登录');
      }
      if (EasDataProvider.isHttpOk(subjectResp)) {
        subjects = parseShenzhenWebSelectedSubjects(subjectResp.body);
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'shenzhen selected subject probe failed %{public}s', String(e));
    }

    const timetableOpts: EasApiClientOptions = EasDataProvider.shenzhenFormOptions(
      session, 'xn=' + encodeURIComponent(term.yearCode) + '&xq=' + encodeURIComponent(term.termCode),
      60000, '/xszykb/queryxszykb');
    timetableOpts.extraHeaders.set('Referer', EasApiClient.joinUrl(
      session.webBaseUrl, '/xszykb/queryxszykb'));
    const timetableResp: EasApiResponse = await this.api.request(session, cfg,
      EasShenzhenEndpoints.timetablePath, timetableOpts);
    hilog.info(DOMAIN, TAG, 'shenzhen timetable term=%{public}s status=%{public}d len=%{public}d',
      term.getCode(), timetableResp.statusCode, timetableResp.body.length);
    if (timetableResp.statusCode === 401 || timetableResp.statusCode === 403 || isExpiredEasResponse(timetableResp) ||
      EasDataProvider.isLoginResponse(timetableResp.body)) {
      throw new Error('深圳教务会话已失效，请重新登录');
    }
    if (!EasDataProvider.isHttpOk(timetableResp)) {
      throw new Error('深圳课表请求失败 HTTP ' + timetableResp.statusCode.toString());
    }
    const courses: EasCourseItem[] | undefined = parseShenzhenWebTimetable(timetableResp.body, subjects);
    if (courses === undefined || courses.length === 0) {
      throw new Error('深圳课表解析为空，请检查该学期是否已有课表');
    }
    return courses;
  }

  /** 供成绩/课表结构页面复用的深圳节次接口。 */
  async getShenzhenScheduleStructure(session: EasSession, term: EasTermItem): Promise<EasTimePeriodInDay[]> {
    const cfg = easWebLoginConfigFor(session.campus, session.getStudentType());
    const body: string = 'xn=' + encodeURIComponent(term.yearCode) + '&xq=' +
      encodeURIComponent(term.termCode) + '&pylx=' + encodeURIComponent(session.getStudentType());
    const resp: EasApiResponse = await this.api.request(session, cfg,
      EasShenzhenEndpoints.scheduleStructurePath,
      EasDataProvider.shenzhenFormOptions(session, body, 20000));
    const parsed = parseShenzhenWebScheduleStructure(resp.body);
    return parsed === undefined ? [] : parsed;
  }

  private static shenzhenFormOptions(session: EasSession, body: string, timeoutMs: number,
    refererPath: string = '/authentication/main'): EasApiClientOptions {
    const opts: EasApiClientOptions = new EasApiClientOptions();
    opts.method = EasHttpMethod.POST;
    opts.body = body;
    opts.timeoutMs = timeoutMs;
    opts.extraHeaders.set('Content-Type', 'application/x-www-form-urlencoded; charset=UTF-8');
    opts.extraHeaders.set('Accept', 'application/json, text/plain, */*');
    opts.extraHeaders.set('Accept-Language', 'zh-CN,zh;q=0.9');
    opts.extraHeaders.set('RoleCode', '01');
    opts.extraHeaders.set('X-Requested-With', 'XMLHttpRequest');
    if (session.webBaseUrl.length > 0) {
      opts.extraHeaders.set('Origin', session.webBaseUrl);
      opts.extraHeaders.set('Referer', EasApiClient.joinUrl(session.webBaseUrl, refererPath));
    }
    return opts;
  }

  private static shenzhenTermBody(session: EasSession): string {
    // Android jwFormPost(queryXnxq) sends no form fields; keep the body empty
    // so the portal can apply its own current-role defaults.
    return '';
  }

  private static shenzhenSelectionBody(session: EasSession, term: EasTermItem): string {
    const pylx: string = encodeURIComponent(session.getStudentType());
    const value = (key: string, raw: string): string => key + '=' + encodeURIComponent(raw);
    const fields: string[] = [
      value('cxsfmt', '0'), value('p_pylx', session.getStudentType()), value('mxpylx', session.getStudentType()),
      value('p_sfgldjr', '0'), value('p_sfredis', '0'), value('p_sfsyxkgwc', '0'), value('p_xktjz', ''),
      value('p_chaxunxh', ''), value('p_gjz', ''), value('p_skjs', ''), value('p_xn', term.yearCode),
      value('p_xq', term.termCode), value('p_xnxq', term.getCode()), value('p_xkfsdm', 'yixuan'),
      value('p_xiaoqu', ''), value('p_kkyx', ''), value('p_kclb', ''), value('p_xkxs', ''), value('p_dyc', ''),
      value('p_kkxnxq', ''), value('p_id', ''), value('p_sfhlctkc', '0'), value('p_sfhllrlkc', '0'),
      value('p_kxsj_xqj', ''), value('p_kxsj_ksjc', ''), value('p_kxsj_jsjc', ''), value('p_kcdm_js', ''),
      value('p_kcdm_cxrw', ''), value('p_kcdm_cxrw_zckc', ''), value('p_kc_gjz', ''), value('p_xzcxtjz_nj', ''),
      value('p_xzcxtjz_yx', ''), value('p_xzcxtjz_zy', ''), value('p_xzcxtjz_zyfx', ''), value('p_xzcxtjz_bj', ''),
      value('p_sfxsgwckb', '1'), value('p_skyy', ''), value('p_sfmxzj', ''), value('p_chaxunxkfsdm', ''),
      value('pageNum', '1'), value('pageSize', '200')
    ];
    return fields.join('&') + '&studentType=' + pylx;
  }

  private static extractShenzhenSelectionTermId(body: string): string {
    try {
      const root: Record<string, Object> = JSON.parse(body) as Record<string, Object>;
      const scan = (value: Object | undefined): string => {
        if (value === undefined || value === null || typeof value !== 'object') {
          return '';
        }
        const record: Record<string, Object> = value as Record<string, Object>;
        const year: string = EasDataProvider.objectText(record, ['p_xn', 'xn', 'XN', 'p_dqxn', 'dqxn']);
        const term: string = EasDataProvider.objectText(record, ['p_xq', 'xq', 'XQ', 'p_dqxq', 'dqxq']);
        if (year.length > 0 && term.length > 0) {
          return year + '-' + term;
        }
        const keys: string[] = Object.keys(record);
        for (let i = 0; i < keys.length; i++) {
          const found: string = scan(record[keys[i]]);
          if (found.length > 0) {
            return found;
          }
        }
        return '';
      };
      return scan(root);
    } catch (e) {
      return '';
    }
  }

  private static objectText(record: Record<string, Object>, keys: string[]): string {
    for (let i = 0; i < keys.length; i++) {
      const raw: Object | undefined = record[keys[i]];
      if (raw !== undefined && raw !== null) {
        const text: string = String(raw).trim();
        if (text.length > 0 && text.toLowerCase() !== 'null') {
          return text;
        }
      }
    }
    return '';
  }

  private static scoreTermsPathOf(session: EasSession): string {
    return session.campus === EasCampus.WEIHAI ? EasWeihaiEndpoints.scoreTermsPath :
      session.campus === EasCampus.BENBU ? EasBenbuEndpoints.scoreTermsPath : EasShenzhenEndpoints.termsPath;
  }

  private static timetableTermsPathOf(session: EasSession): string {
    return session.campus === EasCampus.WEIHAI ? EasWeihaiEndpoints.timetableTermsPath :
      session.campus === EasCampus.BENBU ? EasBenbuEndpoints.timetableTermsPath : EasShenzhenEndpoints.termsPath;
  }

  private static timetablePathOf(session: EasSession): string {
    return session.campus === EasCampus.WEIHAI ? EasWeihaiEndpoints.timetablePath : EasBenbuEndpoints.timetablePath;
  }

  private static mergeTerms(scoreTerms: EasTermItem[], timetableTerms: EasTermItem[]): EasTermItem[] {
    const merged: Map<string, EasTermItem> = new Map<string, EasTermItem>();
    for (let i: number = 0; i < timetableTerms.length; i++) {
      merged.set(timetableTerms[i].getCode(), timetableTerms[i]);
    }
    for (let i: number = 0; i < scoreTerms.length; i++) {
      const key: string = scoreTerms[i].getCode();
      const existing: EasTermItem | undefined = merged.get(key);
      if (existing === undefined) {
        merged.set(key, scoreTerms[i]);
      } else {
        if (scoreTerms[i].termName.length > 0) {
          existing.termName = scoreTerms[i].termName;
        }
        existing.isCurrent = existing.isCurrent || scoreTerms[i].isCurrent;
      }
    }
    const out: EasTermItem[] = [];
    merged.forEach((value: EasTermItem) => out.push(value));
    return out;
  }

  private static isHttpOk(resp: EasApiResponse): boolean {
    return resp.statusCode >= 200 && resp.statusCode < 300;
  }

  private static isLoginResponse(body: string): boolean {
    const text: string = body.toLowerCase();
    // A normal legacy EAS page can contain a loginCAS link in its menu.  Only
    // classify it as expired when the response looks like an actual login or
    // re-auth page, while preserving the JSON/CAS checks used by Shenzhen.
    const hasBusinessPage: boolean = text.indexOf('addlist_01') >= 0 ||
      text.indexOf('name="xnxq"') >= 0 || text.indexOf('name="pagexnxq"') >= 0 ||
      text.indexOf('querygrkb') >= 0 || text.indexOf('queryqmcj') >= 0;
    if (hasBusinessPage) {
      return false;
    }
    const hasLoginForm: boolean = text.indexOf('<form') >= 0 &&
      (text.indexOf('logincas') >= 0 || text.indexOf('name="password"') >= 0 ||
        text.indexOf('name="mm"') >= 0 || text.indexOf('action="/login') >= 0);
    const hasReAuthPage: boolean = text.indexOf('reauth') >= 0 &&
      text.indexOf('reauth_success') < 0;
    const explicitExpired: boolean = text.indexOf('会话已失效') >= 0 ||
      text.indexOf('会话超时') >= 0 || text.indexOf('未登录') >= 0;
    return hasLoginForm || hasReAuthPage || explicitExpired ||
      (text.indexOf('/common/caslogin') >= 0 && text.indexOf('<form') >= 0) ||
      (text.indexOf('/cas/login') >= 0 && text.indexOf('<form') >= 0) ||
      text.indexOf('统一身份认证登录') >= 0;
  }

  async getPersonalScores(session: EasSession, term: EasTermItem): Promise<EasScoresResult> {
    if (session.campus === EasCampus.SHENZHEN) {
      return await this.getShenzhenScores(session, term);
    }
    const path: string = EasDataProvider.scoresPathOf(session);
    if (path.length === 0) {
      throw new Error('当前校区暂不支持成绩查询');
    }
    const opts: EasApiClientOptions = new EasApiClientOptions();
    opts.method = EasHttpMethod.POST;
    opts.body = JSON.stringify({ 'termCode': term.getCode() });
    opts.extraHeaders.set('Content-Type', 'application/json; charset=UTF-8');
    const cfg = easWebLoginConfigFor(session.campus, session.getStudentType());
    const resp: EasApiResponse = await this.api.request(session, cfg, path, opts);
    if (resp.statusCode === 0) {
      throw new Error('成绩请求网络失败');
    }
    const parsed: ParsedShenzhenWebScores | undefined = parseShenzhenWebScores(resp.body, term);
    const result: EasScoresResult = new EasScoresResult();
    if (parsed === undefined) {
      result.ok = false;
      result.msg = '成绩响应解析失败（HTTP ' + resp.statusCode.toString() + '）';
      return result;
    }
    result.code = parsed.code;
    result.msg = parsed.msg;
    result.items = parsed.list;
    result.ok = parsed.code === 0;
    return result;
  }

  /** 深圳新版 Web 成绩查询，参数与 Android EASWebSource.fetchShenzhenWebScoreItems 对齐。 */
  private async getShenzhenScores(session: EasSession, term: EasTermItem): Promise<EasScoresResult> {
    if (!session.hasShenzhenWebSession()) {
      throw new Error('深圳教务会话已失效，请重新登录');
    }
    const cfg = easWebLoginConfigFor(session.campus, session.getStudentType());
    const opts: EasApiClientOptions = new EasApiClientOptions();
    opts.method = EasHttpMethod.POST;
    opts.timeoutMs = 60000;
    opts.body = '{"xn":"' + EasDataProvider.jsonEscape(term.yearCode) +
      '","xq":"' + EasDataProvider.jsonEscape(term.termCode) +
      '","kcmc":null,"cxbj":"-1","pylx":"' + session.getStudentType() +
      '","current":1,"pageSize":1000,"xscjlb":null,"sffx":null}';
    opts.extraHeaders.set('Content-Type', 'application/json;charset=UTF-8');
    opts.extraHeaders.set('Accept', '*/*');
    opts.extraHeaders.set('RoleCode', '01');
    opts.extraHeaders.set('X-Requested-With', 'XMLHttpRequest');
    const resp: EasApiResponse = await this.api.request(session, cfg,
      EasShenzhenEndpoints.scoresPath, opts);
    if (resp.statusCode === 401 || resp.statusCode === 403 || isExpiredEasResponse(resp) ||
      EasDataProvider.isLoginResponse(resp.body)) {
      throw new Error('深圳教务会话已失效，请重新登录');
    }
    if (resp.statusCode === 0) {
      throw new Error('成绩请求网络失败');
    }
    const parsed: ParsedShenzhenWebScores | undefined = parseShenzhenWebScores(resp.body, term);
    const result: EasScoresResult = new EasScoresResult();
    if (parsed === undefined) {
      result.ok = false;
      result.msg = '成绩响应解析失败（HTTP ' + resp.statusCode.toString() + '）';
      return result;
    }
    result.code = parsed.code;
    result.msg = parsed.msg;
    result.items = parsed.list;
    result.ok = parsed.code === 0 || parsed.code === 200;
    return result;
  }

  private static jsonEscape(raw: string): string {
    return raw.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
  }

  private static scoresPathOf(session: EasSession): string {
    return session.campus === EasCampus.WEIHAI ? EasWeihaiEndpoints.scoresPath :
      session.campus === EasCampus.BENBU ? EasBenbuEndpoints.scoresPath : EasShenzhenEndpoints.scoresPath;
  }

  async getExamItems(session: EasSession, term: EasTermItem | undefined): Promise<EasExamItem[]> {
    return (await this.getExamResult(session, term)).items;
  }

  /** Prefer the exam page's selected term over unrelated course-registration terms. */
  async getExamTerms(session: EasSession): Promise<EasTermItem[]> {
    if (session.campus === EasCampus.SHENZHEN) {
      return this.getAllTerms(session);
    }
    EasDataProvider.assertLegacyExamSession(session);
    const path: string = session.campus === EasCampus.WEIHAI ?
      EasWeihaiEndpoints.examsPath : EasBenbuEndpoints.examsPath;
    const response: EasApiResponse = await this.getHtml(session, path);
    if (response.statusCode === 405) {
      return this.getAllTerms(session);
    }
    EasDataProvider.assertExamResponse(response);
    const terms: EasTermItem[] = EasLegacyTimetableParser.parseTerms(response.body);
    return terms.length > 0 ? terms : this.getAllTerms(session);
  }

  async getExamResult(session: EasSession, term: EasTermItem | undefined): Promise<EasExamQueryResult> {
    if (term === undefined) {
      throw new Error('未获取到学期列表');
    }
    if (session.campus === EasCampus.SHENZHEN) {
      const result: EasExamQueryResult = new EasExamQueryResult();
      result.items = await this.getShenzhenExams(session, term);
      return result;
    }
    return this.getLegacyExams(session, term);
  }

  private static assertLegacyExamSession(session: EasSession): void {
    if (session.campus !== EasCampus.BENBU && session.campus !== EasCampus.WEIHAI) {
      throw new Error('当前校区暂不支持考试查询，请手动添加考试');
    }
    if (session.getStudentType() === '2') {
      throw new Error('本部和威海研究生考试接口暂未接入，请到教务网站查询');
    }
    if (session.webCookies.size === 0) {
      throw new Error('教务会话已失效，请重新登录');
    }
  }

  private static assertExamResponse(response: EasApiResponse): void {
    const body: string = response.body.toLowerCase();
    if (response.statusCode === 401 || response.statusCode === 403 ||
      response.statusCode === 302 || response.statusCode === 303 ||
      EasDataProvider.isLoginResponse(response.body) ||
      /<input\b[^>]*type\s*=\s*["']?password\b/.test(body) ||
      /请(?:先|重新)登录|登录(?:已)?(?:失效|过期)|会话(?:已)?(?:失效|过期|超时)/.test(body) ||
      /(?:window|top|parent)(?:\.location)(?:\.href)?\s*=\s*["'][^"']*(?:logincas|\/cas\/login|\/login)/.test(body)) {
      throw new Error('教务会话已失效，请重新登录');
    }
    if (response.statusCode === 0) {
      throw new Error('考试请求网络失败');
    }
    if (!EasDataProvider.isHttpOk(response)) {
      throw new Error('教务考试查询暂不可用，请稍后重试');
    }
  }

  private async getLegacyExams(session: EasSession, term: EasTermItem): Promise<EasExamQueryResult> {
    EasDataProvider.assertLegacyExamSession(session);
    if (term.yearCode.trim().length === 0 || term.termCode.trim().length === 0) {
      throw new Error('未获取到学期列表');
    }
    const path: string = session.campus === EasCampus.WEIHAI ?
      EasWeihaiEndpoints.examsPath : EasBenbuEndpoints.examsPath;
    const codes: string[] = ['01', '02', '03'];
    const names: string[] = ['期末', '期中', '补考'];
    const result: EasExamQueryResult = new EasExamQueryResult();
    const seen: Set<string> = new Set<string>();
    let lastError: Error = new Error('未获取到考试安排');
    for (let i: number = 0; i < codes.length; i++) {
      try {
        const fields: Map<string, string> = new Map<string, string>();
        fields.set('xnxq', term.getCode());
        fields.set('kssjd', codes[i]);
        // Android Benbu uses Jsoup's default GET, whereas Weihai requires a form POST.
        let response: EasApiResponse = session.campus === EasCampus.WEIHAI ?
          await this.postForm(session, path, fields, 20000) :
          await this.getHtml(session, path + '?xnxq=' + encodeURIComponent(term.getCode()) +
            '&kssjd=' + codes[i], 20000);
        if (session.campus === EasCampus.BENBU && response.statusCode === 405) {
          // Aura uses POST for this same endpoint. Only retry a definite method rejection.
          response = await this.postForm(session, path, fields, 20000);
        }
        EasDataProvider.assertExamResponse(response);
        const rows: EasExamItem[] = LegacyWebExams.parse(
          response.body, term, names[i], ExamSchedule.campusName(session.campus.toString()));
        for (let j: number = 0; j < rows.length; j++) {
          const row: EasExamItem = rows[j];
          const key: string = JSON.stringify([row.courseName, row.examDate, row.examTime, row.examLocation,
            row.examType]);
          if (!seen.has(key)) {
            seen.add(key);
            result.items.push(row);
          }
        }
        hilog.info(DOMAIN, TAG, 'exams campus=%{public}s period=%{public}s count=%{public}d',
          session.campus.toString(), codes[i], rows.length);
      } catch (e) {
        lastError = e instanceof Error ? e : new Error('未获取到考试安排');
        if (lastError.message === '教务会话已失效，请重新登录') {
          throw lastError;
        }
        result.failedTypes.push(names[i]);
      }
    }
    if (result.failedTypes.length === codes.length) {
      throw lastError;
    }
    result.items.sort((a: EasExamItem, b: EasExamItem): number => {
      const first: number[] | undefined = ExamSchedule.parseRange(a.examDate, a.examTime);
      const second: number[] | undefined = ExamSchedule.parseRange(b.examDate, b.examTime);
      return (first === undefined ? Number.MAX_SAFE_INTEGER : first[0]) -
        (second === undefined ? Number.MAX_SAFE_INTEGER : second[0]);
    });
    return result;
  }

  /** 深圳 Web 考试安排使用独立的表单接口，不沿用成绩查询的 JSON 参数。 */
  private async getShenzhenExams(session: EasSession, term: EasTermItem): Promise<EasExamItem[]> {
    if (!session.hasShenzhenWebSession()) {
      throw new Error('深圳教务会话已失效，请重新登录');
    }
    const cfg = easWebLoginConfigFor(session.campus, session.getStudentType());
    if (term.yearCode.trim().length === 0 || term.termCode.trim().length === 0) {
      throw new Error('未获取到学期列表');
    }
    const opts: EasApiClientOptions = new EasApiClientOptions();
    opts.method = EasHttpMethod.POST;
    opts.timeoutMs = 60000;
    opts.useCache = false;
    opts.body = 'pxn=' + encodeURIComponent(term.yearCode) +
      '&pxq=' + encodeURIComponent(term.termCode) + '&pageNum=1&pageSize=500';
    opts.extraHeaders.set('Content-Type', 'application/x-www-form-urlencoded; charset=UTF-8');
    opts.extraHeaders.set('Accept', '*/*');
    opts.extraHeaders.set('Accept-Language', 'zh-CN,zh;q=0.9');
    opts.extraHeaders.set('RoleCode', '01');
    opts.extraHeaders.set('X-Requested-With', 'XMLHttpRequest');
    if (session.webBaseUrl.length > 0) {
      opts.extraHeaders.set('Origin', session.webBaseUrl);
      opts.extraHeaders.set('Referer', EasApiClient.joinUrl(session.webBaseUrl, '/kscxtj/queryXsksByxh'));
    }
    const resp: EasApiResponse = await this.api.request(session, cfg, EasShenzhenEndpoints.examsPath, opts);
    hilog.info(DOMAIN, TAG, 'shenzhen exams status=%{public}d len=%{public}d',
      resp.statusCode, resp.body.length);
    if (isExpiredEasResponse(resp)) {
      throw new Error('深圳教务会话已失效，请重新登录');
    }
    if (resp.statusCode === 0) {
      throw new Error('考试请求网络失败');
    }
    if (!EasDataProvider.isHttpOk(resp)) {
      throw new Error('教务考试查询暂不可用，请稍后重试');
    }
    const parsed: ParsedShenzhenWebExams | undefined = parseShenzhenWebExams(resp.body, term);
    if (parsed === undefined || (parsed.code !== 0 && parsed.code !== 200)) {
      throw new Error('考试页面无法识别，请稍后重试');
    }
    for (const item of parsed.list) {
      item.campusName = ExamSchedule.campusName(session.campus.toString());
    }
    hilog.info(DOMAIN, TAG, 'shenzhen exams count=%{public}d', parsed.list.length);
    return parsed.list;
  }

}
