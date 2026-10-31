import { LearningTask } from './LearningTask';
import { newId } from '../timetable/TimetableModels';

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
}

export function studyOperationExpired(operation: StudyOperation, now: number): boolean {
  return operation.status === 'pending' && now - operation.createdAt >= 30 * 60000;
}

export function sameStudyOperationTarget(a: StudyOperation, b: StudyOperation): boolean {
  if (a.kind !== b.kind || a.task.timetableId !== b.task.timetableId || a.task.subjectId !== b.task.subjectId) return false;
  if (a.kind === 'complete') return a.task.id === b.task.id && a.task.updatedAt === b.task.updatedAt;
  return a.task.courseName === b.task.courseName && a.task.courseCode === b.task.courseCode &&
    a.task.title === b.task.title && a.task.note === b.task.note && a.task.dueAt === b.task.dueAt &&
    a.task.allDay === b.task.allDay && a.task.remindAt === b.task.remindAt;
}
