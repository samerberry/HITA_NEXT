import { EasEventItem, EasEventType } from '../../../common/model/timetable/TimetableModels';
import { CourseBatchEdit } from '../CourseBatchEdit';

/** Share block grouping between calendar alarms and in-process notifications. */
export class ReminderEventSelection {
  static blocks(events: EasEventItem[]): EasEventItem[] {
    const sorted: EasEventItem[] = events.filter((event: EasEventItem): boolean =>
      event.type === EasEventType.CLASS || event.type === EasEventType.EXAM)
      .sort((a: EasEventItem, b: EasEventItem): number => a.from - b.from);
    const result: EasEventItem[] = [];
    for (const event of sorted) {
      const previous: EasEventItem | undefined = result.length > 0 ? result[result.length - 1] : undefined;
      if (previous !== undefined && event.type === EasEventType.CLASS && previous.type === EasEventType.CLASS &&
        event.subjectId.length > 0 && previous.subjectId === event.subjectId && previous.timetableId === event.timetableId &&
        previous.name === event.name && previous.place === event.place && previous.teacher === event.teacher &&
        new Date(previous.from).toDateString() === new Date(event.from).toDateString() &&
        event.from <= previous.to + 20 * 60000) {
        previous.to = Math.max(previous.to, event.to);
      } else {
        result.push(CourseBatchEdit.copy(event));
      }
    }
    return result;
  }
}
