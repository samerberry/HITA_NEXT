/**
 * TimetableUpdateDiff.ets — 教务课表更新：与上次导入的教务版本三方合并，生成要落库的改动和
 * 供用户确认的变化清单。
 *
 * 只处理课程（CLASS）；考试等其他日程不受影响。用户翘过、改过、添加的课保持不变。
 * 同一门课、同一时段、同一处改动的多周变化合并为一组，例如“第1-16周 地点 A101 → B202”。
 */
import {
  EasEventItem,
  EasEventType,
  EasImportBaseEntry,
  EasTimetable,
  WEEK_MILLIS
} from '../../../common/model/timetable/TimetableModels';
import { normalizeHtmlSpaces } from '../../../common/util/HtmlSpaces';

export enum TimetableChangeKind {
  ADDED = 'ADDED',
  MOVED = 'MOVED',
  DETAILS = 'DETAILS',
  REMOVED = 'REMOVED'
}

export class TimetableChangeGroup {
  kind: TimetableChangeKind = TimetableChangeKind.ADDED;
  name: string = '';
  /** 原时段（新增时为新时段），如“周二 3-4节”。 */
  slot: string = '';
  /** 调整后的时段，仅 MOVED。 */
  newSlot: string = '';
  /** 新增课程的地点，或地点/教师的变化说明。 */
  detail: string = '';
  weeks: number[] = [];
}

/** 一次合并要落库的改动，以及合并后应记录的教务版本。 */
export class TimetableMergePlan {
  /** 教务新增、本地没有的课。 */
  inserts: EasEventItem[] = [];
  /** 用户没改过、教务改了地点/教师/节次的课（沿用本地 id）。 */
  updates: EasEventItem[] = [];
  /** 用户没改过、教务取消的课。 */
  deletes: EasEventItem[] = [];
  /** 合并后作为下次基准的教务版本。 */
  base: EasImportBaseEntry[] = [];
  changes: TimetableChangeGroup[] = [];
}

const WEEKDAYS: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
const KIND_ORDER: TimetableChangeKind[] = [TimetableChangeKind.ADDED, TimetableChangeKind.MOVED,
  TimetableChangeKind.DETAILS, TimetableChangeKind.REMOVED];

export class TimetableUpdateDiff {
  /** 教务课程内容的版本指纹：与课次 id、顺序无关，任一课次的名称、时间、地点或教师变化都会改变。 */
  static fingerprint(events: EasEventItem[]): string {
    const lines: string[] = TimetableUpdateDiff.classes(events).map((event: EasEventItem): string =>
      [event.name, event.from.toString(), event.to.toString(), event.place, event.teacher].join('\u0001'));
    lines.sort();
    const text: string = lines.join('\u0002');
    let hash: number = 0x811c9dc5;
    for (let i: number = 0; i < text.length; i++) {
      hash = Math.imul(hash ^ text.charCodeAt(i), 16777619) >>> 0;
    }
    return lines.length.toString() + ':' + hash.toString(16);
  }

  /**
   * 三方合并：base 是上次导入或更新时的教务版本，local 是本地课表，remote 是教务最新版本。
   * 只把教务端的变化落到用户没动过的课上；翘掉（删掉）的课不恢复，改过的课保留用户版本，
   * 手动添加的课不动。base 为空（旧版本导入的课表）时视教务现状为基准，不产生任何变化。
   */
  static merge(startTime: number, local: EasEventItem[], base: Map<string, string> | undefined,
    remote: EasEventItem[]): TimetableMergePlan {
    const plan: TimetableMergePlan = new TimetableMergePlan();
    const remoteClasses: EasEventItem[] = TimetableUpdateDiff.classes(remote);
    const remoteKeys: Set<string> = new Set<string>();
    for (const event of remoteClasses) {
      const key: string = TimetableUpdateDiff.keyOf(event);
      if (!remoteKeys.has(key)) {
        remoteKeys.add(key);
        plan.base.push(new EasImportBaseEntry(event.name, event.from, event.to, TimetableUpdateDiff.signatureOf(event)));
      }
    }
    const known: Map<string, string> = base !== undefined ? base : TimetableUpdateDiff.baseMap(plan.base);
    const localByKey: Map<string, EasEventItem[]> = new Map<string, EasEventItem[]>();
    for (const event of TimetableUpdateDiff.classes(local)) {
      const key: string = TimetableUpdateDiff.keyOf(event);
      const list: EasEventItem[] | undefined = localByKey.get(key);
      if (list === undefined) {
        localByKey.set(key, [event]);
      } else {
        list.push(event);
      }
    }

    const added: EasEventItem[] = [];
    const removed: EasEventItem[] = [];
    const detailPairs: EasEventItem[][] = [];
    const handled: Set<string> = new Set<string>();
    for (const event of remoteClasses) {
      const key: string = TimetableUpdateDiff.keyOf(event);
      if (handled.has(key)) {
        continue;
      }
      handled.add(key);
      const locals: EasEventItem[] | undefined = localByKey.get(key);
      const before: EasEventItem | undefined = locals === undefined ? undefined : locals[0];
      const baseSignature: string | undefined = known.get(key);
      if (baseSignature === undefined) {
        // 教务新增的课；本地已有同一课次（用户自己加过）就不重复添加。
        if (before === undefined) {
          plan.inserts.push(event);
          added.push(event);
        }
        continue;
      }
      // 本地没有：用户翘掉或删掉了。本地改过：保留用户版本。教务没变：无需处理。
      const remoteSignature: string = TimetableUpdateDiff.signatureOf(event);
      if (before === undefined || TimetableUpdateDiff.signatureOf(before) !== baseSignature ||
        remoteSignature === baseSignature) {
        continue;
      }
      const updated: EasEventItem = TimetableUpdateDiff.withDetails(before, event);
      plan.updates.push(updated);
      detailPairs.push([before, updated]);
    }
    known.forEach((baseSignature: string, key: string) => {
      if (remoteKeys.has(key)) {
        return;
      }
      // 教务取消的课：只删除用户没改过的那一节。
      const locals: EasEventItem[] | undefined = localByKey.get(key);
      if (locals === undefined) {
        return;
      }
      for (const event of locals) {
        if (TimetableUpdateDiff.signatureOf(event) === baseSignature) {
          plan.deletes.push(event);
          removed.push(event);
        }
      }
    });
    plan.changes = TimetableUpdateDiff.group(startTime, added, removed, detailPairs);
    return plan;
  }

  /** 课次定位：课程名与起止时间。 */
  static keyOf(event: EasEventItem): string {
    return TimetableUpdateDiff.slotKey(event.name, event.from, event.to);
  }

  private static slotKey(name: string, from: number, to: number): string {
    return name + '|' + from.toString() + '|' + to.toString();
  }

  /** 同一课次下可能单独变化的字段；地点按读库时的规则规整，避免误判为用户改过。 */
  static signatureOf(event: EasEventItem): string {
    return [normalizeHtmlSpaces(event.place), event.teacher, event.fromNumber.toString(),
      event.lastNumber.toString()].join('\u0001');
  }

  static baseMap(entries: EasImportBaseEntry[]): Map<string, string> {
    const out: Map<string, string> = new Map<string, string>();
    for (const entry of entries) {
      out.set(TimetableUpdateDiff.slotKey(entry.name, entry.from, entry.to), entry.signature);
    }
    return out;
  }

  static baseOf(events: EasEventItem[]): EasImportBaseEntry[] {
    return TimetableUpdateDiff.merge(0, [], undefined, events).base;
  }

  private static withDetails(local: EasEventItem, remote: EasEventItem): EasEventItem {
    const out: EasEventItem = new EasEventItem();
    out.id = local.id;
    out.type = local.type;
    out.name = local.name;
    out.subjectId = local.subjectId;
    out.timetableId = local.timetableId;
    out.from = local.from;
    out.to = local.to;
    out.createdAt = local.createdAt;
    out.color = local.color;
    out.place = remote.place;
    out.teacher = remote.teacher;
    out.fromNumber = remote.fromNumber;
    out.lastNumber = remote.lastNumber;
    return out;
  }

  private static group(startTime: number, addedEvents: EasEventItem[], removedEvents: EasEventItem[],
    detailPairs: EasEventItem[][]): TimetableChangeGroup[] {
    const added: EasEventItem[] = addedEvents.slice().sort((a: EasEventItem, b: EasEventItem): number => a.from - b.from);
    const removed: EasEventItem[] = removedEvents.slice()
      .sort((a: EasEventItem, b: EasEventItem): number => a.from - b.from);
    const groups: Map<string, TimetableChangeGroup> = new Map<string, TimetableChangeGroup>();
    const record = (kind: TimetableChangeKind, event: EasEventItem, newSlot: string, detail: string): void => {
      const slot: string = TimetableUpdateDiff.slotOf(event);
      const key: string = [kind, event.name, slot, newSlot, detail].join('\u0001');
      let group: TimetableChangeGroup | undefined = groups.get(key);
      if (group === undefined) {
        group = new TimetableChangeGroup();
        group.kind = kind;
        group.name = event.name;
        group.slot = slot;
        group.newSlot = newSlot;
        group.detail = detail;
        groups.set(key, group);
      }
      const week: number = TimetableUpdateDiff.weekOf(startTime, event.from);
      if (group.weeks.indexOf(week) < 0) {
        group.weeks.push(week);
      }
    };

    // 同一周里取消一节、又新增同名一节，视为调整时间。
    for (const after of added.slice()) {
      const week: number = TimetableUpdateDiff.weekOf(startTime, after.from);
      const index: number = removed.findIndex((before: EasEventItem): boolean =>
        before.name === after.name && TimetableUpdateDiff.weekOf(startTime, before.from) === week);
      if (index >= 0) {
        const before: EasEventItem = removed.splice(index, 1)[0];
        added.splice(added.indexOf(after), 1);
        record(TimetableChangeKind.MOVED, before, TimetableUpdateDiff.slotOf(after), '');
      }
    }
    for (const event of added) {
      record(TimetableChangeKind.ADDED, event, '', event.place);
    }
    for (const pair of detailPairs) {
      record(TimetableChangeKind.DETAILS, pair[1], '', TimetableUpdateDiff.detailChange(pair[0], pair[1]));
    }
    for (const event of removed) {
      record(TimetableChangeKind.REMOVED, event, '', '');
    }
    const out: TimetableChangeGroup[] = Array.from(groups.values());
    out.forEach((group: TimetableChangeGroup) => {
      group.weeks.sort((a: number, b: number): number => a - b);
    });
    out.sort((a: TimetableChangeGroup, b: TimetableChangeGroup): number => {
      const byKind: number = KIND_ORDER.indexOf(a.kind) - KIND_ORDER.indexOf(b.kind);
      return byKind !== 0 ? byKind : a.weeks[0] - b.weeks[0];
    });
    return out;
  }

  static kindLabel(kind: TimetableChangeKind): string {
    if (kind === TimetableChangeKind.ADDED) {
      return '新增';
    }
    if (kind === TimetableChangeKind.MOVED) {
      return '调整';
    }
    if (kind === TimetableChangeKind.DETAILS) {
      return '变更';
    }
    return '取消';
  }

  /** 课程名之后的说明：时段、周次，以及地点或改动内容。 */
  static detailText(group: TimetableChangeGroup): string {
    const weeks: string = TimetableUpdateDiff.weeksText(group.weeks);
    if (group.kind === TimetableChangeKind.ADDED) {
      return group.slot + ' ' + weeks + (group.detail.length > 0 ? ' · ' + group.detail : '');
    }
    if (group.kind === TimetableChangeKind.MOVED) {
      return group.slot + ' → ' + group.newSlot + ' ' + weeks;
    }
    if (group.kind === TimetableChangeKind.DETAILS) {
      return group.slot + ' ' + weeks + ' · ' + group.detail;
    }
    return group.slot + ' ' + weeks;
  }

  /** 单行描述，用于无障碍朗读。 */
  static describe(group: TimetableChangeGroup): string {
    return TimetableUpdateDiff.kindLabel(group.kind) + ' ' + TimetableUpdateDiff.displayName(group.name) + ' ' +
      TimetableUpdateDiff.detailText(group);
  }

  static displayName(name: string): string {
    return name.trim().length === 0 || name === 'NULL' ? '未命名课程' : name;
  }

  /** [1,2,3,5,7,8] → “第1-3、5、7-8周”。 */
  static weeksText(weeks: number[]): string {
    const parts: string[] = [];
    let i: number = 0;
    while (i < weeks.length) {
      let j: number = i;
      while (j + 1 < weeks.length && weeks[j + 1] === weeks[j] + 1) {
        j++;
      }
      parts.push(j > i ? weeks[i].toString() + '-' + weeks[j].toString() : weeks[i].toString());
      i = j + 1;
    }
    return '第' + parts.join('、') + '周';
  }

  private static classes(events: EasEventItem[]): EasEventItem[] {
    return events.filter((event: EasEventItem): boolean => event.type === EasEventType.CLASS);
  }

  private static weekOf(startTime: number, ts: number): number {
    return Math.floor((EasTimetable.mondayMsOf(ts) - EasTimetable.mondayMsOf(startTime)) / WEEK_MILLIS) + 1;
  }

  private static slotOf(event: EasEventItem): string {
    const day: string = WEEKDAYS[new Date(event.from).getDay()];
    if (event.fromNumber > 0 && event.lastNumber >= event.fromNumber) {
      return day + ' ' + (event.lastNumber > event.fromNumber ?
        event.fromNumber.toString() + '-' + event.lastNumber.toString() : event.fromNumber.toString()) + '节';
    }
    return day + ' ' + TimetableUpdateDiff.clock(event.from) + '-' + TimetableUpdateDiff.clock(event.to);
  }

  private static clock(ts: number): string {
    const date: Date = new Date(ts);
    const minute: number = date.getMinutes();
    return date.getHours().toString() + ':' + (minute < 10 ? '0' : '') + minute.toString();
  }

  private static detailChange(before: EasEventItem, after: EasEventItem): string {
    const parts: string[] = [];
    if (normalizeHtmlSpaces(before.place) !== normalizeHtmlSpaces(after.place)) {
      parts.push('地点 ' + TimetableUpdateDiff.orNone(before.place) + ' → ' + TimetableUpdateDiff.orNone(after.place));
    }
    if (before.teacher !== after.teacher) {
      parts.push('教师 ' + TimetableUpdateDiff.orNone(before.teacher) + ' → ' + TimetableUpdateDiff.orNone(after.teacher));
    }
    if (before.fromNumber !== after.fromNumber || before.lastNumber !== after.lastNumber) {
      parts.push('节次 ' + TimetableUpdateDiff.sections(before) + ' → ' + TimetableUpdateDiff.sections(after));
    }
    return parts.join('，');
  }

  private static sections(event: EasEventItem): string {
    if (event.fromNumber <= 0) {
      return '无';
    }
    return event.lastNumber > event.fromNumber ?
      event.fromNumber.toString() + '-' + event.lastNumber.toString() : event.fromNumber.toString();
  }

  private static orNone(value: string): string {
    return value.trim().length > 0 ? value : '无';
  }
}
