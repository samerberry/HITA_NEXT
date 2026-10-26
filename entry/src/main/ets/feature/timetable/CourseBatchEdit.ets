import { EasEventItem, EasEventType, EasTimetable } from '../../common/model/timetable/TimetableModels';

/** A course series is identified by subject and timetable, never its display name. */
export class CourseBatchEdit {
  static targets(events: EasEventItem[], anchor: EasEventItem, scope: number,
    weeks: number[], timetable: EasTimetable | undefined): EasEventItem[] {
    return events.filter((item: EasEventItem): boolean => {
      if (item.timetableId !== anchor.timetableId || item.type !== EasEventType.CLASS) return false;
      if (scope === 0 || anchor.subjectId.length === 0) return item.id === anchor.id;
      if (item.subjectId !== anchor.subjectId) return false;
      if (scope === 2) return item.from >= anchor.from;
      return timetable !== undefined && weeks.indexOf(timetable.getWeekNumber(item.from)) >= 0;
    }).sort((a: EasEventItem, b: EasEventItem): number => a.from - b.from);
  }

  static copy(source: EasEventItem): EasEventItem {
    const item: EasEventItem = new EasEventItem();
    item.id = source.id;
    item.type = source.type;
    item.name = source.name;
    item.place = source.place;
    item.teacher = source.teacher;
    item.subjectId = source.subjectId;
    item.timetableId = source.timetableId;
    item.from = source.from;
    item.to = source.to;
    item.fromNumber = source.fromNumber;
    item.lastNumber = source.lastNumber;
    item.createdAt = source.createdAt;
    item.color = source.color;
    return item;
  }

  /** Apply only changed fields; preserve variations between existing occurrences. */
  static update(items: EasEventItem[], original: EasEventItem, edited: EasEventItem): EasEventItem[] {
    const oldDay: Date = new Date(original.from);
    oldDay.setHours(0, 0, 0, 0);
    const newDay: Date = new Date(edited.from);
    newDay.setHours(0, 0, 0, 0);
    const days: number = Math.round((newDay.getTime() - oldDay.getTime()) / 86400000);
    const clockChanged: boolean = new Date(original.from).getHours() !== new Date(edited.from).getHours() ||
      new Date(original.from).getMinutes() !== new Date(edited.from).getMinutes() ||
      new Date(original.to).getHours() !== new Date(edited.to).getHours() ||
      new Date(original.to).getMinutes() !== new Date(edited.to).getMinutes();
    return items.map((source: EasEventItem): EasEventItem => {
      const item: EasEventItem = CourseBatchEdit.copy(source);
      if (edited.name !== original.name) item.name = edited.name;
      if (edited.place !== original.place) item.place = edited.place;
      if (edited.teacher !== original.teacher) item.teacher = edited.teacher;
      const from: Date = new Date(item.from);
      const to: Date = new Date(item.to);
      from.setDate(from.getDate() + days);
      to.setDate(to.getDate() + days);
      if (clockChanged) {
        const start: Date = new Date(edited.from);
        const end: Date = new Date(edited.to);
        from.setHours(start.getHours(), start.getMinutes(), 0, 0);
        to.setHours(end.getHours(), end.getMinutes(), 0, 0);
        item.fromNumber = 0;
        item.lastNumber = 0;
      }
      item.from = from.getTime();
      item.to = to.getTime();
      if (item.to <= item.from) throw new Error('结束时间必须晚于开始时间');
      return item;
    });
  }
}
