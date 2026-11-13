import { EasCourseScoreItem, EasTermItem } from '../model/EasModels';
import { EasUserMessages } from '../EasUserMessages';

export enum ScoreTestType { ALL = 'ALL', NORMAL = 'NORMAL', MIDTERM = 'MIDTERM', RETAKE = 'RETAKE' }

export function scoreErrorMessage(message: string): string {
  const known: string[] = [
    '该校区研究生成绩接口暂未接入，请到教务网站查询',
    '未获取到学期列表，请稍后重试', '成绩响应解析失败，请稍后重试',
    '教务未返回有效成绩列表，请稍后重试', '未识别到成绩表，请确认教务登录状态后重试',
    '教务会话已过期，请在“更多”的教务账号中重新登录', '成绩查询失败，请检查网络或稍后重试'
  ];
  if (known.includes(message) || /^请先在“更多 → 教务账号”登录(深圳|本部|威海)教务$/.test(message)) return message;
  return EasUserMessages.fromError(message, '成绩查询失败，请检查网络或稍后重试');
}

export class OfficialScoreSummary {
  scope: string = '';
  weightedAverage: string = '';
  gpa: string = '';
  rank: string = '';
  total: string = '';
  earnedCredits: string = '';
  passedCourses: string = '';
  allCourseWeightedAverage: string = '';
  allPassedCourseGpa: string = '';
  available(): boolean {
    return [this.weightedAverage, this.gpa, this.rank, this.earnedCredits,
      this.passedCourses, this.allCourseWeightedAverage, this.allPassedCourseGpa].some((v: string) => v.length > 0);
  }
}

export class LocalScoreStatistics {
  count: number = 0;
  credits: number = 0;
  passed: number = 0;
  failed: number = 0;
  pending: number = 0;
  passedCredits: number = 0;
  numericCount: number = 0;
  numericCredits: number = 0;
  average: number = -1;
  weightedAverage: number = -1;
}

export class ScoreRequestSpec {
  path: string = '';
  fields: Map<string, string> = new Map<string, string>();
}

/** Same endpoints and form parameters as Android Benbu/WeihaiEASWebSource.requestScores. */
export function legacyScoreRequest(campus: string, term: EasTermItem, type: ScoreTestType): ScoreRequestSpec {
  const request = new ScoreRequestSpec();
  if (type === ScoreTestType.ALL && campus === 'BENBU') {
    request.path = '/xfj/queryListXfj';
    request.fields.set('pageXnxqks', term.getCode());
    request.fields.set('pageXnxqjs', term.getCode());
  } else {
    request.path = type === ScoreTestType.MIDTERM ? '/cjcx/queryQzcj' : '/cjcx/queryQmcj';
    request.fields.set('pageXnxq', term.getCode());
    if (type !== ScoreTestType.MIDTERM) {
      request.fields.set('pageBkcxbj', type === ScoreTestType.RETAKE ? '2' : (campus === 'BENBU' ? '0' : ''));
      request.fields.set('pageSfjg', '');
    }
  }
  request.fields.set('pageKcmc', '');
  return request;
}

export function scoreHtmlText(html: string): string {
  return html.replace(/<!--[\s\S]*?-->/g, '').replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, '')
    .replace(/<[^>]*>/g, ' ').replace(/&nbsp;|&#160;/gi, ' ').replace(/&amp;/gi, '&')
    .replace(/&lt;/gi, '<').replace(/&gt;/gi, '>').replace(/&quot;/gi, '"').replace(/&#39;|&apos;/gi, "'")
    .replace(/&#(\d+);/g, (_match: string, n: string): string => String.fromCharCode(Number(n)))
    .replace(/\s+/g, ' ').trim();
}

function cells(row: string): string[] {
  const result: string[] = [];
  const pattern = /<(?:th|td)\b[^>]*>([\s\S]*?)<\/(?:th|td)>/gi;
  let match = pattern.exec(row);
  while (match !== null) { result.push(scoreHtmlText(match[1])); match = pattern.exec(row); }
  return result;
}

function column(headers: string[], values: string[], names: string[]): string {
  for (const name of names) { const index = headers.indexOf(name); if (index >= 0) return values[index] ?? ''; }
  return '';
}

/** undefined means an unrecognised response, distinct from a recognised empty grade table. */
export function parseLegacyScores(html: string, term: EasTermItem): EasCourseScoreItem[] | undefined {
  const tables = /<table\b[^>]*>([\s\S]*?)<\/table>/gi;
  let table = tables.exec(html);
  let best: EasCourseScoreItem[] | undefined = undefined;
  while (table !== null) {
    const rows = /<tr\b[^>]*>([\s\S]*?)<\/tr>/gi;
    let row = rows.exec(table[1]);
    let headers: string[] = [];
    const items: EasCourseScoreItem[] = [];
    while (row !== null) {
      const values = cells(row[1]);
      if (headers.length === 0) {
        const candidate = values.map((v: string) => v.replace(/[\s:：]/g, ''));
        if (candidate.includes('课程名称') && ['最终成绩', '总成绩', '成绩'].some((v: string) => candidate.includes(v))) headers = candidate;
      } else if (values.length >= headers.length) {
        const item = new EasCourseScoreItem();
        item.courseName = column(headers, values, ['课程名称']);
        item.courseCode = column(headers, values, ['课程代码', '课程号']);
        item.finalScoresText = column(headers, values, ['最终成绩', '成绩', '总成绩']);
        item.finalScores = numericScore(item.finalScoresText);
        item.credits = Number(column(headers, values, ['学分'])) || 0;
        item.hours = Number(column(headers, values, ['学时'])) || 0;
        item.termName = column(headers, values, ['学年学期']) || term.name;
        item.courseProperty = column(headers, values, ['课程性质']);
        item.courseCategory = column(headers, values, ['课程类别']);
        item.assessMethod = column(headers, values, ['考核方式', '是否考试课']);
        item.schoolName = column(headers, values, ['开课院系', '开课学院']);
        if (item.courseName.length > 0 && item.courseName !== '课程名称') items.push(item);
      }
      row = rows.exec(table[1]);
    }
    if (headers.length > 0 && (best === undefined || items.length > best.length)) best = items;
    table = tables.exec(html);
  }
  if (best === undefined && /queryQ[mz]cj|pageBkcxbj|queryListXfj/i.test(html) &&
    /暂无(?:成绩|数据|记录)|没有(?:符合|查询到|成绩)|无记录/.test(scoreHtmlText(html))) return [];
  return best;
}

export function parseOfficialLegacySummary(html: string): OfficialScoreSummary {
  const summary = new OfficialScoreSummary();
  summary.scope = '教务累计统计';
  const spans = /<span\b[^>]*\bid\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)<\/span>/gi;
  let span = spans.exec(html);
  while (span !== null) {
    if (span[1].toLowerCase() === 'pjxfj') summary.weightedAverage = scoreHtmlText(span[2]);
    if (span[1].toLowerCase() === 'zrs') {
      const parts = scoreHtmlText(span[2]).split('/');
      summary.rank = parts[0].trim(); summary.total = (parts[1] ?? '').trim();
    }
    span = spans.exec(html);
  }
  return summary;
}

function officialValue(data: Record<string, Object>, key: string): string {
  const value = data[key];
  return value === undefined || value === null || String(value) === 'null' ? '' : String(value).trim();
}

export function parseOfficialShenzhenSummary(body: string): OfficialScoreSummary {
  const summary = new OfficialScoreSummary();
  summary.scope = '教务所选学期统计';
  const data = JSON.parse(body) as Record<string, Object>;
  if (!data || typeof data !== 'object' || Array.isArray(data)) return summary;
  summary.weightedAverage = officialValue(data, 'PJXFJ');
  summary.gpa = officialValue(data, 'GPA');
  summary.rank = officialValue(data, 'PJXFJ_PM') || officialValue(data, 'PM');
  summary.total = officialValue(data, 'ZRS');
  summary.earnedCredits = officialValue(data, 'HDXF');
  summary.passedCourses = officialValue(data, 'TGKC');
  summary.allCourseWeightedAverage = officialValue(data, 'QBKCPJXFJ');
  summary.allPassedCourseGpa = officialValue(data, 'GPA_QBJQKC');
  return summary;
}

export function numericScore(raw: string): number {
  const text = raw.trim();
  if (!/^\d+(?:\.\d+)?$/.test(text)) return -1;
  const value = Number(text);
  return value >= 0 && value <= 100 ? value : -1;
}

/** Local calculations never invent a GPA or school rank from a percentage grade. */
export function localScoreStatistics(items: EasCourseScoreItem[], classifyCompletion: boolean = true): LocalScoreStatistics {
  const stats = new LocalScoreStatistics();
  let sum: number = 0; let weighted: number = 0;
  for (const item of items) {
    stats.count++;
    const credits = Number.isFinite(item.credits) ? Math.max(0, item.credits) : 0;
    stats.credits += credits;
    const text = item.displayScore().trim().toUpperCase();
    const numeric = numericScore(text);
    const passed = classifyCompletion && (numeric >= 60 || /^(优秀|优|良好|良|中等|中|及格|合格|通过|P|PASS)$/.test(text));
    const failed = classifyCompletion && ((numeric >= 0 && numeric < 60) || /^(不及格|不合格|未通过|不通过|F|FAIL)$/.test(text));
    if (passed) { stats.passed++; stats.passedCredits += credits; }
    else if (failed) stats.failed++;
    else stats.pending++;
    if (numeric >= 0) {
      stats.numericCount++; sum += numeric;
      stats.numericCredits += credits; weighted += numeric * credits;
    }
  }
  if (stats.numericCount > 0) stats.average = sum / stats.numericCount;
  if (stats.numericCredits > 0) stats.weightedAverage = weighted / stats.numericCredits;
  return stats;
}
