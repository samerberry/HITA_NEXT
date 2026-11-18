import { EasTimePeriodInDay, EasTimetable } from '../../../common/model/timetable/TimetableModels';
import { IcsCalendarData, IcsEventInstance, IcsParser } from '../../../common/util/ICSImport';
import { EasCourseItem, EasTermItem } from '../model/EasModels';
import { DEMO_TIMETABLE_ICS } from './DemoTimetableSource';

/** The presentation timetable uses the attached calendar's local teaching dates and times. */
export class DemoTimetableData {
  static readonly CODE: string = 'DEMO:SHENZHEN:2026-20271';

  static term(): EasTermItem {
    const term: EasTermItem = new EasTermItem();
    term.yearCode = '2026-2027';
    term.yearName = '2026-2027 ';
    term.termCode = '1';
    term.termName = '第一学期';
    term.isCurrent = true;
    return term;
  }

  static matchesTerm(term: EasTermItem): boolean {
    return term.equalsKey(DemoTimetableData.term());
  }

  static startDate(): number {
    // The first ICS class is 2026-09-07 and explicitly says 第2周.
    return new Date(2026, 7, 31, 0, 0, 0, 0).getTime();
  }

  static courses(term: EasTermItem): EasCourseItem[] {
    if (!DemoTimetableData.matchesTerm(term)) return [];
    const calendar: IcsCalendarData = IcsParser.parse(DEMO_TIMETABLE_ICS);
    return calendar.events.map((event: IcsEventInstance): EasCourseItem => {
      const course: EasCourseItem = new EasCourseItem();
      const from: Date = new Date(event.from);
      const to: Date = new Date(event.to);
      const section: RegExpExecArray | null = /第(\d+)-(\d+)节/.exec(event.description);
      const teacher: RegExpExecArray | null = /教师[：:]\s*([^\n]+)/.exec(event.description);
      course.name = event.summary;
      course.rawName = event.summary;
      course.teacher = teacher === null ? '' : teacher[1].trim();
      course.classroom = event.location;
      course.scheduledDate = from.getFullYear().toString() + '-' +
        DemoTimetableData.two(from.getMonth() + 1) + '-' + DemoTimetableData.two(from.getDate());
      course.startTime = DemoTimetableData.two(from.getHours()) + ':' + DemoTimetableData.two(from.getMinutes());
      course.endTime = DemoTimetableData.two(to.getHours()) + ':' + DemoTimetableData.two(to.getMinutes());
      course.dayOfWeek = EasTimetable.dowOfMs(event.from);
      course.weekNumbers = [Math.floor((EasTimetable.mondayMsOf(event.from) - DemoTimetableData.startDate()) /
        (7 * 24 * 60 * 60 * 1000)) + 1];
      course.beginSection = section === null ? 0 : Number(section[1]);
      course.sectionCount = section === null ? 0 : Number(section[2]) - course.beginSection + 1;
      return course;
    });
  }

  /** Pair boundaries match the ICS exactly; the split inside a pair is for the demo grid only. */
  static schedule(): EasTimePeriodInDay[] {
    return [
      EasTimePeriodInDay.ofHour(8, 0, 8, 45), EasTimePeriodInDay.ofHour(8, 55, 9, 40),
      EasTimePeriodInDay.ofHour(10, 0, 10, 45), EasTimePeriodInDay.ofHour(10, 55, 11, 40),
      EasTimePeriodInDay.ofHour(14, 30, 15, 15), EasTimePeriodInDay.ofHour(15, 25, 16, 10),
      EasTimePeriodInDay.ofHour(16, 30, 17, 15), EasTimePeriodInDay.ofHour(17, 25, 18, 10),
      EasTimePeriodInDay.ofHour(19, 0, 19, 45), EasTimePeriodInDay.ofHour(19, 55, 20, 40),
      EasTimePeriodInDay.ofHour(21, 0, 21, 45), EasTimePeriodInDay.ofHour(21, 55, 22, 40)
    ];
  }

  private static two(value: number): string {
    return value < 10 ? '0' + value.toString() : value.toString();
  }
}
