import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { fileIo, picker } from '@kit.CoreFileKit';
import { RdbHelper } from '../../common/db/RdbHelper';
import { newId } from '../../common/model/timetable/TimetableModels';
import { AppearanceStore } from '../../common/theme/AppearanceStore';
import { TimetableBackgroundStore } from '../timetable/data/TimetableBackgroundStore';
import { TimetableDisplayOptions } from '../timetable/data/TimetableDisplayOptions';
import { ScheduleSyncService } from '../timetable/data/ScheduleSyncService';
import { WidgetBackgroundStore } from '../widget/WidgetBackgroundStore';
import { BackupArchive, BackupSource, PreparedBackup } from './BackupArchive';
import { BackupManifest, BackupModel, BackupSettings } from './BackupModel';

const KEYS: string[] = ['class_reminder_enabled', 'class_reminder_lead_minutes', 'exam_reminder_enabled',
  'exam_reminder_lead_minutes', 'active_timetable_id', 'timetable_text_color', 'timetable_text_color_custom',
  'timetable_display_options'];
const DEFAULTS: preferences.ValueType[] = [false, 15, false, 60, '', 'auto', false, ''];
const JOURNAL: string = '/backup-restore-journal.json';

class SavedPreference {
  exists: boolean = false;
  value: preferences.ValueType = '';
}
class SavedFile {
  exists: boolean = false;
  text: string = '';
}
class RestoreJournal {
  receipt: string = '';
  previous: SavedPreference[] = [];
  appearance: SavedPreference = new SavedPreference();
  files: SavedFile[] = [];
  created: string[] = [];
}

export class BackupService {
  private static busy: boolean = false;

  static async exportFile(context: common.UIAbilityContext, progress: (message: string) => void): Promise<boolean> {
    if (BackupService.busy) throw new Error('正在处理另一项备份操作');
    BackupService.busy = true;
    const path = context.cacheDir + '/hita-export-' + newId() + '.hita-backup';
    try {
      progress('正在读取课表与设置');
      const rdb = RdbHelper.getInstance();
      await rdb.init(context);
      const manifest = new BackupManifest();
      manifest.timetables = await rdb.createBackupSnapshot();
      manifest.settings = await BackupService.readSettings(context);
      // A removed/stale selection is not an invalid backup; the first table is the display fallback.
      if (!manifest.timetables.some(item => item.timetable.id === manifest.settings.activeTimetable)) {
        manifest.settings.activeTimetable = manifest.timetables[0]?.timetable.id ?? '';
      }
      const sources: BackupSource[] = [];
      const background = TimetableBackgroundStore.load(context);
      if (background.imagePath) sources.push(new BackupSource('poster', background.imagePath));
      if (background.videoPath) sources.push(new BackupSource('video', background.videoPath));
      const widget = WidgetBackgroundStore.load(context);
      if (widget !== undefined) {
        const files = WidgetBackgroundStore.filesForPublish(context);
        if (files === undefined) throw new Error('服务卡片背景文件缺失，请重新设置背景后备份');
        sources.push(new BackupSource('widgetSource', WidgetBackgroundStore.sourcePath(context, widget)));
        sources.push(new BackupSource('widgetCompact', files.compactPath));
        sources.push(new BackupSource('widgetWide', files.widePath));
        widget.source = widget.source.endsWith('.png') ? 'source.png' : 'source.jpg';
        manifest.widget = widget;
      }
      await BackupArchive.create(path, manifest, sources, progress);
      progress('请选择保存位置');
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = ['HITA-NEXT-' + new Date().toISOString().slice(0, 10) + '.hita-backup'];
      options.fileSuffixChoices = ['HITA NEXT 备份|.hita-backup'];
      const uris = await new picker.DocumentViewPicker(context).save(options);
      if (uris.length === 0) return false;
      progress('正在保存备份');
      const output = await fileIo.open(uris[0], fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      try { await fileIo.copyFile(path, output.fd); await fileIo.fsync(output.fd); }
      finally { await fileIo.close(output); }
      return true;
    } finally {
      BackupService.unlink(path);
      BackupService.busy = false;
    }
  }

  static async pick(context: common.UIAbilityContext, progress: (message: string) => void): Promise<PreparedBackup | undefined> {
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.fileSuffixFilters = ['HITA NEXT 备份|.hita-backup'];
    const uris = await new picker.DocumentViewPicker(context).select(options);
    if (uris.length === 0) return undefined;
    const directory = context.cacheDir + '/hita-backup-' + newId();
    try { return await BackupArchive.prepare(uris[0], directory, progress); }
    catch (error) { BackupService.discardDirectory(directory); throw error as Error; }
  }

  static discard(prepared: PreparedBackup | undefined): void {
    if (prepared !== undefined) BackupService.discardDirectory(prepared.directory);
  }

  static async restore(context: common.UIAbilityContext, prepared: PreparedBackup,
    progress: (message: string) => void): Promise<void> {
    if (BackupService.busy) throw new Error('正在处理另一项备份操作');
    BackupService.busy = true;
    let journal: RestoreJournal | undefined = undefined;
    try {
      await ScheduleSyncService.pauseForRestore();
      await BackupService.recover(context);
      const rdb = RdbHelper.getInstance();
      await rdb.init(context);
      progress('正在检查恢复文件');
      await BackupArchive.verify(prepared);
      const copy = BackupModel.remap(prepared.manifest);
      journal = await BackupService.capture(context);
      journal.receipt = newId();
      // All destination names are generated locally. Never use a path supplied by a backup.
      const dir = context.filesDir + '/restored-' + journal.receipt;
      for (const asset of copy.assets) journal.created.push(dir + '-' + asset.role + BackupService.extension(asset.role, copy));
      BackupService.writeText(context.filesDir + JOURNAL, JSON.stringify(journal));
      progress('正在恢复背景');
      for (let i = 0; i < copy.assets.length; i++) {
        await BackupService.copyDurable(prepared.directory + '/' + copy.assets[i].role, journal.created[i]);
      }
      const created = journal.created;
      const lookup = (role: string): string => {
        const index = copy.assets.findIndex(asset => asset.role === role);
        return index >= 0 ? created[index] : '';
      };
      progress('正在恢复课表与设置');
      await rdb.restoreBackup(copy.timetables, journal.receipt, async (): Promise<void> => {
        await BackupService.writeSettings(context, copy.settings);
        BackupService.writeText(context.filesDir + '/timetable-background.json',
          JSON.stringify({ imagePath: lookup('poster'), videoPath: lookup('video') }));
        const widgetFile = WidgetBackgroundStore.dir(context) + '/state.json';
        if (copy.widget !== undefined) {
          const w = copy.widget;
          const previous = WidgetBackgroundStore.load(context);
          w.revision = Math.max(Date.now(), (previous?.revision ?? 0) + 1);
          const widgetDir = WidgetBackgroundStore.dir(context);
          if (!fileIo.accessSync(widgetDir)) fileIo.mkdirSync(widgetDir, true);
          // Widget readers accept filenames within their directory, so publish copies there.
          w.source = 'source-' + w.revision.toString() + (copy.widget.source.endsWith('.png') ? '.png' : '.jpg');
          const targets: string[] = [widgetDir + '/' + w.source, widgetDir + '/compact-' + w.revision.toString() + '.jpg',
            widgetDir + '/wide-' + w.revision.toString() + '.jpg'];
          journal!.created.push(...targets);
          BackupService.writeText(context.filesDir + JOURNAL, JSON.stringify(journal));
          await BackupService.copyDurable(lookup('widgetSource'), targets[0]);
          await BackupService.copyDurable(lookup('widgetCompact'), targets[1]);
          await BackupService.copyDurable(lookup('widgetWide'), targets[2]);
          BackupService.writeText(widgetFile, JSON.stringify(w));
        } else BackupService.unlink(widgetFile);
        BackupService.writeText(context.getApplicationContext().filesDir + '/active_timetable_id.txt', copy.settings.activeTimetable);
      });
      // A committed receipt makes startup recovery finish the operation even after a process exit here.
      BackupService.finishCommitted(context, journal);
      BackupService.unlink(context.filesDir + JOURNAL);
      AppearanceStore.getInstance().initialize(context);
      AppearanceStore.getInstance().onContentReady();
      AppStorage.setOrCreate('hita_backup_revision', Date.now());
    } catch (error) {
      if (journal !== undefined) await BackupService.recover(context);
      throw error as Error;
    } finally {
      ScheduleSyncService.resumeAfterRestore();
      BackupService.busy = false;
    }
  }

  /** Called before loading Home or starting reminders; a durable receipt decides commit versus rollback. */
  static async recover(context: common.Context): Promise<void> {
    const path = context.filesDir + JOURNAL;
    if (!fileIo.accessSync(path)) return;
    const journal = JSON.parse(fileIo.readTextSync(path)) as RestoreJournal;
    if (!/^[a-z0-9]+-[a-z0-9]+$/.test(journal.receipt) || journal.previous.length !== KEYS.length || journal.files.length !== 3) {
      throw new Error('备份恢复记录损坏，请保留应用数据');
    }
    const rdb = RdbHelper.getInstance();
    await rdb.init(context);
    if (!await rdb.hasBackupReceipt(journal.receipt)) {
      // Free staged video space first, so a full disk cannot prevent restoring the small state files.
      for (const created of journal.created) {
        if (created.startsWith(context.filesDir + '/restored-' + journal.receipt + '-') ||
          /^\/(source|compact|wide)-[0-9]+\.(jpg|png)$/.test(created.slice(WidgetBackgroundStore.dir(context).length)) &&
          created.startsWith(WidgetBackgroundStore.dir(context) + '/')) BackupService.unlink(created);
      }
      const store = await preferences.getPreferences(context, { name: 'hitanext_store' });
      for (let i = 0; i < KEYS.length; i++) {
        const previous = journal.previous[i];
        if (previous.exists) await store.put(KEYS[i], previous.value);
        else await store.delete(KEYS[i]);
      }
      await store.flush();
      const appearance = await preferences.getPreferences(context, { name: 'hita_appearance' });
      if (journal.appearance.exists) await appearance.put('mode', journal.appearance.value);
      else await appearance.delete('mode');
      await appearance.flush();
      const paths = BackupService.statePaths(context);
      for (let i = 0; i < paths.length; i++) {
        if (journal.files[i].exists) BackupService.writeText(paths[i], journal.files[i].text);
        else BackupService.unlink(paths[i]);
      }
    } else BackupService.finishCommitted(context, journal);
    // Do not remove the journal if rollback throws: the next launch can retry safely.
    fileIo.unlinkSync(path);
  }

  private static async readSettings(context: common.Context): Promise<BackupSettings> {
    const store = await preferences.getPreferences(context, { name: 'hitanext_store' });
    const s = new BackupSettings();
    s.classEnabled = await store.get(KEYS[0], false) as boolean;
    s.classMinutes = await store.get(KEYS[1], 15) as number;
    s.examEnabled = await store.get(KEYS[2], false) as boolean;
    s.examMinutes = await store.get(KEYS[3], 60) as number;
    s.activeTimetable = await store.get(KEYS[4], '') as string;
    s.textColor = await store.get(KEYS[5], 'auto') as string;
    s.customTextColor = await store.get(KEYS[6], false) as boolean;
    s.display = TimetableDisplayOptions.parse(await store.get(KEYS[7], '') as string);
    const appearance = await preferences.getPreferences(context, { name: 'hita_appearance' });
    s.appearance = await appearance.get('mode', 'system') as string;
    return s;
  }

  private static async writeSettings(context: common.Context, s: BackupSettings): Promise<void> {
    const store = await preferences.getPreferences(context, { name: 'hitanext_store' });
    const values: preferences.ValueType[] = [s.classEnabled, s.classMinutes, s.examEnabled, s.examMinutes,
      s.activeTimetable, s.textColor, s.customTextColor, JSON.stringify(s.display)];
    for (let i = 0; i < KEYS.length; i++) await store.put(KEYS[i], values[i]);
    await store.flush();
    const appearance = await preferences.getPreferences(context, { name: 'hita_appearance' });
    await appearance.put('mode', s.appearance);
    await appearance.flush();
  }

  private static async capture(context: common.Context): Promise<RestoreJournal> {
    const result = new RestoreJournal();
    const store = await preferences.getPreferences(context, { name: 'hitanext_store' });
    for (let i = 0; i < KEYS.length; i++) {
      const item = new SavedPreference();
      item.exists = await store.has(KEYS[i]);
      item.value = await store.get(KEYS[i], DEFAULTS[i]);
      result.previous.push(item);
    }
    const appearance = await preferences.getPreferences(context, { name: 'hita_appearance' });
    result.appearance.exists = await appearance.has('mode');
    result.appearance.value = await appearance.get('mode', 'system');
    for (const path of BackupService.statePaths(context)) {
      const item = new SavedFile();
      item.exists = fileIo.accessSync(path);
      if (item.exists) item.text = fileIo.readTextSync(path);
      result.files.push(item);
    }
    return result;
  }

  private static statePaths(context: common.Context): string[] {
    return [context.filesDir + '/timetable-background.json', WidgetBackgroundStore.dir(context) + '/state.json',
      context.getApplicationContext().filesDir + '/active_timetable_id.txt'];
  }
  /** Stale exports/previews can be large videos; clean them only at cold startup, before a picker can be active. */
  static clearAbandonedFiles(context: common.Context): void {
    try {
      for (const name of fileIo.listFileSync(context.cacheDir)) {
        if (/^hita-export-[a-z0-9]+-[a-z0-9]+\.hita-backup$/.test(name)) BackupService.unlink(context.cacheDir + '/' + name);
        if (/^hita-backup-[a-z0-9]+-[a-z0-9]+$/.test(name)) BackupService.discardDirectory(context.cacheDir + '/' + name);
      }
    } catch (_) {}
  }
  private static finishCommitted(context: common.Context, journal: RestoreJournal): void {
    // Redundant widget staging copies are no longer needed after the widget state has been published.
    for (const created of journal.created) {
      if (created.startsWith(context.filesDir + '/restored-' + journal.receipt + '-widget')) BackupService.unlink(created);
    }
    BackupService.unlink(TimetableBackgroundStore.destPath(context));
    try {
      const old = JSON.parse(journal.files[0].text) as Record<string, string>;
      for (const path of [old['imagePath'], old['videoPath']]) {
        if (typeof path === 'string' && path.startsWith(context.filesDir + '/') &&
          /^(timetable-background-[a-z0-9-]+\.(jpg|video)|restored-[a-z0-9-]+-(poster\.jpg|video\.video))$/
            .test(path.slice(context.filesDir.length + 1))) BackupService.unlink(path);
      }
    } catch (_) {}
    try {
      const old = JSON.parse(journal.files[1].text) as Record<string, Object>;
      const source = old['source'];
      const revision = old['revision'];
      if (typeof source === 'string' && /^source-[0-9]+\.(jpg|png)$/.test(source)) {
        BackupService.unlink(WidgetBackgroundStore.dir(context) + '/' + source);
      }
      if (typeof revision === 'number' && Number.isSafeInteger(revision)) {
        BackupService.unlink(WidgetBackgroundStore.dir(context) + '/compact-' + revision.toString() + '.jpg');
        BackupService.unlink(WidgetBackgroundStore.dir(context) + '/wide-' + revision.toString() + '.jpg');
      }
    } catch (_) {}
  }
  private static async copyDurable(source: string, target: string): Promise<void> {
    await fileIo.copyFile(source, target);
    const file = await fileIo.open(target, fileIo.OpenMode.READ_WRITE);
    try { await fileIo.fsync(file.fd); } finally { await fileIo.close(file); }
  }
  private static extension(role: string, manifest: BackupManifest): string {
    if (role === 'video') return '.video';
    if (role === 'widgetSource' && manifest.widget?.source.endsWith('.png')) return '.png';
    return '.jpg';
  }
  private static writeText(path: string, text: string): void {
    const temp = path + '.backup-tmp';
    const out = fileIo.openSync(temp, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try { fileIo.writeSync(out.fd, text); fileIo.fsyncSync(out.fd); } finally { fileIo.closeSync(out); }
    fileIo.renameSync(temp, path);
  }
  private static unlink(path: string): void {
    try { if (fileIo.accessSync(path)) fileIo.unlinkSync(path); } catch (_) {}
  }
  private static discardDirectory(path: string): void {
    try {
      for (const name of fileIo.listFileSync(path)) BackupService.unlink(path + '/' + name);
      fileIo.rmdirSync(path);
    } catch (_) {}
  }
}
