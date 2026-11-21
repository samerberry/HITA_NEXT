import { DAY_MILLIS, EasTimePeriodInDay, EasTimetable } from '../../../common/model/timetable/TimetableModels';
import { EasApiClient, EasApiClientOptions, EasApiResponse, EasHttpMethod } from '../EasApiClient';
import { EasCampus, EasSession } from '../EasSession';
import { isExpiredEasResponse } from '../EasSessionStatus';
import { EasCourseItem, EasTermItem } from '../model/EasModels';
import { easWebLoginConfigFor, EasUserAgent } from '../webLogin/EasWebLoginConfig';
import { parseShenzhenWebSelectedSubjects, parseShenzhenWebTerms,
  parseShenzhenWebTimetable } from './ShenzhenWebTimetableParser';

export function isWeihaiGraduate(session: EasSession): boolean {
  return session.campus === EasCampus.WEIHAI && session.getStudentType() === '2';
}

export class WeihaiGraduateTimetable {
  private readonly api: EasApiClient;

  constructor(api: EasApiClient) {
    this.api = api;
  }

  async terms(session: EasSession): Promise<EasTermItem[]> {
    const currentBody: string = await this.request(session, '/component/querydangqianxnxq');
    const current: EasTermItem | undefined = parseShenzhenWebTerms('[' + currentBody + ']')[0];
    if (current === undefined) throw new Error('未获取到威海研究生当前学期');
    const listBody: string = await this.request(session, '/component/queryxnxqdata');
    const raw = JSON.parse(listBody) as Object;
    if (!Array.isArray(raw)) throw new Error('威海研究生学期列表格式异常');
    const terms: EasTermItem[] = parseShenzhenWebTerms(listBody);
    if (!terms.some((term: EasTermItem): boolean => term.equalsKey(current))) terms.push(current);
    terms.forEach((term: EasTermItem) => { term.isCurrent = term.equalsKey(current); });
    return terms.sort((a: EasTermItem, b: EasTermItem): number =>
      a.isCurrent === b.isCurrent ? b.getCode().localeCompare(a.getCode()) : a.isCurrent ? -1 : 1);
  }

  async startDate(session: EasSession, term: EasTermItem): Promise<number | undefined> {
    const body: string = await this.request(session, '/Xiaoli/queryMonthList', WeihaiGraduateTimetable.termBody(term));
    try {
      const root = JSON.parse(body) as Record<string, Object>;
      if (!Array.isArray(root['xlList'])) return undefined;
      const rows = root['xlList'] as Array<Record<string, Object>>;
      const starts: Set<number> = new Set<number>();
      for (const row of rows) {
        const week: number = Number(row['ZC']);
        if (String(row['XNXQ']) !== term.getCode() || !Number.isInteger(week) || week < 1 || week > 33) continue;
        const parts: RegExpExecArray | null = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(row['RQ']));
        if (parts === null) continue;
        const year: number = Number(parts[1]);
        const month: number = Number(parts[2]);
        const day: number = Number(parts[3]);
        const date: Date = new Date(year, month - 1, day);
        if (date.getFullYear() !== year || date.getMonth() !== month - 1 || date.getDate() !== day) continue;
        starts.add(EasTimetable.mondayMsOf(date.getTime() - (week - 1) * 7 * DAY_MILLIS));
      }
      return starts.size === 1 ? Array.from(starts)[0] : undefined;
    } catch (_) {
      return undefined;
    }
  }

  async courses(session: EasSession, term: EasTermItem): Promise<EasCourseItem[]> {
    const fields: string = WeihaiGraduateTimetable.termBody(term);
    const page: string = '/xszykb/queryxszykb';
    const published: string = (await this.request(session, '/xszykb/querykbsffb', fields, page)).trim();
    if (published === '0') throw new Error('该学期课表尚未发布');
    if (published === '2') throw new Error('请先在威海研究生教务完成课程评价');
    if (published !== '1') throw new Error('未能确认威海研究生课表发布状态');

    const body: string = await this.request(session, '/xszykb/queryxszykbzong', fields, page);
    const payload = JSON.parse(body) as Object;
    if (!Array.isArray(payload)) throw new Error('威海研究生课表格式异常');
    const rows = (payload as Array<Record<string, Object>>).filter((row: Record<string, Object>): boolean =>
      String(row['KEY']).toLowerCase() !== 'bz');
    if (rows.length === 0) return [];

    const selection: Record<string, Object> = await this.selected(session, term);
    const schedule: EasTimePeriodInDay[] = WeihaiGraduateTimetable.parseSchedule(selection, term);
    for (const row of rows) {
      const cell: RegExpExecArray | null = /^xq([1-7])_jc\d+$/i.exec(String(row['KEY']));
      const from: number = Number(row['KSJC']);
      const to: number = Number(row['JSJC']);
      const weeks: string = String(row['ZC']);
      if (cell === null || !Number.isInteger(from) || !Number.isInteger(to) || from < 1 || to < from ||
        to > schedule.length || !/^[01]{34}$/.test(weeks) || !weeks.substring(1).includes('1')) {
        throw new Error('威海研究生课表返回了无法识别的课程');
      }
      row['XQJ'] = Number(cell[1]);
    }
    const courses: EasCourseItem[] | undefined = parseShenzhenWebTimetable(JSON.stringify(rows),
      parseShenzhenWebSelectedSubjects(JSON.stringify(selection['yxkcList'])));
    if (courses === undefined || courses.length !== rows.length) {
      throw new Error('威海研究生课表返回了无法识别的课程');
    }
    for (let i = 0; i < rows.length; i++) {
      const detail: string = String(rows[i]['SKSJ'] ?? '');
      const lines: string[] = detail.replace(/<br\s*\/?>/gi, '\n').split(/\r?\n/);
      if (lines.length < 3) continue;
      const teacher: string = lines[1].trim().replace(/^[\[【]|[\]】]$/g, '');
      const location: RegExpExecArray | null = /[\[【][^\]】]*周[^\]】]*[\]】]\s*[\[【]([^\]】]+)[\]】]/.exec(lines[2]);
      if (teacher.length > 0) courses[i].teacher = teacher;
      if (location !== null) {
        const classroom: string = location[1].trim();
        if (teacher.length === 0 && courses[i].teacher === classroom) courses[i].teacher = '';
        courses[i].classroom = classroom;
      }
    }
    return courses;
  }

  async schedule(session: EasSession, term: EasTermItem): Promise<EasTimePeriodInDay[]> {
    return WeihaiGraduateTimetable.parseSchedule(await this.selected(session, term), term);
  }

  private static parseSchedule(selection: Record<string, Object>, term: EasTermItem): EasTimePeriodInDay[] {
    if (!Array.isArray(selection['kbjclist'])) throw new Error('未获取到威海研究生节次');
    const rows = (selection['kbjclist'] as Array<Record<string, Object>>)
      .sort((a: Record<string, Object>, b: Record<string, Object>): number => Number(a['XJ']) - Number(b['XJ']));
    if (rows.length === 0) throw new Error('未获取到威海研究生节次');
    const periods: EasTimePeriodInDay[] = [];
    for (let i = 0; i < rows.length; i++) {
      const row: Record<string, Object> = rows[i];
      if (String(row['XN']) !== term.yearCode || String(row['XQ']) !== term.termCode || Number(row['XJ']) !== i + 1) {
        throw new Error('威海研究生节次与所选学期不匹配');
      }
      const from: number = WeihaiGraduateTimetable.clockMinutes(String(row['KSSJ']));
      const to: number = WeihaiGraduateTimetable.clockMinutes(String(row['JSSJ']));
      if (from < 0 || to <= from || (i > 0 && periods[i - 1].to.hour * 60 + periods[i - 1].to.minute > from)) {
        throw new Error('威海研究生节次时间格式异常');
      }
      periods.push(EasTimePeriodInDay.ofHour(Math.floor(from / 60), from % 60, Math.floor(to / 60), to % 60));
    }
    return periods;
  }

  private static clockMinutes(value: string): number {
    const clock: RegExpExecArray | null = /^(\d{1,2}):(\d{2})(?::(\d{2}))?$/.exec(value.trim());
    if (clock !== null) {
      const hour: number = Number(clock[1]);
      const minute: number = Number(clock[2]);
      const second: number = clock[3] === undefined ? 0 : Number(clock[3]);
      return hour < 24 && minute < 60 && second < 60 ? hour * 60 + minute : -1;
    }
    if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/.test(value)) return -1;
    const milliseconds: number = Date.parse(value);
    if (!Number.isFinite(milliseconds)) return -1;
    // Teaching periods are campus-local even when the device is in another time zone.
    const campusClock: Date = new Date(milliseconds + 8 * 60 * 60 * 1000);
    return campusClock.getUTCHours() * 60 + campusClock.getUTCMinutes();
  }

  private async selected(session: EasSession, term: EasTermItem): Promise<Record<string, Object>> {
    const page: string = '/Xsxk/query/2';
    const html: string = await this.request(session, page, '', page, EasHttpMethod.GET);
    const fields: Map<string, string> = new Map<string, string>();
    const runtime: string[] = ['p_pylx', 'p_sfgldjr', 'p_sfredis', 'p_sfsyxkgwc'];
    for (const name of runtime) {
      const pattern: RegExp = new RegExp('(?:var|let|const)\\s+' + name +
        '\\s*=\\s*["\'](-?\\d+)["\']', 'g');
      const value: RegExpExecArray | null = pattern.exec(html);
      if (value === null || pattern.exec(html) !== null) throw new Error('未获取到威海研究生选课配置');
      fields.set(name, value[1]);
    }
    if (fields.get('p_pylx') !== '2') throw new Error('当前会话未进入威海研究生教务');
    fields.set('mxpylx', '2');
    const moduleBody: string = await this.request(session, '/Xsxk/queryXkdqXnxq',
      WeihaiGraduateTimetable.form(fields), page);
    const moduleTerm = JSON.parse(moduleBody) as Record<string, Object>;
    const year: string = String(moduleTerm['p_dqxn'] ?? '');
    const semester: string = String(moduleTerm['p_dqxq'] ?? '');
    if (year.length === 0 || semester.length === 0 || String(moduleTerm['p_dqxnxq']) !== year + semester) {
      throw new Error('未获取到威海研究生选课学期');
    }
    fields.set('p_dqxn', year);
    fields.set('p_dqxq', semester);
    fields.set('p_dqxnxq', year + semester);
    fields.set('p_xn', term.yearCode);
    fields.set('p_xq', term.termCode);
    fields.set('p_xnxq', term.getCode());
    fields.set('p_xkfsdm', 'yixuan');
    fields.set('p_chaxunxh', '');
    fields.set('p_sfhlctkc', '0');
    fields.set('p_sfhllrlkc', '0');
    fields.set('p_gjz', '');
    const body: string = await this.request(session, '/Xsxk/queryYxkc', WeihaiGraduateTimetable.form(fields), page);
    const selection = JSON.parse(body) as Record<string, Object>;
    if (!Array.isArray(selection['yxkcList'])) throw new Error('未获取到威海研究生课程信息');
    return selection;
  }

  private async request(session: EasSession, path: string, body: string = '',
    referer: string = '/authentication/main', method: EasHttpMethod = EasHttpMethod.POST): Promise<string> {
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
      options.extraHeaders.set('Content-Type', 'application/x-www-form-urlencoded; charset=UTF-8');
    }
    const response: EasApiResponse = await this.api.request(session,
      easWebLoginConfigFor(session.campus, session.getStudentType()), path, options);
    if (isExpiredEasResponse(response)) throw new Error('威海研究生教务会话已失效，请重新登录');
    if (response.statusCode === 0) throw new Error('无法连接威海研究生教务，请检查网络后重试');
    if (response.statusCode < 200 || response.statusCode >= 300) throw new Error('威海研究生教务暂时无法提供查询');
    return response.body;
  }

  private static termBody(term: EasTermItem): string {
    return 'xn=' + encodeURIComponent(term.yearCode) + '&xq=' + encodeURIComponent(term.termCode);
  }

  private static form(fields: Map<string, string>): string {
    const pairs: string[] = [];
    fields.forEach((value: string, key: string) => pairs.push(key + '=' + encodeURIComponent(value)));
    return pairs.join('&');
  }
}
