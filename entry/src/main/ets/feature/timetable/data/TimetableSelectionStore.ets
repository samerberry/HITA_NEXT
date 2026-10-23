/** Persists the timetable selected for the main timetable/today views. */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { TimetableTheme } from '../../../common/theme/TimetableTheme';
import { ScheduleChangeSignal } from '../../../common/util/ScheduleChangeSignal';

const STORE_NAME: string = 'hitanext_store';
const MIRROR_FILE: string = 'active_timetable_id.txt';
const ACTIVE_TIMETABLE_KEY: string = 'active_timetable_id';
const TEXT_COLOR_KEY: string = 'timetable_text_color';
const CUSTOM_TEXT_COLOR_KEY: string = 'timetable_text_color_custom';

export class TimetableSelectionStore {
  private static instance: TimetableSelectionStore | undefined = undefined;
  private store: preferences.Preferences | undefined = undefined;
  private mirror: string = '';

  static getInstance(): TimetableSelectionStore {
    if (TimetableSelectionStore.instance === undefined) {
      TimetableSelectionStore.instance = new TimetableSelectionStore();
    }
    return TimetableSelectionStore.instance;
  }

  async init(context: common.Context): Promise<void> {
    try {
      this.store = await preferences.getPreferences(context, { name: STORE_NAME });
    } catch (e) {
      this.store = undefined;
    }
    if (this.mirror.length === 0) {
      try {
        this.mirror = TimetableSelectionStore.mirrorPath(context);
        // Older versions kept the selection only in preferences; seed the card's copy once per launch.
        this.writeMirror(await this.load());
      } catch (e) {
        this.mirror = '';
      }
    }
  }

  async load(): Promise<string> {
    if (this.store === undefined) {
      return '';
    }
    try {
      const raw: preferences.ValueType = await this.store.get(ACTIVE_TIMETABLE_KEY, '');
      return raw === undefined || raw === null ? '' : String(raw);
    } catch (e) {
      return '';
    }
  }

  /**
   * Reads the selection for the service card. The card may share the app process, so it must never evict
   * the shared preferences cache: a detached instance held by other stores would later flush the old
   * selection back to disk. The id is mirrored to a plain file that every write keeps current.
   */
  static async loadLatest(context: common.Context): Promise<string> {
    try {
      const path: string = TimetableSelectionStore.mirrorPath(context);
      if (!fileIo.accessSync(path)) {
        return '';
      }
      return fileIo.readTextSync(path).trim();
    } catch (e) {
      return '';
    }
  }

  async save(id: string): Promise<void> {
    if (this.store === undefined || id.length === 0) {
      return;
    }
    try {
      await this.store.put(ACTIVE_TIMETABLE_KEY, id);
      await this.store.flush();
      this.writeMirror(id);
      ScheduleChangeSignal.notify();
    } catch (e) {
    }
  }

  async clear(): Promise<void> {
    if (this.store === undefined) {
      return;
    }
    try {
      await this.store.delete(ACTIVE_TIMETABLE_KEY);
      await this.store.flush();
      this.writeMirror('');
      ScheduleChangeSignal.notify();
    } catch (e) {
    }
  }

  /** Application-level files dir: the same path from the app and the form extension. */
  private static mirrorPath(context: common.Context): string {
    return context.getApplicationContext().filesDir + '/' + MIRROR_FILE;
  }

  private writeMirror(id: string): void {
    if (this.mirror.length === 0) {
      return;
    }
    try {
      // Write then rename so the card never reads a half-written id.
      const temp: string = this.mirror + '.tmp';
      const file: fileIo.File = fileIo.openSync(temp,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      try {
        fileIo.writeSync(file.fd, id);
      } finally {
        fileIo.closeSync(file);
      }
      fileIo.renameSync(temp, this.mirror);
    } catch (e) {
      hilog.warn(0x0000, 'HitaSelection', 'mirror write failed: %{public}s', String(e));
    }
  }

  async clearIf(id: string): Promise<void> {
    if (id.length === 0) {
      return;
    }
    const current: string = await this.load();
    if (current === id) {
      await this.clear();
    }
  }

  async loadTextColor(fallback: string): Promise<string> {
    if (this.store === undefined) {
      return fallback;
    }
    try {
      const raw: preferences.ValueType = await this.store.get(TEXT_COLOR_KEY, fallback);
      const color: string = raw === undefined || raw === null ? fallback : String(raw);
      const custom = await this.store.get(CUSTOM_TEXT_COLOR_KEY, false);
      // Older versions saved the default theme color as if it were a manual choice.
      if (color.toUpperCase() === TimetableTheme.DEFAULT_TEXT && custom !== true) return TimetableTheme.AUTO_TEXT;
      return color === TimetableTheme.AUTO_TEXT || /^#[0-9A-Fa-f]{6}$/.test(color) ? color : fallback;
    } catch (e) {
      return fallback;
    }
  }

  async saveTextColor(color: string): Promise<void> {
    if (this.store === undefined || (color !== TimetableTheme.AUTO_TEXT && !/^#[0-9A-Fa-f]{6}$/.test(color))) {
      throw new Error('Text color store unavailable or invalid color');
    }
    const previous = await this.store.get(TEXT_COLOR_KEY, TimetableTheme.AUTO_TEXT);
    const wasCustom = await this.store.get(CUSTOM_TEXT_COLOR_KEY, false);
    try {
      await this.store.put(TEXT_COLOR_KEY, color);
      await this.store.put(CUSTOM_TEXT_COLOR_KEY, color !== TimetableTheme.AUTO_TEXT);
      await this.store.flush();
    } catch (_) {
      await this.store.put(TEXT_COLOR_KEY, previous);
      await this.store.put(CUSTOM_TEXT_COLOR_KEY, wasCustom);
      throw new Error('Text color save failed');
    }
  }
}
