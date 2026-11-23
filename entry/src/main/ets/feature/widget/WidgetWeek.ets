import { EasEventItem, EasEventType } from '../../common/model/timetable/TimetableModels';

export class WeekItem {
  id: string = '';
  name: string = '';
  place: string = '';
  teacher?: string;
  railColor?: number;
  start: number = 0;
  end: number = 0;
  exam: boolean = false;
}

class WeekPacket {
  monday: number = 0;
  items: WeekItem[] = [];
}

export class WidgetDay {
  index: number = 0;
  date: number = 0;
  numeral: string = '';
  items: WeekItem[] = [];
}

export class WidgetWeek {
  days: WidgetDay[] = [];
  range: string = '';
  today: number = 0;
  message: string = '';
  stale: boolean = false;

  static dayOffset(time: number, count: number): number {
    const d = new Date(time);
    return new Date(d.getFullYear(), d.getMonth(), d.getDate() + count).getTime();
  }

  static monday(now: number): number {
    return WidgetWeek.dayOffset(now, -((new Date(now).getDay() + 6) % 7));
  }

  static clock(time: number): string {
    const d = new Date(time);
    return d.getHours().toString().padStart(2, '0') + ':' + d.getMinutes().toString().padStart(2, '0');
  }

  static shortDate(time: number): string {
    const d = new Date(time);
    return (d.getMonth() + 1) + '/' + d.getDate();
  }

  static pack(events: EasEventItem[], now: number, railColors: Map<string, number>): string {
    const packet = new WeekPacket();
    packet.monday = WidgetWeek.monday(now);
    const end = WidgetWeek.dayOffset(packet.monday, 7);
    for (const event of events) {
      if ((event.type !== EasEventType.CLASS && event.type !== EasEventType.EXAM) ||
        !Number.isFinite(event.from) || !Number.isFinite(event.to) || event.to <= event.from ||
        event.from >= end || event.to <= packet.monday) continue;
      const item = new WeekItem();
      item.id = event.id;
      item.exam = event.type === EasEventType.EXAM;
      item.name = (event.name || (item.exam ? '未命名考试' : '未命名课程')).slice(0, 80);
      item.place = (event.place || '').slice(0, 48);
      if (!item.exam) {
        item.teacher = (event.teacher || '').slice(0, 48);
        item.railColor = railColors.get(event.subjectId);
      }
      item.start = event.from;
      item.end = event.to;
      packet.items.push(item);
    }
    packet.items.sort((a, b) => a.start - b.start || a.end - b.end || a.id.localeCompare(b.id));
    return JSON.stringify(packet);
  }

  static view(json: string, hasTimetable: boolean, state: string, now: number): WidgetWeek {
    const week = new WidgetWeek();
    const monday = WidgetWeek.monday(now);
    week.today = (new Date(now).getDay() + 6) % 7;
    week.range = WidgetWeek.shortDate(monday) + ' – ' + WidgetWeek.shortDate(WidgetWeek.dayOffset(monday, 6));
    for (let i = 0; i < 7; i++) {
      const day = new WidgetDay();
      day.index = i;
      day.date = WidgetWeek.dayOffset(monday, i);
      day.numeral = new Date(day.date).getDate().toString();
      week.days.push(day);
    }
    if (state !== 'ready' || !hasTimetable) {
      week.message = state === 'loading' ? '正在读取课表' : state === 'error' ? '课表暂不可用' : '还没有课表';
      return week;
    }
    try {
      const packet = JSON.parse(json) as WeekPacket;
      if (packet.monday !== monday) {
        week.stale = true;
        week.message = '正在更新本周课表';
        return week;
      }
      for (const day of week.days) {
        const end = WidgetWeek.dayOffset(day.date, 1);
        for (const item of packet.items) {
          if (item.start >= end || item.end <= day.date) continue;
          day.items.push(item);
        }
      }
    } catch (_) {
      week.message = '课表暂不可用';
    }
    return week;
  }
}
