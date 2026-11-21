/**
 * ShenzhenWebExams.ets — 深圳考试安排 JSON 解析。
 *
 * 教务不同模块会把列表放在 content.list / data / rows 里，字段名也不统一，
 * 因此按语义取首个非空值，对齐成绩解析器的 text() 策略。
 */
import { EasExamItem, EasTermItem } from '../model/EasModels';

export class ParsedShenzhenWebExams {
  code: number = 0;
  msg: string = '';
  list: EasExamItem[] = [];
}

function asRecord(value: Object | undefined): Record<string, Object> | undefined {
  if (value === undefined || value === null || typeof value !== 'object' || Array.isArray(value)) {
    return undefined;
  }
  return value as Record<string, Object>;
}

function easText(obj: Record<string, Object>, keys: string[]): string {
  for (let i = 0; i < keys.length; i++) {
    const v: Object | undefined = obj[keys[i]];
    if (v === undefined || v === null) {
      continue;
    }
    const t: string = typeof v === 'string' ? v : String(v);
    const trimmed: string = t.trim();
    if (trimmed.length > 0 && trimmed !== 'null') {
      return trimmed;
    }
  }
  return '';
}

function easNumber(obj: Record<string, Object>, key: string): number | undefined {
  const v: Object | undefined = obj[key];
  if (v === undefined || v === null) {
    return undefined;
  }
  if (typeof v === 'number') {
    return v as number;
  }
  if (typeof v === 'string') {
    const n: number = Number((v as string).trim());
    if (!Number.isNaN(n)) {
      return n;
    }
  }
  return undefined;
}

function rowsFromValue(value: Object | undefined): Array<Record<string, Object>> | undefined {
  const result: Array<Record<string, Object>> = [];
  if (value === undefined || value === null) {
    return undefined;
  }
  if (Array.isArray(value)) {
    const values: Object[] = value as Object[];
    for (let i = 0; i < values.length; i++) {
      const row: Record<string, Object> | undefined = asRecord(values[i]);
      if (row === undefined) return undefined;
      result.push(row);
    }
    return result;
  }
  const record: Record<string, Object> | undefined = asRecord(value);
  if (record === undefined) {
    return undefined;
  }
  const nestedKeys: string[] = ['content', 'data', 'list', 'rows', 'result', 'resultData', 'ksapList'];
  for (let i = 0; i < nestedKeys.length; i++) {
    const nested: Array<Record<string, Object>> | undefined = rowsFromValue(record[nestedKeys[i]]);
    if (nested !== undefined) {
      return nested;
    }
  }
  return undefined;
}

function examDate(raw: string): string {
  // 教务可能返回 UTC 时间戳，考试日期固定按中国时区计算，避免午夜落到前一天。
  if (/T.*(?:Z|[+-]\d{2}:?\d{2})$/i.test(raw)) {
    const time: number = Date.parse(raw);
    if (!Number.isNaN(time)) {
      return new Date(time + 8 * 60 * 60 * 1000).toISOString().slice(0, 10);
    }
  }
  const date: RegExpMatchArray | null = raw.match(/^\d{4}-\d{2}-\d{2}/);
  return date === null ? raw : date[0];
}

function itemFromJson(item: Record<string, Object>, term: EasTermItem): EasExamItem {
  const out: EasExamItem = new EasExamItem();
  out.courseName = easText(item, ['kcmc', 'KCMC', 'courseName', 'kcm', 'KCM']);
  out.examDate = examDate(easText(item, ['ksrq', 'KSRQ', 'ksrqmc', 'KSRQMC', 'examDate', 'rq', 'RQ']));
  out.examTime = easText(item, [
    'KSJTSJ', 'ksjtsj', 'kssj', 'KSSJ', 'kssjms', 'KSSJMS', 'kssjfw', 'KSSJFW', 'examTime', 'sj', 'SJ'
  ]);
  out.examType = easText(item, ['KSSJDMC', 'kssjdmc', 'kslx', 'KSLX', 'ksmc', 'KSMC', 'kslxmc', 'KSLXMC', 'examType']);
  if (out.examType.length === 0) {
    out.examType = '考试';
  }
  out.examLocation = easText(item, [
    'kscd', 'KSCD', 'ksdd', 'KSDD', 'cdmc', 'CDMC', 'jasmc', 'JASMC',
    'kscdmc', 'KSCDMC', 'examLocation', 'dd', 'DD'
  ]);
  const building: string = easText(item, ['JXLMC', 'jxlmc']);
  const room: string = easText(item, ['JXCDMC', 'jxcdmc', 'CDMC', 'cdmc']);
  const seat: string = easText(item, ['ZWH', 'zwh']);
  const locations: string[] = [];
  for (const part of [building, room]) {
    if (part.length > 0 && locations.indexOf(part) < 0) {
      locations.push(part);
    }
  }
  if (locations.length > 0) {
    out.examLocation = locations.join(' ');
  }
  if (seat.length > 0) {
    out.examLocation = (out.examLocation + ' 座位 ' + seat).trim();
  }
  const termName: string = easText(item, ['xnxqmc', 'XNXQMC', 'termName']);
  out.termName = termName.length > 0 ? termName : term.name;
  return out;
}

export function parseShenzhenWebExams(body: string, term: EasTermItem): ParsedShenzhenWebExams | undefined {
  let root: Object;
  try {
    root = JSON.parse(body) as Object;
  } catch (_) {
    return undefined;
  }
  if (root === undefined || root === null || typeof root !== 'object') {
    return undefined;
  }
  const obj = root as Record<string, Object>;
  const parsed: ParsedShenzhenWebExams = new ParsedShenzhenWebExams();
  const code: number | undefined = easNumber(obj, 'code');
  parsed.code = code === undefined ? 0 : code;
  parsed.msg = easText(obj, ['msg', 'message']);
  const rows: Array<Record<string, Object>> | undefined = rowsFromValue(root);
  if (rows === undefined) {
    // 错误对象或未知结构不能被误报成“暂无考试”。
    return parsed.code !== 0 && parsed.code !== 200 ? parsed : undefined;
  }
  for (let i = 0; i < rows.length; i++) {
    const item: EasExamItem = itemFromJson(rows[i], term);
    // A malformed row cannot be treated as a removed exam when syncing the whole result.
    if (item.courseName.length === 0) return undefined;
    parsed.list.push(item);
  }
  return parsed;
}
