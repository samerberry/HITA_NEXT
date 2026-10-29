import { EasEventItem, EasEventType, EasTermSubject, EasTimetable, newId } from '../timetable/TimetableModels';

export enum LearningTaskKind {
  HOMEWORK = 'HOMEWORK',
  REVIEW = 'REVIEW'
}

/** Tasks belong to a subject or exam, never to a single class occurrence. */
export class LearningTask {
  id: string = newId();
  kind: LearningTaskKind = LearningTaskKind.HOMEWORK;
  title: string = '';
  note: string = '';
  timetableId: string = '';
  subjectId: string = '';
  courseName: string = '';
  courseCode: string = '';
  examId: string = '';
  examName: string = '';
  examAt: number = 0;
  dueAt: number = 0;
  allDay: boolean = false;
  completedAt: number = 0;
  remindAt: number = 0;
  notifiedAt: number = 0;
  createdAt: number = Date.now();
  updatedAt: number = Date.now();
}

export class LearningContext {
  timetables: EasTimetable[] = [];
  subjects: EasTermSubject[] = [];
  events: EasEventItem[] = [];
}

export class LearningTaskRules {
  static copy(task: LearningTask): LearningTask {
    return JSON.parse(JSON.stringify(task)) as LearningTask;
  }

  static dayStart(time: number): number {
    const date: Date = new Date(time);
    return new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
  }

  static deadline(task: LearningTask): number {
    if (!task.allDay || task.dueAt === 0) return task.dueAt;
    const date: Date = new Date(task.dueAt);
    return new Date(date.getFullYear(), date.getMonth(), date.getDate() + 1).getTime() - 1;
  }

  /** 0 overdue, 1 today, 2 later, 3 undated, 4 completed. */
  static group(task: LearningTask, now: number): number {
    if (task.completedAt > 0) return 4;
    if (task.dueAt === 0) return 3;
    if (LearningTaskRules.deadline(task) < now) return 0;
    return LearningTaskRules.dayStart(task.dueAt) === LearningTaskRules.dayStart(now) ? 1 : 2;
  }

  static sort(tasks: LearningTask[], now: number): LearningTask[] {
    return tasks.slice().sort((a: LearningTask, b: LearningTask): number => {
      const group: number = LearningTaskRules.group(a, now) - LearningTaskRules.group(b, now);
      if (group !== 0) return group;
      if (a.completedAt > 0) return b.completedAt - a.completedAt || a.id.localeCompare(b.id);
      return (a.dueAt || Number.MAX_SAFE_INTEGER) - (b.dueAt || Number.MAX_SAFE_INTEGER) ||
        a.createdAt - b.createdAt || a.id.localeCompare(b.id);
    });
  }

  /** Checks that hold for a saved task in any device time zone; reads and restores use only these. */
  static storedValidation(task: LearningTask): string {
    if (task.id.trim().length === 0) return '待办标识无效';
    if (task.title.trim().length === 0) return '请填写待办名称';
    if (task.title.length > 120 || task.note.length > 4000) return '名称或备注过长';
    if (task.kind !== LearningTaskKind.HOMEWORK && task.kind !== LearningTaskKind.REVIEW) return '待办类型无效';
    for (const time of [task.dueAt, task.examAt, task.completedAt, task.remindAt, task.notifiedAt,
      task.createdAt, task.updatedAt]) {
      if (!Number.isSafeInteger(time) || time < 0 || time > 8640000000000000) return '日期无效';
    }
    if (!Number.isFinite(LearningTaskRules.deadline(task))) return '日期无效';
    return '';
  }

  static validation(task: LearningTask): string {
    const stored: string = LearningTaskRules.storedValidation(task);
    if (stored.length > 0) return stored;
    // An all-day deadline follows the device time zone, so this rule is checked when saving only.
    if (task.remindAt > 0 && task.dueAt > 0 && task.remindAt > LearningTaskRules.deadline(task)) {
      return '提醒时间不能晚于截止时间';
    }
    return '';
  }

  static subject(task: LearningTask, context: LearningContext): EasTermSubject | undefined {
    const original: EasTermSubject | undefined = context.subjects.find((subject: EasTermSubject): boolean =>
      subject.id === task.subjectId && subject.timetableId === task.timetableId);
    if (original !== undefined) return original;
    // Relink only within the original timetable, and only on an unambiguous course identity.
    const matches: EasTermSubject[] = context.subjects.filter((subject: EasTermSubject): boolean =>
      subject.timetableId === task.timetableId && (task.courseCode.length > 0 ? subject.code === task.courseCode :
        task.courseName.length > 0 && subject.name === task.courseName));
    return matches.length === 1 ? matches[0] : undefined;
  }

  static exam(task: LearningTask, context: LearningContext): EasEventItem | undefined {
    return context.events.find((event: EasEventItem): boolean => event.id === task.examId &&
      event.timetableId === task.timetableId && event.type === EasEventType.EXAM);
  }

  static nextClass(subject: EasTermSubject, events: EasEventItem[], now: number): EasEventItem | undefined {
    return events.filter((event: EasEventItem): boolean => event.type === EasEventType.CLASS &&
      event.subjectId === subject.id && event.timetableId === subject.timetableId && event.from > now)
      .sort((a: EasEventItem, b: EasEventItem): number => a.from - b.from)[0];
  }

  static shifted(task: LearningTask, exam: EasEventItem): LearningTask {
    const result: LearningTask = LearningTaskRules.copy(task);
    if (task.completedAt > 0 || task.examId !== exam.id || task.timetableId !== exam.timetableId || task.examAt <= 0) {
      return result;
    }
    const delta: number = exam.from - task.examAt;
    if (result.dueAt > 0) result.dueAt += delta;
    if (result.remindAt > 0) result.remindAt += delta;
    result.examAt = exam.from;
    result.examName = exam.name;
    result.notifiedAt = 0;
    return result;
  }

  static reminderDue(task: LearningTask, now: number): boolean {
    return task.completedAt === 0 && task.remindAt > 0 && task.notifiedAt !== task.remindAt &&
      task.remindAt <= now && now - task.remindAt < 86400000;
  }
}
