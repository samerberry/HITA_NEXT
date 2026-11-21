import { EasApiClient, EasHttpMethod } from '../EasApiClient';
import { EasSession } from '../EasSession';
import { EasCourseScoreItem, EasExamItem, EasTermItem } from '../model/EasModels';
import { ClassroomBuilding, ClassroomRoom, EmptyClassroomData } from '../classroom/EmptyClassroomData';
import { WeihaiGraduateClient } from './WeihaiGraduateClient';

const PAGE_SIZE: number = 20;
const MAX_PAGES: number = 100;

type GraduateRow = Record<string, Object>;

export class WeihaiGraduateRecords {
  private readonly client: WeihaiGraduateClient;

  constructor(api: EasApiClient) {
    this.client = new WeihaiGraduateClient(api);
  }

  async grades(session: EasSession, term: EasTermItem): Promise<EasCourseScoreItem[]> {
    const rows: GraduateRow[] = await this.collect(async (page: number): Promise<string> =>
      this.client.request(session, '/cjgl/grcjcx/grcjcx', JSON.stringify({
        xn: term.yearCode, xq: term.termCode, kcmc: null, cxbj: '-1', pylx: '2', current: page,
        pageSize: PAGE_SIZE, sffx: null
      }), '/cjgl/grcjcx/go/2', EasHttpMethod.POST, true), true);
    return rows.map((row: GraduateRow): EasCourseScoreItem => {
      const item: EasCourseScoreItem = new EasCourseScoreItem();
      item.courseName = WeihaiGraduateRecords.required(row, 'kcmc');
      item.courseCode = WeihaiGraduateRecords.required(row, 'kcdm');
      item.finalScoresText = WeihaiGraduateRecords.text(row, 'xscj');
      const publishedNumber: string = WeihaiGraduateRecords.text(row, 'xszscj');
      if (item.finalScoresText.length > 0 && publishedNumber.length > 0 && Number.isFinite(Number(publishedNumber))) {
        item.finalScores = Math.trunc(Number(publishedNumber));
      }
      item.credits = WeihaiGraduateRecords.number(row, 'xf');
      item.hours = WeihaiGraduateRecords.number(row, 'xs');
      item.courseProperty = WeihaiGraduateRecords.text(row, 'kcxz');
      item.courseCategory = WeihaiGraduateRecords.text(row, 'kclb');
      item.schoolName = WeihaiGraduateRecords.text(row, 'yxmc');
      item.assessMethod = WeihaiGraduateRecords.text(row, 'khfs');
      item.termName = WeihaiGraduateRecords.text(row, 'xnxqmc') || term.name;
      return item;
    });
  }

  async exams(session: EasSession, term: EasTermItem): Promise<EasExamItem[]> {
    const fields: Map<string, string> = new Map<string, string>([
      ['ppylx', '2'], ['pxn', term.yearCode], ['pxq', term.termCode], ['pkssjdm', '']
    ]);
    const rows: GraduateRow[] = await this.collectForm(session, '/kscxtj/queryXsksByxhList',
      '/kscxtj/queryXskscxByXh', fields);
    return rows.map((row: GraduateRow): EasExamItem => {
      if (WeihaiGraduateRecords.text(row, 'PYLX') !== '2') throw new Error('考试返回的培养层次与当前会话不符');
      const item: EasExamItem = new EasExamItem();
      item.courseName = WeihaiGraduateRecords.required(row, 'KCMC');
      item.courseCode = WeihaiGraduateRecords.required(row, 'KCDM');
      item.examDate = WeihaiGraduateRecords.text(row, 'KSRQ2');
      item.examTime = WeihaiGraduateRecords.text(row, 'KSJTSJ');
      if (item.examTime.length === 0) {
        const first: number = WeihaiGraduateRecords.number(row, 'KSJC');
        const last: number = WeihaiGraduateRecords.number(row, 'JSJC');
        if (Number.isInteger(first) && Number.isInteger(last) && first > 0 && last >= first) {
          item.examTime = '第' + first.toString() + '-' + last.toString() + '节';
        }
      }
      item.examType = WeihaiGraduateRecords.text(row, 'KSSJDMC');
      const building: string = WeihaiGraduateRecords.text(row, 'JXLMC');
      const room: string = WeihaiGraduateRecords.text(row, 'CDMC');
      item.examLocation = room.length > 0 && building.length > 0 && room.startsWith(building) ?
        room : (building + ' ' + room).trim();
      item.termName = term.name;
      item.campusName = '威海校区';
      return item;
    });
  }

  async buildings(session: EasSession): Promise<ClassroomBuilding[]> {
    const body: string = await this.client.request(session, '/pksd/queryjxlList', '', '/cdkb/querycdzy');
    if (!body.trim().startsWith('[')) throw new Error('威海研究生教务返回了无法识别的记录');
    return EmptyClassroomData.parseBuildings(body);
  }

  async classrooms(session: EasSession, term: EasTermItem, building: ClassroomBuilding,
    week: number): Promise<ClassroomRoom[]> {
    const referer: string = '/cdkb/querycdzy';
    const fields: Map<string, string> = new Map<string, string>([
      ['pxn', term.yearCode], ['pxq', term.termCode], ['jxl', building.id], ['zc', week.toString()],
      ['wpksfxs', '1'], ['kjs', '0'], ['xsbkycd', '0']
    ]);
    const rows: GraduateRow[] = await this.collectForm(session, '/cdkb/querycdzyleftzhou', referer, fields);
    const rooms: ClassroomRoom[] = EmptyClassroomData.parseShenzhenRooms(JSON.stringify(rows)).rooms;
    if (rooms.length === 0) return rooms;
    fields.delete('pageSize');
    fields.delete('pageNum');
    const occupancy: string = await this.client.request(session, '/cdkb/querycdzyrightzhou',
      WeihaiGraduateClient.form(fields), referer);
    EmptyClassroomData.applyWeihaiGraduateOccupancy(rooms, occupancy);
    return rooms;
  }

  private collectForm(session: EasSession, path: string, referer: string,
    fields: Map<string, string>): Promise<GraduateRow[]> {
    fields.set('pageSize', PAGE_SIZE.toString());
    return this.collect((page: number): Promise<string> => {
      fields.set('pageNum', page.toString());
      return this.client.request(session, path, WeihaiGraduateClient.form(fields), referer);
    });
  }

  private async collect(load: (page: number) => Promise<string>, enveloped: boolean = false): Promise<GraduateRow[]> {
    const result: GraduateRow[] = [];
    let expected: number = -1;
    let pageSize: number = 0;
    const seen: Set<string> = new Set<string>();
    for (let page: number = 1; page <= MAX_PAGES; page++) {
      const body: string = await load(page);
      let root: GraduateRow;
      try {
        root = JSON.parse(body) as GraduateRow;
      } catch (_) {
        break;
      }
      const data = (enveloped ? root?.['content'] : root) as GraduateRow;
      const code: string = String(root?.['code'] ?? '200');
      if (!data || !Array.isArray(data['list']) || data['success'] === false ||
        (enveloped && code !== '200' && code !== '0') || (!enveloped && root['content'] !== undefined)) break;
      const count: string = WeihaiGraduateRecords.text(data, 'total');
      const total: number = Number(count);
      const rows = data['list'] as GraduateRow[];
      const size: number = Number(data['pageSize']);
      if (!/^\d+$/.test(count) || !Number.isInteger(size) || size < 1 || size > PAGE_SIZE ||
        total > MAX_PAGES * size || (expected !== -1 && (total !== expected || size !== pageSize)) ||
        Number(data['pageNum']) !== page || rows.length !== Math.min(size, total - result.length) ||
        rows.some((row: GraduateRow): boolean => !row || typeof row !== 'object' || Array.isArray(row))) break;
      expected = total;
      pageSize = size;
      for (const row of rows) {
        const key: string = JSON.stringify(Object.keys(row).sort().map((field: string): Object[] => [field, row[field]]));
        seen.add(key);
      }
      result.push(...rows);
      if (seen.size !== result.length) break;
      if (result.length === total) return result;
    }
    throw new Error('威海研究生教务未返回完整的查询结果，请稍后重试');
  }

  private static required(row: GraduateRow, key: string): string {
    const value: string = WeihaiGraduateRecords.text(row, key);
    if (value.length === 0) throw new Error('威海研究生教务返回了无法识别的记录');
    return value;
  }

  private static text(row: GraduateRow, key: string): string {
    return EmptyClassroomData.text(row, [key]);
  }

  private static number(row: GraduateRow, key: string): number {
    const number: number = Number(WeihaiGraduateRecords.text(row, key));
    return Number.isFinite(number) && number >= 0 ? number : 0;
  }
}
