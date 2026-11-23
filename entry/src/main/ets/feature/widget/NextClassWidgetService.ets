import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { formBindingData, formProvider } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { RdbHelper } from '../../common/db/RdbHelper';
import { EasEventItem, EasTimetable } from '../../common/model/timetable/TimetableModels';
import { ScheduleChangeSignal } from '../../common/util/ScheduleChangeSignal';
import { TimetableSelectionStore } from '../timetable/data/TimetableSelectionStore';
import { TimetableResolver } from '../timetable/data/TimetableResolver';
import { timetableBlockColor } from '../timetable/views/TimetableWeekDraw';
import { NextClassModel, NextClassSnapshot } from './NextClassModel';
import { WidgetAgenda } from './WidgetAgenda';
import { WidgetWeek } from './WidgetWeek';
import { WidgetBackgroundFiles, WidgetBackgroundStore } from './WidgetBackgroundStore';

/** Card storage: schedule fields plus the baked background for each card size. */
class NextClassPayload extends NextClassSnapshot {
  courseOnly?: boolean;
  // Always sent so removing the background clears previously merged card storage.
  bgCompact: string = '';
  bgWide: string = '';
  formImages?: Record<string, number>;
}

export class NextClassWidgetService {
  private static context: common.Context | undefined = undefined;
  /** Replaceable in tests; reads only local files. */
  static backgroundFiles: (context: common.Context) => WidgetBackgroundFiles | undefined =
    (context: common.Context): WidgetBackgroundFiles | undefined => WidgetBackgroundStore.filesForPublish(context);
  private static timer: number = -1;
  private static revision: number = 0;
  private static publishing: boolean = false;
  private static pending: boolean = false;

  static attach(context: common.Context): void {
    NextClassWidgetService.context = context.getApplicationContext();
    ScheduleChangeSignal.listener = (): void => NextClassWidgetService.scheduleRefresh();
    NextClassWidgetService.scheduleRefresh();
  }

  static scheduleRefresh(): void {
    NextClassWidgetService.revision++;
    if (NextClassWidgetService.timer !== -1) clearTimeout(NextClassWidgetService.timer);
    // Imports contain many successful writes; publish only the settled schedule.
    NextClassWidgetService.timer = setTimeout((): void => {
      NextClassWidgetService.timer = -1;
      void NextClassWidgetService.refreshAll();
    }, 300);
  }

  /** fromCardProcess: the form extension must bypass its stale per-process preferences cache. */
  static async load(context: common.Context, fromCardProcess: boolean = false,
    includeWeek: boolean = false, onlyCourse: boolean = false): Promise<NextClassSnapshot> {
    let snapshot = new NextClassSnapshot();
    const rdb = RdbHelper.getInstance();
    try {
      await rdb.init(context);
    } catch (_) {
      snapshot.dataState = 'error';
      return snapshot;
    }
    const now = Date.now();
    try {
      let selectedId: string;
      if (fromCardProcess) {
        selectedId = await TimetableSelectionStore.loadLatest(context);
      } else {
        const selection = TimetableSelectionStore.getInstance();
        await selection.init(context);
        selectedId = await selection.load();
      }
      let timetable: EasTimetable | undefined = selectedId.length > 0 ?
        await rdb.getTimetableById(selectedId, true) : undefined;
      if (timetable === undefined) timetable = await TimetableResolver.getForDisplay(rdb, true);
      const events: EasEventItem[] = timetable === undefined ? [] : await rdb.getEventsOfTimetable(timetable.id, true);
      snapshot = NextClassModel.snapshot(events, timetable !== undefined, now,
        timetable === undefined ? '' : timetable.id);
      if (includeWeek) {
        const railColors = new Map<string, number>();
        if (timetable !== undefined) {
          try {
            const subjects = await rdb.getSubjectsOfTimetable(timetable.id);
            for (const subject of subjects) railColors.set(subject.id, timetableBlockColor(subject.color));
          } catch (_) {
            hilog.warn(0x0000, 'NextClassWidget', 'course colors unavailable');
          }
        }
        snapshot.weekJson = WidgetWeek.pack(events, now, railColors);
      }
    } catch (error) {
      hilog.warn(0x0000, 'NextClassWidget', 'load failed: %{public}s', String(error));
      snapshot.dataState = 'error';
    }
    if (onlyCourse) return snapshot;
    // The exam and task pages span timetables. A failed section must not blank the other two.
    try {
      snapshot.examJson = WidgetAgenda.exams(await rdb.getUpcomingExams(now), now);
    } catch (_) { hilog.warn(0x0000, 'NextClassWidget', 'exam list unavailable'); }
    try {
      snapshot.taskJson = WidgetAgenda.tasks(await rdb.getLearningTasks());
    } catch (_) { hilog.warn(0x0000, 'NextClassWidget', 'task list unavailable'); }
    return snapshot;
  }

  /** Called only by NextClassFormAbility, which runs in the card's own process. */
  static async refreshForm(context: common.Context, formId: string, formName: string = ''): Promise<void> {
    if (!formName) {
      try { formName = (await formProvider.getPublishedRunningFormInfoById(formId)).formName; } catch (_) {}
    }
    let revision: number;
    let snapshot: NextClassSnapshot;
    do {
      revision = NextClassWidgetService.revision;
      snapshot = await NextClassWidgetService.load(context, true, !formName || formName === 'WeekTimetableCard',
        formName === 'LessonCountdownCard');
    } while (revision !== NextClassWidgetService.revision);
    await NextClassWidgetService.publish(context, formId, snapshot, formName);
  }

  static async refreshAll(): Promise<void> {
    NextClassWidgetService.pending = true;
    if (NextClassWidgetService.publishing || NextClassWidgetService.context === undefined) return;
    NextClassWidgetService.publishing = true;
    try {
      while (NextClassWidgetService.pending) {
        NextClassWidgetService.pending = false;
        const revision = NextClassWidgetService.revision;
        const forms = (await formProvider.getPublishedRunningFormInfos()).filter((form): boolean =>
          form.moduleName === 'entry' && ['NextClassCard', 'LessonCountdownCard', 'WeekTimetableCard'].includes(form.formName));
        if (forms.length === 0) continue;
        const snapshot = await NextClassWidgetService.load(NextClassWidgetService.context, false,
          forms.some(form => form.formName === 'WeekTimetableCard'), forms.every(form => form.formName === 'LessonCountdownCard'));
        if (revision !== NextClassWidgetService.revision) {
          NextClassWidgetService.pending = true;
          continue;
        }
        for (const form of forms) {
          if (revision !== NextClassWidgetService.revision) {
            NextClassWidgetService.pending = true;
            break;
          }
          await NextClassWidgetService.publish(NextClassWidgetService.context, form.formId, snapshot, form.formName);
        }
      }
    } catch (error) {
      hilog.warn(0x0000, 'NextClassWidget', 'refresh failed: %{public}s', String(error));
    } finally {
      NextClassWidgetService.publishing = false;
    }
  }

  private static async publish(context: common.Context, formId: string, snapshot: NextClassSnapshot, formName: string): Promise<void> {
    const payload = new NextClassPayload();
    if (formName) payload.courseOnly = formName === 'LessonCountdownCard';
    if (formName !== 'WeekTimetableCard') payload.scheduleJson = snapshot.scheduleJson;
    if (!formName || formName === 'NextClassCard') payload.examJson = snapshot.examJson;
    if (formName !== 'LessonCountdownCard') payload.taskJson = snapshot.taskJson;
    if (!formName || formName === 'WeekTimetableCard') payload.weekJson = snapshot.weekJson;
    payload.hasTimetable = snapshot.hasTimetable;
    payload.dataState = snapshot.dataState;
    const opened: fileIo.File[] = [];
    try {
      const files = formName === 'WeekTimetableCard' ? undefined : NextClassWidgetService.backgroundFiles(context);
      if (files !== undefined) {
        // Each card gets its own descriptors; the image data is copied while binding.
        const compact = fileIo.openSync(files.compactPath, fileIo.OpenMode.READ_ONLY);
        opened.push(compact);
        const wide = fileIo.openSync(files.widePath, fileIo.OpenMode.READ_ONLY);
        opened.push(wide);
        const images: Record<string, number> = {};
        images[files.compactName] = compact.fd;
        images[files.wideName] = wide.fd;
        payload.bgCompact = files.compactName;
        payload.bgWide = files.wideName;
        payload.formImages = images;
      }
    } catch (error) {
      // The background was replaced or removed meanwhile; publish the schedule without it.
      hilog.warn(0x0000, 'NextClassWidget', 'background unavailable: %{public}s', String(error));
      NextClassWidgetService.close(opened);
      opened.length = 0;
      payload.bgCompact = '';
      payload.bgWide = '';
      payload.formImages = undefined;
    }
    try {
      await formProvider.updateForm(formId, formBindingData.createFormBindingData(payload));
    } catch (error) {
      // A card may have been removed while the local database was loading.
      hilog.warn(0x0000, 'NextClassWidget', 'publish failed: %{public}s', String(error));
    } finally {
      NextClassWidgetService.close(opened);
    }
  }

  private static close(files: fileIo.File[]): void {
    for (const file of files) {
      try {
        fileIo.closeSync(file);
      } catch (_) {
      }
    }
  }
}
