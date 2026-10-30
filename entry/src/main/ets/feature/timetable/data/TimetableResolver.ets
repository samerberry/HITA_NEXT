/** Selects an imported or manually created timetable for automatic display. */
import { RdbHelper } from '../../../common/db/RdbHelper';
import { EasTimetable } from '../../../common/model/timetable/TimetableModels';

// Exclude legacy generated records from automatic selection without deleting
// stored data: users can still manage those records in the timetable library.
const LEGACY_SAMPLE_CODE: string = 'LOCAL_DEMO_001';

export class TimetableResolver {
  static isReal(timetable: EasTimetable): boolean {
    // A blank timetable created from the manager is local-only. It must not
    // replace the imported EAS timetable selected by the main timetable view.
    return timetable.code !== LEGACY_SAMPLE_CODE &&
      !timetable.code.startsWith('LOCAL:');
  }

  static isLocal(timetable: EasTimetable): boolean {
    return timetable.code.startsWith('LOCAL:');
  }

  static async getReal(rdb: RdbHelper, strict: boolean = false): Promise<EasTimetable | undefined> {
    const all: EasTimetable[] = await rdb.getTimetables(strict);
    for (let i: number = 0; i < all.length; i++) {
      if (TimetableResolver.isReal(all[i])) {
        return all[i];
      }
    }
    return undefined;
  }

  static async getForDisplay(rdb: RdbHelper, strict: boolean = false): Promise<EasTimetable | undefined> {
    const real: EasTimetable | undefined = await TimetableResolver.getReal(rdb, strict);
    if (real !== undefined) {
      return real;
    }
    const all: EasTimetable[] = await rdb.getTimetables(strict);
    for (let i: number = 0; i < all.length; i++) {
      if (TimetableResolver.isLocal(all[i])) {
        return all[i];
      }
    }
    return undefined;
  }

  /** Android recent timetable semantics: latest timetable whose term has started. */
  static async getRecent(rdb: RdbHelper, now: number = Date.now()): Promise<EasTimetable | undefined> {
    const all: EasTimetable[] = await rdb.getTimetables();
    for (let i: number = 0; i < all.length; i++) {
      if (TimetableResolver.isReal(all[i]) && all[i].startTime <= now) {
        return all[i];
      }
    }
    return await TimetableResolver.getForDisplay(rdb);
  }
}
