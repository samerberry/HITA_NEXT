/** Imports a legacy EAS timetable into the local timetable database. */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { RdbHelper } from '../../common/db/RdbHelper';
import {
  EasEventItem,
  EasEventType,
  EasImportBaseEntry,
  EasSubjectType,
  EasTermSubject,
  EasTimePeriodInDay,
  EasTimetable,
  newId
} from '../../common/model/timetable/TimetableModels';
import { EasCampus, EasSession } from './EasSession';
import { EasSessionStore } from './EasSessionStore';
import { EasDataProvider, LegacyCatalogFetch } from './EasDataProvider';
import { BenbuExperimentParser } from './data/BenbuExperimentParser';
import { EasCourseItem, EasTermItem } from './model/EasModels';
import { EasApiClient } from './EasApiClient';
import { EasUserMessages } from './EasUserMessages';
import { EasLegacyCourseCatalogParser, LegacyCourseAttributes } from './data/EasLegacyCourseCatalogParser';
import { TimetableChangeGroup, TimetableMergePlan, TimetableUpdateDiff } from '../timetable/data/TimetableUpdateDiff';
import { TimetableUpdateStore } from '../timetable/data/TimetableUpdateStore';

const DOMAIN: number = 0x0000;
const TAG: string = 'HitaEasImport';

/** 一次导入将要写入的完整内容；写库前即可用于比较。 */
export class EasImportPlan {
  timetable: EasTimetable = new EasTimetable();
  subjects: EasTermSubject[] = [];
  events: EasEventItem[] = [];
  replaceCourses: boolean = false;
}

/** 教务端相对上次导入的变化，以及合并到本地课表的改动，等待用户确认。 */
export class EasTimetableUpdate {
  timetable: EasTimetable = new EasTimetable();
  plan: EasImportPlan = new EasImportPlan();
  merge: TimetableMergePlan = new TimetableMergePlan();
  /** 新增课程用到、本地还没有的科目。 */
  newSubjects: EasTermSubject[] = [];
  changes: TimetableChangeGroup[] = [];
  fingerprint: string = '';
}

export class EasImportResult {
  success: boolean = false;
  message: string = '';
  timetable: EasTimetable | undefined = undefined;
  term: EasTermItem | undefined = undefined;
  courseCount: number = 0;
  eventCount: number = 0;
}

export class EasTermStartResult {
  startTime: number = 0;
  fromSaved: boolean = false;
}

export class EasTimetableImporter {
  /**
   * 导入当前学期。传入参数时复用同一条链路导入指定学期，并使用页面编辑后的
   * 开学日期和节次结构。这让“导入课表”页面和首页快捷导入共享完全相同的
   * 会话、解析与本地写库逻辑。
   */
  static async importCurrent(context: common.Context, selectedTerm?: EasTermItem,
    startTimeMs?: number, scheduleOverride?: EasTimePeriodInDay[], studentType?: string): Promise<EasImportResult> {
    const result: EasImportResult = new EasImportResult();
    try {
      await EasSessionStore.getInstance().init(context);
      const rdb: RdbHelper = RdbHelper.getInstance();
      await rdb.init(context);
      const session: EasSession | undefined = await EasSessionStore.getInstance().loadPreferred();
      if (session === undefined) {
        result.message = '请先登录统一身份认证';
        return result;
      }
      if (studentType !== undefined && studentType.length > 0) {
        session.setStudentType(studentType);
      }
      if (session.campus === EasCampus.BENBU && session.getStudentType() === '2') {
        result.message = '暂不支持导入本部研究生课表';
        return result;
      }
      const provider: EasDataProvider = new EasDataProvider(new EasApiClient());
      hilog.info(DOMAIN, TAG, 'loading terms campus=%{public}s', session.campus.toString());
      const terms: EasTermItem[] = await provider.getAllTerms(session);
      if (terms.length === 0) {
        result.message = '未找到可导入的学期';
        return result;
      }
      let term: EasTermItem = terms[0];
      if (selectedTerm !== undefined) {
        let found: boolean = false;
        for (let i: number = 0; i < terms.length; i++) {
          if (terms[i].equalsKey(selectedTerm)) {
            term = terms[i];
            found = true;
            break;
          }
        }
        if (!found) {
          result.message = '所选学期已不可用，请重新选择';
          return result;
        }
      } else {
        for (let i: number = 0; i < terms.length; i++) {
          if (terms[i].isCurrent) {
            term = terms[i];
            break;
          }
        }
      }
      result.term = term;
      const start: EasTermStartResult = startTimeMs === undefined ?
        await EasTimetableImporter.loadStartDate(rdb, provider, session, term) : new EasTermStartResult();
      if (startTimeMs !== undefined && Number.isFinite(startTimeMs) && startTimeMs > 0) {
        start.startTime = EasTimetable.mondayMsOf(startTimeMs);
      }
      if (!Number.isFinite(start.startTime) || start.startTime <= 0) {
        result.message = '未能获取开学日期，请在导入课表中手动选择';
        return result;
      }
      const courses: EasCourseItem[] = await EasTimetableImporter.fetchCourses(provider, session, term);
      result.courseCount = courses.length;
      if (courses.length === 0) {
        result.message = '课表为空，未导入';
        return result;
      }
      let schedule: EasTimePeriodInDay[] = scheduleOverride !== undefined && scheduleOverride.length > 0 ?
        scheduleOverride : EasTimetableImporter.scheduleStructure(session.campus);
      if ((scheduleOverride === undefined || scheduleOverride.length === 0) && session.campus === EasCampus.SHENZHEN) {
        try {
          const remoteSchedule: EasTimePeriodInDay[] = await provider.getShenzhenScheduleStructure(session, term);
          if (remoteSchedule.length > 0) {
            schedule = remoteSchedule;
          }
        } catch (e) {
          hilog.warn(DOMAIN, TAG, 'using fallback Shenzhen schedule %{public}s', String(e));
        }
      }
      const plan: EasImportPlan = await EasTimetableImporter.saveCourses(rdb, session, term, courses, schedule,
        start.startTime);
      const timetable: EasTimetable = plan.timetable;
      result.timetable = timetable;
      const readback: EasEventItem[] = await rdb.getEventsOfTimetable(timetable.id);
      result.eventCount = readback.length;
      hilog.info(DOMAIN, TAG, 'RDB readback timetable=%{public}s subjects/events=%{public}d',
        timetable.id, readback.length);
      if (readback.length === 0) {
        result.message = '课表保存失败，请重试';
        return result;
      }
      // 刚导入的教务版本不需要再提醒更新。
      await EasTimetableImporter.rememberRemote(context, timetable.id, plan.events);
      result.success = true;
      result.message = '已导入 ' + readback.length.toString() + ' 个课次';
      if (start.fromSaved) {
        result.message += '，开学日期沿用本地设置，请核对';
      }
      if (provider.importWarnings.length > 0) {
        result.message += '；' + provider.importWarnings.join('；');
      }
      return result;
    } catch (e) {
      const text: string = e instanceof Error ? e.message : String(e);
      hilog.error(DOMAIN, TAG, 'import failed %{public}s', text);
      result.message = EasUserMessages.fromError(text, '导入课表失败，请稍后重试');
      return result;
    }
  }

  /**
   * 读取教务端该学期的最新课表并与本地课表比较，不写库。沿用本地课表的开学日期和
   * 节次结构；教务内容与上次导入或上次提醒时相同就不再提醒，即使本地翘过课、改过课。
   * minIntervalMs 大于 0 时，距上次实际检查这张课表不足该时长就跳过（跨重启有效）。
   */
  static async checkForUpdate(context: common.Context, timetable: EasTimetable,
    minIntervalMs: number = 0): Promise<EasTimetableUpdate | undefined> {
    const source: string[] | undefined = EasTimetableImporter.sourceOf(timetable);
    if (source === undefined) {
      return undefined;
    }
    await EasSessionStore.getInstance().init(context);
    const campus: EasCampus = source[0] === EasCampus.BENBU.toString() ? EasCampus.BENBU :
      source[0] === EasCampus.WEIHAI.toString() ? EasCampus.WEIHAI : EasCampus.SHENZHEN;
    const session: EasSession | undefined = await EasSessionStore.getInstance().load(campus);
    if (session === undefined || !session.isLogin() || session.loginExpired ||
      (campus === EasCampus.BENBU && session.getStudentType() === '2')) {
      return undefined;
    }
    const store: TimetableUpdateStore = TimetableUpdateStore.getInstance();
    await store.init(context);
    const now: number = Date.now();
    const elapsed: number = now - await store.loadCheckedAt(timetable.id);
    // 时钟被往回调过时上次时间在未来，视为已到期，不能因此长期不检查。
    if (minIntervalMs > 0 && elapsed >= 0 && elapsed < minIntervalMs) {
      return undefined;
    }
    // 联网前记下时间：网络失败也算一次检查，避免反复请求。
    await store.saveCheckedAt(timetable.id, now);
    const rdb: RdbHelper = RdbHelper.getInstance();
    await rdb.init(context);
    const provider: EasDataProvider = new EasDataProvider(new EasApiClient());
    const terms: EasTermItem[] = await provider.getAllTerms(session);
    const term: EasTermItem | undefined = terms.find((item: EasTermItem): boolean => item.getCode() === source[1]);
    if (term === undefined) {
      return undefined;
    }
    const courses: EasCourseItem[] = await EasTimetableImporter.fetchCourses(provider, session, term);
    if (courses.length === 0) {
      // 教务暂时返回空课表时不提议清空本地课程。
      return undefined;
    }
    const plan: EasImportPlan = await EasTimetableImporter.buildImport(rdb, session, term, courses,
      timetable.scheduleStructure, timetable.startTime);
    if (!plan.replaceCourses || plan.timetable.id !== timetable.id) {
      return undefined;
    }
    const fingerprint: string = TimetableUpdateDiff.fingerprint(plan.events);
    const recorded: EasImportBaseEntry[] = await rdb.getImportBase(timetable.id);
    if (recorded.length === 0) {
      // 旧版本导入的课表还没有基准：以教务现状为基准且不提醒，免得把用户的修改当成教务变化。
      // 先于“已提醒版本”判断，否则版本没变时永远记不下基准，之后的真实变化会被吞掉。
      await rdb.saveImportBase(timetable.id, TimetableUpdateDiff.baseOf(plan.events));
      await store.saveSeen(timetable.id, fingerprint);
      hilog.info(DOMAIN, TAG, 'timetable update base initialized term=%{public}s', term.getCode());
      return undefined;
    }
    if (await store.loadSeen(timetable.id) === fingerprint) {
      return undefined;
    }
    const local: EasEventItem[] = await rdb.getEventsOfTimetable(timetable.id);
    const merge: TimetableMergePlan = TimetableUpdateDiff.merge(plan.timetable.startTime, local,
      TimetableUpdateDiff.baseMap(recorded), plan.events);
    hilog.info(DOMAIN, TAG, 'timetable update check term=%{public}s changes=%{public}d',
      term.getCode(), merge.changes.length);
    if (merge.changes.length === 0) {
      // 教务端的变化都落在用户翘过、改过的课上：没有要改的，只记下这一教务版本。
      await rdb.saveImportBase(timetable.id, merge.base);
      await store.saveSeen(timetable.id, fingerprint);
      return undefined;
    }
    const existing: Set<string> = new Set<string>((await rdb.getSubjectsOfTimetable(timetable.id))
      .map((subject: EasTermSubject): string => subject.id));
    const update: EasTimetableUpdate = new EasTimetableUpdate();
    update.timetable = timetable;
    update.plan = plan;
    update.merge = merge;
    update.newSubjects = plan.subjects.filter((subject: EasTermSubject): boolean => !existing.has(subject.id) &&
      merge.inserts.some((event: EasEventItem): boolean => event.subjectId === subject.id));
    update.changes = merge.changes;
    update.fingerprint = fingerprint;
    return update;
  }

  /** 用户确认后只把清单里的变化落到本课表；翘过、改过、添加的课和其他日程保持不变。 */
  static async applyUpdate(context: common.Context, update: EasTimetableUpdate): Promise<void> {
    const rdb: RdbHelper = RdbHelper.getInstance();
    await rdb.init(context);
    await rdb.applyTimetableMerge(update.timetable.id, update.newSubjects, update.merge.inserts,
      update.merge.updates, update.merge.deletes, update.merge.base);
    await EasTimetableImporter.rememberRemote(context, update.timetable.id, update.plan.events);
  }

  /** 用户选择暂不更新：同一教务版本不再提醒。 */
  static async dismissUpdate(context: common.Context, update: EasTimetableUpdate): Promise<void> {
    const store: TimetableUpdateStore = TimetableUpdateStore.getInstance();
    await store.init(context);
    await store.saveSeen(update.timetable.id, update.fingerprint);
  }

  /** 教务导入的课表编码为“校区:学期代码”；其他来源（ICS、手建）没有教务对应。 */
  static isEasTimetable(timetable: EasTimetable): boolean {
    return EasTimetableImporter.sourceOf(timetable) !== undefined;
  }

  private static sourceOf(timetable: EasTimetable): string[] | undefined {
    const separator: number = timetable.code.indexOf(':');
    if (separator <= 0 || separator === timetable.code.length - 1) {
      return undefined;
    }
    const campus: string = timetable.code.substring(0, separator);
    if (campus !== EasCampus.SHENZHEN.toString() && campus !== EasCampus.BENBU.toString() &&
      campus !== EasCampus.WEIHAI.toString()) {
      return undefined;
    }
    return [campus, timetable.code.substring(separator + 1)];
  }

  private static async rememberRemote(context: common.Context, timetableId: string,
    events: EasEventItem[]): Promise<void> {
    const store: TimetableUpdateStore = TimetableUpdateStore.getInstance();
    await store.init(context);
    await store.saveSeen(timetableId, TimetableUpdateDiff.fingerprint(events));
  }

  /** 课表课程；旧校区再按课程名补全性质、考核方式与学分。 */
  private static async fetchCourses(provider: EasDataProvider, session: EasSession,
    term: EasTermItem): Promise<EasCourseItem[]> {
    const courses: EasCourseItem[] = await provider.getTimetableOfTerm(session, term);
    if (courses.length > 0 && session.campus !== EasCampus.SHENZHEN) {
      const fetched: LegacyCatalogFetch = await provider.getLegacyCourseAttributes(session, term);
      const matched: number = EasTimetableImporter.applyLegacyAttributes(courses, fetched.rows, term);
      hilog.info(DOMAIN, TAG, 'course attributes %{public}s matched=%{public}d/%{public}d',
        fetched.diag, matched, courses.length);
    }
    return courses;
  }

  private static async saveCourses(rdb: RdbHelper, session: EasSession, term: EasTermItem,
    courses: EasCourseItem[], schedule: EasTimePeriodInDay[], startTimeMs: number): Promise<EasImportPlan> {
    const plan: EasImportPlan = await EasTimetableImporter.buildImport(rdb, session, term, courses, schedule,
      startTimeMs);
    await rdb.saveImportedTimetable(plan.timetable, plan.subjects, plan.events, plan.replaceCourses,
      TimetableUpdateDiff.baseOf(plan.events));
    return plan;
  }

  private static async buildImport(rdb: RdbHelper, session: EasSession, term: EasTermItem,
    courses: EasCourseItem[], schedule: EasTimePeriodInDay[], startTimeMs: number): Promise<EasImportPlan> {
    const code: string = session.campus.toString() + ':' + term.getCode();
    let timetable: EasTimetable | undefined = await rdb.getTimetableByEasCode(code);
    const replaceCourses: boolean = timetable !== undefined;
    if (timetable === undefined) {
      timetable = new EasTimetable();
      timetable.code = code;
    }
    timetable.name = term.name;
    timetable.startTime = EasTimetable.mondayMsOf(startTimeMs);
    let maxWeek: number = 1;
    for (let i = 0; i < courses.length; i++) {
      for (let j = 0; j < courses[i].weekNumbers.length; j++) {
        const week = courses[i].weekNumbers[j];
        if (Number.isInteger(week) && week > 0) maxWeek = Math.max(maxWeek, week);
      }
    }
    timetable.endTime = timetable.startTime + maxWeek * 7 * 24 * 60 * 60 * 1000 - 1;
    timetable.createdAt = Date.now();
    timetable.scheduleStructure = schedule.length > 0 ? schedule : EasTimetableImporter.scheduleStructure(session.campus);
    const subjects: EasTermSubject[] = await rdb.getSubjectsOfTimetable(timetable.id);
    let validCourseCount: number = 0;
    let savedEventCount: number = 0;
    // 教务会把多位教师/多个教室同时段授课的同一门课拆成多条，同名同时段只保留一个课次。
    const eventByKey: Map<string, EasEventItem> = new Map<string, EasEventItem>();
    for (let i: number = 0; i < courses.length; i++) {
      const course: EasCourseItem = courses[i];
      const startMinutes: number = BenbuExperimentParser.timeMinutes(course.startTime);
      const endMinutes: number = BenbuExperimentParser.timeMinutes(course.endTime);
      const freeTime: boolean = startMinutes >= 0 && endMinutes > startMinutes;
      const dated: boolean = course.scheduledDate.length > 0;
      const scheduledMs: number = BenbuExperimentParser.dateMs(course.scheduledDate);
      if (!Number.isInteger(course.dayOfWeek) || course.dayOfWeek < 1 || course.dayOfWeek > 7 ||
        (dated && (!freeTime || !Number.isFinite(scheduledMs))) ||
        (!freeTime && (!Number.isInteger(course.beginSection) || course.beginSection < 1 ||
        !Number.isInteger(course.sectionCount) || course.sectionCount < 1 ||
        course.beginSection + course.sectionCount - 1 > timetable.scheduleStructure.length))) {
        hilog.warn(DOMAIN, TAG, 'skip invalid course name=%{public}s day=%{public}d section=%{public}d count=%{public}d',
          course.name, course.dayOfWeek, course.beginSection, course.sectionCount);
        continue;
      }
      validCourseCount++;
      let subject: EasTermSubject | undefined = undefined;
      for (let j: number = 0; j < subjects.length; j++) {
        if (subjects[j].name === course.name) {
          subject = subjects[j];
          break;
        }
      }
      if (subject === undefined) {
        subject = new EasTermSubject();
        subject.timetableId = timetable.id;
        subject.name = course.name;
        subject.code = course.code;
        subject.type = EasTimetableImporter.subjectTypeForCourse(course);
        subject.credit = course.credit > 0 ? course.credit : 0;
        subjects.push(subject);
      } else if (EasTimetableImporter.hasSubjectTypeHint(course)) {
        // 旧版本导入器曾把所有新科目默认写成 COM_A（必修·考试）。
        // 重新导入时，仅在教务返回了明确分类时修正已有科目，避免用不完整
        // 的课表数据覆盖用户手动调整过的类型。
        const inferredType: EasSubjectType = EasTimetableImporter.subjectTypeForCourse(course);
        const nextCredit: number = course.credit > 0 ? course.credit : subject.credit;
        if (subject.type !== inferredType || subject.credit !== nextCredit) {
          subject.type = inferredType;
          subject.credit = nextCredit;
        }
      }
      const weeks: number[] = dated ? [1] : course.weekNumbers;
      for (let w: number = 0; w < weeks.length; w++) {
        const week: number = weeks[w];
        if (!Number.isInteger(week) || week < 1 || week > maxWeek) continue;
        let timestamps: number[];
        if (freeTime) {
          const date: Date = new Date(dated ? scheduledMs : timetable.startTime);
          if (!dated) date.setDate(date.getDate() + (week - 1) * 7 + course.dayOfWeek - 1);
          date.setHours(0, startMinutes, 0, 0);
          const from: number = date.getTime();
          date.setHours(0, endMinutes, 0, 0);
          timestamps = [from, date.getTime()];
        } else {
          timestamps = timetable.getTimestamps(week, course.dayOfWeek,
            course.beginSection, course.beginSection + course.sectionCount - 1);
        }
        const key: string = course.name + '|' + timestamps[0].toString() + '|' + timestamps[1].toString();
        const duplicate: EasEventItem | undefined = eventByKey.get(key);
        if (duplicate !== undefined) {
          duplicate.teacher = EasTimetableImporter.joinDistinct(duplicate.teacher, course.teacher);
          duplicate.place = EasTimetableImporter.joinDistinct(duplicate.place, course.classroom);
          continue;
        }
        const event: EasEventItem = new EasEventItem();
        event.id = newId();
        event.type = EasEventType.CLASS;
        event.name = course.name;
        event.place = course.classroom;
        event.teacher = course.teacher;
        event.subjectId = subject.id;
        event.timetableId = timetable.id;
        event.from = timestamps[0];
        event.to = timestamps[1];
        event.fromNumber = freeTime ? -1 : course.beginSection;
        event.lastNumber = freeTime ? -1 : course.beginSection + course.sectionCount - 1;
        eventByKey.set(key, event);
        savedEventCount++;
      }
    }
    hilog.info(DOMAIN, TAG, 'import plan courses=%{public}d valid=%{public}d events=%{public}d',
      courses.length, validCourseCount, savedEventCount);
    if (courses.length > 0 && validCourseCount === 0) {
      throw new Error('课表已获取，但课程节次无法解析');
    }
    if (validCourseCount > 0 && savedEventCount === 0) {
      throw new Error('课表已解析，但本地没有写入任何课次');
    }
    const allEvents: EasEventItem[] = Array.from(eventByKey.values());
    let lastEnd: number = 0;
    for (const event of allEvents) {
      if (Number.isFinite(event.to) && event.from >= timetable.startTime && event.to > event.from) {
        lastEnd = Math.max(lastEnd, event.to);
      }
    }
    if (lastEnd > 0) {
      const end: Date = new Date(EasTimetable.mondayMsOf(lastEnd));
      end.setDate(end.getDate() + 7);
      timetable.endTime = end.getTime() - 1;
    }
    const plan: EasImportPlan = new EasImportPlan();
    plan.timetable = timetable;
    plan.subjects = subjects;
    plan.events = allEvents;
    plan.replaceCourses = replaceCourses;
    return plan;
  }

  /**
   * 将教务课程的性质/选课类别/考核方式映射为 Android 同源的科目类型。
   * 规则优先使用明确的“考查/非考试/否”，避免把考查课误判为考试课。
   */
  private static subjectTypeForCourse(course: EasCourseItem): EasSubjectType {
    const property: string = EasTimetableImporter.normalizeTypeText(course.courseProperty);
    const category: string = EasTimetableImporter.normalizeTypeText(course.courseCategory);
    const selection: string = EasTimetableImporter.normalizeTypeText(course.selectionCategory);
    const assess: string = EasTimetableImporter.normalizeTypeText(course.assessMethod);
    const all: string = property + '|' + category + '|' + selection;

    if (/(?:MOOC|慕课|在线开放课程|网络课程)/i.test(all)) {
      return EasSubjectType.MOOC;
    }

    const assessLower: string = assess.toLowerCase();
    const isAssessment: boolean = assess.length > 0 &&
      (/非考试|考查|考察|不考试|否/.test(assess) ||
        assessLower === 'false' || assessLower === 'no' || assessLower === '0');
    const isExam: boolean = assess.length > 0 && !isAssessment &&
      (/考试|考试课|是/.test(assess) ||
        assessLower === 'true' || assessLower === 'yes' || assessLower === '1');

    // 课程性质优先决定必修/选修；考核方式只影响必修课的 A/B。
    if (/必修|共同必修|核心必修/.test(property)) {
      return isAssessment ? EasSubjectType.COM_B : EasSubjectType.COM_A;
    }
    if (/限选|专选|指定选修/.test(property + '|' + selection) ||
      /(^|\|)xx(?:[-_]|$)/i.test(selection)) {
      return EasSubjectType.OPT_A;
    }
    if (/任选|任意选修|公共选修|通识选修/.test(property + '|' + selection) ||
      /(^|\|)rx(?:[-_]|$)/i.test(selection)) {
      return EasSubjectType.OPT_B;
    }
    if (/选修/.test(property + '|' + selection)) {
      return EasSubjectType.OPT_B;
    }

    // 有些接口只返回考核方式，不返回课程性质；明确的考查课仍应识别为
    // COM_B，考试课则保留兼容性的 COM_A 默认值。
    if (isAssessment) {
      return EasSubjectType.COM_B;
    }
    if (isExam) {
      return EasSubjectType.COM_A;
    }
    return EasSubjectType.COM_A;
  }

  /**
   * 用执行计划/期末成绩表按课程名补全课表课程的性质、考核方式与学分。
   * 本学期的行优先；同一优先级内“是否考试课”互相矛盾时不采用（多专业同名课）。
   */
  private static applyLegacyAttributes(courses: EasCourseItem[], attributes: LegacyCourseAttributes[],
    term: EasTermItem): number {
    if (attributes.length === 0) {
      return 0;
    }
    const byName: Map<string, LegacyCourseAttributes> = new Map<string, LegacyCourseAttributes>();
    const conflicted: Set<string> = new Set<string>();
    const termMatchedNames: Set<string> = new Set<string>();
    for (let pass: number = 0; pass < 2; pass++) {
      const wantTermMatch: boolean = pass === 0;
      for (let i: number = 0; i < attributes.length; i++) {
        const row: LegacyCourseAttributes = attributes[i];
        if (EasLegacyCourseCatalogParser.matchesTerm(row.termText, term) !== wantTermMatch) {
          continue;
        }
        const key: string = EasLegacyCourseCatalogParser.nameKey(row.name);
        if (!wantTermMatch && termMatchedNames.has(key)) {
          continue;
        }
        if (wantTermMatch) {
          termMatchedNames.add(key);
        }
        const existing: LegacyCourseAttributes | undefined = byName.get(key);
        if (existing === undefined) {
          byName.set(key, row);
          continue;
        }
        const a: string = EasTimetableImporter.normalizeTypeText(existing.assessMethod);
        const b: string = EasTimetableImporter.normalizeTypeText(row.assessMethod);
        if (a.length === 0 && b.length > 0) {
          byName.set(key, row);
        } else if (a.length > 0 && b.length > 0 && a !== b) {
          conflicted.add(key);
        }
      }
    }
    let matched: number = 0;
    const unmatched: EasCourseItem[] = [];
    for (let i: number = 0; i < courses.length; i++) {
      const course: EasCourseItem = courses[i];
      const row: LegacyCourseAttributes | undefined =
        byName.get(EasLegacyCourseCatalogParser.nameKey(course.name));
      if (row === undefined) {
        unmatched.push(course);
        continue;
      }
      matched++;
      EasTimetableImporter.fillCourseFromRow(course, row, conflicted.has(
        EasLegacyCourseCatalogParser.nameKey(course.name)));
    }
    // 前缀兜底：教务表里的课名常带后缀（“体育Ⅲ（三）”vs“体育Ⅲ”“管理会计（双语）”vs
    // “管理会计”）。仅当这门课与某一行在两个方向上都唯一对应时才采用，避免“体育”吸走多门课。
    if (unmatched.length > 0) {
      const fallback = (course: EasCourseItem): LegacyCourseAttributes | undefined => {
        const courseKey: string = EasLegacyCourseCatalogParser.nameKey(course.name);
        if (courseKey.length < 2) {
          return undefined;
        }
        const candidates: LegacyCourseAttributes[] = [];
        const seenKeys: Set<string> = new Set<string>();
        for (let i: number = 0; i < attributes.length; i++) {
          const rowKey: string = EasLegacyCourseCatalogParser.nameKey(attributes[i].name);
          if (seenKeys.has(rowKey) || rowKey.length < 2) {
            continue;
          }
          const related: boolean = rowKey.length < courseKey.length && courseKey.startsWith(rowKey) ||
            rowKey.length > courseKey.length && rowKey.startsWith(courseKey);
          if (related) {
            candidates.push(attributes[i]);
            seenKeys.add(rowKey);
          }
        }
        if (candidates.length === 0) {
          return undefined;
        }
        // 多个变体（管理会计/管理会计（双语）/管理会计学…）时，只有本学期开课的那条
        // 才是当前上的课；过滤后仍不唯一则放弃，交给手动修正。
        const termRows: LegacyCourseAttributes[] = candidates.filter((row: LegacyCourseAttributes): boolean =>
          EasLegacyCourseCatalogParser.matchesTerm(row.termText, term));
        if (termRows.length === 1) {
          return termRows[0];
        }
        return candidates.length === 1 ? candidates[0] : undefined;
      };
      for (let i: number = 0; i < unmatched.length; i++) {
        const row: LegacyCourseAttributes | undefined = fallback(unmatched[i]);
        if (row === undefined) {
          continue;
        }
        matched++;
        EasTimetableImporter.fillCourseFromRow(unmatched[i], row, false);
      }
    }
    hilog.info(DOMAIN, TAG, 'legacy attributes matched=%{public}d/%{public}d conflicts=%{public}d',
      matched, courses.length, conflicted.size);
    return matched;
  }

  private static fillCourseFromRow(course: EasCourseItem, row: LegacyCourseAttributes, conflicted: boolean): void {
    if (course.courseProperty.trim().length === 0) {
      course.courseProperty = row.property;
    }
    if (course.courseCategory.trim().length === 0) {
      course.courseCategory = row.category;
    }
    if (course.assessMethod.trim().length === 0 && !conflicted) {
      course.assessMethod = row.assessMethod;
    }
    if (course.credit <= 0 && row.credit > 0) {
      course.credit = row.credit;
    }
    if (course.code.trim().length === 0) {
      course.code = row.code;
    }
  }

  private static joinDistinct(current: string, extra: string): string {
    const value: string = extra.trim();
    if (value.length === 0 || current.split('/').indexOf(value) >= 0) {
      return current;
    }
    return current.length > 0 ? current + '/' + value : value;
  }

  private static hasSubjectTypeHint(course: EasCourseItem): boolean {
    return course.courseProperty.trim().length > 0 ||
      course.courseCategory.trim().length > 0 ||
      course.assessMethod.trim().length > 0 ||
      course.selectionCategory.trim().length > 0;
  }

  private static normalizeTypeText(value: string): string {
    return value.replace(/[\s\u00a0：:，,;；（）()]/g, '').trim();
  }

  /** 默认作息结构，供导入页显示和编辑时使用。 */
  static scheduleStructure(campus: EasCampus = EasCampus.BENBU): EasTimePeriodInDay[] {
    if (campus === EasCampus.WEIHAI) {
      return EasTimetable.getWeihaiTimeStructure();
    }
    if (campus === EasCampus.SHENZHEN) {
      return EasTimetable.getDefaultTimeStructure();
    }
    return EasTimetable.getBenbuTimeStructure();
  }

  /** Preserve a saved date only when the calendar is unavailable, and report that fallback. */
  static async loadStartDate(rdb: RdbHelper, provider: EasDataProvider, session: EasSession,
    term: EasTermItem): Promise<EasTermStartResult> {
    const out: EasTermStartResult = new EasTermStartResult();
    const remote: number | undefined = await provider.getStartDate(session, term);
    if (remote !== undefined && Number.isFinite(remote) && remote > 0) {
      out.startTime = EasTimetable.mondayMsOf(remote);
      return out;
    }
    const saved: EasTimetable | undefined = await rdb.getTimetableByEasCode(
      session.campus.toString() + ':' + term.getCode());
    if (saved !== undefined && Number.isFinite(saved.startTime) && saved.startTime > 0) {
      out.startTime = EasTimetable.mondayMsOf(saved.startTime);
      out.fromSaved = true;
    }
    return out;
  }
}
