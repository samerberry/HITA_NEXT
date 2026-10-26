import { TimetableBackup } from '../../common/model/timetable/TimetableBackup';
import { newId } from '../../common/model/timetable/TimetableModels';
import { TimetableDisplayOptions } from '../timetable/data/TimetableDisplayOptions';
import { WidgetBackgroundState } from '../widget/WidgetBackgroundModel';

export class BackupSettings {
  classEnabled: boolean = false;
  classMinutes: number = 15;
  examEnabled: boolean = false;
  examMinutes: number = 60;
  appearance: string = 'system';
  activeTimetable: string = '';
  textColor: string = 'auto';
  customTextColor: boolean = false;
  display: TimetableDisplayOptions = new TimetableDisplayOptions();
}

export class BackupAsset {
  role: string = '';
  size: number = 0;
  sha256: string = '';
}

export class BackupManifest {
  format: string = 'HITA NEXT';
  version: number = 1;
  createdAt: number = Date.now();
  timetables: TimetableBackup[] = [];
  settings: BackupSettings = new BackupSettings();
  assets: BackupAsset[] = [];
  widget: WidgetBackgroundState | undefined = undefined;
}

/** Portable metadata contains no filesystem paths or account preferences. Media follows it as byte streams. */
export class BackupModel {
  static readonly ROLES: string[] = ['poster', 'video', 'widgetSource', 'widgetCompact', 'widgetWide'];
  static readonly MAX_MANIFEST: number = 16 * 1024 * 1024;

  static parse(raw: string): BackupManifest {
    try {
      const value = JSON.parse(raw) as BackupManifest;
      BackupModel.object(value);
      if (value.format !== 'HITA NEXT') throw new Error();
      if (value.version !== 1) throw new Error('VERSION');
      BackupModel.integer(value.createdAt, 1, 8640000000000000);
      BackupModel.array(value.timetables, 500);
      const tableIds = new Set<string>();
      const subjectIds = new Set<string>();
      const eventIds = new Set<string>();
      for (const item of value.timetables) {
        BackupModel.object(item);
        const t = item.timetable;
        BackupModel.object(t);
        BackupModel.identity(t.id, tableIds);
        BackupModel.strings(t, ['name', 'code']);
        BackupModel.integer(t.startTime, 0, 8640000000000000);
        BackupModel.integer(t.endTime, t.startTime, 8640000000000000);
        BackupModel.integer(t.createdAt, 0, 8640000000000000);
        BackupModel.array(t.scheduleStructure, 200);
        if (t.scheduleStructure.length === 0) throw new Error();
        for (const period of t.scheduleStructure) {
          BackupModel.object(period);
          BackupModel.object(period.from);
          BackupModel.object(period.to);
          BackupModel.integer(period.from.hour, 0, 23);
          BackupModel.integer(period.to.hour, 0, 23);
          BackupModel.integer(period.from.minute, 0, 59);
          BackupModel.integer(period.to.minute, 0, 59);
        }
        BackupModel.array(item.subjects, 50000);
        const localSubjects = new Set<string>();
        for (const s of item.subjects) {
          BackupModel.object(s);
          BackupModel.identity(s.id, subjectIds);
          localSubjects.add(s.id);
          if (s.timetableId !== t.id || !['COM_A', 'COM_B', 'OPT_A', 'OPT_B', 'MOOC', 'TAG'].includes(s.type)) {
            throw new Error();
          }
          BackupModel.strings(s, ['name', 'field', 'school', 'code', 'key']);
          BackupModel.number(s.credit, 0, 10000);
          BackupModel.bool(s.countInSPA);
          BackupModel.integer(s.createdAt, 0, 8640000000000000);
          BackupModel.integer(s.color, -2147483648, 4294967295);
        }
        BackupModel.array(item.events, 200000);
        for (const e of item.events) {
          BackupModel.object(e);
          BackupModel.identity(e.id, eventIds);
          if (e.timetableId !== t.id || !['CLASS', 'EXAM', 'OTHER', 'TAG'].includes(e.type)) throw new Error();
          BackupModel.strings(e, ['name', 'place', 'teacher', 'subjectId']);
          if (e.subjectId.length > 0 && !localSubjects.has(e.subjectId)) throw new Error();
          BackupModel.integer(e.from, 0, 8640000000000000);
          BackupModel.integer(e.to, e.from, 8640000000000000);
          BackupModel.integer(e.fromNumber, 0, 200);
          BackupModel.integer(e.lastNumber, 0, 200);
          BackupModel.integer(e.createdAt, 0, 8640000000000000);
          BackupModel.integer(e.color, -2147483648, 4294967295);
        }
        BackupModel.array(item.importBase, 200000);
        for (const b of item.importBase) {
          BackupModel.object(b);
          BackupModel.strings(b, ['name', 'signature']);
          BackupModel.integer(b.from, 0, 8640000000000000);
          BackupModel.integer(b.to, b.from, 8640000000000000);
        }
      }
      const s = value.settings;
      BackupModel.object(s);
      BackupModel.bool(s.classEnabled);
      BackupModel.bool(s.examEnabled);
      BackupModel.bool(s.customTextColor);
      BackupModel.integer(s.classMinutes, 1, 120);
      BackupModel.integer(s.examMinutes, 1, 120);
      if (!['system', 'light', 'dark'].includes(s.appearance)) throw new Error();
      BackupModel.strings(s, ['activeTimetable', 'textColor']);
      if (s.activeTimetable !== '' && !tableIds.has(s.activeTimetable)) throw new Error();
      if (s.textColor !== 'auto' && !/^#[0-9a-fA-F]{6}$/.test(s.textColor)) throw new Error();
      BackupModel.object(s.display);
      BackupModel.bool(s.display.drawTimeLines);
      BackupModel.bool(s.display.eveningHint);
      BackupModel.integer(s.display.wallpaperMask, 0, 80);
      if (s.display.timeLineColor !== '' && !/^#[0-9a-fA-F]{6}$/.test(s.display.timeLineColor)) throw new Error();
      BackupModel.array(value.assets, 5);
      const roles = new Set<string>();
      for (const a of value.assets) {
        BackupModel.object(a);
        if (!BackupModel.ROLES.includes(a.role) || roles.has(a.role)) throw new Error();
        roles.add(a.role);
        BackupModel.integer(a.size, 1, Number.MAX_SAFE_INTEGER);
        if (typeof a.sha256 !== 'string' || !/^[0-9a-f]{64}$/.test(a.sha256)) throw new Error();
      }
      if (roles.has('video') && !roles.has('poster')) throw new Error();
      if (value.widget !== undefined) {
        const w = value.widget;
        BackupModel.object(w);
        if (!roles.has('widgetSource') || !roles.has('widgetCompact') || !roles.has('widgetWide')) throw new Error();
        if (w.source !== 'source.jpg' && w.source !== 'source.png') throw new Error();
        BackupModel.integer(w.sourceWidth, 1, 1000000);
        BackupModel.integer(w.sourceHeight, 1, 1000000);
        BackupModel.integer(w.revision, 0, Number.MAX_SAFE_INTEGER);
        BackupModel.number(w.veil, 0, 80);
        for (const frame of [w.compact, w.wide]) {
          BackupModel.object(frame);
          BackupModel.number(frame.scale, 0.000001, 4);
          BackupModel.number(frame.x, 0, 1);
          BackupModel.number(frame.y, 0, 1);
        }
      } else if (roles.has('widgetSource') || roles.has('widgetCompact') || roles.has('widgetWide')) throw new Error();
      return value;
    } catch (error) {
      if (error instanceof Error && error.message === 'VERSION') throw new Error('备份版本暂不支持，请更新应用后重试');
      throw new Error('备份内容不完整或格式不正确');
    }
  }

  /** Do not mutate the preview. Every restore is an independent copy, including all subject references. */
  static remap(value: BackupManifest): BackupManifest {
    const copy = BackupModel.parse(JSON.stringify(value));
    const ids = new Map<string, string>();
    for (const item of copy.timetables) {
      const old = item.timetable.id;
      item.timetable.id = newId();
      ids.set(old, item.timetable.id);
      item.timetable.name += '（恢复）';
      const subjectIds = new Map<string, string>();
      for (const subject of item.subjects) {
        const oldSubject = subject.id;
        subject.id = newId();
        subjectIds.set(oldSubject, subject.id);
        subject.timetableId = item.timetable.id;
      }
      for (const event of item.events) {
        event.id = newId();
        event.timetableId = item.timetable.id;
        event.subjectId = subjectIds.get(event.subjectId) ?? '';
      }
    }
    copy.settings.activeTimetable = ids.get(copy.settings.activeTimetable) ?? copy.timetables[0]?.timetable.id ?? '';
    return copy;
  }

  private static object(value: Object): void {
    if (value === null || typeof value !== 'object' || Array.isArray(value)) throw new Error();
  }
  private static array(value: Object, max: number): void {
    if (!Array.isArray(value) || value.length > max) throw new Error();
  }
  private static strings(value: Object, keys: string[]): void {
    const record = value as Record<string, Object>;
    for (const key of keys) {
      const text = record[key];
      if (typeof text !== 'string' || text.length > 65536) throw new Error();
    }
  }
  private static bool(value: boolean): void {
    if (typeof value !== 'boolean') throw new Error();
  }
  private static number(value: number, min: number, max: number): void {
    if (typeof value !== 'number' || !Number.isFinite(value) || value < min || value > max) throw new Error();
  }
  private static integer(value: number, min: number, max: number): void {
    BackupModel.number(value, min, max);
    if (!Number.isSafeInteger(value)) throw new Error();
  }
  private static identity(value: string, ids: Set<string>): void {
    if (typeof value !== 'string' || value.length === 0 || value.length > 1024 || ids.has(value)) throw new Error();
    ids.add(value);
  }
}
