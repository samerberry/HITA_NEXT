import { EasEventItem, EasEventType } from '../../common/model/timetable/TimetableModels';
import { CurrentClassSelection } from '../../common/model/timetable/CurrentClassSelection';

/** A small, local-only projection; never send accounts or credentials to the launcher. */
export class WidgetCourse {
  id: string = '';
  timetableId: string = '';
  name: string = '';
  place: string = '';
  teacher: string = '';
  from: number = 0;
  to: number = 0;
}

export class NextClassSnapshot {
  scheduleJson: string = '[]';
  // An empty string means this section could not be read; [] is a successful empty result.
  examJson: string = '';
  taskJson: string = '';
  hasTimetable: boolean = false;
  dataState: string = 'loading';
}

export class NextClassView {
  hasCourse: boolean = false;
  isOngoing: boolean = false;
  courseKey: string = '';
  title: string = '还没有课表';
  countdown: string = '—';
  hours: string = '';
  minutes: string = '';
  countdownUnit: string = '打开应用添加课表';
  startLabel: string = '下一节课';
  timeLabel: string = '';
  countdownMs: number = 0;
  countdownTarget: number = 0;
  place: string = '地点待定';
  teacher: string = '教师待定';
  progressPercent: number = 0;
}

export class NextClassModel {
  static snapshot(events: EasEventItem[], hasTimetable: boolean, now: number = Date.now(),
    timetableId: string = ''): NextClassSnapshot {
    const snapshot = new NextClassSnapshot();
    snapshot.hasTimetable = hasTimetable;
    snapshot.dataState = 'ready';
    const courses: WidgetCourse[] = [];
    const ordered = events.filter((event: EasEventItem): boolean => hasTimetable &&
      (timetableId.length === 0 || event.timetableId === timetableId) &&
      event.type === EasEventType.CLASS && Number.isFinite(event.from) &&
      Number.isFinite(event.to) && event.to > now && event.to > event.from)
      .sort((a: EasEventItem, b: EasEventItem): number => a.from - b.from || a.id.localeCompare(b.id));
    // Bounded payload. The extension refills it every 30 minutes, independently of the app.
    for (const event of ordered.slice(0, 64)) {
      const course = new WidgetCourse();
      course.id = event.id;
      course.timetableId = event.timetableId === undefined ? '' : event.timetableId;
      course.name = NextClassModel.label(event.name, '未命名课程');
      course.place = NextClassModel.label(event.place, '地点待定');
      course.teacher = NextClassModel.label(event.teacher, '教师待定');
      course.from = event.from;
      course.to = event.to;
      courses.push(course);
    }
    snapshot.scheduleJson = JSON.stringify(courses);
    return snapshot;
  }

  static view(scheduleJson: string, hasTimetable: boolean, dataState: string,
    now: number = Date.now()): NextClassView {
    const view = new NextClassView();
    if (dataState === 'loading') {
      view.title = '正在读取课表';
      view.countdownUnit = '稍候即可查看下一节课';
      return view;
    }
    if (dataState === 'error') {
      view.title = '课表暂不可用';
      view.countdownUnit = '打开应用后重试';
      return view;
    }
    if (!hasTimetable) return view;
    let courses: WidgetCourse[] = [];
    try {
      courses = JSON.parse(scheduleJson) as WidgetCourse[];
      if (!Array.isArray(courses)) throw new Error('Invalid schedule');
    } catch (_) {
      view.title = '课表暂不可用';
      view.countdownUnit = '打开应用后重试';
      return view;
    }
    const validCourses: WidgetCourse[] = courses.filter((course: WidgetCourse): boolean =>
      course !== null && typeof course === 'object');
    const selection = CurrentClassSelection.find(validCourses, now);
    const current: WidgetCourse | undefined = selection.current;
    const next: WidgetCourse | undefined = selection.next;
    if (current !== undefined) {
      NextClassModel.applyCourse(view, current, now);
      view.isOngoing = true;
      const duration = current.to - current.from;
      view.countdownTarget = current.to;
      view.countdownMs = Math.max(0, current.to - now);
      NextClassModel.setCountdown(view);
      view.countdownUnit = '后下课';
      view.progressPercent = Math.max(0, Math.min(100,
        (now - current.from) / duration * 100));
      return view;
    }
    if (next === undefined) {
      view.hasCourse = false;
      view.title = '暂无待上课程';
      view.countdownUnit = '打开应用查看课表';
      return view;
    }
    NextClassModel.applyCourse(view, next, now);
    view.isOngoing = false;
    view.countdownTarget = next.from;
    view.countdownMs = Math.max(0, next.from - now);
    NextClassModel.setCountdown(view);
    view.countdownUnit = '后上课';
    return view;
  }

  /** Name, place, teacher and time always come from the same selected course. */
  private static applyCourse(view: NextClassView, course: WidgetCourse, now: number): void {
    view.hasCourse = true;
    view.courseKey = course.timetableId + ':' + course.id;
    view.title = NextClassModel.label(course.name, '未命名课程');
    view.place = NextClassModel.label(course.place, '地点待定');
    view.teacher = NextClassModel.label(course.teacher, '教师待定');
    view.startLabel = NextClassModel.startLabel(course.from, now);
    view.timeLabel = NextClassModel.timeLabel(course.from, course.to, now);
  }

  static label(value: string, fallback: string): string {
    if (typeof value !== 'string') return fallback;
    const text = value.trim();
    return text.length === 0 || text.toUpperCase() === 'NULL' ? fallback : text.slice(0, 100);
  }

  static startLabel(from: number, now: number): string {
    const start = new Date(from);
    const date = NextClassModel.dateLabel(from, now);
    const hour = start.getHours().toString().padStart(2, '0');
    const minute = start.getMinutes().toString().padStart(2, '0');
    return date + ' ' + hour + ':' + minute;
  }

  static timeLabel(from: number, to: number, now: number): string {
    const start = new Date(from);
    const end = new Date(to);
    const sameDate: boolean = start.getFullYear() === end.getFullYear() &&
      start.getMonth() === end.getMonth() && start.getDate() === end.getDate();
    const endHour: string = end.getHours().toString().padStart(2, '0');
    const endMinute: string = end.getMinutes().toString().padStart(2, '0');
    return NextClassModel.startLabel(from, now) + '–' +
      (sameDate ? '' : NextClassModel.dateLabel(to, now) + ' ') + endHour + ':' + endMinute;
  }

  static dateLabel(timestamp: number, now: number): string {
    const start = new Date(timestamp);
    const today = new Date(now);
    const tomorrow = new Date(now);
    tomorrow.setDate(tomorrow.getDate() + 1);
    const date = start.toDateString() === today.toDateString() ? '今天' :
      (start.toDateString() === tomorrow.toDateString() ? '明天' :
        (start.getMonth() + 1).toString() + '月' + start.getDate().toString() + '日');
    return date;
  }

  private static setCountdown(view: NextClassView): void {
    // The service card intentionally presents the countdown at minute
    // precision. The cached timestamp remains millisecond precise so the
    // progress ring can still advance on every timer tick.
    const totalMinutes: number = Math.max(0, Math.ceil(view.countdownMs / 60000));
    const hours: number = Math.floor(totalMinutes / 60);
    const minutes: number = totalMinutes % 60;
    view.hours = hours > 0 ? hours.toString() : '';
    view.minutes = hours === 0 || minutes > 0 ? minutes.toString() : '';
    view.countdown = (view.hours ? view.hours + 'h' : '') + (view.minutes ? view.minutes + 'min' : '');
  }
}
