/**
 * ExamSchedule.ets — 考试时间解析、倒计时与教务条目落库。
 * 无 UI / Kit 依赖，便于脚本测试。
 */
import { EasEventItem, EasEventType, newId } from '../../common/model/timetable/TimetableModels';
import { EasExamItem } from './model/EasModels';

export class ExamSchedule {
  static campusName(campus: string): string {
    if (campus === 'SHENZHEN') {
      return '深圳校区';
    }
    if (campus === 'BENBU') {
      return '本部';
    }
    if (campus === 'WEIHAI') {
      return '威海校区';
    }
    return '';
  }

  static remainingLabel(from: number, to: number, now: number): string {
    if (now >= to) {
      return '已结束';
    }
    if (now >= from && now < to) {
      return '进行中';
    }
    const start: Date = new Date(now);
    start.setHours(0, 0, 0, 0);
    const exam: Date = new Date(from);
    exam.setHours(0, 0, 0, 0);
    const days: number = Math.round((exam.getTime() - start.getTime()) / (24 * 60 * 60 * 1000));
    if (days <= 0) {
      return '今天';
    }
    if (days === 1) {
      return '明天';
    }
    return '还有 ' + days.toString() + ' 天';
  }

  static isUpcoming(to: number, now: number): boolean {
    return to >= now;
  }

  static parseRange(dateText: string, timeText: string): number[] | undefined {
    const combined: string = (dateText + ' ' + timeText).trim();
    const day: number | undefined = ExamSchedule.parseDay(combined);
    if (day === undefined) {
      return undefined;
    }
    const clocks: number[] | undefined = ExamSchedule.parseClocks(combined);
    if (clocks === undefined || clocks[1] <= clocks[0]) {
      return undefined;
    }
    return [day + clocks[0] * 60 * 1000, day + clocks[1] * 60 * 1000];
  }

  static sourceKey(source: string, item: EasExamItem): string {
    return source + JSON.stringify([item.courseName.trim(), item.examType.trim()]);
  }

  static toEvent(item: EasExamItem, timetableId: string, source: string = ''): EasEventItem | undefined {
    const range: number[] | undefined = ExamSchedule.parseRange(item.examDate, item.examTime);
    if (range === undefined || timetableId.length === 0) {
      return undefined;
    }
    const event: EasEventItem = new EasEventItem();
    event.id = newId();
    event.type = EasEventType.EXAM;
    event.name = item.courseName.trim();
    event.place = item.examLocation.trim();
    event.teacher = item.examType.trim();
    event.timetableId = timetableId;
    event.from = range[0];
    event.to = range[1];
    event.color = 0xFFD93025;
    if (source.length > 0) event.examSource = ExamSchedule.sourceKey(source, item);
    return event;
  }

  static dateOf(ms: number): string {
    const d: Date = new Date(ms);
    return d.getFullYear().toString() + '-' + ExamSchedule.pad(d.getMonth() + 1) + '-' +
      ExamSchedule.pad(d.getDate());
  }

  static timeOf(ms: number): string {
    const d: Date = new Date(ms);
    return ExamSchedule.pad(d.getHours()) + ':' + ExamSchedule.pad(d.getMinutes());
  }

  private static pad(n: number): string {
    return n < 10 ? '0' + n.toString() : n.toString();
  }

  private static parseDay(text: string): number | undefined {
    const match: RegExpExecArray | null = /(\d{4})\s*[-/.年]\s*(\d{1,2})\s*[-/.月]\s*(\d{1,2})/.exec(text);
    if (match === null) {
      return undefined;
    }
    const year: number = Number(match[1]);
    const month: number = Number(match[2]);
    const day: number = Number(match[3]);
    if (month < 1 || month > 12 || day < 1 || day > 31) {
      return undefined;
    }
    const parsed: Date = new Date(year, month - 1, day, 0, 0, 0, 0);
    return parsed.getFullYear() === year && parsed.getMonth() === month - 1 && parsed.getDate() === day ?
      parsed.getTime() : undefined;
  }

  private static parseClocks(text: string): number[] | undefined {
    const range: RegExpExecArray | null =
      /(\d{1,2})\s*[:：]\s*(\d{2})\s*[-~—–－～至到]+\s*(\d{1,2})\s*[:：]\s*(\d{2})/.exec(text);
    if (range !== null) {
      if (Number(range[1]) > 23 || Number(range[3]) > 23 ||
        Number(range[2]) > 59 || Number(range[4]) > 59) {
        return undefined;
      }
      return [
        Number(range[1]) * 60 + Number(range[2]),
        Number(range[3]) * 60 + Number(range[4])
      ];
    }
    return undefined;
  }
}
