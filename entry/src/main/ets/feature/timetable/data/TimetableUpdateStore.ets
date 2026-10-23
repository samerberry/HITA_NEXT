/**
 * TimetableUpdateStore.ets — 记住每张教务课表最近一次导入或已提醒过的教务版本，以及上次检查的时间。
 *
 * 只有教务端内容相对这个版本发生变化时才再次提醒；用户在本地翘课、改课不会触发提醒。
 * 检查时间持久化，冷启动也遵守检查间隔。
 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const STORE_NAME: string = 'hitanext_store';
const SEEN_PREFIX: string = 'timetable_remote_seen_';
const CHECKED_PREFIX: string = 'timetable_update_checked_';

export class TimetableUpdateStore {
  private static instance: TimetableUpdateStore | undefined = undefined;
  private store: preferences.Preferences | undefined = undefined;

  static getInstance(): TimetableUpdateStore {
    if (TimetableUpdateStore.instance === undefined) {
      TimetableUpdateStore.instance = new TimetableUpdateStore();
    }
    return TimetableUpdateStore.instance;
  }

  async init(context: common.Context): Promise<void> {
    try {
      this.store = await preferences.getPreferences(context, { name: STORE_NAME });
    } catch (e) {
      this.store = undefined;
    }
  }

  async loadSeen(timetableId: string): Promise<string> {
    if (this.store === undefined || timetableId.length === 0) {
      return '';
    }
    try {
      const raw: preferences.ValueType = await this.store.get(SEEN_PREFIX + timetableId, '');
      return raw === undefined || raw === null ? '' : String(raw);
    } catch (e) {
      return '';
    }
  }

  /** 上次向教务检查这张课表的时间（毫秒）；从未检查过为 0。 */
  async loadCheckedAt(timetableId: string): Promise<number> {
    if (this.store === undefined || timetableId.length === 0) {
      return 0;
    }
    try {
      const raw: preferences.ValueType = await this.store.get(CHECKED_PREFIX + timetableId, 0);
      const value: number = Number(raw);
      return Number.isFinite(value) ? value : 0;
    } catch (e) {
      return 0;
    }
  }

  async saveCheckedAt(timetableId: string, time: number): Promise<void> {
    if (this.store === undefined || timetableId.length === 0) {
      return;
    }
    try {
      await this.store.put(CHECKED_PREFIX + timetableId, time);
      await this.store.flush();
    } catch (e) {}
  }

  async saveSeen(timetableId: string, fingerprint: string): Promise<void> {
    if (this.store === undefined || timetableId.length === 0 || fingerprint.length === 0) {
      return;
    }
    try {
      await this.store.put(SEEN_PREFIX + timetableId, fingerprint);
      await this.store.flush();
    } catch (e) {}
  }
}
