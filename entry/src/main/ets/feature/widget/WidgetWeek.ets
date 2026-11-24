import { EasEventItem, EasEventType, EasTimetable } from '../../common/model/timetable/TimetableModels';
import { NextClassModel } from './NextClassModel';

export class WeekItem {
  id: string = '';
  name: string = '';
  place: string = '';
  teacher: string = '';
  start: number = 0;
  end: number = 0;
  exam: boolean = false;
  period: string = '';
  status?: string;
}

class WeekPacket {
  monday: number = 0;
  firstDate: number = 0;
  teachingWeeks: Record<string, number> = {};
  items: WeekItem[] = [];
}

export class WidgetDay {
  index: number = 0;
  date: number = 0;
  numeral: string = '';
  teachingWeek: number = 0;
  hasEvents: boolean = false;
  items: WeekItem[] = [];
}

export class WidgetWeek {
  days: WidgetDay[] = [];
  today: number = 0;
  message: string = '';
  stale: boolean = false;
  nextChange: number = 0;

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

  static termLabel(day: WidgetDay | undefined): string {
    if (!day) return '';
    const month = new Date(day.date).getMonth() + 1;
    return month + '月' + (day.teachingWeek > 0 ? '  ·  第' + day.teachingWeek + '周' : '');
  }

  static subtitle(item: WeekItem): string {
    return [item.place, item.teacher].filter((text: string) => !!text).join(' · ');
  }

  static pack(events: EasEventItem[], now: number, timetable?: EasTimetable): string {
    const packet = new WeekPacket();
    packet.monday = WidgetWeek.monday(now);
    // Include both Sunday-first and Monday-first weeks, including the next strip after Saturday midnight.
    packet.firstDate = WidgetWeek.dayOffset(packet.monday, -1);
    const end = WidgetWeek.dayOffset(packet.monday, 13);
    if (timetable && timetable.startTime > 0 && timetable.endTime >= timetable.startTime) {
      for (let offset = -7; offset <= 7; offset += 7) {
        const monday = WidgetWeek.dayOffset(packet.monday, offset);
        const number = timetable.getWeekNumber(monday);
        if (number > 0) packet.teachingWeeks[monday.toString()] = number;
      }
    }
    for (const event of events) {
      if ((event.type !== EasEventType.CLASS && event.type !== EasEventType.EXAM) ||
        !Number.isFinite(event.from) || !Number.isFinite(event.to) || event.to <= event.from ||
        event.from >= end || event.to <= packet.firstDate) continue;
      const item = new WeekItem();
      item.id = event.id;
      item.exam = event.type === EasEventType.EXAM;
      if (!item.exam && Number.isInteger(event.fromNumber) && Number.isInteger(event.lastNumber) &&
        event.fromNumber > 0 && event.lastNumber >= event.fromNumber) {
        item.period = '第' + event.fromNumber + (event.lastNumber === event.fromNumber ? '' : '–' + event.lastNumber) + '节';
      }
      item.name = NextClassModel.label(event.name, item.exam ? '未命名考试' : '未命名课程').slice(0, 80);
      item.place = NextClassModel.label(event.place, '').slice(0, 48);
      item.teacher = NextClassModel.label(event.teacher, '').slice(0, 48);
      item.start = event.from;
      item.end = event.to;
      packet.items.push(item);
    }
    packet.items.sort((a, b) => a.start - b.start || a.end - b.end || a.id.localeCompare(b.id));
    return JSON.stringify(packet);
  }

  static view(json: string, hasTimetable: boolean, state: string, now: number, calendar: boolean = false): WidgetWeek {
    const week = new WidgetWeek();
    const monday = WidgetWeek.monday(now);
    const weekday = new Date(now).getDay();
    week.today = calendar ? weekday : (weekday + 6) % 7;
    const today = WidgetWeek.dayOffset(now, 0);
    const first = calendar ? WidgetWeek.dayOffset(today, -weekday) : monday;
    week.nextChange = WidgetWeek.dayOffset(today, 1);
    for (let i = 0; i < 7; i++) {
      const day = new WidgetDay();
      day.index = i;
      day.date = WidgetWeek.dayOffset(first, i);
      day.numeral = new Date(day.date).getDate().toString();
      week.days.push(day);
    }
    if (state !== 'ready' || !hasTimetable) {
      week.message = state === 'loading' ? '正在读取课表' : state === 'error' ? '课表暂不可用' : '还没有课表';
      return week;
    }
    try {
      const packet = JSON.parse(json) as WeekPacket;
      // Older cached cards did not publish the Sunday preceding Monday. Refresh before calling that day empty.
      if (packet.monday !== monday || (calendar && packet.firstDate !== WidgetWeek.dayOffset(monday, -1))) {
        week.stale = true;
        week.message = '正在更新本周课表';
        return week;
      }
      for (const day of week.days) {
        day.teachingWeek = packet.teachingWeeks?.[WidgetWeek.monday(day.date).toString()] ?? 0;
        const end = WidgetWeek.dayOffset(day.date, 1);
        for (const item of packet.items) {
          if (item.start >= end || item.end <= day.date) continue;
          day.hasEvents = true;
          if (calendar) {
            item.status = item.end <= now ? '已结束' : item.start <= now ? '进行中' : '未开始';
            if (day.index === week.today && item.end > now) {
              week.nextChange = Math.min(week.nextChange, item.start > now ? item.start : item.end);
            }
          }
          day.items.push(item);
        }
      }
    } catch (_) {
      week.message = '课表暂不可用';
    }
    return week;
  }
}
