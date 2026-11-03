import { LearningTask } from './LearningTask';
import { EasEventItem, EasEventType, EasTermSubject, EasTimetable, newId } from '../timetable/TimetableModels';

/** One dated class occurrence, kept separate from homework and from other calendar items. */
export class StudyCourseDraft {
  subject: EasTermSubject = new EasTermSubject();
  event: EasEventItem = new EasEventItem();
  newSubject: boolean = true;
  termStart: number = 0;
}

export function normalizedCourseName(value: string): string { return value.replace(/\s+/g, '').toLowerCase(); }

export function sameStudyCourse(a: EasEventItem, b: EasEventItem): boolean {
  return a.type === EasEventType.CLASS && b.type === EasEventType.CLASS && a.timetableId === b.timetableId &&
    normalizedCourseName(a.name) === normalizedCourseName(b.name) && a.from === b.from && a.to === b.to &&
    a.place === b.place && a.teacher === b.teacher;
}

export function studyCourseValidation(course: StudyCourseDraft, table: EasTimetable): string {
  const subject: EasTermSubject = course.subject;
  const event: EasEventItem = course.event;
  if (subject.id.length === 0 || event.id.length === 0 || subject.name.trim().length === 0 || subject.name.length > 120 ||
    event.name !== subject.name || event.subjectId !== subject.id || event.timetableId !== table.id ||
    subject.timetableId !== table.id || event.type !== EasEventType.CLASS || event.place.length > 120 || event.teacher.length > 120 ||
    !Number.isFinite(event.from) || !Number.isFinite(event.to) || event.to <= event.from ||
    new Date(event.from).toDateString() !== new Date(event.to).toDateString()) return '课程信息无效，请重新发起';
  if (course.termStart !== table.startTime) return '课表学期开始日期已变化，请重新发起';
  if (event.from < EasTimetable.mondayMsOf(table.startTime)) return '上课日期早于课表第一周，请确认日期或切换课表';
  return '';
}

/** A durable, single-use confirmation. Only the confirmation page may commit it. */
export class StudyOperation {
  id: string = newId();
  requestKey: string = '';
  signature: string = '';
  kind: string = 'create';
  status: string = 'pending';
  createdAt: number = Date.now();
  timetableName: string = '';
  task: LearningTask = new LearningTask();
  course: StudyCourseDraft = new StudyCourseDraft();
}

export function studyOperationExpired(operation: StudyOperation, now: number): boolean {
  return operation.status === 'pending' && now - operation.createdAt >= 30 * 60000;
}

export function sameStudyOperationTarget(a: StudyOperation, b: StudyOperation): boolean {
  if (a.kind === 'create_course' || b.kind === 'create_course') {
    return a.kind === b.kind && a.course.newSubject === b.course.newSubject &&
      a.course.termStart === b.course.termStart && sameStudyCourse(a.course.event, b.course.event) &&
      (a.course.newSubject || a.course.subject.id === b.course.subject.id);
  }
  if (a.kind !== b.kind || a.task.timetableId !== b.task.timetableId || a.task.subjectId !== b.task.subjectId) return false;
  if (a.kind === 'complete') return a.task.id === b.task.id && a.task.updatedAt === b.task.updatedAt;
  return a.task.courseName === b.task.courseName && a.task.courseCode === b.task.courseCode &&
    a.task.title === b.task.title && a.task.note === b.task.note && a.task.dueAt === b.task.dueAt &&
    a.task.allDay === b.task.allDay && a.task.remindAt === b.task.remindAt;
}
