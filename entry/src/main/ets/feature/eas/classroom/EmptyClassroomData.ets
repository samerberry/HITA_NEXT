import { normalizeHtmlSpaces } from '../../../common/util/HtmlSpaces';

export class ClassroomBuilding {
  id: string = '';
  name: string = '';
  area: string = '';

  key(): string {
    return this.area + '/' + this.id;
  }
}

export class ClassroomSlot {
  day: number = 0;
  period: number = 0;
}

export class ClassroomRoom {
  id: string = '';
  name: string = '';
  capacity: number = 0;
  periodCount: number = 12;
  occupied: ClassroomSlot[] = [];
  unknown: ClassroomSlot[] = [];
}

export class ClassroomRoomPage {
  rooms: ClassroomRoom[] = [];
  total: number = -1;
}

export enum ClassroomAvailability {
  FREE = 'FREE',
  OCCUPIED = 'OCCUPIED',
  UNKNOWN = 'UNKNOWN'
}

export class ClassroomQueryError extends Error {
  kind: string;

  constructor(kind: string, message: string) {
    super(message);
    this.kind = kind;
  }
}

/** Parsers shared by the three campus adapters. A failed/malformed response must never become a free room. */
export class EmptyClassroomData {
  static readonly MAX_WEEK: number = 34;

  static text(row: Record<string, Object>, keys: string[]): string {
    for (let i: number = 0; i < keys.length; i++) {
      const value: Object = row[keys[i]];
      if (value !== undefined && value !== null && typeof value !== 'object') {
        const text: string = String(value).trim();
        if (text.length > 0 && text.toLowerCase() !== 'null') {
          return text;
        }
      }
    }
    return '';
  }

  private static dataError(): ClassroomQueryError {
    return new ClassroomQueryError('DATA', '教务返回的数据无法识别，请稍后重试或到教务网站核对');
  }

  private static json(body: string): Object {
    try {
      const root: Object = JSON.parse(body) as Object;
      if (root === null || typeof root !== 'object') {
        throw EmptyClassroomData.dataError();
      }
      return root;
    } catch (e) {
      throw EmptyClassroomData.dataError();
    }
  }

  private static rows(root: Object, depth: number = 0): Record<string, Object>[] | undefined {
    if (root === null || root === undefined || typeof root !== 'object' || depth > 6) {
      return undefined;
    }
    if (Array.isArray(root)) {
      const values: Object[] = root as Object[];
      const result: Record<string, Object>[] = [];
      for (let i: number = 0; i < values.length; i++) {
        if (values[i] === null || typeof values[i] !== 'object' || Array.isArray(values[i])) {
          throw EmptyClassroomData.dataError();
        }
        result.push(values[i] as Record<string, Object>);
      }
      return result;
    }
    const obj: Record<string, Object> = root as Record<string, Object>;
    const code: string = EmptyClassroomData.text(obj, ['code', 'statusCode']);
    if (obj['success'] === false || (code.length > 0 && code !== '0' && code !== '200')) {
      if (code === '401' || code === '403') {
        throw new ClassroomQueryError('AUTH', '教务登录已过期，请重新登录后重试');
      }
      throw EmptyClassroomData.dataError();
    }
    const keys: string[] = ['list', 'content', 'data', 'rows', 'result', 'resultData'];
    for (let i: number = 0; i < keys.length; i++) {
      const value: Object = obj[keys[i]];
      if (value !== undefined && value !== null) {
        const found: Record<string, Object>[] | undefined = EmptyClassroomData.rows(value, depth + 1);
        if (found !== undefined) {
          return found;
        }
      }
    }
    return undefined;
  }

  private static requireRows(root: Object): Record<string, Object>[] {
    const rows: Record<string, Object>[] | undefined = EmptyClassroomData.rows(root);
    if (rows === undefined) {
      throw EmptyClassroomData.dataError();
    }
    return rows;
  }

  static parseBuildings(body: string, area: string = ''): ClassroomBuilding[] {
    const rows: Record<string, Object>[] = EmptyClassroomData.requireRows(EmptyClassroomData.json(body));
    const result: ClassroomBuilding[] = [];
    const seen: Set<string> = new Set<string>();
    for (let i: number = 0; i < rows.length; i++) {
      const item: ClassroomBuilding = new ClassroomBuilding();
      item.id = EmptyClassroomData.text(rows[i], ['DM', 'dm', 'id']);
      item.name = EmptyClassroomData.text(rows[i], ['MC', 'mc', 'name']) || item.id;
      item.area = area;
      if (item.id.length === 0) {
        throw EmptyClassroomData.dataError();
      }
      if (!seen.has(item.key())) {
        result.push(item);
        seen.add(item.key());
      }
    }
    return result;
  }

  private static total(root: Object, depth: number = 0): number {
    if (root === null || root === undefined || typeof root !== 'object' || Array.isArray(root) || depth > 6) {
      return -1;
    }
    const obj: Record<string, Object> = root as Record<string, Object>;
    const raw: string = EmptyClassroomData.text(obj, ['total', 'totalCount', 'recordsTotal']);
    if (/^\d+$/.test(raw)) {
      return Number(raw);
    }
    const keys: string[] = ['content', 'data', 'result', 'resultData'];
    for (let i: number = 0; i < keys.length; i++) {
      const count: number = EmptyClassroomData.total(obj[keys[i]], depth + 1);
      if (count >= 0) {
        return count;
      }
    }
    return -1;
  }

  static parseShenzhenRooms(body: string): ClassroomRoomPage {
    const root: Object = EmptyClassroomData.json(body);
    const rows: Record<string, Object>[] = EmptyClassroomData.requireRows(root);
    const result: ClassroomRoomPage = new ClassroomRoomPage();
    result.total = EmptyClassroomData.total(root);
    const seen: Set<string> = new Set<string>();
    for (let i: number = 0; i < rows.length; i++) {
      const room: ClassroomRoom = new ClassroomRoom();
      room.id = EmptyClassroomData.text(rows[i], ['DM', 'dm', 'id']);
      room.name = EmptyClassroomData.text(rows[i], ['MC', 'mc', 'name']) || room.id;
      const capacity: number = Number(EmptyClassroomData.text(rows[i], ['ZWS', 'zws']));
      room.capacity = Number.isFinite(capacity) && capacity > 0 ? Math.floor(capacity) : 0;
      room.periodCount = 16;
      if (room.id.length === 0 || seen.has(room.id)) {
        throw EmptyClassroomData.dataError();
      }
      seen.add(room.id);
      result.rooms.push(room);
    }
    return result;
  }

  static applyShenzhenOccupancy(rooms: ClassroomRoom[], body: string): void {
    const rows: Record<string, Object>[] = EmptyClassroomData.requireRows(EmptyClassroomData.json(body));
    const byId: Map<string, ClassroomRoom> = new Map<string, ClassroomRoom>();
    rooms.forEach((room: ClassroomRoom) => {
      room.occupied = [];
      byId.set(room.id, room);
    });
    for (let i: number = 0; i < rows.length; i++) {
      const row: Record<string, Object> = rows[i];
      const id: string = EmptyClassroomData.text(row, ['CDDM', 'cddm']);
      const day: number = Number(EmptyClassroomData.text(row, ['XQJ', 'xqj']));
      const period: number = Number(EmptyClassroomData.text(row, ['XJ', 'xj']));
      if (id.length === 0 || !Number.isInteger(day) || day < 1 || day > 7 ||
        !Number.isInteger(period) || period < 1 || period > 16) {
        throw EmptyClassroomData.dataError();
      }
      const flags: string[] = ['PKBJ', 'pkbj', 'JYBJ', 'jybj', 'PKJYBJ', 'pkjybj'];
      let hasFlag: boolean = false;
      let occupied: boolean = false;
      for (let j: number = 0; j < flags.length; j++) {
        if (row[flags[j]] !== undefined) {
          hasFlag = true;
          const value: string = EmptyClassroomData.text(row, [flags[j]]).toLowerCase();
          if (value !== '' && value !== '0' && value !== '否' && value !== 'false') {
            occupied = true;
          }
        }
      }
      if (!hasFlag) {
        throw EmptyClassroomData.dataError();
      }
      const room: ClassroomRoom | undefined = byId.get(id);
      if (room !== undefined && occupied) {
        EmptyClassroomData.addSlot(room.occupied, day, period);
      }
    }
  }

  private static htmlText(html: string): string {
    return normalizeHtmlSpaces(html.replace(/<[^>]*>/g, ' '))
      .replace(/&#(\d+);/g, (_: string, code: string): string => String.fromCharCode(Number(code)))
      .replace(/&#x([0-9a-f]+);/gi, (_: string, code: string): string => String.fromCharCode(parseInt(code, 16)))
      .replace(/&amp;/gi, '&').replace(/&lt;/gi, '<').replace(/&gt;/gi, '>')
      .replace(/&quot;/gi, '"').replace(/&apos;/gi, "'").trim();
  }

  /** Both legacy campuses use 42 cells: seven days, six two-period blocks per day. */
  static parseLegacyRooms(html: string): ClassroomRoom[] {
    const result: ClassroomRoom[] = [];
    const seen: Set<string> = new Set<string>();
    const tables: RegExp = /<table\b([^>]*)>([\s\S]*?)<\/table\s*>/gi;
    let table: RegExpExecArray | null;
    let selectedTable: string = '';
    let widest: number = -1;
    while ((table = tables.exec(html)) !== null) {
      if (!/\bclass\s*=\s*["'][^"']*\bdataTable\b[^"']*["']/i.test(table[1])) {
        continue;
      }
      const rows: string[] = table[2].match(/<tr\b[^>]*>[\s\S]*?<\/tr\s*>/gi) || [];
      let width: number = 0;
      rows.forEach((row: string) => {
        const cells: string[] = row.match(/<t[dh]\b/gi) || [];
        width = Math.max(width, cells.length);
      });
      if (width > widest) {
        widest = width;
        selectedTable = table[0];
      }
    }
    tables.lastIndex = 0;
    let recognized: boolean = false;
    while ((table = tables.exec(selectedTable)) !== null) {
      if (!/\bclass\s*=\s*["'][^"']*\bdataTable\b[^"']*["']/i.test(table[1])) {
        continue;
      }
      const rowPattern: RegExp = /<tr\b[^>]*>([\s\S]*?)<\/tr\s*>/gi;
      let row: RegExpExecArray | null;
      while ((row = rowPattern.exec(table[2])) !== null) {
        if (/<th\b/i.test(row[1])) {
          continue;
        }
        const cells: string[] = [];
        const cellPattern: RegExp = /<td\b([^>]*)>([\s\S]*?)<\/td\s*>/gi;
        let cell: RegExpExecArray | null;
        let spans: boolean = false;
        while ((cell = cellPattern.exec(row[1])) !== null) {
          if (/\b(?:colspan|rowspan)\s*=\s*["']?(?:[2-9]|\d{2,})/i.test(cell[1])) {
            spans = true;
          }
          cells.push(cell[2]);
        }
        const rowText: string = EmptyClassroomData.htmlText(row[1]);
        if (/暂无(?:数据|记录)|没有(?:相关|符合|查询|可用)?(?:数据|记录|教室)|无符合条件|未查询到|no records/i.test(rowText)) {
          recognized = true;
          continue;
        }
        if (cells.length === 0 || /^(?:教室|场地)(?:名称)?$/.test(EmptyClassroomData.htmlText(cells[0]))) {
          continue;
        }
        if (cells.length < 43 || spans) {
          throw EmptyClassroomData.dataError();
        }
        recognized = true;
        const fixed: number = cells.length - 42;
        const room: ClassroomRoom = new ClassroomRoom();
        room.name = EmptyClassroomData.htmlText(cells[0]);
        room.id = room.name;
        if (room.id.length === 0 || seen.has(room.id)) {
          throw EmptyClassroomData.dataError();
        }
        seen.add(room.id);
        for (let i: number = 1; i < fixed; i++) {
          const raw: string = EmptyClassroomData.htmlText(cells[i]);
          if (/^\d+\s*(?:人|座)?$/.test(raw) && room.capacity === 0) {
            room.capacity = parseInt(raw, 10);
          }
        }
        for (let i: number = 0; i < 42; i++) {
          const content: string = cells[fixed + i];
          const day: number = Math.floor(i / 6) + 1;
          const first: number = (i % 6) * 2 + 1;
          const occupied: boolean = /\bclass\s*=\s*["'][^"']*\bkjs_icon01\b[^"']*["']/i.test(content);
          const text: string = EmptyClassroomData.htmlText(content);
          // A capacity column shifted into the grid signals a truncated row, not an empty time block.
          if (/^\d+\s*(?:人|座)?$/.test(text)) {
            throw EmptyClassroomData.dataError();
          }
          const unfamiliarIcon: boolean = /\bkjs_icon(?!01\b|02\b)\d+\b/i.test(content);
          const unknown: boolean = !occupied && (unfamiliarIcon ||
            (text.length > 0 && text !== '空闲' && text !== '空'));
          if (occupied || unknown) {
            const slots: ClassroomSlot[] = occupied ? room.occupied : room.unknown;
            EmptyClassroomData.addSlot(slots, day, first);
            EmptyClassroomData.addSlot(slots, day, first + 1);
          }
        }
        result.push(room);
      }
    }
    if (!recognized) {
      throw EmptyClassroomData.dataError();
    }
    return result;
  }

  private static addSlot(slots: ClassroomSlot[], day: number, period: number): void {
    if (!slots.some((slot: ClassroomSlot): boolean => slot.day === day && slot.period === period)) {
      const slot: ClassroomSlot = new ClassroomSlot();
      slot.day = day;
      slot.period = period;
      slots.push(slot);
    }
  }

  static availability(room: ClassroomRoom, day: number, start: number, end: number): ClassroomAvailability {
    if (!Number.isInteger(day) || day < 1 || day > 7 || !Number.isInteger(start) ||
      !Number.isInteger(end) || start < 1 || end > room.periodCount || start > end) {
      return ClassroomAvailability.UNKNOWN;
    }
    if (room.occupied.some((slot: ClassroomSlot): boolean =>
      slot.day === day && slot.period >= start && slot.period <= end)) {
      return ClassroomAvailability.OCCUPIED;
    }
    if (room.unknown.some((slot: ClassroomSlot): boolean =>
      slot.day === day && slot.period >= start && slot.period <= end)) {
      return ClassroomAvailability.UNKNOWN;
    }
    return ClassroomAvailability.FREE;
  }

}
