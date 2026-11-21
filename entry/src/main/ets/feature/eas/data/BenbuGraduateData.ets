import { EasTimePeriodInDay } from '../../../common/model/timetable/TimetableModels';
import { BenbuExperimentService } from '../BenbuExperimentService';
import { EasApiClient, EasApiClientOptions, EasApiResponse, EasHttpMethod, EasUserAgentFallback } from '../EasApiClient';
import { EasCampus, EasSession } from '../EasSession';
import { isExpiredEasResponse } from '../EasSessionStatus';
import { EasCourseItem, EasCourseScoreItem, EasTermItem } from '../model/EasModels';
import { easWebLoginConfigFor, EasCampusUrls } from '../webLogin/EasWebLoginConfig';
import { EasLegacyTimetableParser } from './EasLegacyTimetableParser';
import { parseLegacyScores } from './ScoreData';

const COURSE_ORIGIN: string = 'http://gcourse-hit-edu-cn.vpn.hit.edu.cn:1080';
const TIMETABLE_ENTRY: string = '/yjsgl/outInterface/grkb';
const GRADE_ENTRY: string = '/yjsgl/outInterface/cjcx';
const GRADE_PAGE: string = '/xscjb/queryXscjbByXh';
const PROFILE: string = '/yjsgl/common/getXsJbxx?sf_request_type=ajax';
const DAYS: string[] = ['MON', 'TUES', 'WED', 'THUR', 'FRI', 'SAT', 'SUN'];
const SEASONS: string[] = ['秋', '春', '夏', '冬'];
const ORDINALS: string[] = ['一', '二', '三', '四'];

type BenbuRow = Record<string, Object>;

export function isBenbuGraduate(session: EasSession): boolean {
  return session.campus === EasCampus.BENBU && session.getStudentType() === '2';
}

export class BenbuGraduateScores {
  items: EasCourseScoreItem[] = [];
  includesAllTerms: boolean = false;
}

export class BenbuGraduateData {
  private readonly api: EasApiClient;

  constructor(api: EasApiClient) {
    this.api = api;
  }

  async verify(session: EasSession, timeoutMs: number): Promise<EasApiResponse> {
    return this.portal(session, PROFILE, EasHttpMethod.POST, timeoutMs);
  }

  static studentId(response: EasApiResponse): string {
    try {
      const root = JSON.parse(response.body) as BenbuRow;
      const module = root['module'] as BenbuRow;
      const identity = module['data'] as BenbuRow;
      const studentId: string = String(identity['XH'] ?? '').trim();
      return root['isSuccess'] === true && /^[A-Za-z0-9-]{4,32}$/.test(studentId) ? studentId : '';
    } catch (_) {
      return '';
    }
  }

  async terms(session: EasSession): Promise<EasTermItem[]> {
    const response: EasApiResponse = await this.portal(session, '/yjsgl/common/getSemester', EasHttpMethod.POST);
    BenbuGraduateData.expectSession(response);
    const terms: EasTermItem[] = response.statusCode === 200 ? BenbuGraduateData.parseTerms(response.body) : [];
    if (terms.length > 1 && terms.some((term: EasTermItem): boolean => term.isCurrent)) return terms;
    const cookies: Map<string, string> = new Map<string, string>();
    const page: string = await this.bridge(session, TIMETABLE_ENTRY, cookies);
    const options: EasTermItem[] = EasLegacyTimetableParser.parseTermsBySelect(page, 'xnxq');
    if (options.length === 0 && terms.length === 0) throw new Error('未获取到本部研究生学期');
    const officialCurrent: EasTermItem | undefined = terms.find((term: EasTermItem): boolean => term.isCurrent);
    for (const option of options) {
      if (officialCurrent !== undefined) option.isCurrent = officialCurrent.equalsKey(option);
    }
    for (const term of terms) {
      if (!options.some((item: EasTermItem): boolean => term.equalsKey(item))) options.push(term);
    }
    if (options.length === 1) options[0].isCurrent = true;
    return options;
  }

  async courses(session: EasSession, term: EasTermItem): Promise<EasCourseItem[]> {
    const id: string = await this.identity(session);
    const cookies: Map<string, string> = new Map<string, string>();
    await this.bridge(session, TIMETABLE_ENTRY, cookies);
    const current: boolean = term.isCurrent;
    const path: string = current ? '/kbgl/queryXsckcb' : '/kbgl/queryXsckcbyy';
    const body: string = await this.coursePage(path + '?xh=' + encodeURIComponent(id) +
      '&xnxq=' + encodeURIComponent(term.getCode()) + (current ? '&ys=1' : ''), cookies, '/kbgl/queryxskbxsy');
    return BenbuGraduateData.parseTimetable(body);
  }

  async grades(session: EasSession, term: EasTermItem): Promise<BenbuGraduateScores> {
    const id: string = await this.identity(session);
    const query: string = '?xh=' + encodeURIComponent(id);
    const cookies: Map<string, string> = new Map<string, string>();
    const entry: string = await this.bridge(session, GRADE_ENTRY + query, cookies);
    let items: EasCourseScoreItem[] | undefined = parseLegacyScores(entry, term, false);
    if (items === undefined) {
      items = parseLegacyScores(await this.coursePage(GRADE_PAGE + query, cookies, GRADE_PAGE), term, false);
    }
    if (items === undefined) throw new Error('未识别到本部研究生成绩表，请稍后重试');
    const result: BenbuGraduateScores = new BenbuGraduateScores();
    if (items.length > 0 && items.every((item: EasCourseScoreItem): boolean => item.termName.length === 0)) {
      result.includesAllTerms = true;
      result.items = items;
      return result;
    }
    for (const item of items) {
      const code: string = BenbuGraduateData.gradeTerm(item.termName);
      if (code.length === 0) throw new Error('本部研究生成绩缺少可识别的学期，请到研究生系统核对');
      if (code === term.getCode() || code === term.yearCode.substring(0, 4) + term.termCode) result.items.push(item);
    }
    return result;
  }

  static gradeTerm(label: string): string {
    const value: string = label.replace(/[\s学年期]/g, '').replace(/[—－–]/g, '-')
      .replace(/^(\d{4})(?=\d{4}[1-4]$)/, '$1-').replace(/寒/g, '冬');
    const code: RegExpExecArray | null = /^(\d{4}(?:-\d{4})?)([1-4])$/.exec(value);
    if (code !== null) return code[1] + code[2];
    const year: RegExpExecArray | null = /^(\d{4}(?:-\d{4})?)/.exec(value);
    if (year === null) return '';
    const season: number = SEASONS.findIndex((name: string): boolean => value.includes(name));
    const ordinal: number = ORDINALS.findIndex((name: string): boolean => value.includes('第' + name));
    const term: number = season >= 0 ? season : ordinal;
    return term < 0 ? '' : year[1] + (term + 1).toString();
  }

  private async identity(session: EasSession): Promise<string> {
    const response: EasApiResponse = await this.verify(session, 20000);
    BenbuGraduateData.expectOk(response);
    const id: string = BenbuGraduateData.studentId(response);
    if (id.length === 0) throw new Error('未获取到本部研究生账号信息，请重新登录');
    return id;
  }

  private async portal(session: EasSession, path: string, method: EasHttpMethod,
    timeoutMs: number = 20000): Promise<EasApiResponse> {
    const options: EasApiClientOptions = new EasApiClientOptions();
    options.method = method;
    options.timeoutMs = timeoutMs;
    options.useCache = false;
    options.followRedirects = false;
    options.extraHeaders = BenbuGraduateData.headers(method === EasHttpMethod.POST);
    return this.api.request(session, easWebLoginConfigFor(session.campus, session.getStudentType()), path, options);
  }

  private async bridge(session: EasSession, entry: string, cookies: Map<string, string>): Promise<string> {
    let response: EasApiResponse = await this.portal(session, entry, EasHttpMethod.GET);
    let base: string = EasCampusUrls.GRADUATE_BASE;
    const deadline: number = Date.now() + 20000;
    for (let i: number = 0; i < 6; i++) {
      BenbuGraduateData.expectSession(response);
      if (response.statusCode < 300 || response.statusCode >= 400) {
        BenbuGraduateData.expectOk(response);
        if (base !== COURSE_ORIGIN) throw new Error('本部研究生课程系统连接失败，请稍后重试');
        return response.body;
      }
      const location: string = response.location.trim();
      if (/[\\\x00-\x20]/.test(location)) break;
      if (location.startsWith(COURSE_ORIGIN + '/')) {
        base = COURSE_ORIGIN;
      } else if (base !== COURSE_ORIGIN || !/^\/(?![\/\\])/.test(location)) {
        break;
      }
      const destination: string = location.startsWith('/') ? base + location : location;
      const headers: Map<string, string> = BenbuGraduateData.headers(false);
      headers.set('Cookie', EasSession.buildCookieHeader(cookies));
      const remaining: number = deadline - Date.now();
      if (remaining <= 0) break;
      response = await EasApiClient.doHttp(destination, EasHttpMethod.GET, headers, '', remaining, false, false);
      BenbuExperimentService.mergeCookies(cookies, response.cookies);
    }
    throw new Error('本部研究生课程系统连接失败，请稍后重试');
  }

  private async coursePage(path: string, cookies: Map<string, string>, referer: string): Promise<string> {
    const headers: Map<string, string> = BenbuGraduateData.headers(path.startsWith('/kbgl/'));
    headers.set('Referer', COURSE_ORIGIN + referer);
    headers.set('Cookie', EasSession.buildCookieHeader(cookies));
    const response: EasApiResponse = await EasApiClient.doHttp(COURSE_ORIGIN + path, EasHttpMethod.GET,
      headers, '', 20000, false, false);
    BenbuGraduateData.expectOk(response);
    return response.body;
  }

  private static headers(ajax: boolean): Map<string, string> {
    const headers: Map<string, string> = new Map<string, string>();
    headers.set('User-Agent', EasUserAgentFallback.value);
    headers.set('Accept', ajax ? 'application/json, text/plain, */*' : 'text/html,application/xhtml+xml,*/*');
    if (ajax) headers.set('X-Requested-With', 'XMLHttpRequest');
    return headers;
  }

  private static expectSession(response: EasApiResponse): void {
    const location: string = response.location ?? '';
    if (isExpiredEasResponse(response) || /\/(?:common\/(?:login|casLogin)|authserver\/login)(?:[/?#]|$)/i.test(location)) {
      throw new Error('教务会话已失效，请重新登录');
    }
  }

  private static expectOk(response: EasApiResponse): void {
    BenbuGraduateData.expectSession(response);
    if (response.statusCode === 0) throw new Error('本部研究生教务连接失败，请检查网络');
    if (response.statusCode < 200 || response.statusCode >= 300) throw new Error('本部研究生教务暂时无法提供查询');
  }

  static parseTerms(body: string): EasTermItem[] {
    const terms: Map<string, EasTermItem> = new Map<string, EasTermItem>();
    try {
      BenbuGraduateData.collectTerms(JSON.parse(body) as Object, terms, 0);
    } catch (_) {
      return [];
    }
    return Array.from(terms.values()).sort((a: EasTermItem, b: EasTermItem): number =>
      a.isCurrent === b.isCurrent ? b.getCode().localeCompare(a.getCode()) : a.isCurrent ? -1 : 1);
  }

  private static collectTerms(value: Object, out: Map<string, EasTermItem>, depth: number): void {
    if (!value || typeof value !== 'object' || depth > 6) return;
    if (Array.isArray(value)) {
      for (const row of value as Object[]) BenbuGraduateData.collectTerms(row, out, depth + 1);
      return;
    }
    const obj = value as BenbuRow;
    if (obj['isSuccess'] === false) return;
    const values: Object[] = Object.values(obj);
    const code: string = String(values.find((field: Object): boolean => /^\d{4}-\d{4}[1-4]$/.test(String(field))) ?? '');
    if (code.length > 0) {
      const term: EasTermItem = new EasTermItem();
      term.yearCode = code.substring(0, 9);
      term.yearName = term.yearCode + '学年';
      term.termCode = code.substring(9);
      term.termName = SEASONS[Number(term.termCode) - 1] + '季学期';
      const current: string = String(obj['current'] ?? obj['isCurrent'] ?? '').toLowerCase();
      term.isCurrent = current === 'true' || current === '1' ||
        values.some((field: Object): boolean => field === true ||
          (typeof field === 'string' && /当前|本学期/.test(String(field))));
      if (!out.has(code) || term.isCurrent) out.set(code, term);
    }
    for (const row of values) BenbuGraduateData.collectTerms(row, out, depth + 1);
  }

  static schedule(): EasTimePeriodInDay[] {
    const times: number[][] = [
      [8, 0, 8, 50], [8, 55, 9, 45], [10, 0, 10, 50], [10, 55, 11, 45],
      [14, 0, 14, 50], [14, 55, 15, 45], [16, 0, 16, 50], [16, 55, 17, 45],
      [18, 45, 19, 35], [19, 40, 20, 30], [20, 45, 21, 35], [21, 40, 22, 30]
    ];
    return times.map((time: number[]): EasTimePeriodInDay => EasTimePeriodInDay.ofHour(time[0], time[1], time[2], time[3]));
  }

  static parseTimetable(body: string): EasCourseItem[] {
    let raw: Object;
    try {
      raw = JSON.parse(body) as Object;
    } catch (_) {
      throw BenbuGraduateData.invalidTimetable();
    }
    if (!Array.isArray(raw)) throw BenbuGraduateData.invalidTimetable();
    const result: EasCourseItem[] = [];
    for (const row of raw as BenbuRow[]) {
      if (!row || typeof row !== 'object') throw BenbuGraduateData.invalidTimetable();
      const period: number[] = BenbuGraduateData.period(String(row['JCMC'] ?? row['jcmc'] ?? ''));
      for (let day: number = 0; day < DAYS.length; day++) {
        const cell: string = String(row[DAYS[day]] ?? row[DAYS[day].toLowerCase()] ?? '');
        const lines: string[] = cell.split(/<br\s*\/?>/gi);
        for (const line of lines) {
          const content: string = EasLegacyTimetableParser.decodeHtml(line.replace(/<[^>]*>/g, '')).trim()
            .replace(/【/g, '[').replace(/】/g, ']');
          if (content.length === 0 || /^(?:-|—|无|暂无)$/.test(content)) continue;
          result.push(...BenbuGraduateData.meetings(content, day + 1, period));
        }
      }
    }
    return result;
  }

  private static meetings(line: string, day: number, period: number[]): EasCourseItem[] {
    const clock: RegExpExecArray | null = /\[(\d+\s*(?:[-,，]\s*\d+)?)\](?:\s*节)?\s*[^\[\]◇周]*$/.exec(line);
    if (line.includes('◇') && clock !== null) {
      const displayed: number[] = BenbuGraduateData.period(clock[1]);
      if (displayed[0] !== period[0] || displayed[1] !== period[1]) throw BenbuGraduateData.invalidTimetable();
      line = line.substring(0, clock.index).trim();
    }
    const open: number = line.indexOf('[');
    if (open <= 0) throw BenbuGraduateData.invalidTimetable();
    const identity: string[] = line.substring(0, open).split('◇');
    const name: string = identity[0].trim();
    let teacher: string = (identity[1] ?? '').trim();
    const tail: string[] = line.substring(open).split('◇');
    if (name.length === 0 || identity.length > 2 || tail.length > 2) throw BenbuGraduateData.invalidTimetable();
    const chunks: string[] = tail[0].split(/\[([^\[\]]*周[^\[\]]*)\]/g);
    if (chunks.length < 3) throw BenbuGraduateData.invalidTimetable();
    const sharedRoom: string = (tail[1] ?? '').trim();
    const courses: EasCourseItem[] = [];
    for (let i: number = 1; i < chunks.length; i += 2) {
      const remaining: string = chunks[i + 1].trim();
      const last: boolean = i + 2 >= chunks.length;
      const divider: number = last ? -1 : Math.max(remaining.lastIndexOf('，'), remaining.lastIndexOf(','));
      if (!last && divider < 0 && remaining.length > 0) throw BenbuGraduateData.invalidTimetable();
      let location: string = (divider >= 0 ? remaining.substring(0, divider) : remaining).trim() || sharedRoom;
      const meta: RegExpExecArray | null = last ? /^(.*?)\[([^\[\]]+)\](?:[^[]*)$/.exec(location) : null;
      const item: EasCourseItem = new EasCourseItem();
      if (meta !== null) {
        location = meta[1].trim();
        for (const value of meta[2].split(/[,，]/)) {
          const field: string = value.trim();
          if (/必修|选修|限选|任选/.test(field)) item.courseProperty = field;
          else if (teacher.length === 0) teacher = field;
        }
      }
      if (/[\[\]◇]/.test(location + teacher)) throw BenbuGraduateData.invalidTimetable();
      item.name = name;
      item.rawName = name;
      item.teacher = teacher;
      item.classroom = location;
      item.weekNumbers = BenbuGraduateData.weeks(chunks[i]);
      item.weeks = item.weekNumbers.join(',');
      item.dayOfWeek = day;
      item.beginSection = period[0];
      item.sectionCount = period[1] - period[0] + 1;
      courses.push(item);
      if (divider >= 0) teacher = remaining.substring(divider + 1).trim() || teacher;
    }
    return courses;
  }

  private static weeks(value: string): number[] {
    const raw: string = value.replace(/\s/g, '');
    const parts: string[] = raw.replace(/[单双周()（）]/g, '').split(/[,，、]/);
    if (parts.some((part: string): boolean => !/^\d{1,2}(?:[-~至到]\d{1,2})?$/.test(part))) {
      throw BenbuGraduateData.invalidTimetable();
    }
    const weeks: number[] = EasLegacyTimetableParser.parseWeeksString(raw.replace(/[~到]/g, '-'), '');
    if (weeks.length === 0 || weeks[weeks.length - 1] > 34) throw BenbuGraduateData.invalidTimetable();
    return weeks;
  }

  private static period(value: string): number[] {
    const match: RegExpExecArray | null = /^(?:第\s*)?(\d+)(?:\s*[-,，]\s*(\d+))?\s*节?$/.exec(value.trim());
    const first: number = Number(match?.[1] ?? '0');
    const last: number = Number(match?.[2] ?? first);
    if (first < 1 || last < first || last > 12) throw BenbuGraduateData.invalidTimetable();
    return [first, last];
  }

  private static invalidTimetable(): Error {
    return new Error('本部研究生教务返回了无法识别的课表，请到研究生系统核对');
  }
}
