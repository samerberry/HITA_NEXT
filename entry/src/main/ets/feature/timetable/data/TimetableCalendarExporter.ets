import { CalendarReminderOptions, CalendarSyncStore } from './CalendarSyncStore';
import { ReminderEventSelection } from './ReminderEventSelection';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { calendarManager } from '@kit.CalendarKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { RdbHelper } from '../../../common/db/RdbHelper';
import { EasEventItem, EasEventType, EasTimetable } from '../../../common/model/timetable/TimetableModels';

const CALENDAR_PERMISSIONS: Permissions[] = ['ohos.permission.READ_CALENDAR', 'ohos.permission.WRITE_CALENDAR'];
const EVENT_PREFIX: string = 'hita-course:';

export class CalendarExportResult {
  success: boolean = false;
  calendarRemindersEnabled: boolean = true;
  coverage: string[] = [];
  written: number = 0;
  total: number = 0;
  message: string = '';
}

export class TimetableCalendarExporter {
  // Serialize exports across pages, including while the permission dialog is open.
  private static exporting: boolean = false;

  static async exportTimetable(context: common.UIAbilityContext,
    timetable: EasTimetable | undefined, requestPermission: boolean = true,
    reminders: CalendarReminderOptions | undefined = undefined, allowEmpty: boolean = false): Promise<CalendarExportResult> {
    const result: CalendarExportResult = new CalendarExportResult();
    if (timetable === undefined) {
      result.message = '请先新建或导入课表';
      return result;
    }
    if (TimetableCalendarExporter.exporting) {
      result.message = '正在导出，请稍候';
      return result;
    }
    TimetableCalendarExporter.exporting = true;
    try {
      const rdb: RdbHelper = RdbHelper.getInstance();
      await rdb.init(context);
      const saved: EasTimetable | undefined = await rdb.getTimetableById(timetable.id, true);
      if (saved === undefined) {
        result.message = '课表不存在或已删除';
        return result;
      }
      const sources: EasEventItem[] = await rdb.getEventsOfTimetable(saved.id, true);
      const events: calendarManager.Event[] = TimetableCalendarExporter.calendarEvents(saved, sources, reminders);
      if (reminders !== undefined) {
        for (const event of ReminderEventSelection.blocks(sources)) {
          if ((event.type === EasEventType.CLASS && reminders.classes) || (event.type === EasEventType.EXAM && reminders.exams)) {
            result.coverage.push(CalendarSyncStore.coverageKey(event.id, event.from,
              event.type === EasEventType.EXAM ? reminders.examMinutes : reminders.classMinutes));
          }
        }
      }
      result.total = events.length;
      if (events.length === 0 && !allowEmpty) {
        result.message = '当前课表没有可导出的课程';
        return result;
      }
      if (requestPermission) {
        const permission = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(context, CALENDAR_PERMISSIONS);
        if (permission.authResults.length !== CALENDAR_PERMISSIONS.length ||
          permission.authResults.some((status: number): boolean => status !== 0)) {
          result.message = '未获得日历权限，请在系统设置中允许 HITA 访问日历后重试';
          return result;
        }
      }
      const calendar: calendarManager.Calendar = await TimetableCalendarExporter.getCalendar(context, saved);
      if (reminders !== undefined && requestPermission) {
        const config: calendarManager.CalendarConfig = await calendar.getConfig();
        config.enableReminder = true;
        await calendar.setConfig(config);
      }
      await TimetableCalendarExporter.writeEvents(calendar, events, result);
      if (reminders !== undefined && !(await calendar.getConfig()).enableReminder) {
        result.calendarRemindersEnabled = false;
        result.coverage = [];
      }
      result.success = true;
      hilog.info(0x0000, 'TimetableCalendar', 'export complete total=%{public}d', result.total);
      result.message = '已将 ' + result.total.toString() + ' 条日程导出至手机日历';
    } catch (e) {
      const code: number = (e as BusinessError).code;
      hilog.error(0x0000, 'TimetableCalendar',
        'export failed code=%{public}d written=%{public}d detail=%{private}s',
        code, result.written, (e as BusinessError).message);
      if (code === 201) {
        result.message = '日历权限不可用，请在系统设置中允许 HITA 访问日历后重试';
      } else if (e instanceof Error && e.message === 'INVALID_COURSE_TIME') {
        result.message = '课表中有无效的课程时间，请修正后重试';
      } else if (result.written > 0) {
        result.message = '已写入 ' + result.written.toString() + '/' + result.total.toString() +
          ' 条日程，导出未完成，请重试';
      } else {
        result.message = '导出至手机日历失败，请稍后重试';
      }
    } finally {
      TimetableCalendarExporter.exporting = false;
    }
    return result;
  }

  /** Remove our exports only; retain the account and every user-created event. Never create an account to clean it. */
  static async clearTimetable(context: common.UIAbilityContext, timetableId: string): Promise<void> {
    const manager: calendarManager.CalendarManager = calendarManager.getCalendarManager(context);
    const calendars: calendarManager.Calendar[] = await manager.getAllCalendars();
    for (const calendar of calendars) {
      const account: calendarManager.CalendarAccount = calendar.getAccount();
      if (account.name !== 'hita-timetable-' + timetableId || account.type !== calendarManager.CalendarType.LOCAL) continue;
      await TimetableCalendarExporter.writeEvents(calendar, [], new CalendarExportResult());
    }
  }

  private static async getCalendar(context: common.UIAbilityContext,
    timetable: EasTimetable): Promise<calendarManager.Calendar> {
    const manager: calendarManager.CalendarManager = calendarManager.getCalendarManager(context);
    const account: calendarManager.CalendarAccount = {
      name: 'hita-timetable-' + timetable.id,
      type: calendarManager.CalendarType.LOCAL,
      displayName: ('HITA · ' + timetable.name).slice(0, 64)
    };
    const calendars: calendarManager.Calendar[] = await manager.getAllCalendars();
    for (let i: number = 0; i < calendars.length; i++) {
      const existing: calendarManager.CalendarAccount = calendars[i].getAccount();
      if (existing.name === account.name && existing.type === account.type) {
        return calendars[i];
      }
    }
    const created: calendarManager.Calendar = await manager.createCalendar(account);
    if (!Number.isFinite(created.id) || created.id <= 0) {
      throw new Error('CALENDAR_CREATE_FAILED');
    }
    await created.setConfig({ enableReminder: true });
    return created;
  }

  private static calendarEvents(timetable: EasTimetable, sources: EasEventItem[],
    reminders: CalendarReminderOptions | undefined = undefined): calendarManager.Event[] {
    const starts: Set<string> = new Set<string>(ReminderEventSelection.blocks(sources).map((event: EasEventItem): string => event.id));
    const events: calendarManager.Event[] = [];
    const identifiers: Set<string> = new Set<string>();
    for (let i: number = 0; i < sources.length; i++) {
      const source: EasEventItem = sources[i];
      if (source.type === EasEventType.TAG || source.timetableId !== timetable.id) {
        continue;
      }
      if (!Number.isFinite(new Date(source.from).getTime()) ||
        !Number.isFinite(new Date(source.to).getTime()) || source.from <= 0 || source.to <= source.from) {
        throw new Error('INVALID_COURSE_TIME');
      }
      // EAS imports regenerate row IDs; the occurrence identity survives re-imports.
      const identifier: string = EVENT_PREFIX + JSON.stringify([source.type, source.name,
        source.from.toString(), source.to.toString()]);
      if (identifiers.has(identifier)) {
        continue;
      }
      identifiers.add(identifier);
      const description: string[] = ['课表：' + timetable.name];
      if (source.teacher.length > 0) {
        description.push('教师：' + source.teacher);
      }
      if (source.fromNumber > 0 && source.lastNumber >= source.fromNumber) {
        description.push('节次：第 ' + source.fromNumber.toString() + '-' + source.lastNumber.toString() + ' 节');
      }
      const event: calendarManager.Event = {
        type: calendarManager.EventType.NORMAL,
        title: source.name,
        startTime: source.from,
        endTime: source.to,
        isAllDay: false,
        timeZone: 'Asia/Shanghai',
        location: { location: source.place },
        description: description.join('\n'),
        identifier: identifier,
        reminderTime: reminders === undefined || !starts.has(source.id) ? [] :
          (source.type === EasEventType.CLASS && reminders.classes ? [reminders.classMinutes] :
            (source.type === EasEventType.EXAM && reminders.exams ? [reminders.examMinutes] : []))
      };
      events.push(event);
    }
    return events;
  }

  private static async writeEvents(calendar: calendarManager.Calendar, events: calendarManager.Event[],
    result: CalendarExportResult): Promise<void> {
    // Native overload dispatch rejects an explicit undefined filter (401).
    // API 20+ includes id and identifier in the no-argument query's default fields.
    const existing: calendarManager.Event[] = await calendar.getEvents();
    const byIdentifier: Map<string, calendarManager.Event> = new Map<string, calendarManager.Event>();
    for (let i: number = 0; i < existing.length; i++) {
      const event: calendarManager.Event = existing[i];
      if (event.identifier !== undefined && event.identifier.startsWith(EVENT_PREFIX) &&
        event.id !== undefined && event.id > 0) {
        byIdentifier.set(event.identifier, event);
      }
    }
    const keptIds: Set<number> = new Set<number>();
    for (let i: number = 0; i < events.length; i++) {
      const event: calendarManager.Event = events[i];
      const previous: calendarManager.Event | undefined = byIdentifier.get(event.identifier as string);
      if (previous !== undefined) {
        event.id = previous.id;
        if (!TimetableCalendarExporter.sameContent(previous, event)) await calendar.updateEvent(event);
        keptIds.add(previous.id as number);
      } else {
        const id: number = await calendar.addEvent(event);
        if (!Number.isFinite(id) || id <= 0) {
          throw new Error('CALENDAR_EVENT_WRITE_FAILED');
        }
        keptIds.add(id);
      }
      result.written++;
    }
    // Only prune our obsolete exports after every current occurrence was written.
    // User-created events in this calendar and other calendars are left intact.
    for (let i: number = 0; i < existing.length; i++) {
      const event: calendarManager.Event = existing[i];
      if (event.identifier !== undefined && event.identifier.startsWith(EVENT_PREFIX) &&
        event.id !== undefined && event.id > 0 && !keptIds.has(event.id)) {
        await calendar.deleteEvent(event.id);
      }
    }
  }

  private static sameContent(a: calendarManager.Event, b: calendarManager.Event): boolean {
    return a.type === b.type && a.title === b.title && a.startTime === b.startTime && a.endTime === b.endTime &&
      a.isAllDay === b.isAllDay && a.timeZone === b.timeZone && a.description === b.description &&
      a.location?.location === b.location?.location && JSON.stringify(a.reminderTime ?? []) === JSON.stringify(b.reminderTime ?? []);
  }
}
