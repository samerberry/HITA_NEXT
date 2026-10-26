import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

export class CalendarReminderOptions {
  classes: boolean = false;
  exams: boolean = false;
  classMinutes: number = 15;
  examMinutes: number = 60;
}

/** Only explicitly enrolled timetables may be written to the user's calendar. */
export class CalendarSyncStore {
  private static instance: CalendarSyncStore = new CalendarSyncStore();
  private store: preferences.Preferences | undefined = undefined;
  static getInstance(): CalendarSyncStore { return CalendarSyncStore.instance; }

  async init(context: common.Context): Promise<void> {
    if (this.store === undefined) this.store = await preferences.getPreferences(context, { name: 'hita_calendar_sync' });
  }

  async ids(): Promise<string[]> {
    if (this.store === undefined) return [];
    const parsed: string[] = JSON.parse(String(await this.store.get('timetables', '[]'))) as string[];
    if (!Array.isArray(parsed) || parsed.some((id: string): boolean => typeof id !== 'string' || id.length === 0)) {
      throw new Error('Invalid calendar sync settings');
    }
    return parsed;
  }

  async enabled(id: string): Promise<boolean> { return (await this.ids()).indexOf(id) >= 0; }

  async setEnabled(id: string, enabled: boolean): Promise<void> {
    if (this.store === undefined || id.length === 0) throw new Error('Calendar settings unavailable');
    const ids: string[] = (await this.ids()).filter((value: string): boolean => value !== id);
    if (enabled) ids.push(id);
    await this.store.put('timetables', JSON.stringify(ids));
    await this.store.flush();
  }

  static coverageKey(id: string, from: number, minutes: number): string {
    return JSON.stringify([id, from.toString(), minutes.toString()]);
  }

  async setCoverage(timetableId: string, keys: string[]): Promise<void> {
    if (this.store === undefined) throw new Error('Calendar settings unavailable');
    await this.store.put('coverage:' + timetableId, JSON.stringify(keys));
    await this.store.flush();
  }

  async covers(timetableId: string, id: string, from: number, minutes: number): Promise<boolean> {
    try {
      if (this.store === undefined || !(await this.enabled(timetableId))) return false;
      const keys: string[] = JSON.parse(String(await this.store.get('coverage:' + timetableId, '[]'))) as string[];
      return Array.isArray(keys) && keys.indexOf(CalendarSyncStore.coverageKey(id, from, minutes)) >= 0;
    } catch (_) { return false; }
  }
}
