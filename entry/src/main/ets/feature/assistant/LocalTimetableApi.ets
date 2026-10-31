import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { i18n } from '@kit.LocalizationKit';
import { EasEventItem, EasEventType, EasTimetable } from '../../common/model/timetable/TimetableModels';
import { LocalTimetableReader, LocalTimetableSnapshot } from '../timetable/data/LocalTimetableReader';

export enum TimetableQueryCode {
  OK = 0,
  NO_TIMETABLE = 1,
  INVALID_ARGUMENT = 2,
  READ_FAILED = 3,
  UNSUPPORTED_TOOL = 4
}

/** All fields are optional. Without dates, query all locally saved dates of the selected timetable. */
export class TimetableQuery {
  startDate: string = '';
  endDate: string = '';
  teachingWeek: number = 0;
  dayOfWeek: number = 0;
  queryMode: string = 'range';
  offset: number = 0;
  limit: number = 200;
}

export class TimetableCourseData {
  id: string = '';
  subjectId: string = '';
  timetableId: string = '';
  type: string = '';
  name: string = '';
  teacher: string = '';
  place: string = '';
  startTime: string = '';
  endTime: string = '';
  startTimestamp: number = 0;
  endTimestamp: number = 0;
  dayOfWeek: number = 0;
  teachingWeek: number = -1;
  firstPeriod: number = 0;
  lastPeriod: number = 0;
}

export class TimetableQueryData {
  message: string = '';
  source: string = 'local';
  currentTime: string = '';
  timeZone: string = '';
  hasTimetable: boolean = false;
  timetableId: string = '';
  timetableName: string = '';
  termStart: string = '';
  termEnd: string = '';
  currentWeek: number = -1;
  startDate: string = '';
  endDate: string = '';
  teachingWeek: number = 0;
  dayOfWeek: number = 0;
  queryMode: string = 'range';
  total: number = 0;
  offset: number = 0;
  limit: number = 200;
  returned: number = 0;
  hasMore: boolean = false;
  nextOffset: number = -1;
  isComplete: boolean = false;
  courses: TimetableCourseData[] = [];
}

export class TimetableQueryResponse {
  code: number = TimetableQueryCode.OK;
  result: TimetableQueryData = new TimetableQueryData();
}

/** Read-only ArkTS API. No network request, UI operation, credential or model key is involved. */
export class LocalTimetableApi {
  static readonly TOOL_NAME: string = 'Timetable';
  static readonly TOOL_VERSION: string = '0.1.0';

  static async query(context: common.Context,
    parameters: Record<string, Object> = {}): Promise<TimetableQueryResponse> {
    let query: TimetableQuery;
    try {
      query = LocalTimetableApi.parse(parameters);
    } catch (error) {
      return LocalTimetableApi.failure(TimetableQueryCode.INVALID_ARGUMENT,
        error instanceof Error ? error.message : '查询参数无效');
    }
    let stage: string = 'read';
    try {
      const snapshot: LocalTimetableSnapshot = await LocalTimetableReader.load(context);
      stage = 'project';
      return LocalTimetableApi.project(snapshot, query, Date.now());
    } catch (_) {
      hilog.error(0x0000, 'HitaQuery', 'query failed stage=%{public}s', stage);
      // Never turn database/cursor/selection failures into "no classes" or expose internal error text.
      return LocalTimetableApi.failure(TimetableQueryCode.READ_FAILED, '本地课表读取失败，请稍后重试');
    }
  }

  static failure(code: TimetableQueryCode, message: string): TimetableQueryResponse {
    const response: TimetableQueryResponse = new TimetableQueryResponse();
    response.code = code;
    response.result.message = message;
    LocalTimetableApi.setClock(response.result, Date.now());
    return response;
  }

  private static parse(parameters: Record<string, Object>): TimetableQuery {
    const query: TimetableQuery = new TimetableQuery();
    const start: Object | undefined = parameters['startDate'];
    const end: Object | undefined = parameters['endDate'];
    if (start !== undefined) {
      if (typeof start !== 'string') throw new Error('startDate 必须是 YYYY-MM-DD 格式的字符串');
      query.startDate = start.trim();
    }
    if (end !== undefined) {
      if (typeof end !== 'string') throw new Error('endDate 必须是 YYYY-MM-DD 格式的字符串');
      query.endDate = end.trim();
    }
    if (query.startDate.length > 0 && query.endDate.length === 0) query.endDate = query.startDate;
    if (query.endDate.length > 0 && query.startDate.length === 0) query.startDate = query.endDate;
    if (query.startDate.length > 0 &&
      LocalTimetableApi.parseDate(query.startDate) > LocalTimetableApi.parseDate(query.endDate)) {
      throw new Error('开始日期不能晚于结束日期');
    }
    query.teachingWeek = LocalTimetableApi.optionalInteger(parameters, 'teachingWeek', 1, 1000);
    query.dayOfWeek = LocalTimetableApi.optionalInteger(parameters, 'dayOfWeek', 1, 7);
    const mode: Object | undefined = parameters['queryMode'];
    if (mode !== undefined) {
      if (typeof mode !== 'string' || ['range', 'nextClass', 'currentClass', 'upcomingExams'].indexOf(mode) < 0) {
        throw new Error('queryMode 必须是 range、nextClass、currentClass 或 upcomingExams');
      }
      query.queryMode = mode;
    }
    if (query.teachingWeek > 0 && query.startDate.length > 0) {
      throw new Error('teachingWeek 与日期范围不能同时提供；教学周日期由 HITA 计算');
    }
    if (query.queryMode !== 'range' &&
      (query.startDate.length > 0 || query.teachingWeek > 0 || query.dayOfWeek > 0)) {
      throw new Error('当前、下一节课程或未来考试由设备时间确定，不要同时提供日期、教学周或星期');
    }
    const offset: Object | undefined = parameters['offset'];
    if (offset !== undefined) {
      if (typeof offset !== 'number' || !Number.isSafeInteger(offset) || offset < 0) {
        throw new Error('offset 必须是大于或等于 0 的整数');
      }
      query.offset = offset;
    }
    const limit: Object | undefined = parameters['limit'];
    if (limit !== undefined) {
      if (typeof limit !== 'number' || !Number.isInteger(limit) || limit < 1 || limit > 500) {
        throw new Error('limit 必须是 1 到 500 之间的整数');
      }
      query.limit = limit;
    }
    return query;
  }

  private static optionalInteger(parameters: Record<string, Object>, key: string,
    minimum: number, maximum: number): number {
    const value: Object | undefined = parameters[key];
    if (value === undefined) return 0;
    if (typeof value !== 'number' || !Number.isInteger(value) || value < minimum || value > maximum) {
      throw new Error(key + ' 必须是 ' + minimum.toString() + ' 到 ' + maximum.toString() + ' 之间的整数');
    }
    return value;
  }

  private static parseDate(value: string): number {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) throw new Error('日期必须使用 YYYY-MM-DD 格式');
    const year: number = Number(value.slice(0, 4));
    const month: number = Number(value.slice(5, 7));
    const day: number = Number(value.slice(8, 10));
    if (year < 1000 || year > 9999) throw new Error('日期年份无效');
    // Date-only strings are not parsed as UTC; match the app's local calendar dates.
    const date: Date = new Date(year, month - 1, day);
    if (date.getFullYear() !== year || date.getMonth() !== month - 1 || date.getDate() !== day) {
      throw new Error('日期不存在');
    }
    return date.getTime();
  }

  private static project(snapshot: LocalTimetableSnapshot, query: TimetableQuery,
    now: number): TimetableQueryResponse {
    const response: TimetableQueryResponse = new TimetableQueryResponse();
    const result: TimetableQueryData = response.result;
    LocalTimetableApi.setClock(result, now);
    result.startDate = query.startDate;
    result.endDate = query.endDate;
    result.teachingWeek = query.teachingWeek;
    result.dayOfWeek = query.dayOfWeek;
    result.queryMode = query.queryMode;
    result.offset = query.offset;
    result.limit = query.limit;
    const timetable: EasTimetable | undefined = snapshot.timetable;
    if (timetable === undefined) {
      response.code = TimetableQueryCode.NO_TIMETABLE;
      result.message = '尚未保存可用课表，请先在 Hita 中导入或创建课表';
      return response;
    }
    result.hasTimetable = true;
    result.timetableId = timetable.id;
    result.timetableName = timetable.name;
    result.termStart = LocalTimetableApi.dateTime(timetable.startTime);
    result.termEnd = LocalTimetableApi.dateTime(timetable.endTime);
    result.currentWeek = timetable.getWeekNumber(now);
    if (query.teachingWeek > 0) {
      const start: Date = new Date(timetable.startTime);
      start.setDate(start.getDate() + (query.teachingWeek - 1) * 7 + Math.max(0, query.dayOfWeek - 1));
      const end: Date = new Date(start.getTime());
      if (query.dayOfWeek === 0) end.setDate(end.getDate() + 6);
      result.startDate = LocalTimetableApi.dateTime(start.getTime()).slice(0, 10);
      result.endDate = LocalTimetableApi.dateTime(end.getTime()).slice(0, 10);
    }
    let from: number = Number.NEGATIVE_INFINITY;
    let to: number = Number.POSITIVE_INFINITY;
    if (result.startDate.length > 0) {
      from = LocalTimetableApi.parseDate(result.startDate);
      const nextDay: Date = new Date(LocalTimetableApi.parseDate(result.endDate));
      nextDay.setDate(nextDay.getDate() + 1);
      to = nextDay.getTime();
    }
    let matching: EasEventItem[] = [];
    let nextStart: number = Number.POSITIVE_INFINITY;
    for (const event of snapshot.events) {
      if (event.type === EasEventType.TAG) continue;
      if (!Number.isFinite(event.from) || !Number.isFinite(event.to) || event.to <= event.from) {
        throw new Error('Invalid saved event time');
      }
      if (event.from >= to || event.to <= from) continue;
      if (query.teachingWeek > 0 && timetable.getWeekNumber(event.from) !== query.teachingWeek) continue;
      if (query.dayOfWeek > 0 && EasTimetable.dowOfMs(event.from) !== query.dayOfWeek) continue;
      if (query.queryMode === 'upcomingExams') {
        if (event.type !== EasEventType.EXAM || event.to <= now) continue;
      } else if (query.queryMode !== 'range') {
        if (event.type !== EasEventType.CLASS) continue;
        if (query.queryMode === 'nextClass') {
          if (event.from <= now) continue;
          nextStart = Math.min(nextStart, event.from);
        } else if (event.from > now || event.to <= now) {
          continue;
        }
      }
      matching.push(event);
    }
    if (query.queryMode === 'nextClass') {
      matching = matching.filter((event: EasEventItem): boolean => event.from === nextStart);
    }
    hilog.info(0x0000, 'HitaQuery',
      'filter mode=%{public}s week=%{public}d weekday=%{public}d from=%{public}s to=%{public}s offset=%{public}d limit=%{public}d matches=%{public}d',
      query.queryMode, query.teachingWeek, query.dayOfWeek, result.startDate, result.endDate,
      query.offset, query.limit, matching.length);
    result.total = matching.length;
    const page: EasEventItem[] = matching.slice(query.offset, query.offset + query.limit);
    result.courses = page.map((event: EasEventItem): TimetableCourseData =>
      LocalTimetableApi.course(event, timetable));
    result.returned = result.courses.length;
    result.hasMore = query.offset + result.returned < result.total;
    result.nextOffset = result.hasMore ? query.offset + result.returned : -1;
    result.isComplete = query.offset === 0 && !result.hasMore;
    result.message = result.total === 0 ? '查询成功，所选范围内没有已保存的课程或考试' :
      (result.hasMore ? '查询成功，仍有记录，请使用 nextOffset 继续获取' : '查询成功');
    return response;
  }

  private static course(event: EasEventItem, timetable: EasTimetable): TimetableCourseData {
    const value: TimetableCourseData = new TimetableCourseData();
    value.id = event.id;
    value.subjectId = event.subjectId;
    value.timetableId = event.timetableId;
    value.type = event.type;
    value.name = event.name;
    value.teacher = event.teacher;
    value.place = event.place;
    value.startTime = LocalTimetableApi.dateTime(event.from);
    value.endTime = LocalTimetableApi.dateTime(event.to);
    value.startTimestamp = event.from;
    value.endTimestamp = event.to;
    value.dayOfWeek = new Date(event.from).getDay() || 7;
    value.teachingWeek = timetable.getWeekNumber(event.from);
    value.firstPeriod = event.fromNumber;
    value.lastPeriod = event.lastNumber;
    return value;
  }

  private static setClock(result: TimetableQueryData, now: number): void {
    result.currentTime = LocalTimetableApi.dateTime(now);
    try { result.timeZone = i18n.getTimeZone().getID(); }
    catch (_) { result.timeZone = 'UTC' + LocalTimetableApi.offsetText(now); }
  }

  private static pad(value: number): string {
    return value.toString().padStart(2, '0');
  }

  private static offsetText(timestamp: number): string {
    const offset: number = -new Date(timestamp).getTimezoneOffset();
    return (offset < 0 ? '-' : '+') + LocalTimetableApi.pad(Math.floor(Math.abs(offset) / 60)) + ':' +
      LocalTimetableApi.pad(Math.abs(offset) % 60);
  }

  private static dateTime(timestamp: number): string {
    const date: Date = new Date(timestamp);
    return date.getFullYear().toString().padStart(4, '0') + '-' + LocalTimetableApi.pad(date.getMonth() + 1) + '-' +
      LocalTimetableApi.pad(date.getDate()) + 'T' + LocalTimetableApi.pad(date.getHours()) + ':' +
      LocalTimetableApi.pad(date.getMinutes()) + ':' + LocalTimetableApi.pad(date.getSeconds()) +
      LocalTimetableApi.offsetText(timestamp);
  }
}
