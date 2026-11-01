/**
 * TimetableIcsImporter.ets — 从 .ics 日历文件导入为一张新的本地课表。
 *
 * 系统文件选择器选取文件 → IcsParser 展开事件 → 新建课表并按课程名建科目；
 * 名称含“考试”的条目写为考试事件。导入后设为当前课表。
 */
import { common } from '@kit.AbilityKit';
import { buffer } from '@kit.ArkTS';
import { fileIo, picker } from '@kit.CoreFileKit';
import { RdbHelper } from '../../../common/db/RdbHelper';
import {
  EasEventItem,
  EasEventType,
  EasSubjectType,
  EasTermSubject,
  EasTimePeriodInDay,
  EasTimetable,
  WEEK_MILLIS
} from '../../../common/model/timetable/TimetableModels';
import { IcsCalendarData, IcsEventInstance, IcsParser } from '../../../common/util/ICSImport';
import { EasCampus } from '../../eas/EasSession';
import { EasTimetableImporter } from '../../eas/EasTimetableImporter';
import { TimetableSelectionStore } from './TimetableSelectionStore';

export class IcsImportResult {
  success: boolean = false;
  message: string = '';
  timetableId: string = '';
  eventCount: number = 0;
}

export class TimetableIcsImporter {
  /** 选择并导入；传入 targetTimetableId 时合并到该课表。用户取消选择时返回 undefined。 */
  static async pickAndImport(context: common.UIAbilityContext,
    targetTimetableId?: string): Promise<IcsImportResult | undefined> {
    const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.fileSuffixFilters = ['日历文件(.ics)|.ics'];
    const uris: string[] = await new picker.DocumentViewPicker(context).select(options);
    if (uris === undefined || uris.length === 0) {
      return undefined;
    }
    const result: IcsImportResult = new IcsImportResult();
    let text: string = '';
    try {
      text = TimetableIcsImporter.readText(uris[0]);
    } catch (e) {
      result.message = '无法读取所选文件';
      return result;
    }
    return await TimetableIcsImporter.importText(context, text, TimetableIcsImporter.fileTitle(uris[0]),
      targetTimetableId);
  }

  static async importText(context: common.Context, text: string, fallbackName: string,
    targetTimetableId?: string): Promise<IcsImportResult> {
    const result: IcsImportResult = new IcsImportResult();
    if (text.indexOf('BEGIN:VCALENDAR') < 0) {
      result.message = '所选文件不是有效的 ICS 日历文件';
      return result;
    }
    const calendar: IcsCalendarData = IcsParser.parse(text);
    const events: IcsEventInstance[] = calendar.events.filter((ev: IcsEventInstance): boolean =>
      ev.summary.length > 0 && ev.to > ev.from);
    if (events.length === 0) {
      result.message = calendar.skippedAllDay > 0 ? '文件中只有全天事件，没有可导入的课程' : '文件中没有可导入的课程';
      return result;
    }
    if (targetTimetableId !== undefined && targetTimetableId.length > 0) {
      return await TimetableIcsImporter.mergeInto(context, targetTimetableId, events);
    }

    const timetable: EasTimetable = new EasTimetable();
    timetable.name = calendar.name.length > 0 ? calendar.name :
      (fallbackName.length > 0 ? fallbackName : 'ICS 导入课表');
    timetable.code = 'ICS:' + timetable.id;
    timetable.startTime = EasTimetable.mondayMsOf(events[0].from);
    timetable.endTime = EasTimetable.mondayMsOf(events[events.length - 1].from) + WEEK_MILLIS - 1;
    timetable.createdAt = Date.now();
    timetable.scheduleStructure = TimetableIcsImporter.bestSchedule(events);

    const rdb: RdbHelper = RdbHelper.getInstance();
    await rdb.init(context);
    const subjects: Map<string, EasTermSubject> = new Map<string, EasTermSubject>();
    const importedEvents: EasEventItem[] = [];
    for (let i: number = 0; i < events.length; i++) {
      const ics: IcsEventInstance = events[i];
      const event: EasEventItem = new EasEventItem();
      event.type = /考试/.test(ics.summary) ? EasEventType.EXAM : EasEventType.CLASS;
      event.name = ics.summary;
      event.place = ics.location;
      event.teacher = TimetableIcsImporter.teacherOf(ics.description);
      event.timetableId = timetable.id;
      event.from = ics.from;
      event.to = ics.to;
      const numbers: number[] = TimetableIcsImporter.periodNumbers(timetable.scheduleStructure, ics);
      event.fromNumber = numbers[0];
      event.lastNumber = numbers[1];
      if (event.type === EasEventType.CLASS) {
        let subject: EasTermSubject | undefined = subjects.get(ics.summary);
        if (subject === undefined) {
          subject = new EasTermSubject();
          subject.timetableId = timetable.id;
          subject.name = ics.summary;
          // ICS 不携带课程性质与考核方式，标记为“其他”，可在课表详情中修改。
          subject.type = EasSubjectType.TAG;
          subject.field = 'ics';
          subjects.set(ics.summary, subject);
        }
        event.subjectId = subject.id;
      }
      importedEvents.push(event);
    }

    await rdb.saveImportedTimetable(timetable, Array.from(subjects.values()), importedEvents, false);
    await TimetableSelectionStore.getInstance().init(context);
    await TimetableSelectionStore.getInstance().save(timetable.id);
    result.success = true;
    result.timetableId = timetable.id;
    result.eventCount = events.length;
    result.message = '已导入 ' + subjects.size.toString() + ' 门课程，共 ' + events.length.toString() + ' 个课次';
    return result;
  }

  /**
   * 合并到已有课表：同名、同起止时间的课次（或考试）换成文件里的地点、教师和节次，其余新增；
   * 课表里其他课程和日程不动，不新建课表，也不改变当前课表。
   */
  private static async mergeInto(context: common.Context, timetableId: string,
    events: IcsEventInstance[]): Promise<IcsImportResult> {
    const result: IcsImportResult = new IcsImportResult();
    const rdb: RdbHelper = RdbHelper.getInstance();
    await rdb.init(context);
    const timetable: EasTimetable | undefined = await rdb.getTimetableById(timetableId, true);
    if (timetable === undefined) {
      result.message = '要合并的课表已不存在';
      return result;
    }
    const local: Map<string, EasEventItem> = new Map<string, EasEventItem>();
    for (const event of await rdb.getEventsOfTimetable(timetableId, true)) {
      const key: string = TimetableIcsImporter.keyOf(event.type, event.name, event.from, event.to);
      if (!local.has(key)) {
        local.set(key, event);
      }
    }
    const subjects: Map<string, EasTermSubject> = new Map<string, EasTermSubject>();
    for (const subject of await rdb.getSubjectsOfTimetable(timetableId)) {
      if (!subjects.has(subject.name)) {
        subjects.set(subject.name, subject);
      }
    }
    const newSubjects: EasTermSubject[] = [];
    const inserts: EasEventItem[] = [];
    const updates: EasEventItem[] = [];
    const handled: Set<string> = new Set<string>();
    let unchanged: number = 0;
    for (const ics of events) {
      const type: EasEventType = /考试/.test(ics.summary) ? EasEventType.EXAM : EasEventType.CLASS;
      const key: string = TimetableIcsImporter.keyOf(type, ics.summary, ics.from, ics.to);
      if (handled.has(key)) {
        continue;
      }
      handled.add(key);
      const numbers: number[] = TimetableIcsImporter.periodNumbers(timetable.scheduleStructure, ics);
      const teacher: string = TimetableIcsImporter.teacherOf(ics.description);
      const before: EasEventItem | undefined = local.get(key);
      if (before !== undefined) {
        if (before.place === ics.location && before.teacher === teacher &&
          before.fromNumber === numbers[0] && before.lastNumber === numbers[1]) {
          unchanged++;
          continue;
        }
        const updated: EasEventItem = new EasEventItem();
        updated.id = before.id;
        updated.type = before.type;
        updated.name = before.name;
        updated.subjectId = before.subjectId;
        updated.timetableId = before.timetableId;
        updated.from = before.from;
        updated.to = before.to;
        updated.createdAt = before.createdAt;
        updated.color = before.color;
        updated.place = ics.location;
        updated.teacher = teacher;
        updated.fromNumber = numbers[0];
        updated.lastNumber = numbers[1];
        updates.push(updated);
        continue;
      }
      const event: EasEventItem = new EasEventItem();
      event.type = type;
      event.name = ics.summary;
      event.place = ics.location;
      event.teacher = teacher;
      event.timetableId = timetableId;
      event.from = ics.from;
      event.to = ics.to;
      event.fromNumber = numbers[0];
      event.lastNumber = numbers[1];
      if (type === EasEventType.CLASS) {
        let subject: EasTermSubject | undefined = subjects.get(ics.summary);
        if (subject === undefined) {
          subject = new EasTermSubject();
          subject.timetableId = timetableId;
          subject.name = ics.summary;
          subject.type = EasSubjectType.TAG;
          subject.field = 'ics';
          subjects.set(ics.summary, subject);
          newSubjects.push(subject);
        }
        event.subjectId = subject.id;
      }
      inserts.push(event);
    }
    if (inserts.length > 0 || updates.length > 0) {
      await rdb.mergeImportedEvents(timetableId, newSubjects, inserts, updates);
    }
    result.success = true;
    result.timetableId = timetableId;
    result.eventCount = inserts.length + updates.length;
    result.message = inserts.length === 0 && updates.length === 0 ? '“' + timetable.name + '”已是文件里的版本' :
      '已合并到“' + timetable.name + '”：更新 ' + updates.length.toString() + ' 个、新增 ' +
        inserts.length.toString() + ' 个' + (unchanged > 0 ? '，' + unchanged.toString() + ' 个未变' : '');
    return result;
  }

  private static keyOf(type: EasEventType, name: string, from: number, to: number): string {
    return type.toString() + '|' + name + '|' + from.toString() + '|' + to.toString();
  }

  private static readText(uri: string): string {
    const file: fileIo.File = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
    try {
      const size: number = fileIo.statSync(file.fd).size;
      const data: ArrayBuffer = new ArrayBuffer(size);
      const read: number = fileIo.readSync(file.fd, data);
      return buffer.from(data, 0, read).toString('utf-8');
    } finally {
      fileIo.closeSync(file);
    }
  }

  private static fileTitle(uri: string): string {
    const slash: number = uri.lastIndexOf('/');
    let name: string = slash >= 0 ? uri.substring(slash + 1) : uri;
    try {
      name = decodeURIComponent(name);
    } catch (e) {
    }
    return name.replace(/\.ics$/i, '').trim();
  }

  /** 与导出端“教师：xxx”对称，同时兼容常见的“老师/授课教师/Teacher”写法。 */
  private static teacherOf(description: string): string {
    const m: RegExpExecArray | null = /(?:授课教师|教师|老师|Teacher)\s*[：:]\s*([^\n]+)/i.exec(description);
    return m === null ? '' : m[1].trim();
  }

  /** 选与文件中上下课时间吻合最多的作息结构，便于回填节次。 */
  private static bestSchedule(events: IcsEventInstance[]): EasTimePeriodInDay[] {
    const candidates: EasTimePeriodInDay[][] = [
      EasTimetable.getDefaultTimeStructure(),
      EasTimetable.getWeihaiTimeStructure(),
      EasTimetableImporter.scheduleStructure(EasCampus.BENBU)
    ];
    let best: EasTimePeriodInDay[] = candidates[0];
    let bestScore: number = -1;
    for (let c: number = 0; c < candidates.length; c++) {
      let score: number = 0;
      for (let i: number = 0; i < events.length; i++) {
        const numbers: number[] = TimetableIcsImporter.periodNumbers(candidates[c], events[i]);
        if (numbers[0] > 0) {
          score++;
        }
      }
      if (score > bestScore) {
        best = candidates[c];
        bestScore = score;
      }
    }
    return best;
  }

  /** 上课时刻等于某节开始、下课时刻等于某节结束时返回 [起始节, 结束节]，否则 [0, 0]。 */
  private static periodNumbers(schedule: EasTimePeriodInDay[], ev: IcsEventInstance): number[] {
    const from: Date = new Date(ev.from);
    const to: Date = new Date(ev.to);
    const fromMinutes: number = from.getHours() * 60 + from.getMinutes();
    const toMinutes: number = to.getHours() * 60 + to.getMinutes();
    let first: number = 0;
    let last: number = 0;
    for (let i: number = 0; i < schedule.length; i++) {
      if (schedule[i].from.hour * 60 + schedule[i].from.minute === fromMinutes && first === 0) {
        first = i + 1;
      }
      if (schedule[i].to.hour * 60 + schedule[i].to.minute === toMinutes) {
        last = i + 1;
      }
    }
    return first > 0 && last >= first ? [first, last] : [0, 0];
  }
}
