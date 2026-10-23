/**
 * RdbHelper.ets — 本地 RDB（对应 HITA_X AppDatabase v1：timetable/subject/events；Room → relationalStore）。
 *
 * 对齐：
 *  - AppDatabase.kt（三实体，库名 "hita"）
 *  - TypeConverters.kt（Timestamp→Long、枚举→name 文本、scheduleStructure→JSON）
 *  - TimetableDao / SubjectDao / EventItemDao（同步方法面，LiveData 观察由页面状态层承担）
 * Event timestamps use fromTime/toTime instead of SQLite reserved words so
 * ValuesBucket inserts work consistently on HarmonyOS devices.
 */
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { relationalStore } from '@kit.ArkData';
import {
  EasEventItem,
  EasEventType,
  EasImportBaseEntry,
  EasSubjectColor,
  EasSubjectType,
  EasTermSubject,
  EasTimePeriodInDay,
  EasTimetable
} from '../model/timetable/TimetableModels';
import { CourseDateSelection } from '../../feature/timetable/CourseDateSelection';
import { normalizeHtmlSpaces } from '../util/HtmlSpaces';
import { ScheduleChangeSignal } from '../util/ScheduleChangeSignal';

// The first prototype shipped a different schema under this name.  Use a
// versioned store so an upgrade cannot keep an incompatible old table layout.
const DB_NAME: string = 'hita_next_v3.db';
const DOMAIN: number = 0x0000;
const TAG: string = 'HitaRdb';

const CREATE_TIMETABLE: string =
  'CREATE TABLE IF NOT EXISTS timetable (' +
  'id TEXT PRIMARY KEY, name TEXT, code TEXT, startTime INTEGER NOT NULL, ' +
  'endTime INTEGER NOT NULL, createdAt INTEGER NOT NULL, scheduleStructure TEXT NOT NULL)';

const CREATE_SUBJECT: string =
  'CREATE TABLE IF NOT EXISTS subject (' +
  'id TEXT PRIMARY KEY, timetableId TEXT NOT NULL, name TEXT NOT NULL, type TEXT NOT NULL, ' +
  'field TEXT, credit REAL NOT NULL, school TEXT, countInSPA INTEGER NOT NULL, ' +
  'code TEXT, key TEXT, createdAt INTEGER NOT NULL, color INTEGER NOT NULL)';

const CREATE_EVENTS: string =
  'CREATE TABLE IF NOT EXISTS events (' +
  'id TEXT PRIMARY KEY, type TEXT NOT NULL, name TEXT NOT NULL, place TEXT, teacher TEXT, ' +
  'subjectId TEXT NOT NULL, timetableId TEXT NOT NULL, fromTime INTEGER NOT NULL, toTime INTEGER NOT NULL, ' +
  'fromNumber INTEGER NOT NULL, lastNumber INTEGER NOT NULL, createdAt INTEGER NOT NULL, ' +
  'color INTEGER NOT NULL DEFAULT 0)';

/**
 * 每张教务课表上次导入或更新时的教务版本，用来区分教务端变化与用户自己的修改。
 * 不设唯一约束：调整开学日期时整表平移，逐行检查唯一性会在中途误报冲突。
 */
const CREATE_IMPORT_BASE: string =
  'CREATE TABLE IF NOT EXISTS import_base (' +
  'timetableId TEXT NOT NULL, name TEXT NOT NULL, fromTime INTEGER NOT NULL, toTime INTEGER NOT NULL, ' +
  'signature TEXT NOT NULL)';

export class RdbHelper {
  private static instance: RdbHelper | undefined = undefined;
  private store: relationalStore.RdbStore | undefined = undefined;
  private initializing: Promise<void> | undefined = undefined;

  static getInstance(): RdbHelper {
    if (RdbHelper.instance === undefined) {
      RdbHelper.instance = new RdbHelper();
    }
    return RdbHelper.instance;
  }

  async init(context: common.Context): Promise<void> {
    if (this.initializing !== undefined) {
      await this.initializing;
      return;
    }
    if (this.store !== undefined) {
      return;
    }
    this.initializing = this.openStore(context);
    try {
      await this.initializing;
    } catch (e) {
      this.store = undefined;
      throw new Error(e instanceof Error ? e.message : String(e));
    } finally {
      this.initializing = undefined;
    }
  }

  private async openStore(context: common.Context): Promise<void> {
    const config: relationalStore.StoreConfig = {
      name: DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    };
    try {
      this.store = await relationalStore.getRdbStore(context, config);
    } catch (e) {
      throw new Error('RdbHelper init failed');
    }
    await this.execSql(CREATE_TIMETABLE);
    await this.execSql(CREATE_SUBJECT);
    await this.execSql(CREATE_EVENTS);
    await this.execSql(CREATE_IMPORT_BASE);
    await this.ensureEventColorColumn();
    await this.repairLegacyWeihaiTimetables();
    await this.repairLegacyBenbuTimetables();
    await this.repairLegacyImportedWeeks();
  }

  private async ensureEventColorColumn(): Promise<void> {
    const columns: relationalStore.ResultSet = await this.s().querySql('PRAGMA table_info(events)');
    let hasColor: boolean = false;
    try {
      while (columns.goToNextRow()) {
        if (columns.getString(columns.getColumnIndex('name')) === 'color') {
          hasColor = true;
          break;
        }
      }
    } finally {
      columns.close();
    }
    if (!hasColor) {
      await this.execSql('ALTER TABLE events ADD COLUMN color INTEGER NOT NULL DEFAULT 0');
    }
  }

  private s(): relationalStore.RdbStore {
    if (this.store === undefined) {
      throw new Error('RdbHelper 未初始化：请先 init(context)');
    }
    return this.store;
  }

  // —— 异常安全助手（函数 may throw → 就地吞掉/返回 null）——
  private async del(pred: relationalStore.RdbPredicates): Promise<void> {
    try {
      await this.s().delete(pred);
      ScheduleChangeSignal.notify();
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'delete failed %{public}s', String(e));
      throw new Error(String(e));
    }
  }

  private async ins(table: string, bucket: relationalStore.ValuesBucket): Promise<void> {
    try {
      const rowId: number = await this.s().insert(table, bucket);
      if (rowId < 0) {
        throw new Error('insert returned ' + rowId.toString());
      }
      ScheduleChangeSignal.notify();
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'insert table=%{public}s failed %{public}s', table, String(e));
      throw new Error(String(e));
    }
  }

  private async upd(values: relationalStore.ValuesBucket, pred: relationalStore.RdbPredicates): Promise<void> {
    try {
      await this.s().update(values, pred);
      ScheduleChangeSignal.notify();
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'update failed %{public}s', String(e));
      throw new Error(String(e));
    }
  }

  private async qry(pred: relationalStore.RdbPredicates,
    columns?: string[]): Promise<relationalStore.ResultSet | null> {
    try {
      if (columns === undefined || columns === null) {
        return await this.s().query(pred);
      }
      return await this.s().query(pred, columns);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'query failed %{public}s', String(e));
      return null;
    }
  }

  private async execSql(sql: string): Promise<void> {
    try {
      await this.s().executeSql(sql);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'execSql failed %{public}s', String(e));
      throw new Error(String(e));
    }
  }

  // ------------------------------------------------------------------
  // 通用
  // ------------------------------------------------------------------

  async clearTable(table: string): Promise<void> {
    await this.del(new relationalStore.RdbPredicates(table));
  }

  private async replaceRow(table: string, bucket: relationalStore.ValuesBucket, pkColumn: string,
    pkValue: string): Promise<void> {
    await this.writeTransaction(async (transaction: relationalStore.Transaction): Promise<void> => {
      await RdbHelper.upsertRow(transaction, table, bucket, pkColumn, pkValue);
    });
  }

  private async writeTransaction(action: (transaction: relationalStore.Transaction) => Promise<void>): Promise<void> {
    const transaction: relationalStore.Transaction = await this.s().createTransaction();
    try {
      await action(transaction);
      await transaction.commit();
      ScheduleChangeSignal.notify();
    } catch (error) {
      try { await transaction.rollback(); } catch (_) {}
      throw new Error(error instanceof Error ? error.message : String(error));
    }
  }

  private static async upsertRow(transaction: relationalStore.Transaction, table: string,
    bucket: relationalStore.ValuesBucket, pkColumn: string, pkValue: string): Promise<void> {
    const predicate: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(table).equalTo(pkColumn, pkValue);
    const rows: relationalStore.ResultSet = await transaction.query(predicate, [pkColumn]);
    let exists: boolean = false;
    try { exists = rows.goToFirstRow(); } finally { rows.close(); }
    if (exists) {
      if (await transaction.update(bucket, predicate) !== 1) throw new Error('Record update failed');
    } else if (await transaction.insert(table, bucket) < 0) {
      throw new Error('Record insert failed');
    }
  }

  /** 修复早期版本把威海误存为本部作息的本地课表。 */
  private async repairLegacyWeihaiTimetables(): Promise<void> {
    const timetables: EasTimetable[] = await this.getTimetables();
    const correct: EasTimePeriodInDay[] = EasTimetable.getWeihaiTimeStructure();
    for (let i: number = 0; i < timetables.length; i++) {
      const timetable: EasTimetable = timetables[i];
      if (!timetable.code.startsWith('WEIHAI:') || !RdbHelper.isLegacyBenbuSchedule(timetable)) {
        continue;
      }
      const events: EasEventItem[] = await this.getEventsOfTimetable(timetable.id);
      timetable.scheduleStructure = correct;
      await this.saveTimetable(timetable);
      for (let j: number = 0; j < events.length; j++) {
        const event: EasEventItem = events[j];
        if (event.type !== EasEventType.CLASS || event.fromNumber < 1 || event.lastNumber < event.fromNumber ||
          event.lastNumber > correct.length) {
          continue;
        }
        const oldDate: Date = new Date(event.from);
        const dayStart: number = new Date(oldDate.getFullYear(), oldDate.getMonth(), oldDate.getDate(),
          0, 0, 0, 0).getTime();
        event.from = dayStart + correct[event.fromNumber - 1].from.toMills();
        event.to = dayStart + correct[event.lastNumber - 1].to.toMills();
        await this.saveEvent(event);
      }
      hilog.info(DOMAIN, TAG, 'repaired legacy Weihai timetable=%{public}s events=%{public}d',
        timetable.id, events.length);
    }
  }

  /** Correct only untouched legacy Benbu course times, atomically with their bell schedule. */
  private async repairLegacyBenbuTimetables(): Promise<void> {
    const timetables: EasTimetable[] = await this.getTimetables();
    for (const timetable of timetables) {
      if (!timetable.code.startsWith('BENBU:') || !RdbHelper.isLegacyBenbuSchedule(timetable)) continue;
      await this.writeTransaction(async (transaction: relationalStore.Transaction): Promise<void> => {
        const predicate: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('timetable')
          .equalTo('id', timetable.id).equalTo('code', timetable.code);
        const rows: relationalStore.ResultSet = await transaction.query(predicate, ['scheduleStructure']);
        try {
          if (!rows.goToFirstRow()) return;
          timetable.scheduleStructure = EasTimetable.decodeStructure(rows.getString(rows.getColumnIndex('scheduleStructure')));
        } finally { rows.close(); }
        if (!RdbHelper.isLegacyBenbuSchedule(timetable)) return;
        const previous: EasTimePeriodInDay[] = timetable.scheduleStructure;
        const correct: EasTimePeriodInDay[] = EasTimetable.getBenbuTimeStructure();
        const events: EasEventItem[] = RdbHelper.readRows(await transaction.query(
          new relationalStore.RdbPredicates('events').equalTo('timetableId', timetable.id)
            .equalTo('type', EasEventType.CLASS)), RdbHelper.eventMapper);
        for (const event of events) {
          if (!Number.isInteger(event.fromNumber) || !Number.isInteger(event.lastNumber) ||
            event.fromNumber < 1 || event.lastNumber < event.fromNumber || event.lastNumber > correct.length ||
            !Number.isFinite(event.from) || !Number.isFinite(event.to)) continue;
          const date: Date = new Date(event.from);
          const dayStart: number = new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
          if (event.from !== dayStart + previous[event.fromNumber - 1].from.toMills() ||
            event.to !== dayStart + previous[event.lastNumber - 1].to.toMills()) continue;
          await transaction.update({
            fromTime: dayStart + correct[event.fromNumber - 1].from.toMills(),
            toTime: dayStart + correct[event.lastNumber - 1].to.toMills()
          }, new relationalStore.RdbPredicates('events').equalTo('id', event.id));
        }
        await transaction.update({
          scheduleStructure: EasTimetable.encodeStructure(correct)
        }, predicate);
      });
    }
  }

  private async repairLegacyImportedWeeks(): Promise<void> {
    const timetables = await this.getTimetables();
    for (const timetable of timetables) {
      if (timetable.code.length === 0 || timetable.endTime !== timetable.startTime + 25 * 7 * 86400000) continue;
      const events = await this.getEventsOfTimetable(timetable.id);
      const endTime = CourseDateSelection.repairedImportedEnd(timetable, events);
      if (endTime !== timetable.endTime) {
        await this.upd({ 'endTime': endTime }, new relationalStore.RdbPredicates('timetable')
          .equalTo('id', timetable.id).equalTo('endTime', timetable.endTime));
      }
    }
  }

  private static isLegacyBenbuSchedule(timetable: EasTimetable): boolean {
    if (timetable.scheduleStructure.length !== 12) {
      return false;
    }
    const legacy: number[][] = [
      [8, 0, 8, 50], [8, 55, 9, 45], [10, 5, 10, 55], [11, 0, 11, 50],
      [13, 30, 14, 20], [14, 25, 15, 15], [15, 25, 16, 15], [16, 20, 17, 10],
      [17, 20, 18, 10], [18, 30, 19, 20], [19, 30, 20, 20], [20, 30, 21, 20]
    ];
    for (let i: number = 0; i < legacy.length; i++) {
      const period: EasTimePeriodInDay = timetable.scheduleStructure[i];
      const old: number[] = legacy[i];
      if (period.from.hour !== old[0] || period.from.minute !== old[1] ||
        period.to.hour !== old[2] || period.to.minute !== old[3]) return false;
    }
    return true;
  }

  // ------------------------------------------------------------------
  // timetable
  // ------------------------------------------------------------------

  async saveTimetable(t: EasTimetable): Promise<void> {
    await this.replaceRow('timetable', RdbHelper.timetableValues(t), 'id', t.id);
  }

  private static timetableValues(t: EasTimetable): relationalStore.ValuesBucket {
    return {
      'id': t.id,
      'name': t.name,
      'code': t.code,
      'startTime': t.startTime,
      'endTime': t.endTime,
      'createdAt': t.createdAt,
      'scheduleStructure': EasTimetable.encodeStructure(t.scheduleStructure)
    };
  }

  /**
   * Publish a complete import together; re-importing courses must retain exams and other events.
   * The school version of the imported classes becomes the base for later merge updates.
   */
  async saveImportedTimetable(timetable: EasTimetable, subjects: EasTermSubject[], events: EasEventItem[],
    replaceCourses: boolean, base: EasImportBaseEntry[] = []): Promise<void> {
    if (timetable.id.length === 0 || !Number.isFinite(timetable.startTime) ||
      !Number.isFinite(timetable.endTime) || timetable.endTime <= timetable.startTime || events.length === 0 ||
      subjects.some((subject: EasTermSubject): boolean => subject.timetableId !== timetable.id) ||
      events.some((event: EasEventItem): boolean => event.timetableId !== timetable.id ||
        !Number.isFinite(event.from) || !Number.isFinite(event.to) || event.to <= event.from ||
        (replaceCourses && event.type !== EasEventType.CLASS))) {
      throw new Error('Invalid timetable import');
    }
    let finalEnd: number = timetable.endTime;
    await this.writeTransaction(async (transaction: relationalStore.Transaction): Promise<void> => {
      if (replaceCourses) {
        const changed: number = await transaction.update(RdbHelper.timetableValues(timetable),
          new relationalStore.RdbPredicates('timetable').equalTo('id', timetable.id));
        if (changed !== 1) throw new Error('Timetable no longer exists');
        await transaction.delete(new relationalStore.RdbPredicates('events')
          .equalTo('timetableId', timetable.id).equalTo('type', EasEventType.CLASS));
      } else if (await transaction.insert('timetable', RdbHelper.timetableValues(timetable)) < 0) {
        throw new Error('Timetable insert failed');
      }
      for (const subject of subjects) {
        await RdbHelper.upsertRow(transaction, 'subject', RdbHelper.subjectValues(subject), 'id', subject.id);
      }
      for (const event of events) {
        if (await transaction.insert('events', RdbHelper.eventValues(event)) < 0) {
          throw new Error('Event insert failed');
        }
      }
      if (base.length > 0) {
        await RdbHelper.replaceImportBase(transaction, timetable.id, base);
      }
      // Retained exams or reminders can extend beyond the imported teaching weeks.
      const last: relationalStore.ResultSet = await transaction.query(
        new relationalStore.RdbPredicates('events').equalTo('timetableId', timetable.id)
          .orderByDesc('toTime').limitAs(1), ['toTime']);
      try {
        if (last.goToFirstRow()) {
          finalEnd = Math.max(finalEnd, CourseDateSelection.weekEnd(last.getLong(last.getColumnIndex('toTime'))));
        }
      } finally { last.close(); }
      if (finalEnd !== timetable.endTime) {
        await transaction.update({ endTime: finalEnd },
          new relationalStore.RdbPredicates('timetable').equalTo('id', timetable.id));
      }
    });
    timetable.endTime = finalEnd;
  }

  /** 上次导入或更新时的教务版本；旧版本导入、还没有记录时为空。 */
  async getImportBase(timetableId: string): Promise<EasImportBaseEntry[]> {
    const rows: relationalStore.ResultSet = await this.s().query(
      new relationalStore.RdbPredicates('import_base').equalTo('timetableId', timetableId),
      ['name', 'fromTime', 'toTime', 'signature']);
    const out: EasImportBaseEntry[] = [];
    try {
      while (rows.goToNextRow()) {
        out.push(new EasImportBaseEntry(rows.getString(rows.getColumnIndex('name')),
          rows.getLong(rows.getColumnIndex('fromTime')), rows.getLong(rows.getColumnIndex('toTime')),
          rows.getString(rows.getColumnIndex('signature'))));
      }
    } finally {
      rows.close();
    }
    return out;
  }

  async saveImportBase(timetableId: string, base: EasImportBaseEntry[]): Promise<void> {
    await this.writeTransaction(async (transaction: relationalStore.Transaction): Promise<void> => {
      await RdbHelper.replaceImportBase(transaction, timetableId, base);
    });
  }

  /**
   * 合并更新：逐条新增、修改、删除课程并记录新的教务基准，整体在一个事务里完成。
   * 只动合并结果点名的课次；用户翘过、改过、添加的课，考试等其他日程和已有科目都不动。
   */
  async applyTimetableMerge(timetableId: string, newSubjects: EasTermSubject[], inserts: EasEventItem[],
    updates: EasEventItem[], deletes: EasEventItem[], base: EasImportBaseEntry[]): Promise<void> {
    if (newSubjects.some((subject: EasTermSubject): boolean => subject.timetableId !== timetableId) ||
      inserts.concat(updates).some((event: EasEventItem): boolean => event.timetableId !== timetableId ||
        event.type !== EasEventType.CLASS || !Number.isFinite(event.from) || !Number.isFinite(event.to) ||
        event.to <= event.from)) {
      throw new Error('Invalid timetable merge');
    }
    await this.writeTransaction(async (transaction: relationalStore.Transaction): Promise<void> => {
      const table: relationalStore.ResultSet = await transaction.query(
        new relationalStore.RdbPredicates('timetable').equalTo('id', timetableId), ['endTime']);
      let currentEnd: number = 0;
      try {
        if (!table.goToFirstRow()) throw new Error('Timetable no longer exists');
        currentEnd = table.getLong(table.getColumnIndex('endTime'));
      } finally { table.close(); }
      for (const subject of newSubjects) {
        if (await transaction.insert('subject', RdbHelper.subjectValues(subject)) < 0) {
          throw new Error('Subject insert failed');
        }
      }
      for (const event of inserts) {
        if (await transaction.insert('events', RdbHelper.eventValues(event)) < 0) {
          throw new Error('Event insert failed');
        }
      }
      for (const event of updates) {
        const changed: number = await transaction.update(RdbHelper.eventValues(event),
          new relationalStore.RdbPredicates('events').equalTo('id', event.id)
            .equalTo('timetableId', timetableId).equalTo('type', EasEventType.CLASS));
        if (changed !== 1) throw new Error('Course changed during update');
      }
      for (const event of deletes) {
        await transaction.delete(new relationalStore.RdbPredicates('events').equalTo('id', event.id)
          .equalTo('timetableId', timetableId).equalTo('type', EasEventType.CLASS));
      }
      await RdbHelper.replaceImportBase(transaction, timetableId, base);
      const lastEnd: number = inserts.reduce((end: number, event: EasEventItem): number =>
        Math.max(end, event.to), currentEnd);
      if (lastEnd > currentEnd) {
        const updated: number = await transaction.update({ 'endTime': CourseDateSelection.weekEnd(lastEnd) },
          new relationalStore.RdbPredicates('timetable').equalTo('id', timetableId));
        if (updated !== 1) throw new Error('Timetable update failed');
      }
    });
  }

  private static async replaceImportBase(transaction: relationalStore.Transaction, timetableId: string,
    base: EasImportBaseEntry[]): Promise<void> {
    await transaction.delete(new relationalStore.RdbPredicates('import_base').equalTo('timetableId', timetableId));
    for (const entry of base) {
      const row: relationalStore.ValuesBucket = {
        'timetableId': timetableId,
        'name': entry.name,
        'fromTime': entry.from,
        'toTime': entry.to,
        'signature': entry.signature
      };
      if (await transaction.insert('import_base', row) < 0) {
        throw new Error('Import base insert failed');
      }
    }
  }

  /** Move the term and every occurrence in one transaction; reject an outdated editor. */
  async shiftTimetableStart(id: string, previousStart: number, previousEnd: number, nextStart: number): Promise<void> {
    if (id.length === 0 || !Number.isFinite(previousStart) || !Number.isFinite(previousEnd) ||
      !Number.isFinite(nextStart) || nextStart <= 0 || previousEnd < previousStart) {
      throw new Error('Invalid timetable date');
    }
    const delta: number = nextStart - EasTimetable.mondayMsOf(previousStart);
    const nextEnd: number = nextStart + Math.max(86400000, previousEnd - previousStart);
    await this.writeTransaction(async (transaction: relationalStore.Transaction): Promise<void> => {
      const changed: number = await transaction.update({ startTime: nextStart, endTime: nextEnd },
        new relationalStore.RdbPredicates('timetable').equalTo('id', id)
          .equalTo('startTime', previousStart).equalTo('endTime', previousEnd));
      if (changed !== 1) throw new Error('Timetable changed; reload before editing');
      await transaction.execute(
        'UPDATE events SET fromTime = fromTime + ?, toTime = toTime + ? WHERE timetableId = ?', [delta, delta, id]);
      // 教务基准随课次一起平移，否则下次检查会把整学期误当作教务端变化。
      await transaction.execute(
        'UPDATE import_base SET fromTime = fromTime + ?, toTime = toTime + ? WHERE timetableId = ?', [delta, delta, id]);
    });
  }

  /** 按 -startTime 排序的全量课表。 */
  async getTimetables(): Promise<EasTimetable[]> {
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('timetable');
    pred.orderByDesc('startTime');
    const rs: relationalStore.ResultSet | null = await this.qry(pred);
    return RdbHelper.readRows(rs, (col: (name: string) => ValueGetter) => {
      const t: EasTimetable = new EasTimetable();
      t.id = col('id').str();
      t.name = col('name').str();
      t.code = col('code').str();
      t.startTime = col('startTime').num();
      t.endTime = col('endTime').num();
      t.createdAt = col('createdAt').num();
      t.scheduleStructure = EasTimetable.decodeStructure(col('scheduleStructure').str());
      return t;
    });
  }

  async getTimetableById(id: string): Promise<EasTimetable | undefined> {
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('timetable');
    pred.equalTo('id', id);
    return RdbHelper.firstRow(await this.qry(pred), (col: (name: string) => ValueGetter) => {
      const t: EasTimetable = new EasTimetable();
      t.id = col('id').str();
      t.name = col('name').str();
      t.code = col('code').str();
      t.startTime = col('startTime').num();
      t.endTime = col('endTime').num();
      t.createdAt = col('createdAt').num();
      t.scheduleStructure = EasTimetable.decodeStructure(col('scheduleStructure').str());
      return t;
    });
  }

  async getTimetableByEasCode(easCode: string): Promise<EasTimetable | undefined> {
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('timetable');
    pred.equalTo('code', easCode);
    return RdbHelper.firstRow(await this.qry(pred), (col: (name: string) => ValueGetter) => {
      const t: EasTimetable = new EasTimetable();
      t.id = col('id').str();
      t.name = col('name').str();
      t.code = col('code').str();
      t.startTime = col('startTime').num();
      t.endTime = col('endTime').num();
      t.createdAt = col('createdAt').num();
      t.scheduleStructure = EasTimetable.decodeStructure(col('scheduleStructure').str());
      return t;
    });
  }

  async deleteTimetablesInIds(ids: string[]): Promise<void> {
    if (ids.length === 0) {
      return;
    }
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('timetable');
    pred.in('id', ids);
    await this.del(pred);
  }

  /** 删除课表以及其科目、课程事件，避免留下无法再访问的孤立数据。 */
  async deleteTimetablesCascade(ids: string[]): Promise<void> {
    if (ids.length === 0) {
      return;
    }
    await this.writeTransaction(async (transaction: relationalStore.Transaction): Promise<void> => {
      await transaction.delete(new relationalStore.RdbPredicates('events').in('timetableId', ids));
      await transaction.delete(new relationalStore.RdbPredicates('subject').in('timetableId', ids));
      await transaction.delete(new relationalStore.RdbPredicates('import_base').in('timetableId', ids));
      await transaction.delete(new relationalStore.RdbPredicates('timetable').in('id', ids));
    });
  }

  // ------------------------------------------------------------------
  // subject
  // ------------------------------------------------------------------

  async saveSubject(s: EasTermSubject): Promise<void> {
    await this.replaceRow('subject', RdbHelper.subjectValues(s), 'id', s.id);
  }

  async saveSubjectType(id: string, timetableId: string, type: EasSubjectType): Promise<void> {
    if (id.length === 0 || timetableId.length === 0) {
      throw new Error('Missing course identity');
    }
    const changed: number = await this.s().update({ 'type': type.toString() },
      new relationalStore.RdbPredicates('subject').equalTo('id', id).equalTo('timetableId', timetableId));
    if (changed !== 1) {
      throw new Error('Course no longer exists');
    }
  }

  private static subjectValues(s: EasTermSubject): relationalStore.ValuesBucket {
    return {
      'id': s.id,
      'timetableId': s.timetableId,
      'name': s.name,
      'type': s.type.toString(),
      'field': s.field,
      'credit': s.credit,
      'school': s.school,
      'countInSPA': s.countInSPA ? 1 : 0,
      'code': s.code,
      'key': s.key,
      'createdAt': s.createdAt,
      'color': s.color
    };
  }

  /** 某课表科目，按 credit 降序（对应 SubjectDao.getSubjects）。 */
  async getSubjectsOfTimetable(timetableId: string): Promise<EasTermSubject[]> {
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('subject');
    pred.equalTo('timetableId', timetableId);
    pred.orderByDesc('credit');
    return this.readSubjects(pred);
  }

  /** Credit statistics aggregate all saved timetables, with deduplication in the credit feature. */
  async getAllSubjects(): Promise<EasTermSubject[]> {
    return this.readSubjects(new relationalStore.RdbPredicates('subject').orderByDesc('createdAt'));
  }

  private async readSubjects(pred: relationalStore.RdbPredicates): Promise<EasTermSubject[]> {
    const rs: relationalStore.ResultSet | null = await this.qry(pred);
    return RdbHelper.readRows(rs, (col: (name: string) => ValueGetter) => {
      const s: EasTermSubject = new EasTermSubject();
      s.id = col('id').str();
      s.timetableId = col('timetableId').str();
      s.name = col('name').str();
      s.type = RdbHelper.subjectTypeOf(col('type').str());
      s.field = col('field').str();
      s.credit = col('credit').numD();
      s.school = col('school').str();
      s.countInSPA = col('countInSPA').num() !== 0;
      s.code = col('code').str();
      s.key = col('key').str();
      s.createdAt = col('createdAt').num();
      s.color = col('color').num();
      return s;
    });
  }

  /** 指定科目 id 的 (id,color) 投影（对应 SubjectDao.getSubjectColorsWithId）。 */
  async getSubjectColors(ids: string[]): Promise<EasSubjectColor[]> {
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('subject');
    pred.in('id', ids);
    const rs: relationalStore.ResultSet | null = await this.qry(pred, ['id', 'color']);
    return RdbHelper.readRows(rs, (col: (name: string) => ValueGetter) => {
      const c: EasSubjectColor = new EasSubjectColor();
      c.id = col('id').str();
      c.color = col('color').num();
      return c;
    });
  }

  /** Save the subject color; propagate failures so the editor cannot report a false success. */
  async saveCourseColor(id: string, timetableId: string, color: number): Promise<void> {
    if (id.length === 0 || timetableId.length === 0) {
      throw new Error('Missing course identity');
    }
    const changed: number = await this.s().update({ 'color': color },
      new relationalStore.RdbPredicates('subject').equalTo('id', id).equalTo('timetableId', timetableId));
    if (changed !== 1) {
      throw new Error('Course no longer exists');
    }
  }

  async changeSubjectColor(id: string, color: number): Promise<void> {
    await this.upd({ 'color': color },
      new relationalStore.RdbPredicates('subject').equalTo('id', id));
  }

  // ------------------------------------------------------------------
  // events
  // ------------------------------------------------------------------

  async saveEvent(e: EasEventItem): Promise<void> {
    await this.replaceRow('events', RdbHelper.eventValues(e), 'id', e.id);
  }

  /** Save all selected course occurrences together; failures leave no partial course behind. */
  async saveCourseOccurrences(subject: EasTermSubject, events: EasEventItem[], newSubject: boolean): Promise<void> {
    if (events.length === 0 || events.some((event: EasEventItem): boolean =>
      event.type !== EasEventType.CLASS || event.subjectId !== subject.id ||
      event.timetableId !== subject.timetableId || event.to <= event.from)) {
      throw new Error('Invalid course occurrences');
    }
    const transaction: relationalStore.Transaction = await this.s().createTransaction();
    try {
      const table: relationalStore.ResultSet = await transaction.query(
        new relationalStore.RdbPredicates('timetable').equalTo('id', subject.timetableId), ['startTime', 'endTime']);
      let currentEnd: number = 0;
      let currentStart: number = 0;
      try {
        if (!table.goToFirstRow()) throw new Error('Timetable no longer exists');
        currentStart = table.getLong(table.getColumnIndex('startTime'));
        currentEnd = table.getLong(table.getColumnIndex('endTime'));
      } finally { table.close(); }
      if (events.some((event: EasEventItem): boolean => event.from < EasTimetable.mondayMsOf(currentStart))) {
        throw new Error('Course predates timetable');
      }
      if (newSubject) await transaction.insert('subject', RdbHelper.subjectValues(subject));
      for (const event of events) {
        await transaction.insert('events', RdbHelper.eventValues(event));
      }
      const lastEnd: number = events.reduce((end: number, event: EasEventItem): number => Math.max(end, event.to), currentEnd);
      if (lastEnd > currentEnd) {
        const updated: number = await transaction.update({ 'endTime': CourseDateSelection.weekEnd(lastEnd) },
          new relationalStore.RdbPredicates('timetable').equalTo('id', subject.timetableId));
        if (updated !== 1) throw new Error('Timetable update failed');
      }
      await transaction.commit();
    } catch (error) {
      try { await transaction.rollback(); } catch (_) {}
      throw new Error('课程未保存，请重试');
    }
    ScheduleChangeSignal.notify();
  }

  /** Exam colors belong to individual events, never to their linked course. */
  async saveExamColor(id: string, timetableId: string, color: number): Promise<void> {
    if (id.length === 0 || timetableId.length === 0) {
      throw new Error('Missing exam identity');
    }
    const changed: number = await this.s().update({ 'color': color },
      new relationalStore.RdbPredicates('events').equalTo('id', id)
        .equalTo('timetableId', timetableId).equalTo('type', EasEventType.EXAM));
    if (changed !== 1) {
      throw new Error('Exam no longer exists');
    }
  }

  /** Edit in place: failed writes must not remove or recreate an existing event. */
  async updateEvent(e: EasEventItem): Promise<void> {
    try {
      const count: number = await this.s().update(RdbHelper.eventValues(e),
        new relationalStore.RdbPredicates('events').equalTo('id', e.id));
      if (count !== 1) {
        throw new Error('Event no longer exists');
      }
      ScheduleChangeSignal.notify();
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'update event failed %{public}s', String(e));
      throw new Error(String(e));
    }
  }

  private static eventValues(e: EasEventItem): relationalStore.ValuesBucket {
    return {
      'id': e.id,
      'type': e.type.toString(),
      'name': e.name,
      'place': e.place,
      'teacher': e.teacher,
      'subjectId': e.subjectId,
      'timetableId': e.timetableId,
      'fromTime': e.from,
      'toTime': e.to,
      'fromNumber': e.fromNumber,
      'lastNumber': e.lastNumber,
      'createdAt': e.createdAt,
      'color': e.type === EasEventType.EXAM ? e.color : 0
    };
  }

  /** 区间内事件（对应 getEventsDuringSync：from/to 四向包含）。 */
  async getEventsDuring(fromT: number, toT: number): Promise<EasEventItem[]> {
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('events');
    pred.greaterThanOrEqualTo('fromTime', fromT).lessThanOrEqualTo('fromTime', toT)
      .greaterThanOrEqualTo('toTime', fromT).lessThanOrEqualTo('toTime', toT);
    pred.orderByAsc('fromTime');
    return RdbHelper.readRows(await this.qry(pred), RdbHelper.eventMapper);
  }

  /** from >= fromT，升序取前 limit 条（对应 getEventsAfter）。 */
  async getEventsAfter(fromT: number, limit: number): Promise<EasEventItem[]> {
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('events');
    pred.greaterThanOrEqualTo('fromTime', fromT);
    pred.orderByAsc('fromTime');
    pred.limitAs(limit);
    return RdbHelper.readRows(await this.qry(pred), RdbHelper.eventMapper);
  }

  /** 某课表全部事件（对应 getEventsOfTimetableSync）。 */
  async getEventsOfTimetable(timetableId: string): Promise<EasEventItem[]> {
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('events');
    pred.equalTo('timetableId', timetableId);
    pred.orderByAsc('fromTime');
    return RdbHelper.readRows(await this.qry(pred), RdbHelper.eventMapper);
  }

  async getClassesOfSubject(subjectId: string): Promise<EasEventItem[]> {
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('events');
    pred.equalTo('subjectId', subjectId);
    pred.orderByAsc('fromTime');
    return RdbHelper.readRows(await this.qry(pred), RdbHelper.eventMapper);
  }

  /** 删除某课表的课程类事件（对应 deleteCourseFromTimetable）。 */
  async deleteCourseFromTimetable(timetableId: string): Promise<void> {
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('events');
    pred.equalTo('timetableId', timetableId);
    pred.in('type', [EasEventType.CLASS.toString(), EasEventType.EXAM.toString()]);
    await this.del(pred);
  }

  /** 单条事件读取。 */
  async getEventById(id: string): Promise<EasEventItem | undefined> {
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('events');
    pred.equalTo('id', id);
    return RdbHelper.firstRow(await this.qry(pred), RdbHelper.eventMapper);
  }

  /** 删除单条事件。 */
  async deleteEvent(id: string): Promise<void> {
    await this.del(new relationalStore.RdbPredicates('events').equalTo('id', id));
  }

  /** Remove only the occurrences represented by one timetable card, never its subject or exams. */
  async deleteClassOccurrences(ids: string[], timetableId: string): Promise<void> {
    if (ids.length === 0 || ids.some((id: string): boolean => id.length === 0) || timetableId.length === 0) {
      throw new Error('Missing class occurrence identity');
    }
    const removed: number = await this.s().delete(new relationalStore.RdbPredicates('events')
      .equalTo('timetableId', timetableId).equalTo('type', EasEventType.CLASS).in('id', ids));
    if (removed === 0) {
      throw new Error('Class occurrence no longer exists');
    }
    ScheduleChangeSignal.notify();
  }

  /** 删除某科目全部课程事件。 */
  async deleteEventsOfSubject(subjectId: string): Promise<void> {
    await this.del(new relationalStore.RdbPredicates('events').equalTo('subjectId', subjectId));
  }

  /** 原子删除一门课程及其课时；关联考试由考试管理独立维护。 */
  async deleteCourseWithClasses(subjectId: string, timetableId: string): Promise<void> {
    if (subjectId.length === 0 || timetableId.length === 0) {
      throw new Error('Missing course identity');
    }
    const transaction: relationalStore.Transaction = await this.s().createTransaction();
    try {
      const removed: number = await transaction.delete(new relationalStore.RdbPredicates('subject')
        .equalTo('id', subjectId).equalTo('timetableId', timetableId));
      if (removed !== 1) {
        throw new Error('Course no longer exists');
      }
      await transaction.delete(new relationalStore.RdbPredicates('events')
        .equalTo('subjectId', subjectId).equalTo('timetableId', timetableId)
        .equalTo('type', EasEventType.CLASS));
      await transaction.commit();
      ScheduleChangeSignal.notify();
    } catch (e) {
      try {
        await transaction.rollback();
      } catch (rollbackError) {
        hilog.error(DOMAIN, TAG, 'rollback course delete failed %{public}s', String(rollbackError));
      }
      hilog.error(DOMAIN, TAG, 'delete course failed %{public}s', String(e));
      throw new Error(String(e));
    }
  }

  /** 删除科目。 */
  async deleteSubject(id: string): Promise<void> {
    await this.del(new relationalStore.RdbPredicates('subject').equalTo('id', id));
  }

  /** 删除某课表全部事件（对应 deleteEventsFromTimetablesSync 单表实现）。 */
  async deleteEventsOfTimetable(timetableId: string): Promise<void> {
    await this.del(new relationalStore.RdbPredicates('events').equalTo('timetableId', timetableId));
  }

  // ------------------------------------------------------------------
  // 私有：行 → 模型
  // ------------------------------------------------------------------

  private static eventMapper(col: (name: string) => ValueGetter): EasEventItem {
    const e: EasEventItem = new EasEventItem();
    e.id = col('id').str();
    e.type = RdbHelper.eventTypeOf(col('type').str());
    e.name = col('name').str();
    e.place = col('place').str();
    if (e.type === EasEventType.CLASS) {
      // Also clean placeholders in courses imported by earlier app versions.
      e.place = normalizeHtmlSpaces(e.place);
    }
    e.teacher = col('teacher').str();
    e.subjectId = col('subjectId').str();
    e.timetableId = col('timetableId').str();
    e.from = col('fromTime').num();
    e.to = col('toTime').num();
    e.fromNumber = col('fromNumber').num();
    e.lastNumber = col('lastNumber').num();
    e.createdAt = col('createdAt').num();
    e.color = col('color').num();
    return e;
  }

  private static eventTypeOf(s: string): EasEventType {
    if (s === 'EXAM') {
      return EasEventType.EXAM;
    }
    if (s === 'OTHER') {
      return EasEventType.OTHER;
    }
    if (s === 'TAG') {
      return EasEventType.TAG;
    }
    return EasEventType.CLASS;
  }

  private static subjectTypeOf(s: string): EasSubjectType {
    if (s === 'COM_B') {
      return EasSubjectType.COM_B;
    }
    if (s === 'OPT_A') {
      return EasSubjectType.OPT_A;
    }
    if (s === 'OPT_B') {
      return EasSubjectType.OPT_B;
    }
    if (s === 'MOOC') {
      return EasSubjectType.MOOC;
    }
    if (s === 'TAG') {
      return EasSubjectType.TAG;
    }
    return EasSubjectType.COM_A;
  }

  private static readRows<T>(rs: relationalStore.ResultSet | null,
    mapper: (col: (name: string) => ValueGetter) => T): T[] {
    const out: T[] = [];
    if (rs === null || rs === undefined) {
      return out;
    }
    try {
      while (rs.goToNextRow()) {
        const col = (name: string): ValueGetter => {
          return new ValueGetter(rs, name);
        };
        out.push(mapper(col));
      }
    } catch (e) {
    } finally {
      try {
        rs.close();
      } catch (e) {
      }
    }
    return out;
  }

  private static firstRow<T>(rs: relationalStore.ResultSet | null,
    mapper: (col: (name: string) => ValueGetter) => T): T | undefined {
    if (rs === null || rs === undefined) {
      return undefined;
    }
    try {
      if (rs.goToNextRow()) {
        const col = (name: string): ValueGetter => {
          return new ValueGetter(rs, name);
        };
        return mapper(col);
      }
      return undefined;
    } catch (e) {
      return undefined;
    } finally {
      try {
        rs.close();
      } catch (e) {
      }
    }
  }
}

/** ResultSet 单元格安全读取器。 */
class ValueGetter {
  private rs: relationalStore.ResultSet;
  private name: string;

  constructor(rs: relationalStore.ResultSet, name: string) {
    this.rs = rs;
    this.name = name;
  }

  str(): string {
    try {
      const idx: number = this.rs.getColumnIndex(this.name);
      const v = this.rs.getString(idx);
      return v === undefined || v === null ? '' : v;
    } catch (e) {
      return '';
    }
  }

  num(): number {
    try {
      const idx: number = this.rs.getColumnIndex(this.name);
      const v = this.rs.getLong(idx);
      return v === undefined || v === null ? 0 : Number(v);
    } catch (e) {
      return 0;
    }
  }

  /** 小数（REAL 列用 getDouble）。 */
  numD(): number {
    try {
      const idx: number = this.rs.getColumnIndex(this.name);
      const v = this.rs.getDouble(idx);
      return v === undefined || v === null ? 0 : Number(v);
    } catch (e) {
      return 0;
    }
  }
}
