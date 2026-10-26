import { common } from '@kit.AbilityKit';
import { RdbHelper } from '../../../common/db/RdbHelper';
import { EasTimetable } from '../../../common/model/timetable/TimetableModels';
import { ScheduleChangeSignal } from '../../../common/util/ScheduleChangeSignal';
import { CalendarReminderOptions, CalendarSyncStore } from './CalendarSyncStore';
import { ClassReminderStore } from './ClassReminderStore';
import { ClassReminderScheduler } from './ClassReminderScheduler';
import { CalendarExportResult, TimetableCalendarExporter } from './TimetableCalendarExporter';
import { TimetableSelectionStore } from './TimetableSelectionStore';
import { TimetableResolver } from './TimetableResolver';

/** Serialize opt-in calendar reconciliation, including changes arriving during a sync. */
export class ScheduleSyncService {
  private static context: common.UIAbilityContext | undefined = undefined;
  private static queue: Promise<void> = Promise.resolve();
  private static timer: number = -1;
  private static tick: number = -1;
  private static restorePaused: boolean = false;
  private static reminderWork: Promise<void> = Promise.resolve();

  static async pauseForRestore(): Promise<void> {
    ScheduleSyncService.restorePaused = true;
    clearTimeout(ScheduleSyncService.timer);
    await ScheduleSyncService.queue;
    await ScheduleSyncService.reminderWork.catch(() => {});
  }

  static resumeAfterRestore(): void {
    ScheduleSyncService.restorePaused = false;
    ScheduleSyncService.schedule();
  }

  static attach(context: common.UIAbilityContext): void {
    ScheduleSyncService.context = context;
    ScheduleChangeSignal.subscribe('calendar-and-reminders', (): void => ScheduleSyncService.schedule());
    if (ScheduleSyncService.tick === -1) {
      ScheduleSyncService.tick = setInterval((): void => { void ScheduleSyncService.refreshReminders().catch(() => {}); }, 15000);
    }
    ScheduleSyncService.schedule();
  }

  static detach(): void {
    clearTimeout(ScheduleSyncService.timer);
    clearInterval(ScheduleSyncService.tick);
    ScheduleSyncService.timer = -1;
    ScheduleSyncService.tick = -1;
    ScheduleSyncService.context = undefined;
  }

  static schedule(): void {
    if (ScheduleSyncService.restorePaused) return;
    if (ScheduleSyncService.context === undefined) return;
    if (ScheduleSyncService.timer !== -1) clearTimeout(ScheduleSyncService.timer);
    ScheduleSyncService.timer = setTimeout((): void => {
      ScheduleSyncService.timer = -1;
      void ScheduleSyncService.syncNow().catch(() => {});
    }, 500);
  }

  private static enqueue(action: () => Promise<void>): Promise<void> {
    const next: Promise<void> = ScheduleSyncService.queue.then(action);
    ScheduleSyncService.queue = next.catch(() => {});
    return next;
  }

  static async options(context: common.Context): Promise<CalendarReminderOptions> {
    const store: ClassReminderStore = ClassReminderStore.getInstance();
    await store.init(context);
    const options: CalendarReminderOptions = new CalendarReminderOptions();
    options.classes = await store.loadEnabled(true);
    options.exams = await store.loadExamEnabled();
    options.classMinutes = await store.loadLeadMinutes(true);
    options.examMinutes = await store.loadExamLeadMinutes();
    return options;
  }

  static async enable(context: common.UIAbilityContext, timetable: EasTimetable): Promise<CalendarExportResult> {
    let result: CalendarExportResult = new CalendarExportResult();
    await ScheduleSyncService.enqueue(async (): Promise<void> => {
      const store: CalendarSyncStore = CalendarSyncStore.getInstance();
      await store.init(context);
      // Persist enrollment before publishing: partial writes must be discoverable after a process exit.
      const previous: boolean = await store.enabled(timetable.id);
      await store.setEnabled(timetable.id, true);
      result = await TimetableCalendarExporter.exportTimetable(context, timetable, true,
        await ScheduleSyncService.options(context), true);
      if (result.success) {
        await store.setCoverage(timetable.id, result.coverage);
        result.message = '已同步至手机日历，后续课程变更会自动更新';
      } else if (!previous && result.message.indexOf('权限') >= 0) {
        await store.setEnabled(timetable.id, false);
      }
      ScheduleSyncService.status(result.success ? '已同步至手机日历' : result.message);
    });
    ScheduleSyncService.schedule();
    return result;
  }

  static async disable(context: common.UIAbilityContext, timetableId: string): Promise<void> {
    await ScheduleSyncService.enqueue(async (): Promise<void> => {
      const store: CalendarSyncStore = CalendarSyncStore.getInstance();
      await store.init(context);
      // Do not claim to be disabled while old calendar alarms are still present.
      await TimetableCalendarExporter.clearTimetable(context, timetableId);
      await store.setCoverage(timetableId, []);
      await store.setEnabled(timetableId, false);
      ScheduleSyncService.status('已关闭同步并移除该课表的同步日程');
    });
  }

  static syncNow(): Promise<void> {
    return ScheduleSyncService.enqueue(async (): Promise<void> => {
      if (ScheduleSyncService.restorePaused) return;
      const context: common.UIAbilityContext | undefined = ScheduleSyncService.context;
      if (context === undefined) return;
      const store: CalendarSyncStore = CalendarSyncStore.getInstance();
      try {
        await store.init(context);
        const rdb: RdbHelper = RdbHelper.getInstance();
        await rdb.init(context);
        const options: CalendarReminderOptions = await ScheduleSyncService.options(context);
        let failed: boolean = false;
        let remindersDisabled: boolean = false;
        const ids: string[] = await store.ids();
        for (const id of ids) {
          try {
            const timetable: EasTimetable | undefined = await rdb.getTimetableById(id, true);
            if (timetable === undefined) {
              await TimetableCalendarExporter.clearTimetable(context, id);
              await store.setCoverage(id, []);
              await store.setEnabled(id, false);
            } else {
              const result: CalendarExportResult = await TimetableCalendarExporter.exportTimetable(context, timetable,
                false, options, true);
              if (!result.success) throw new Error(result.message);
              if (!result.calendarRemindersEnabled) remindersDisabled = true;
              await store.setCoverage(id, result.coverage);
            }
          } catch (_) { failed = true; }
        }
        if (ids.length > 0) ScheduleSyncService.status(failed ? '日历同步未完成，请检查权限后重试' :
          (remindersDisabled ? '日程已同步，手机日历中的提醒已关闭，请前往日历设置开启' : '已同步至手机日历'));
      } catch (_) { ScheduleSyncService.status('日历同步未完成，请稍后重试'); }
      await ScheduleSyncService.refreshReminders();
    });
  }

  static refreshReminders(): Promise<void> {
    if (ScheduleSyncService.restorePaused) return Promise.resolve();
    const work = ScheduleSyncService.reminderWork.catch(() => {}).then(() => ScheduleSyncService.refreshRemindersNow());
    ScheduleSyncService.reminderWork = work;
    return work;
  }

  private static async refreshRemindersNow(): Promise<void> {
    if (ScheduleSyncService.restorePaused) return;
    const context: common.UIAbilityContext | undefined = ScheduleSyncService.context;
    if (context === undefined) return;
    const rdb: RdbHelper = RdbHelper.getInstance();
    await rdb.init(context);
    const selection: TimetableSelectionStore = TimetableSelectionStore.getInstance();
    await selection.init(context);
    const id: string = await selection.load();
    let timetable: EasTimetable | undefined = id.length > 0 ? await rdb.getTimetableById(id, true) : undefined;
    if (timetable === undefined) timetable = await TimetableResolver.getForDisplay(rdb);
    await ClassReminderStore.getInstance().init(context);
    await ClassReminderScheduler.sync(context, timetable === undefined ? [] : await rdb.getEventsOfTimetable(timetable.id, true));
  }

  private static status(message: string): void {
    AppStorage.setOrCreate('hita_calendar_sync_status', message);
  }
}
