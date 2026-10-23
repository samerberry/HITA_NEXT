/**
 * TimetableModels.ets - local timetable/event domain models ported from HITA_X
 * (Timetable/TimeInDay/TimePeriodInDay/TermSubject/EventItem/SubjectColor).
 * Time values are epoch-ms numbers. Enums stored as name strings in RDB.
 */

export const DAY_MILLIS: number = 24 * 60 * 60 * 1000;
export const WEEK_MILLIS: number = 7 * DAY_MILLIS;

/** 生成简易 id（原 UUID；ArkTS 侧以 时间戳+随机 兜底，后续可换 UUID Kit）。 */
export function newId(): string {
  return Date.now().toString(36) + '-' + Math.floor(Math.random() * 0x7fffffff).toString(36);
}

/** 科目类型（TermSubject.TYPE）。 */
export enum EasSubjectType {
  COM_A = 'COM_A',   // 必修-考试
  COM_B = 'COM_B',   // 必修-考察
  OPT_A = 'OPT_A',   // 选修-专选
  OPT_B = 'OPT_B',   // 选修-任选
  MOOC = 'MOOC',     // 慕课
  TAG = 'TAG'
}

/** 事件类型（EventItem.TYPE）。 */
export enum EasEventType {
  CLASS = 'CLASS',
  EXAM = 'EXAM',
  OTHER = 'OTHER',
  TAG = 'TAG'
}

/** 一天内时刻（TimeInDay.kt 直迁）。 */
export class EasTimeInDay {
  hour: number = 0;
  minute: number = 0;

  constructor(h: number, m: number) {
    this.hour = h;
    this.minute = m;
  }

  /** 由 ms 时间戳取本地时刻。 */
  static fromTimestamp(ts: number): EasTimeInDay {
    const d: Date = new Date(ts);
    return new EasTimeInDay(d.getHours(), d.getMinutes());
  }

  toString(): string {
    if (this.minute === 0) {
      return this.hour.toString() + ':00';
    }
    return this.hour.toString() + ':' + (this.minute < 10 ? '0' : '') + this.minute.toString();
  }

  compareTo(o: EasTimeInDay): number {
    return this.hour === o.hour ? this.minute - o.minute : this.hour - o.hour;
  }

  before(timeInDay: EasTimeInDay): boolean {
    return this.compareTo(timeInDay) < 0;
  }

  after(timeInDay: EasTimeInDay): boolean {
    return this.compareTo(timeInDay) >= 0;
  }

  /** 距离另一时刻的分钟数。 */
  distanceInMinutes(hour: number, minute: number): number {
    return (hour - this.hour) * 60 + minute - this.minute;
  }

  getAdded(minutes: number): EasTimeInDay {
    let m: number = this.minute + minutes;
    let h: number = this.hour + Math.floor(m / 60);
    m = ((m % 60) + 60) % 60;
    return new EasTimeInDay(h, m);
  }

  toMills(): number {
    return (this.hour * 60 * 60 * 1000 + this.minute * 60 * 1000);
  }

  equals(o: EasTimeInDay | undefined): boolean {
    return o !== undefined && o !== null && this.hour === o.hour && this.minute === o.minute;
  }
}

/** 时间段（TimePeriodInDay.kt 直迁；构造时拷贝）。 */
export class EasTimePeriodInDay {
  from: EasTimeInDay = new EasTimeInDay(0, 0);
  to: EasTimeInDay = new EasTimeInDay(0, 0);

  constructor(f: EasTimeInDay, t: EasTimeInDay) {
    this.from = f.getAdded(0);
    this.to = t.getAdded(0);
  }

  static ofHour(fh: number, fm: number, th: number, tm: number): EasTimePeriodInDay {
    return new EasTimePeriodInDay(new EasTimeInDay(fh, fm), new EasTimeInDay(th, tm));
  }

  getLengthInMinutes(): number {
    return this.from.distanceInMinutes(this.to.hour, this.to.minute);
  }

  toString(): string {
    return this.from.toString() + '-' + this.to.toString();
  }

  /** 拷贝。 */
  clone(): EasTimePeriodInDay {
    return new EasTimePeriodInDay(this.from, this.to);
  }

  contains(tm: EasTimeInDay): boolean {
    return (this.from.before(tm) && tm.before(this.to)) || tm.equals(this.from) || tm.equals(this.to);
  }

  /** 是否包含某 ms 时刻（严格在开区间内，对应原 contains(ts)：from.before && t.before(to)）。 */
  containsTimestamp(ts: number): boolean {
    const t: EasTimeInDay = EasTimeInDay.fromTimestamp(ts);
    return this.from.before(t) && t.before(this.to);
  }
}

/** 课表（Timetable.kt 直迁；scheduleStructure 以 JSON 落库）。 */
export class EasTimetable {
  id: string = newId();
  name: string = '';
  code: string = '';
  startTime: number = 0;
  endTime: number = 0;
  createdAt: number = Date.now();
  scheduleStructure: EasTimePeriodInDay[] = EasTimetable.getDefaultTimeStructure();

  /** 某时间戳对应第几周（周一0点为界；超出学期末返回 -1）。 */
  getWeekNumber(ts: number): number {
    const mondayMs: number = EasTimetable.mondayMsOf(ts);
    if (mondayMs > this.endTime) {
      return -1;
    }
    const x: number = Math.round((mondayMs - this.startTime) / WEEK_MILLIS);
    return x < 0 ? -1 : x + 1;
  }

  /** 第 week 周、dow（周一=1）的第 start..end 节 起止 ms。 */
  getTimestamps(week: number, dow: number, start: number, end: number): number[] {
    const startOfDay: number = this.startTime +
      (week - 1) * WEEK_MILLIS + (dow - 1) * DAY_MILLIS;
    const fromPeriod: EasTimePeriodInDay = this.scheduleStructure[start - 1];
    const toPeriod: EasTimePeriodInDay = this.scheduleStructure[end - 1];
    return [startOfDay + fromPeriod.from.toMills(), startOfDay + toPeriod.to.toMills()];
  }

  transformTimePeriod(start: number, end: number): EasTimePeriodInDay {
    return new EasTimePeriodInDay(this.scheduleStructure[start - 1].from,
      this.scheduleStructure[end - 1].to);
  }

  /** 由时间段反查节次区间 (start节, end节)。 */
  transformCourseNumber(period: EasTimePeriodInDay): number[] {
    let start: number = 0;
    let end: number = 0;
    for (let i = 0; i < this.scheduleStructure.length; i++) {
      if (this.scheduleStructure[i].contains(period.from)) {
        start = i;
      }
      if (this.scheduleStructure[i].contains(period.to)) {
        end = i;
      }
    }
    return [start + 1, end + 1];
  }

  setScheduleStructure(tp: EasTimePeriodInDay, position: number): void {
    if (position < this.scheduleStructure.length) {
      const target: EasTimePeriodInDay = this.scheduleStructure[position];
      target.from = tp.from.getAdded(0);
      target.to = tp.to.getAdded(0);
    }
  }

  static getDefaultTimeStructure(): EasTimePeriodInDay[] {
    const res: EasTimePeriodInDay[] = [];
    res.push(EasTimePeriodInDay.ofHour(8, 30, 9, 20));
    res.push(EasTimePeriodInDay.ofHour(9, 25, 10, 15));
    res.push(EasTimePeriodInDay.ofHour(10, 30, 11, 20));
    res.push(EasTimePeriodInDay.ofHour(11, 25, 12, 15));
    res.push(EasTimePeriodInDay.ofHour(14, 0, 14, 50));
    res.push(EasTimePeriodInDay.ofHour(14, 55, 15, 45));
    res.push(EasTimePeriodInDay.ofHour(16, 0, 16, 50));
    res.push(EasTimePeriodInDay.ofHour(16, 55, 17, 45));
    res.push(EasTimePeriodInDay.ofHour(18, 45, 19, 35));
    res.push(EasTimePeriodInDay.ofHour(19, 40, 20, 30));
    res.push(EasTimePeriodInDay.ofHour(20, 45, 21, 35));
    res.push(EasTimePeriodInDay.ofHour(21, 40, 22, 30));
    return res;
  }

  /** 本部本科作息，与安卓端 CampusDefaultSchedule 的本部表一致。 */
  static getBenbuTimeStructure(): EasTimePeriodInDay[] {
    return [
      EasTimePeriodInDay.ofHour(8, 0, 8, 50),
      EasTimePeriodInDay.ofHour(8, 55, 9, 45),
      EasTimePeriodInDay.ofHour(10, 0, 10, 50),
      EasTimePeriodInDay.ofHour(10, 55, 11, 45),
      EasTimePeriodInDay.ofHour(13, 45, 14, 35),
      EasTimePeriodInDay.ofHour(14, 40, 15, 30),
      EasTimePeriodInDay.ofHour(15, 45, 16, 35),
      EasTimePeriodInDay.ofHour(16, 40, 17, 30),
      EasTimePeriodInDay.ofHour(18, 30, 19, 20),
      EasTimePeriodInDay.ofHour(19, 25, 20, 15),
      EasTimePeriodInDay.ofHour(20, 30, 21, 20),
      EasTimePeriodInDay.ofHour(21, 25, 22, 15)
    ];
  }

  /** 威海校区作息（与安卓端 WeihaiEASWebSource 保持一致）。 */
  static getWeihaiTimeStructure(): EasTimePeriodInDay[] {
    const res: EasTimePeriodInDay[] = [];
    res.push(EasTimePeriodInDay.ofHour(8, 0, 8, 45));
    res.push(EasTimePeriodInDay.ofHour(9, 0, 9, 45));
    res.push(EasTimePeriodInDay.ofHour(10, 5, 10, 50));
    res.push(EasTimePeriodInDay.ofHour(11, 5, 11, 50));
    res.push(EasTimePeriodInDay.ofHour(14, 0, 14, 45));
    res.push(EasTimePeriodInDay.ofHour(15, 0, 15, 45));
    res.push(EasTimePeriodInDay.ofHour(16, 5, 16, 50));
    res.push(EasTimePeriodInDay.ofHour(17, 5, 17, 50));
    res.push(EasTimePeriodInDay.ofHour(18, 40, 19, 25));
    res.push(EasTimePeriodInDay.ofHour(19, 40, 20, 25));
    res.push(EasTimePeriodInDay.ofHour(20, 45, 21, 30));
    res.push(EasTimePeriodInDay.ofHour(21, 45, 22, 30));
    return res;
  }

  /** 某 ms 所在周的周一 0 点。 */
  static mondayMsOf(ts: number): number {
    const d: Date = new Date(ts);
    d.setHours(0, 0, 0, 0);
    const dow: number = EasTimetable.dowOfMs(d.getTime());
    return d.getTime() - (dow - 1) * DAY_MILLIS;
  }

  /** 星期几：周一=1 … 周日=7（对应 TimeTools.getDow）。 */
  static dowOfMs(ts: number): number {
    const d: Date = new Date(ts);
    const wd: number = d.getDay(); // 0=Sun
    return wd === 0 ? 7 : wd;
  }

  /** 结构 JSON 编解码（落库）。 */
  static encodeStructure(structure: EasTimePeriodInDay[]): string {
    const arr: Array<Record<string, number>> = [];
    for (let i = 0; i < structure.length; i++) {
      arr.push({
        'fh': structure[i].from.hour,
        'fm': structure[i].from.minute,
        'th': structure[i].to.hour,
        'tm': structure[i].to.minute
      });
    }
    return JSON.stringify(arr);
  }

  static decodeStructure(raw: string): EasTimePeriodInDay[] {
    const out: EasTimePeriodInDay[] = [];
    if (raw === undefined || raw === null || raw.length === 0) {
      return EasTimetable.getDefaultTimeStructure();
    }
    try {
      const arr: Array<Record<string, Object>> = JSON.parse(raw) as Array<Record<string, Object>>;
      for (let i = 0; i < arr.length; i++) {
        const it: Record<string, Object> = arr[i];
        const num = (k: string): number => {
          const v = it[k];
          return v === undefined || v === null ? 0 : Number(v);
        };
        out.push(EasTimePeriodInDay.ofHour(num('fh'), num('fm'), num('th'), num('tm')));
      }
    } catch (e) {
      return EasTimetable.getDefaultTimeStructure();
    }
    return out;
  }
}

/** 科目（TermSubject.kt 直迁；color 为 ARGB int）。 */
export class EasTermSubject {
  id: string = newId();
  name: string = '';
  timetableId: string = '';
  type: EasSubjectType = EasSubjectType.COM_A;
  field: string = '';
  credit: number = 0;
  school: string = '';
  countInSPA: boolean = false;
  code: string = '';
  key: string = '';
  createdAt: number = Date.now();
  color: number = EasTermSubject.randomMaterialColor();

  /** Material 色板随机取色（ColorTools.randomColorMaterial 语义：队列轮换近似）。 */
  static randomMaterialColor(): number {
    const palette: number[] = [0xFFE57373, 0xFFF06292, 0xFFBA68C8, 0xFF9575CD, 0xFF7986CB,
      0xFF64B5F6, 0xFF4FC3F7, 0xFF4DD0E1, 0xFF4DB6AC, 0xFF81C784,
      0xFFAED581, 0xFFFFB74D, 0xFFFF8A65, 0xFFA1887F, 0xFF90A4AE];
    return palette[Math.floor(Math.random() * palette.length)];
  }
}

/** 事件/课程实例（EventItem.kt 直迁）。 */
/** 上次导入或更新时教务端的一节课：名称与起止时间定位课次，signature 记录会单独变化的字段。 */
export class EasImportBaseEntry {
  name: string = '';
  from: number = 0;
  to: number = 0;
  signature: string = '';

  constructor(name: string, from: number, to: number, signature: string) {
    this.name = name;
    this.from = from;
    this.to = to;
    this.signature = signature;
  }
}

export class EasEventItem {
  id: string = newId();
  type: EasEventType = EasEventType.CLASS;
  name: string = 'NULL';
  place: string = '';
  teacher: string = '';
  subjectId: string = '';
  timetableId: string = '';
  from: number = 0;
  to: number = 0;
  fromNumber: number = 0;
  lastNumber: number = 0;
  createdAt: number = Date.now();
  /** 课程颜色由科目填充；考试颜色按事件保存，0 表示使用默认颜色。 */
  color: number = 0;

  static getTagInstance(name: string): EasEventItem {
    const result: EasEventItem = new EasEventItem();
    result.type = EasEventType.TAG;
    result.name = name;
    return result;
  }

  /** 距开始时间的分钟差（abs）。 */
  getFromTimeDistance(): number {
    return Math.round(Math.abs(this.from - Date.now()) / 60000);
  }

  getDurationInMinutes(): number {
    return Math.round((this.to - this.from) / 60000);
  }

  /** 星期几（周一=1）。 */
  getDow(): number {
    return EasTimetable.dowOfMs(this.from);
  }

  containsTimestamp(ts: number): boolean {
    return this.from < ts && this.to > ts;
  }

  /** 某时间戳在事件中的进度 0..1。 */
  getProgress(ts: number): number {
    if (ts < this.from) {
      return 0;
    }
    if (ts > this.to) {
      return 1;
    }
    if (this.to === this.from) {
      return 1;
    }
    return (ts - this.from) / (this.to - this.from);
  }
}

/** 科目颜色投影（SubjectColor.kt）。 */
export class EasSubjectColor {
  id: string = '';
  color: number = 0;
}
