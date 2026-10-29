/**
 * AssistantService.ets — 「助手」栏的问答逻辑（对应 HITA AI 助手）。
 *
 * 课表类问题（今天/明天/周几/第几周/下一节/考试/课程/老师）直接查本地课表数据库，
 * 保证结果准确且离线可用；其余问题在配置了 API Key 时转给云端大模型，并把课表
 * 摘要放进系统提示，让模型回答时有据可依。
 */
import { common } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { RdbHelper } from '../../common/db/RdbHelper';
import {
  DAY_MILLIS,
  WEEK_MILLIS,
  EasEventItem,
  EasEventType,
  EasTimetable,
  newId
} from '../../common/model/timetable/TimetableModels';
import { DOW_FULL, EasTimeTools } from '../../common/util/EasTimeTools';
import { TimetableResolver } from '../timetable/data/TimetableResolver';
import { TimetableSelectionStore } from '../timetable/data/TimetableSelectionStore';
import { AssistantProvider, AssistantSettings } from './AssistantSettingsStore';

export enum AssistantRole {
  USER = 'user',
  ASSISTANT = 'assistant'
}

export class AssistantMessage {
  id: string = newId();
  role: AssistantRole = AssistantRole.ASSISTANT;
  content: string = '';
  /** 回答来源标注，如「本地课表」「DeepSeek」。 */
  source: string = '';

  static of(role: AssistantRole, content: string, source: string = ''): AssistantMessage {
    const message: AssistantMessage = new AssistantMessage();
    message.role = role;
    message.content = content;
    message.source = source;
    return message;
  }
}

class TimetableSnapshot {
  timetable: EasTimetable | undefined = undefined;
  events: EasEventItem[] = [];
}

class LlmMessage {
  role: string;
  content: string;

  constructor(role: string, content: string) {
    this.role = role;
    this.content = content;
  }
}

class LlmPayload {
  model: string = '';
  messages: LlmMessage[] = [];
  temperature: number = 0.4;
  stream: boolean = false;
}

const LOCAL_SOURCE: string = '本地课表';
const CN_DIGITS: string = '零一二三四五六七八九';

export class AssistantService {
  static readonly SUGGESTIONS: string[] = ['今天有什么课', '明天的课', '下一节课是什么', '现在第几周', '本周课表', '最近的考试'];

  static welcome(): AssistantMessage {
    const message: AssistantMessage = AssistantMessage.of(AssistantRole.ASSISTANT,
      '你好，我是 HITA 助手。可以问我课表相关的问题，比如“明天有什么课”“第三周周五的课”“下一节课在哪”“军事理论什么时候上”。\n' +
        '在右上角设置中填写 DeepSeek 或智谱的 API Key 后，还能回答更开放的校园问题。');
    message.id = 'welcome';
    return message;
  }

  static async reply(context: common.Context, settings: AssistantSettings, history: AssistantMessage[],
    text: string): Promise<AssistantMessage> {
    const snapshot: TimetableSnapshot = await AssistantService.loadSnapshot(context);
    const local: string | undefined = AssistantService.answerLocally(snapshot, text, Date.now());
    if (local !== undefined) {
      return AssistantMessage.of(AssistantRole.ASSISTANT, local, LOCAL_SOURCE);
    }
    if (settings.hasCloudModel()) {
      return await AssistantService.askCloud(settings, snapshot, history, text);
    }
    return AssistantMessage.of(AssistantRole.ASSISTANT,
      '这个问题我暂时只能回答课表相关的内容。可以试试：\n' +
        '· 今天 / 明天 / 周三有什么课\n· 第三周周五的课\n· 下一节课在哪\n· 现在第几周\n· 最近的考试\n· 某门课或某位老师的上课安排\n\n' +
        '如需回答更开放的问题，请点右上角设置填写大模型 API Key。');
  }

  // ------------------------------------------------------------------
  // 数据
  // ------------------------------------------------------------------

  private static async loadSnapshot(context: common.Context): Promise<TimetableSnapshot> {
    const snapshot: TimetableSnapshot = new TimetableSnapshot();
    const rdb: RdbHelper = RdbHelper.getInstance();
    await rdb.init(context);
    const selection: TimetableSelectionStore = TimetableSelectionStore.getInstance();
    await selection.init(context);
    const selectedId: string = await selection.load();
    let timetable: EasTimetable | undefined = selectedId.length > 0 ? await rdb.getTimetableById(selectedId) : undefined;
    if (timetable === undefined) {
      timetable = await TimetableResolver.getForDisplay(rdb);
    }
    snapshot.timetable = timetable;
    const events: EasEventItem[] = timetable === undefined ? [] : await rdb.getEventsOfTimetable(timetable.id);
    const standalone: EasEventItem[] = await rdb.getEventsOfTimetable('');
    snapshot.events = AssistantService.mergeDuplicates(events.concat(standalone));
    return snapshot;
  }

  /** 同名同时段的课次（多位教师/多个教室）合并为一条，教师与地点拼接展示。 */
  private static mergeDuplicates(events: EasEventItem[]): EasEventItem[] {
    const byKey: Map<string, EasEventItem> = new Map<string, EasEventItem>();
    const out: EasEventItem[] = [];
    for (let i: number = 0; i < events.length; i++) {
      const event: EasEventItem = events[i];
      const key: string = event.name + '|' + event.from.toString() + '|' + event.to.toString();
      const existing: EasEventItem | undefined = byKey.get(key);
      if (existing === undefined) {
        byKey.set(key, event);
        out.push(event);
        continue;
      }
      existing.teacher = AssistantService.joinDistinct(existing.teacher, event.teacher);
      existing.place = AssistantService.joinDistinct(existing.place, event.place);
    }
    out.sort((a: EasEventItem, b: EasEventItem): number => a.from - b.from);
    return out;
  }

  private static joinDistinct(current: string, extra: string): string {
    const value: string = extra.trim();
    if (value.length === 0 || current.split('/').indexOf(value) >= 0) {
      return current;
    }
    return current.length > 0 ? current + '/' + value : value;
  }

  // ------------------------------------------------------------------
  // 本地问答
  // ------------------------------------------------------------------

  private static answerLocally(snapshot: TimetableSnapshot, rawText: string, now: number): string | undefined {
    const text: string = rawText.replace(/\s+/g, '');
    if (text.length === 0) {
      return undefined;
    }
    if (snapshot.timetable === undefined && /课|考试|第几周/.test(text)) {
      return '还没有可用的课表。请先在「更多 → 导入课表」从教务系统同步，或在课表管理中手动创建。';
    }
    if (snapshot.timetable === undefined) {
      return undefined;
    }
    const timetable: EasTimetable = snapshot.timetable as EasTimetable;

    if (/考试|考场|期末|期中/.test(text)) {
      return AssistantService.answerExams(snapshot, now);
    }
    if (/下一节|下节课|接下来|待会|一会儿?|马上.*课|现在.*(上什么|什么课)|正在上/.test(text)) {
      return AssistantService.answerNextClass(snapshot, now);
    }
    if (/第几周|哪一?周|几周了|教学周|开学/.test(text) && !/第[0-9一二三四五六七八九十两]+周/.test(text)) {
      return AssistantService.answerWeekNumber(timetable, now);
    }
    const day: number | undefined = AssistantService.resolveDay(timetable, text, now);
    if (day !== undefined) {
      return AssistantService.answerDay(snapshot, day);
    }
    const week: number | undefined = AssistantService.resolveWeek(timetable, text, now);
    if (week !== undefined) {
      return AssistantService.answerWeek(snapshot, week);
    }
    const teacher: string | undefined = AssistantService.answerTeacher(snapshot, text, now);
    if (teacher !== undefined) {
      return teacher;
    }
    const course: string | undefined = AssistantService.answerCourse(snapshot, text, now);
    if (course !== undefined) {
      return course;
    }
    if (/课表|有什么课|有课|几节课|上课/.test(text)) {
      return AssistantService.answerDay(snapshot, AssistantService.dayStart(now));
    }
    return undefined;
  }

  private static dayStart(ts: number): number {
    return new Date(new Date(ts).setHours(0, 0, 0, 0)).getTime();
  }

  private static parseNumber(raw: string): number {
    if (/^\d+$/.test(raw)) {
      return Number(raw);
    }
    const text: string = raw.replace(/两/g, '二');
    if (text === '十') {
      return 10;
    }
    const tenIndex: number = text.indexOf('十');
    if (tenIndex < 0) {
      return CN_DIGITS.indexOf(text);
    }
    const tens: number = tenIndex === 0 ? 1 : CN_DIGITS.indexOf(text.substring(0, tenIndex));
    const ones: number = tenIndex === text.length - 1 ? 0 : CN_DIGITS.indexOf(text.substring(tenIndex + 1));
    return tens < 0 || ones < 0 ? -1 : tens * 10 + ones;
  }

  private static dowOf(raw: string): number {
    if (raw === '日' || raw === '天' || raw === '7') {
      return 7;
    }
    const digit: number = Number(raw);
    if (!isNaN(digit) && digit >= 1 && digit <= 6) {
      return digit;
    }
    return '一二三四五六'.indexOf(raw) + 1;
  }

  /** 解析问题中的具体某一天，返回当天 0 点时间戳。 */
  /**
   * A month/day without a year: the year that puts it inside the term, else the one nearest today.
   * A date that does not exist, such as 2月30日, is not rolled over into the next month.
   */
  private static dateOfMonthDay(timetable: EasTimetable, month: number, day: number, now: number): number | undefined {
    const year: number = new Date(now).getFullYear();
    let best: number | undefined = undefined;
    for (const candidate of [year - 1, year, year + 1]) {
      const date: Date = new Date(candidate, month - 1, day);
      if (date.getMonth() !== month - 1 || date.getDate() !== day) {
        continue;
      }
      const time: number = date.getTime();
      if (time >= EasTimetable.mondayMsOf(timetable.startTime) && time <= timetable.endTime) {
        return time;
      }
      if (best === undefined || Math.abs(time - now) < Math.abs(best - now)) {
        best = time;
      }
    }
    return best;
  }

  private static resolveDay(timetable: EasTimetable, text: string, now: number): number | undefined {
    const today: number = AssistantService.dayStart(now);
    const termWeekDay: RegExpExecArray | null =
      /第([0-9一二三四五六七八九十两]+)周的?(?:周|星期|礼拜)([一二三四五六日天1-7])/.exec(text);
    if (termWeekDay !== null) {
      const week: number = AssistantService.parseNumber(termWeekDay[1]);
      const dow: number = AssistantService.dowOf(termWeekDay[2]);
      if (week > 0 && dow > 0) {
        return EasTimetable.mondayMsOf(timetable.startTime) + (week - 1) * WEEK_MILLIS + (dow - 1) * DAY_MILLIS;
      }
    }
    const weekDay: RegExpExecArray | null =
      /(下下|下[个一]?|上[个一]?|这[个一]?|本)?(?:周|星期|礼拜)(?:的?(?:周|星期|礼拜))?([一二三四五六日天1-7])/.exec(text);
    if (weekDay !== null) {
      const dow: number = AssistantService.dowOf(weekDay[2]);
      const prefix: string = weekDay[1] === undefined ? '' : weekDay[1];
      let offset: number = 0;
      if (prefix === '下下') {
        offset = 2;
      } else if (prefix.startsWith('下')) {
        offset = 1;
      } else if (prefix.startsWith('上')) {
        offset = -1;
      }
      if (dow > 0) {
        return EasTimetable.mondayMsOf(now) + offset * WEEK_MILLIS + (dow - 1) * DAY_MILLIS;
      }
    }
    const monthDay: RegExpExecArray | null = /(\d{1,2})月(\d{1,2})[日号]?/.exec(text);
    if (monthDay !== null) {
      return AssistantService.dateOfMonthDay(timetable, Number(monthDay[1]), Number(monthDay[2]), now);
    }
    const relative: string[] = ['大后天', '后天', '明天', '明日', '今天', '今日', '今晚', '昨天', '前天'];
    const offsets: number[] = [3, 2, 1, 1, 0, 0, 0, -1, -2];
    for (let i: number = 0; i < relative.length; i++) {
      if (text.indexOf(relative[i]) >= 0) {
        return today + offsets[i] * DAY_MILLIS;
      }
    }
    return undefined;
  }

  /** 解析“第N周 / 本周 / 下周 / 上周”，返回教学周序号。 */
  private static resolveWeek(timetable: EasTimetable, text: string, now: number): number | undefined {
    const explicit: RegExpExecArray | null = /第([0-9一二三四五六七八九十两]+)周/.exec(text);
    if (explicit !== null) {
      const week: number = AssistantService.parseNumber(explicit[1]);
      return week > 0 ? week : undefined;
    }
    const current: number = AssistantService.weekIndex(timetable, now);
    if (/下下周/.test(text)) {
      return current + 2;
    }
    if (/下[个一]?(?:周|星期|礼拜)/.test(text)) {
      return current + 1;
    }
    if (/上[个一]?(?:周|星期|礼拜)/.test(text)) {
      return current - 1;
    }
    if (/本周|这周|这个?星期|这个?礼拜|周课表|一周/.test(text)) {
      return current;
    }
    return undefined;
  }

  /** 不受学期边界截断的周序号（开学前为 0 或负数）。 */
  private static weekIndex(timetable: EasTimetable, ts: number): number {
    return Math.round((EasTimetable.mondayMsOf(ts) - EasTimetable.mondayMsOf(timetable.startTime)) / WEEK_MILLIS) + 1;
  }

  private static dayLabel(timetable: EasTimetable, dayStart: number): string {
    const date: Date = new Date(dayStart);
    const relative: string = EasTimeTools.relativeDayTag(dayStart);
    const week: number = AssistantService.weekIndex(timetable, dayStart);
    return (relative.length > 0 && relative !== '大后天' ? relative + ' ' : '') +
      (date.getMonth() + 1).toString() + '月' + date.getDate().toString() + '日 ' +
      DOW_FULL[EasTimeTools.getDow(dayStart)] + (week > 0 ? '（第' + week.toString() + '周）' : '');
  }

  private static eventLine(event: EasEventItem): string {
    let line: string = EasTimeTools.printTime(event.from) + '-' + EasTimeTools.printTime(event.to) + '  ' + event.name;
    if (event.type === EasEventType.EXAM) {
      line += '【考试】';
    }
    if (event.place.trim().length > 0) {
      line += ' @ ' + event.place.trim();
    }
    if (event.teacher.trim().length > 0) {
      line += '（' + event.teacher.trim() + '）';
    }
    return line;
  }

  private static eventsBetween(snapshot: TimetableSnapshot, from: number, to: number): EasEventItem[] {
    return snapshot.events.filter((event: EasEventItem): boolean => event.from >= from && event.from < to);
  }

  private static answerDay(snapshot: TimetableSnapshot, dayStart: number): string {
    const timetable: EasTimetable = snapshot.timetable as EasTimetable;
    const events: EasEventItem[] = AssistantService.eventsBetween(snapshot, dayStart, dayStart + DAY_MILLIS);
    const label: string = AssistantService.dayLabel(timetable, dayStart);
    if (events.length === 0) {
      return label + '没有课程或日程安排。';
    }
    const lines: string[] = events.map((event: EasEventItem): string => '· ' + AssistantService.eventLine(event));
    return label + '共 ' + events.length.toString() + ' 项安排：\n' + lines.join('\n');
  }

  private static answerWeek(snapshot: TimetableSnapshot, week: number): string {
    const timetable: EasTimetable = snapshot.timetable as EasTimetable;
    const monday: number = EasTimetable.mondayMsOf(timetable.startTime) + (week - 1) * WEEK_MILLIS;
    const sunday: Date = new Date(monday + 6 * DAY_MILLIS);
    const mondayDate: Date = new Date(monday);
    const header: string = '第' + week.toString() + '周（' + (mondayDate.getMonth() + 1).toString() + '/' +
      mondayDate.getDate().toString() + ' - ' + (sunday.getMonth() + 1).toString() + '/' + sunday.getDate().toString() + '）';
    const lines: string[] = [];
    let total: number = 0;
    for (let d: number = 0; d < 7; d++) {
      const dayStart: number = monday + d * DAY_MILLIS;
      const events: EasEventItem[] = AssistantService.eventsBetween(snapshot, dayStart, dayStart + DAY_MILLIS);
      if (events.length === 0) {
        continue;
      }
      total += events.length;
      const items: string[] = events.map((event: EasEventItem): string =>
        EasTimeTools.printTime(event.from) + ' ' + event.name);
      lines.push(DOW_FULL[d + 1] + '：' + items.join('，'));
    }
    if (total === 0) {
      return header + '没有课程安排。';
    }
    return header + '共 ' + total.toString() + ' 项安排：\n' + lines.join('\n');
  }

  private static answerWeekNumber(timetable: EasTimetable, now: number): string {
    const start: Date = new Date(EasTimetable.mondayMsOf(timetable.startTime));
    const startText: string = start.getFullYear().toString() + '年' + (start.getMonth() + 1).toString() + '月' +
      start.getDate().toString() + '日';
    const week: number = AssistantService.weekIndex(timetable, now);
    if (week < 1) {
      const days: number = Math.ceil((start.getTime() - AssistantService.dayStart(now)) / DAY_MILLIS);
      return '「' + timetable.name + '」还没开学，开学日期是 ' + startText + '，还有 ' + days.toString() + ' 天。';
    }
    if (now > timetable.endTime) {
      return '「' + timetable.name + '」已经结束（开学日期 ' + startText + '）。';
    }
    return '今天是' + DOW_FULL[EasTimeTools.getDow(now)] + '，第 ' + week.toString() + ' 周。\n「' +
      timetable.name + '」开学日期：' + startText + '。';
  }

  private static answerNextClass(snapshot: TimetableSnapshot, now: number): string {
    const parts: string[] = [];
    const lessons: EasEventItem[] = snapshot.events.filter((event: EasEventItem): boolean =>
      event.type === EasEventType.CLASS || event.type === EasEventType.EXAM);
    for (let i: number = 0; i < lessons.length; i++) {
      if (lessons[i].from <= now && lessons[i].to > now) {
        parts.push('正在进行：' + AssistantService.eventLine(lessons[i]));
        break;
      }
    }
    for (let i: number = 0; i < lessons.length; i++) {
      if (lessons[i].from > now) {
        const event: EasEventItem = lessons[i];
        const minutes: number = Math.ceil((event.from - now) / 60000);
        let wait: string = minutes.toString() + ' 分钟后';
        if (minutes >= 24 * 60) {
          wait = AssistantService.dayLabel(snapshot.timetable as EasTimetable, AssistantService.dayStart(event.from));
        } else if (minutes >= 60) {
          wait = Math.floor(minutes / 60).toString() + ' 小时 ' + (minutes % 60).toString() + ' 分钟后';
        }
        parts.push('下一节（' + wait + '）：' + AssistantService.eventLine(event));
        break;
      }
    }
    return parts.length === 0 ? '本学期后面已经没有课程了。' : parts.join('\n');
  }

  private static answerExams(snapshot: TimetableSnapshot, now: number): string {
    const today: number = AssistantService.dayStart(now);
    const exams: EasEventItem[] = snapshot.events.filter((event: EasEventItem): boolean =>
      event.type === EasEventType.EXAM && event.to >= today);
    if (exams.length === 0) {
      return '课表里没有即将到来的考试。考试安排可以在「更多 → 考试」中从教务系统查询。';
    }
    const lines: string[] = exams.slice(0, 10).map((event: EasEventItem): string =>
      '· ' + EasTimeTools.printDate(event.from) + ' ' + DOW_FULL[EasTimeTools.getDow(event.from)] + ' ' +
        AssistantService.eventLine(event));
    return '接下来的考试：\n' + lines.join('\n');
  }

  private static answerTeacher(snapshot: TimetableSnapshot, text: string, now: number): string | undefined {
    const teachers: Set<string> = new Set<string>();
    for (let i: number = 0; i < snapshot.events.length; i++) {
      const names: string[] = snapshot.events[i].teacher.split(/[\/,，、\s]+/);
      for (let j: number = 0; j < names.length; j++) {
        if (names[j].trim().length >= 2) {
          teachers.add(names[j].trim());
        }
      }
    }
    let matched: string = '';
    teachers.forEach((name: string) => {
      if (text.indexOf(name) >= 0 && name.length > matched.length) {
        matched = name;
      }
    });
    if (matched.length === 0) {
      return undefined;
    }
    const courses: Map<string, number> = new Map<string, number>();
    let next: EasEventItem | undefined = undefined;
    for (let i: number = 0; i < snapshot.events.length; i++) {
      const event: EasEventItem = snapshot.events[i];
      if (event.teacher.indexOf(matched) < 0) {
        continue;
      }
      courses.set(event.name, (courses.get(event.name) ?? 0) + 1);
      if (next === undefined && event.from > now) {
        next = event;
      }
    }
    const lines: string[] = [];
    courses.forEach((count: number, name: string) => {
      lines.push('· ' + name + '（共 ' + count.toString() + ' 次）');
    });
    let answer: string = matched + ' 老师在你的课表中教授：\n' + lines.join('\n');
    if (next !== undefined) {
      const event: EasEventItem = next as EasEventItem;
      answer += '\n\n下一次：' + EasTimeTools.printDate(event.from) + ' ' + DOW_FULL[EasTimeTools.getDow(event.from)] +
        ' ' + AssistantService.eventLine(event);
    }
    return answer;
  }

  private static answerCourse(snapshot: TimetableSnapshot, text: string, now: number): string | undefined {
    const query: string = text.replace(/[？?。！!，,]/g, '')
      .replace(/什么时候|在哪里?上?|哪里|哪个教室|教室|几点|上课|的课|课程|查询?|一下|帮我|请问|是谁|老师|还有几次|几次/g, '');
    const names: Set<string> = new Set<string>();
    for (let i: number = 0; i < snapshot.events.length; i++) {
      const name: string = snapshot.events[i].name.trim();
      if (name.length > 0 && name !== 'NULL') {
        names.add(name);
      }
    }
    let mentioned: string = '';
    let partial: string = '';
    names.forEach((name: string) => {
      if (text.indexOf(name) >= 0) {
        if (name.length > mentioned.length) {
          mentioned = name;
        }
      } else if (query.length >= 2 && name.indexOf(query) >= 0 &&
        (partial.length === 0 || name.length < partial.length)) {
        partial = name;
      }
    });
    const matched: string = mentioned.length > 0 ? mentioned : partial;
    if (matched.length === 0) {
      return undefined;
    }
    const sessions: EasEventItem[] = snapshot.events.filter((event: EasEventItem): boolean => event.name.trim() === matched);
    const teachers: Set<string> = new Set<string>();
    const places: Set<string> = new Set<string>();
    const slots: Set<string> = new Set<string>();
    let next: EasEventItem | undefined = undefined;
    let remaining: number = 0;
    for (let i: number = 0; i < sessions.length; i++) {
      const event: EasEventItem = sessions[i];
      event.teacher.split('/').forEach((name: string) => {
        if (name.trim().length > 0) {
          teachers.add(name.trim());
        }
      });
      event.place.split('/').forEach((place: string) => {
        if (place.trim().length > 0) {
          places.add(place.trim());
        }
      });
      slots.add(DOW_FULL[EasTimeTools.getDow(event.from)] + ' ' + EasTimeTools.printTime(event.from) + '-' +
        EasTimeTools.printTime(event.to));
      if (event.from > now) {
        remaining++;
        if (next === undefined) {
          next = event;
        }
      }
    }
    const lines: string[] = ['「' + matched + '」'];
    if (teachers.size > 0) {
      lines.push('老师：' + Array.from(teachers).join('、'));
    }
    if (places.size > 0) {
      lines.push('地点：' + Array.from(places).join('、'));
    }
    lines.push('上课时间：' + Array.from(slots).join('；'));
    lines.push('共 ' + sessions.length.toString() + ' 次，剩余 ' + remaining.toString() + ' 次');
    if (next !== undefined) {
      const event: EasEventItem = next as EasEventItem;
      lines.push('下一次：' + EasTimeTools.printDate(event.from) + ' ' + DOW_FULL[EasTimeTools.getDow(event.from)] + ' ' +
        EasTimeTools.printTime(event.from) + (event.place.length > 0 ? ' @ ' + event.place : ''));
    }
    return lines.join('\n');
  }

  // ------------------------------------------------------------------
  // 云端大模型
  // ------------------------------------------------------------------

  private static systemPrompt(snapshot: TimetableSnapshot, now: number): string {
    const lines: string[] = [
      '你是 HITA 助手，服务哈尔滨工业大学（本部、威海校区、深圳校区）的学生。',
      '请用简洁的中文回答。涉及课表时只依据下面提供的数据，不要编造课程、成绩或考试安排；数据里没有的就如实说明。',
      '当前时间：' + EasTimeTools.printDate(now) + ' ' + DOW_FULL[EasTimeTools.getDow(now)] + ' ' + EasTimeTools.printTime(now)
    ];
    if (snapshot.timetable === undefined) {
      lines.push('用户还没有导入课表。');
      return lines.join('\n');
    }
    const timetable: EasTimetable = snapshot.timetable as EasTimetable;
    lines.push('当前课表：' + timetable.name + '，开学日期 ' + EasTimeTools.printDate(EasTimetable.mondayMsOf(timetable.startTime)) +
      '，今天是第 ' + AssistantService.weekIndex(timetable, now).toString() + ' 周。');
    const today: number = AssistantService.dayStart(now);
    lines.push('未来 7 天的安排：');
    for (let d: number = 0; d < 7; d++) {
      const dayStart: number = today + d * DAY_MILLIS;
      const events: EasEventItem[] = AssistantService.eventsBetween(snapshot, dayStart, dayStart + DAY_MILLIS);
      const items: string = events.length === 0 ? '无' :
        events.map((event: EasEventItem): string => AssistantService.eventLine(event)).join('；');
      lines.push(EasTimeTools.printDate(dayStart) + ' ' + DOW_FULL[EasTimeTools.getDow(dayStart)] + '：' + items);
    }
    return lines.join('\n');
  }

  private static async askCloud(settings: AssistantSettings, snapshot: TimetableSnapshot,
    history: AssistantMessage[], text: string): Promise<AssistantMessage> {
    const zhipu: boolean = settings.provider === AssistantProvider.ZHIPU;
    const source: string = AssistantSettings.providerName(settings.provider);
    const payload: LlmPayload = new LlmPayload();
    payload.model = zhipu ? 'glm-4-flash' : 'deepseek-chat';
    payload.messages.push(new LlmMessage('system', AssistantService.systemPrompt(snapshot, Date.now())));
    const recent: AssistantMessage[] = history.slice(Math.max(0, history.length - 12));
    for (let i: number = 0; i < recent.length; i++) {
      // Timetable questions answered on the device stay there: skip each local answer and the question before it.
      const local: boolean = recent[i].source === LOCAL_SOURCE ||
        (i + 1 < recent.length && recent[i + 1].source === LOCAL_SOURCE);
      if (recent[i].id !== 'welcome' && !local) {
        payload.messages.push(new LlmMessage(recent[i].role.toString(), recent[i].content));
      }
    }
    payload.messages.push(new LlmMessage('user', text));
    const url: string = zhipu ? 'https://open.bigmodel.cn/api/paas/v4/chat/completions' :
      'https://api.deepseek.com/chat/completions';
    const header: Record<string, string> = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ' + settings.apiKey.trim()
    };
    const request: http.HttpRequest = http.createHttp();
    try {
      const resp: http.HttpResponse = await request.request(url, {
        method: http.RequestMethod.POST,
        header: header,
        extraData: JSON.stringify(payload),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 20000,
        readTimeout: 60000,
        usingCache: false
      });
      const body: string = resp.result === undefined || resp.result === null ? '' : String(resp.result);
      if (resp.responseCode === 401 || resp.responseCode === 403) {
        return AssistantMessage.of(AssistantRole.ASSISTANT, source + ' 拒绝了请求：API Key 无效或没有权限，请在设置中检查。', source);
      }
      if (resp.responseCode === 402) {
        return AssistantMessage.of(AssistantRole.ASSISTANT, source + ' 账户余额不足，请充值后再试。', source);
      }
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        return AssistantMessage.of(AssistantRole.ASSISTANT,
          source + ' 暂时无法回答，请稍后再试。', source);
      }
      const content: string = AssistantService.extractContent(body);
      return AssistantMessage.of(AssistantRole.ASSISTANT,
        content.length > 0 ? content : source + ' 没有返回内容，请换个问法再试。', source);
    } catch (e) {
      return AssistantMessage.of(AssistantRole.ASSISTANT, '连接 ' + source + ' 失败，请检查网络后重试。', source);
    } finally {
      request.destroy();
    }
  }

  private static extractContent(body: string): string {
    try {
      const json: Record<string, Object> = JSON.parse(body) as Record<string, Object>;
      const choices: Object[] | undefined = json['choices'] as Object[] | undefined;
      if (choices === undefined || choices.length === 0) {
        return '';
      }
      const message: Record<string, Object> | undefined =
        (choices[0] as Record<string, Object>)['message'] as Record<string, Object> | undefined;
      if (message === undefined || message['content'] === undefined || message['content'] === null) {
        return '';
      }
      return String(message['content']).trim();
    } catch (e) {
      return '';
    }
  }
}
