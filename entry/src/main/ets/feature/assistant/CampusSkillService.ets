import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { RdbHelper } from '../../common/db/RdbHelper';
import { EasEventItem, EasEventType, EasTimetable, newId } from '../../common/model/timetable/TimetableModels';
import { TimetableSelectionStore } from '../timetable/data/TimetableSelectionStore';
import { TimetableResolver } from '../timetable/data/TimetableResolver';

export class CampusRequest {
  date: string = 'today';
  endDate: string = '';
  keyword: string = '';
  requestKey: string = '';
  operationId: string = '';
  eventId: string = '';
  name: string = '';
  start: string = '';
  end: string = '';
  place: string = '';
}

export class CampusOperation {
  id: string = newId();
  requestKey: string = '';
  signature: string = '';
  createdAt: number = Date.now();
  status: string = 'pending';
  kind: string = '';
  timetableName: string = '';
  before: string = '';
  event: EasEventItem = new EasEventItem();
}

class CampusSnapshot {
  table: EasTimetable | undefined = undefined;
  events: EasEventItem[] = [];
}

/** Local business boundary shared by Skill entry scripts and the confirmation page. */
export class CampusSkillService {
  private static queue: Promise<void> = Promise.resolve();

  static async snapshot(context: common.Context, timetableId: string = ''): Promise<CampusSnapshot> {
    const db = RdbHelper.getInstance();
    await db.init(context);
    const selection = TimetableSelectionStore.getInstance();
    await selection.init(context);
    const id = timetableId.length > 0 ? timetableId : await selection.load(true);
    const result = new CampusSnapshot();
    result.table = id.length > 0 ? await db.getTimetableById(id, true) : await TimetableResolver.getForDisplay(db, true);
    if (result.table === undefined) throw new Error('尚未选择或导入课表，请先在 HITA 中设置课表');
    result.events = (await db.getEventsOfTimetable(result.table.id, true))
      .concat(await db.getEventsOfTimetable('', true));
    result.events.sort((a: EasEventItem, b: EasEventItem): number => a.from - b.from);
    return result;
  }

  static day(value: string): number {
    const now = new Date();
    now.setHours(0, 0, 0, 0);
    if (value === 'today') return now.getTime();
    if (value === 'tomorrow') { now.setDate(now.getDate() + 1); return now.getTime(); }
    if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) throw new Error('日期需要 YYYY-MM-DD、today 或 tomorrow');
    const parts = value.split('-').map((part: string): number => Number(part));
    const date = new Date(parts[0], parts[1] - 1, parts[2]);
    if (date.getFullYear() !== parts[0] || date.getMonth() !== parts[1] - 1 || date.getDate() !== parts[2]) {
      throw new Error('日期无效');
    }
    return date.getTime();
  }

  static instant(value: string): number {
    if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:00(?:Z|[+-]\d{2}:\d{2})$/.test(value)) {
      throw new Error('时间需要带时区的 ISO 格式，例如 2026-11-02T19:00:00+08:00');
    }
    CampusSkillService.day(value.substring(0, 10));
    const time = Date.parse(value);
    if (!Number.isFinite(time) || Number(value.substring(11, 13)) > 23 || Number(value.substring(14, 16)) > 59) {
      throw new Error('时间无效');
    }
    return time;
  }

  static view(event: EasEventItem): Record<string, Object> {
    return { 'eventId': event.id, 'type': event.type, 'name': event.name, 'place': event.place,
      'teacher': event.teacher, 'start': new Date(event.from).toISOString(), 'end': new Date(event.to).toISOString() };
  }

  static async query(context: common.Context, mode: string, request: CampusRequest): Promise<Record<string, Object>> {
    const snapshot = await CampusSkillService.snapshot(context);
    const from = mode === 'next' ? Date.now() : CampusSkillService.day(request.date);
    const finish = new Date(request.endDate.length > 0 ? CampusSkillService.day(request.endDate) : from);
    if (request.endDate.length === 0 && mode === 'exams') finish.setDate(finish.getDate() + 30);
    finish.setDate(finish.getDate() + 1);
    if (finish.getTime() <= from || (mode !== 'next' && finish.getTime() - from > 93 * 86400000)) {
      throw new Error('查询范围需要在 1 至 93 天内');
    }
    let matches = snapshot.events.filter((event: EasEventItem): boolean => {
      const type = mode === 'exams' ? event.type === EasEventType.EXAM :
        mode === 'next' ? event.type === EasEventType.CLASS : event.type !== EasEventType.TAG;
      return type && event.from >= from && (mode === 'next' || event.from < finish.getTime()) &&
        (request.keyword.length === 0 || event.name.includes(request.keyword));
    });
    if (mode === 'next') matches = matches.slice(0, 1);
    return { 'status': 'success', 'source': 'HITA 本地已导入数据', 'timetable': snapshot.table!.name,
      'currentTime': new Date().toISOString(), 'timezoneOffsetMinutes': -new Date().getTimezoneOffset(),
      'events': matches.slice(0, 100).map(CampusSkillService.view), 'total': matches.length, 'truncated': matches.length > 100 };
  }

  private static async store(context: common.Context): Promise<preferences.Preferences> {
    return preferences.getPreferences(context, { name: 'hita_campus_skill' });
  }

  static async operations(context: common.Context): Promise<CampusOperation[]> {
    const store = await CampusSkillService.store(context);
    return JSON.parse(await store.get('operations', '[]') as string) as CampusOperation[];
  }

  private static async write(context: common.Context, operations: CampusOperation[]): Promise<void> {
    const store = await CampusSkillService.store(context);
    await store.put('operations', JSON.stringify(operations));
    await store.flush();
  }

  private static async exclusive<T>(action: () => Promise<T>): Promise<T> {
    const result = CampusSkillService.queue.then(action);
    CampusSkillService.queue = result.then(() => {}, () => {});
    return result;
  }

  static async prepare(context: common.Context, kind: string, request: CampusRequest): Promise<CampusOperation> {
    return CampusSkillService.exclusive(async (): Promise<CampusOperation> => {
      if (!/^[a-zA-Z0-9_-]{8,80}$/.test(request.requestKey)) throw new Error('请提供 8 至 80 位唯一 requestKey；同一请求重试必须复用');
      const signature = JSON.stringify(request) + kind;
      const operations = await CampusSkillService.operations(context);
      const previous = operations.find((op: CampusOperation): boolean => op.requestKey === request.requestKey);
      if (previous !== undefined) {
        if (previous.signature !== signature) throw new Error('requestKey 已被另一项操作使用');
        return CampusSkillService.operation(context, previous.id);
      }
      const snapshot = await CampusSkillService.snapshot(context);
      const operation = new CampusOperation();
      operation.kind = kind;
      operation.requestKey = request.requestKey;
      operation.signature = signature;
      operation.timetableName = snapshot.table!.name;
      if (kind === 'move') {
        const event = snapshot.events.find((item: EasEventItem): boolean => item.id === request.eventId);
        if (event === undefined || event.type !== EasEventType.CLASS) throw new Error('请先查询并选择准确的课程 eventId');
        operation.before = JSON.stringify(event);
        operation.event = JSON.parse(operation.before) as EasEventItem;
      } else {
        if (request.name.trim().length === 0 || request.name.length > 100) throw new Error('日程名称需要 1 至 100 个字符');
        operation.event.id = 'skill-' + operation.id;
        operation.event.type = EasEventType.OTHER;
        operation.event.name = request.name.trim();
        operation.event.timetableId = snapshot.table!.id;
      }
      operation.event.from = CampusSkillService.instant(request.start);
      operation.event.to = CampusSkillService.instant(request.end);
      if (operation.event.to <= operation.event.from || operation.event.to - operation.event.from > 86400000) {
        throw new Error('结束时间必须晚于开始时间，单次日程不超过 24 小时');
      }
      if (operation.event.from < Date.now()) throw new Error('请选择未来的时间');
      if (operation.event.from < snapshot.table!.startTime) throw new Error('日期早于目标课表的开学日期，请选择本学期内或之后的日期');
      if (request.place.length > 200) throw new Error('地点过长');
      if (kind !== 'move' || request.place.length > 0) operation.event.place = request.place;
      if (kind === 'move') {
        const original = JSON.parse(operation.before) as EasEventItem;
        if (original.from === operation.event.from && original.to === operation.event.to &&
          original.place === operation.event.place) throw new Error('时间和地点没有变化，无需修改');
      }
      const original = operation.before.length > 0 ? JSON.parse(operation.before) as EasEventItem : undefined;
      if (original === undefined || original.from !== operation.event.from || original.to !== operation.event.to) {
        operation.event.fromNumber = 0;
        operation.event.lastNumber = 0;
      }
      const retained = operations.filter((op: CampusOperation): boolean => Date.now() - op.createdAt < 7 * 86400000);
      if (retained.length >= 64) throw new Error('近期操作过多，请稍后重试');
      retained.push(operation);
      await CampusSkillService.write(context, retained);
      return operation;
    });
  }

  static async operation(context: common.Context, id: string): Promise<CampusOperation> {
    const operation = (await CampusSkillService.operations(context)).find((item: CampusOperation): boolean => item.id === id);
    if (operation === undefined) throw new Error('操作不存在或已清理');
    // Recover success after a process exit between the database commit and preference flush.
    const db = RdbHelper.getInstance();
    await db.init(context);
    const current = await db.getEventById(operation.event.id, true);
    if (operation.status === 'pending' && current !== undefined &&
      JSON.stringify(CampusSkillService.view(current)) === JSON.stringify(CampusSkillService.view(operation.event))) {
      operation.status = 'saved';
    }
    if (operation.status === 'pending' && Date.now() - operation.createdAt > 30 * 60000) operation.status = 'expired';
    return operation;
  }

  static async conflicts(context: common.Context, operation: CampusOperation): Promise<EasEventItem[]> {
    const snapshot = await CampusSkillService.snapshot(context, operation.event.timetableId);
    return snapshot.events.filter((event: EasEventItem): boolean => event.id !== operation.event.id &&
      event.type !== EasEventType.TAG && event.from < operation.event.to && event.to > operation.event.from);
  }

  static async finish(context: common.Context, id: string, save: boolean): Promise<void> {
    return CampusSkillService.exclusive(async (): Promise<void> => {
      const operation = await CampusSkillService.operation(context, id);
      if (operation.status === 'saved' || operation.status === 'cancelled') return;
      if (operation.status !== 'pending') throw new Error('草稿已过期，请重新发起');
      if (save) {
        if (operation.event.from < Date.now()) throw new Error('开始时间已过，请重新发起');
        const db = RdbHelper.getInstance();
        await db.init(context);
        await db.commitSkillEvent(operation.event, operation.before);
        operation.status = 'saved';
      } else operation.status = 'cancelled';
      const operations = await CampusSkillService.operations(context);
      const index = operations.findIndex((item: CampusOperation): boolean => item.id === id);
      if (index >= 0) operations[index] = operation;
      await CampusSkillService.write(context, operations);
    });
  }
}
