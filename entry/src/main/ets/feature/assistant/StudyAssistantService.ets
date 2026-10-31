import { common } from '@kit.AbilityKit';
import { RdbHelper } from '../../common/db/RdbHelper';
import { LearningContext, LearningTask, LearningTaskKind, LearningTaskRules } from '../../common/model/learning/LearningTask';
import { StudyOperation } from '../../common/model/learning/StudyOperation';
import { EasTermSubject, EasTimetable } from '../../common/model/timetable/TimetableModels';
import { TimetableSelectionStore } from '../timetable/data/TimetableSelectionStore';
import { TimetableResolver } from '../timetable/data/TimetableResolver';
import { LocalTimetableApi } from './LocalTimetableApi';
import { LearningTaskReminders } from '../learning/LearningTaskReminders';

export class StudyInputError extends Error {}

class StudyScope {
  table: EasTimetable = new EasTimetable();
  subjects: EasTermSubject[] = [];
}

/** Device-side study tools. No model-generated field can bypass the on-device confirmation. */
export class StudyAssistantService {
  static text(parameters: Record<string, Object>, key: string, max: number = 120): string {
    const value: Object | undefined = parameters[key];
    if (value === undefined || value === null) return '';
    if (typeof value !== 'string' || value.trim().length > max) throw new StudyInputError(key + ' 参数无效');
    return value.trim();
  }

  private static normalized(value: string): string { return value.replace(/\s+/g, '').toLowerCase(); }

  private static async scope(context: common.Context): Promise<StudyScope> {
    const db: RdbHelper = RdbHelper.getInstance();
    await db.init(context);
    const data: LearningContext = await db.getLearningContext();
    const selected: string = await TimetableSelectionStore.loadForQuery(context);
    const table: EasTimetable | undefined = data.timetables.find(item => item.id === selected) ??
      data.timetables.slice().sort((a, b) => b.startTime - a.startTime).find(item => TimetableResolver.isReal(item)) ??
      data.timetables.slice().sort((a, b) => b.startTime - a.startTime).find(item => TimetableResolver.isLocal(item));
    if (table === undefined) throw new StudyInputError('请先导入或选择课表');
    const scope: StudyScope = new StudyScope();
    scope.table = table;
    scope.subjects = data.subjects.filter(item => item.timetableId === table.id);
    return scope;
  }

  private static matches(subjects: EasTermSubject[], keyword: string): EasTermSubject[] {
    const key: string = StudyAssistantService.normalized(keyword);
    const exact: EasTermSubject[] = subjects.filter(item => StudyAssistantService.normalized(item.name) === key ||
      (item.code.length > 0 && StudyAssistantService.normalized(item.code) === key));
    return exact.length > 0 ? exact : subjects.filter(item => StudyAssistantService.normalized(item.name).includes(key) ||
      (item.code.length > 0 && StudyAssistantService.normalized(item.code).includes(key)));
  }

  private static courseView(subject: EasTermSubject): Record<string, Object> {
    return { 'subjectId': subject.id, 'timetableId': subject.timetableId, 'name': subject.name, 'courseCode': subject.code };
  }

  static taskView(task: LearningTask): Record<string, Object> {
    return { 'taskId': task.id, 'title': task.title, 'note': task.note, 'subjectId': task.subjectId,
      'timetableId': task.timetableId, 'courseName': task.courseName, 'courseCode': task.courseCode,
      'dueDate': task.dueAt > 0 ? StudyAssistantService.date(task.dueAt) : '',
      'dueTime': task.dueAt > 0 && !task.allDay ? StudyAssistantService.time(task.dueAt) : '',
      'allDay': task.allDay, 'dueAt': task.dueAt, 'remindAt': task.remindAt,
      'completed': task.completedAt > 0, 'updatedAt': task.updatedAt };
  }

  static date(value: number): string {
    const date: Date = new Date(value);
    return date.getFullYear().toString().padStart(4, '0') + '-' + (date.getMonth() + 1).toString().padStart(2, '0') +
      '-' + date.getDate().toString().padStart(2, '0');
  }

  static time(value: number): string {
    const date: Date = new Date(value);
    return date.getHours().toString().padStart(2, '0') + ':' + date.getMinutes().toString().padStart(2, '0');
  }

  /** Yearless deadlines use the next occurrence on the device calendar; a date alone is an all-day deadline. */
  static day(value: string, now: number = Date.now()): number {
    const partial: RegExpMatchArray | null = value.match(/^(\d{1,2})(?:月|-)(\d{1,2})日?$/);
    if (partial !== null) {
      let year: number = new Date(now).getFullYear();
      const month: number = Number(partial[1]);
      const day: number = Number(partial[2]);
      // Validate before rolling forward; February 30 must never normalize into March.
      const initial: Date = new Date(year, month - 1, day);
      if (initial.getMonth() !== month - 1 || initial.getDate() !== day) throw new StudyInputError('截止日期不存在，请提供完整日期');
      if (initial.getTime() < LearningTaskRules.dayStart(now)) year++;
      return StudyAssistantService.day(year.toString() + '-' + month.toString().padStart(2, '0') + '-' + day.toString().padStart(2, '0'), now);
    }
    if (/^\d{4}-\d{2}-\d{2}$/.test(value)) {
      const date: Date = new Date(Number(value.slice(0, 4)), Number(value.slice(5, 7)) - 1, Number(value.slice(8, 10)));
      if (Number(value.slice(0, 4)) < 1000 || StudyAssistantService.date(date.getTime()) !== value) throw new StudyInputError('日期不存在');
      return date.getTime();
    }
    try { return LocalTimetableApi.resolveSingleDay(value, now); }
    catch (_) { throw new StudyInputError('请提供明确日期，例如11月10日、2026-11-10、明天或下周一'); }
  }

  private static at(day: number, time: string): number {
    if (!/^([01]\d|2[0-3]):[0-5]\d$/.test(time)) throw new StudyInputError('时间需要 HH:mm 格式');
    const date: Date = new Date(day);
    date.setHours(Number(time.slice(0, 2)), Number(time.slice(3, 5)), 0, 0);
    if (StudyAssistantService.time(date.getTime()) !== time) throw new StudyInputError('该本地时间不存在，请选择其他时间');
    return date.getTime();
  }

  private static pagination(parameters: Record<string, Object>, key: string, fallback: number, max: number): number {
    const raw: Object | undefined = parameters[key];
    if (raw === undefined || raw === null || raw === '') return fallback;
    const value: number = typeof raw === 'string' && /^\d+$/.test(raw) ? Number(raw) : typeof raw === 'number' ? raw : -1;
    if (!Number.isSafeInteger(value) || value < (key === 'limit' ? 1 : 0) || value > max) throw new StudyInputError(key + ' 参数无效');
    return value;
  }

  static async query(context: common.Context, parameters: Record<string, Object>): Promise<Record<string, Object>> {
    const action: string = StudyAssistantService.text(parameters, 'action');
    if (action !== 'courses' && action !== 'tasks') throw new StudyInputError('action 需要 courses 或 tasks');
    const scope: StudyScope = await StudyAssistantService.scope(context);
    const keyword: string = StudyAssistantService.text(parameters, 'keyword');
    const offset: number = StudyAssistantService.pagination(parameters, 'offset', 0, 1000000);
    const limit: number = StudyAssistantService.pagination(parameters, 'limit', 10, 50);
    let records: Record<string, Object>[] = [];
    if (action === 'courses') records = StudyAssistantService.matches(scope.subjects, keyword).map(StudyAssistantService.courseView);
    else {
      const status: string = StudyAssistantService.text(parameters, 'status') || 'pending';
      if (['pending', 'completed', 'all'].indexOf(status) < 0) throw new StudyInputError('status 需要 pending、completed 或 all');
      const subjectId: string = StudyAssistantService.text(parameters, 'subjectId');
      const date: string = StudyAssistantService.text(parameters, 'dueDate');
      const day: number = date.length > 0 ? StudyAssistantService.day(date) : 0;
      const key: string = StudyAssistantService.normalized(keyword);
      const tasks: LearningTask[] = (await RdbHelper.getInstance().getLearningTasks()).filter(item =>
        item.kind === LearningTaskKind.HOMEWORK && item.timetableId === scope.table.id &&
        (subjectId.length === 0 || item.subjectId === subjectId) &&
        (status === 'all' || (status === 'completed' ? item.completedAt > 0 : item.completedAt === 0)) &&
        (key.length === 0 || StudyAssistantService.normalized(item.title + item.courseName).includes(key)) &&
        (day === 0 || (item.dueAt > 0 && LearningTaskRules.dayStart(item.dueAt) === day)));
      records = LearningTaskRules.sort(tasks, Date.now()).map(StudyAssistantService.taskView);
    }
    const page: Record<string, Object>[] = records.slice(offset, offset + limit);
    return { 'status': 'success', 'action': action, 'timetableId': scope.table.id, 'timetableName': scope.table.name,
      'currentDate': StudyAssistantService.date(Date.now()), 'timezoneOffsetMinutes': -new Date().getTimezoneOffset(),
      'total': records.length, 'returned': page.length, 'hasMore': offset + page.length < records.length,
      'nextOffset': offset + page.length < records.length ? offset + page.length : -1, 'records': page };
  }

  static operationView(operation: StudyOperation): Record<string, Object> {
    return { 'status': operation.status === 'pending' ? 'needs_confirmation' : operation.status,
      'operationId': operation.id, 'kind': operation.kind, 'timetableName': operation.timetableName,
      'task': StudyAssistantService.taskView(operation.task), 'expiresAt': operation.createdAt + 30 * 60000,
      'message': operation.status === 'pending' ? '草稿尚未保存。调用 ConfirmLearningOperation 打开 HITA 确认页，再查询操作结果。' :
        operation.status === 'saved' ? '操作已保存' : '操作已取消或过期，未执行新的写入' };
  }

  static async operation(context: common.Context, id: string): Promise<StudyOperation> {
    if (id.length === 0 || id.length > 120) throw new StudyInputError('请提供 operationId');
    const db: RdbHelper = RdbHelper.getInstance();
    await db.init(context);
    const operation: StudyOperation | undefined = await db.getStudyOperation(id);
    if (operation === undefined) throw new StudyInputError('操作不存在或已清理');
    return operation;
  }

  static async prepare(context: common.Context, kind: string, parameters: Record<string, Object>): Promise<Record<string, Object>> {
    if (kind !== 'create' && kind !== 'complete') throw new StudyInputError('不支持此操作');
    const key: string = StudyAssistantService.text(parameters, 'requestKey', 80);
    if (!/^[a-zA-Z0-9_-]{8,80}$/.test(key)) throw new StudyInputError('requestKey 需要8至80位字母、数字、横线或下划线；重试复用同一值');
    const subjectId: string = StudyAssistantService.text(parameters, 'subjectId');
    const courseName: string = StudyAssistantService.text(parameters, 'courseName');
    const title: string = StudyAssistantService.text(parameters, 'title');
    const note: string = StudyAssistantService.text(parameters, 'note', 4000);
    const dueDate: string = StudyAssistantService.text(parameters, 'dueDate');
    const dueTime: string = StudyAssistantService.text(parameters, 'dueTime');
    const remindDate: string = StudyAssistantService.text(parameters, 'remindDate');
    const remindTime: string = StudyAssistantService.text(parameters, 'remindTime');
    const taskId: string = StudyAssistantService.text(parameters, 'taskId');
    const signature: string = JSON.stringify({ kind: kind, subjectId: subjectId, courseName: courseName,
      title: title, note: note, dueDate: dueDate, dueTime: dueTime, remindDate: remindDate, remindTime: remindTime, taskId: taskId });
    const db: RdbHelper = RdbHelper.getInstance();
    await db.init(context);
    const previous: StudyOperation | undefined = await db.getStudyOperation(key, true);
    if (previous !== undefined) {
      if (previous.signature !== signature) throw new StudyInputError('requestKey 已用于其他操作，请重新发起');
      return StudyAssistantService.operationView(previous);
    }
    const scope: StudyScope = await StudyAssistantService.scope(context);
    const operation: StudyOperation = new StudyOperation();
    operation.kind = kind; operation.requestKey = key; operation.signature = signature; operation.timetableName = scope.table.name;
    if (kind === 'create') {
      if (subjectId.length === 0 && courseName.length === 0) throw new StudyInputError('请提供作业关联的课程名称或 subjectId');
      const candidates: EasTermSubject[] = subjectId.length > 0 ? scope.subjects.filter(item => item.id === subjectId) :
        StudyAssistantService.matches(scope.subjects, courseName);
      if (candidates.length !== 1) return { 'status': candidates.length === 0 ? 'course_not_found' : 'needs_selection',
        'message': candidates.length === 0 ? '当前课表未找到对应课程，请确认课程名称' : '找到多个课程，请用户选择后使用 subjectId 重试',
        'candidates': candidates.map(StudyAssistantService.courseView) };
      const task: LearningTask = operation.task;
      task.id = 'study-' + operation.id;
      task.timetableId = scope.table.id; task.subjectId = candidates[0].id;
      task.courseName = candidates[0].name; task.courseCode = candidates[0].code;
      task.title = title.length > 0 ? title : task.courseName + '作业'; task.note = note;
      if (dueDate.length === 0 && dueTime.length > 0) throw new StudyInputError('提供截止时间时还需要截止日期');
      if (dueDate.length > 0) {
        task.allDay = dueTime.length === 0;
        const day: number = StudyAssistantService.day(dueDate);
        task.dueAt = task.allDay ? day : StudyAssistantService.at(day, dueTime);
        if (LearningTaskRules.deadline(task) < Date.now()) throw new StudyInputError('截止日期已过，请确认日期');
      }
      if ((remindDate.length > 0) !== (remindTime.length > 0)) throw new StudyInputError('提醒需要同时提供日期和时间');
      if (remindDate.length > 0) {
        task.remindAt = StudyAssistantService.at(StudyAssistantService.day(remindDate), remindTime);
        if (task.remindAt <= Date.now()) throw new StudyInputError('请选择未来的提醒时间');
      }
      const message: string = LearningTaskRules.validation(task);
      if (message.length > 0) throw new StudyInputError(message);
      const duplicate: LearningTask | undefined = (await db.getLearningTasks()).find(item =>
        item.kind === task.kind && item.timetableId === task.timetableId && item.subjectId === task.subjectId &&
        item.title === task.title && item.note === task.note && item.dueAt === task.dueAt &&
        item.allDay === task.allDay && item.remindAt === task.remindAt);
      if (duplicate !== undefined) return { 'status': 'already_exists', 'message': '相同作业已存在，没有重复添加', 'task': StudyAssistantService.taskView(duplicate) };
    } else {
      if (taskId.length === 0) throw new StudyInputError('请先查询作业并提供准确 taskId');
      const task: LearningTask | undefined = (await db.getLearningTasks()).find(item => item.id === taskId &&
        item.kind === LearningTaskKind.HOMEWORK && item.timetableId === scope.table.id);
      if (task === undefined) throw new StudyInputError('当前课表找不到这条作业，请重新查询');
      if (task.completedAt > 0) return { 'status': 'already_completed', 'task': StudyAssistantService.taskView(task) };
      operation.task = LearningTaskRules.copy(task);
    }
    return StudyAssistantService.operationView(await db.prepareStudyOperation(operation));
  }

  static async finish(context: common.Context, id: string, confirm: boolean): Promise<StudyOperation> {
    const db: RdbHelper = RdbHelper.getInstance();
    await db.init(context);
    const operation: StudyOperation = await db.finishStudyOperation(id, confirm);
    if (operation.status === 'saved' && operation.kind === 'complete') await LearningTaskReminders.cancel(operation.task.id);
    return operation;
  }
}
