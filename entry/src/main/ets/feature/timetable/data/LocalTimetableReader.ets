import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { RdbHelper } from '../../../common/db/RdbHelper';
import { EasEventItem, EasTimetable } from '../../../common/model/timetable/TimetableModels';
import { TimetableResolver } from './TimetableResolver';
import { TimetableSelectionStore } from './TimetableSelectionStore';

export class LocalTimetableSnapshot {
  timetable: EasTimetable | undefined = undefined;
  events: EasEventItem[] = [];
}

/** Local data source for the timetable API and Xiaoyi intent executor. */
export class LocalTimetableReader {
  static async load(context: common.Context): Promise<LocalTimetableSnapshot> {
    const rdb: RdbHelper = RdbHelper.getInstance();
    hilog.info(0x0000, 'HitaQuery', 'read stage=database');
    await rdb.init(context);
    hilog.info(0x0000, 'HitaQuery', 'read stage=selection');
    const selectedId: string = await TimetableSelectionStore.loadForQuery(context);
    hilog.info(0x0000, 'HitaQuery', 'read stage=timetable');
    const snapshot: LocalTimetableSnapshot = new LocalTimetableSnapshot();
    if (selectedId.length > 0) {
      snapshot.timetable = await rdb.getTimetableById(selectedId, true);
    }
    if (snapshot.timetable === undefined) {
      // Same imported/local priority as Home; strict reads preserve database errors.
      const tables: EasTimetable[] = await rdb.getTimetables(true);
      snapshot.timetable = tables.find((table: EasTimetable): boolean => TimetableResolver.isReal(table)) ??
        tables.find((table: EasTimetable): boolean => TimetableResolver.isLocal(table));
    }
    if (snapshot.timetable !== undefined) {
      hilog.info(0x0000, 'HitaQuery', 'read stage=events');
      snapshot.events = await rdb.getEventsOfTimetable(snapshot.timetable.id, true);
    }
    // Include manually created standalone exams/events alongside the selected timetable.
    hilog.info(0x0000, 'HitaQuery', 'read stage=standalone');
    const standalone: EasEventItem[] = await rdb.getEventsOfTimetable('', true);
    snapshot.events = snapshot.events.concat(standalone);
    snapshot.events.sort((a: EasEventItem, b: EasEventItem): number => a.from - b.from || a.id.localeCompare(b.id));
    hilog.info(0x0000, 'HitaQuery', 'read completed events=%{public}d', snapshot.events.length);
    return snapshot;
  }
}
