import { EasApiClient, EasApiClientOptions, EasApiResponse, EasHttpMethod } from '../EasApiClient';
import { EasCampus, EasSession } from '../EasSession';
import { EasTermItem } from '../model/EasModels';
import { easWebLoginConfigFor, EasCampusUrls } from '../webLogin/EasWebLoginConfig';
import {
  ClassroomBuilding, ClassroomQueryError, ClassroomRoom, ClassroomRoomPage, EmptyClassroomData
} from './EmptyClassroomData';

/** Endpoint contracts ported from HITA Android v3.0.0; reuse the existing cookie-aware client. */
export class EmptyClassroomService {
  private api: EasApiClient;

  constructor(api: EasApiClient) {
    this.api = api;
  }

  static assertSession(session: EasSession): void {
    if (!session.isLogin() || session.webCookies.size === 0 ||
      (session.campus === EasCampus.SHENZHEN &&
        (!session.hasShenzhenWebSession() || session.webBaseUrl.length === 0))) {
      throw new ClassroomQueryError('AUTH', '请先登录所选校区的教务系统');
    }
    if (session.campus === EasCampus.BENBU && session.getStudentType() === '2') {
      throw new ClassroomQueryError('UNSUPPORTED', '本部研究生教务接口暂未接入，请到学校教务网站查询');
    }
  }

  async getBuildings(session: EasSession): Promise<ClassroomBuilding[]> {
    EmptyClassroomService.assertSession(session);
    if (session.campus === EasCampus.SHENZHEN) {
      // These requests initialize the classroom page context in the Shenzhen EAS.
      const paths: string[] = ['/pksd/queryxiaoquList', '/pksd/querycdlbList', '/kbfbsz/querydqxnxq'];
      for (let i: number = 0; i < paths.length; i++) {
        await this.post(session, paths[i], new Map<string, string>());
      }
      return EmptyClassroomData.parseBuildings(await this.post(session, '/pksd/queryjxlList',
        new Map<string, string>()));
    }
    if (session.campus === EasCampus.WEIHAI) {
      const primary: ClassroomBuilding[] = await this.buildingsInArea(session, '01');
      if (primary.length > 0) {
        return primary;
      }
    }
    // Retain area + exact server ID; similarly named buildings in different areas are distinct.
    const first: ClassroomBuilding[] = await this.buildingsInArea(session, '1');
    const second: ClassroomBuilding[] = await this.buildingsInArea(session, '2');
    return first.concat(second);
  }

  private async buildingsInArea(session: EasSession, area: string): Promise<ClassroomBuilding[]> {
    const fields: Map<string, string> = new Map<string, string>();
    fields.set('id', area);
    return EmptyClassroomData.parseBuildings(await this.post(session,
      '/kjscx/queryJxlListBySjid?sf_request_type=ajax', fields), area);
  }

  async query(session: EasSession, term: EasTermItem, building: ClassroomBuilding,
    week: number): Promise<ClassroomRoom[]> {
    EmptyClassroomService.assertSession(session);
    if (!Number.isInteger(week) || week < 1 || week > EmptyClassroomData.MAX_WEEK ||
      term.yearCode.trim().length === 0 || term.termCode.trim().length === 0 || building.id.trim().length === 0) {
      throw new ClassroomQueryError('INPUT', '请选择学期、教学楼和有效的教学周');
    }
    if (session.campus === EasCampus.SHENZHEN) {
      return this.queryShenzhen(session, term, building, week);
    }
    const fields: Map<string, string> = new Map<string, string>();
    fields.set('pageXnxq', term.getCode());
    fields.set('pageZc1', week.toString());
    fields.set('pageZc2', week.toString());
    fields.set('pageXiaoqu', '');
    fields.set('pageLhdm', building.id);
    fields.set('pageCddm', '');
    if (session.campus === EasCampus.WEIHAI) {
      return this.queryWeihai(session, building, fields);
    }
    return EmptyClassroomData.parseLegacyRooms(await this.post(session, '/kjscx/queryKjs', fields));
  }

  private async queryWeihai(session: EasSession, building: ClassroomBuilding,
    fields: Map<string, string>): Promise<ClassroomRoom[]> {
    const areas: string[] = ['01', '1', '2', ''];
    const selectors: string[] = ['，', ''];
    const normalized: string = building.id.trim().replace(/^0+/, '') || '0';
    let failure: ClassroomQueryError | undefined = undefined;
    for (let a: number = 0; a < areas.length; a++) {
      let remote: ClassroomBuilding[] = [];
      if (areas[a].length > 0) {
        try {
          remote = await this.buildingsInArea(session, areas[a]);
        } catch (e) {
          if (e instanceof ClassroomQueryError && e.kind === 'AUTH') { throw e; }
        }
      }
      const ids: Set<string> = new Set<string>();
      remote.forEach((candidate: ClassroomBuilding) => {
        if ((candidate.id.trim().replace(/^0+/, '') || '0') === normalized ||
          (building.name.trim().length > 0 && candidate.name.trim() === building.name.trim())) {
          ids.add(candidate.id.trim());
        }
      });
      ids.add(building.id.trim());
      ids.add(normalized);
      ids.add(normalized.padStart(2, '0'));
      // Android also tries an empty building ID. Omit that case: it may return every building
      // under the selected building's title. Preserve the requested building at this boundary.
      const candidates: string[] = Array.from(ids);
      for (let b: number = 0; b < candidates.length; b++) {
        for (let c: number = 0; c < selectors.length; c++) {
          fields.set('pageXiaoqu', areas[a]);
          fields.set('pageLhdm', candidates[b]);
          fields.set('pageCddm', selectors[c]);
          try {
            const rooms: ClassroomRoom[] = EmptyClassroomData.parseLegacyRooms(await this.post(session,
              '/kjscx/queryKjs?vpn-12-o1-jwts.hitwh.edu.cn', fields));
            if (rooms.length > 0) { return rooms; }
          } catch (e) {
            if (e instanceof ClassroomQueryError && (e.kind === 'AUTH' || e.kind === 'NETWORK')) { throw e; }
            failure = e instanceof ClassroomQueryError ? e :
              new ClassroomQueryError('DATA', '教务返回的数据无法识别，请稍后重试或到教务网站核对');
          }
        }
      }
    }
    if (failure !== undefined) { throw failure; }
    return [];
  }

  private async queryShenzhen(session: EasSession, term: EasTermItem, building: ClassroomBuilding,
    week: number): Promise<ClassroomRoom[]> {
    const fields: Map<string, string> = new Map<string, string>();
    fields.set('pxn', term.yearCode);
    fields.set('pxq', term.termCode);
    fields.set('dmmc', '');
    fields.set('xiaoqu', '');
    fields.set('jxl', building.id);
    fields.set('cdlb', '');
    fields.set('zc', '0'.repeat(week - 1) + '1' + '0'.repeat(EmptyClassroomData.MAX_WEEK - week));
    fields.set('wpksfxs', '0');
    fields.set('qsjsz', '16');
    fields.set('kjs', '0');
    fields.set('xsbkycd', '0');
    fields.set('zws', '');
    fields.set('lc', '');
    fields.set('pageSize', '500');
    const rooms: ClassroomRoom[] = [];
    const seen: Set<string> = new Set<string>();
    let complete: boolean = false;
    for (let pageNumber: number = 1; pageNumber <= 40; pageNumber++) {
      fields.set('pageNum', pageNumber.toString());
      const page: ClassroomRoomPage = EmptyClassroomData.parseShenzhenRooms(await this.post(session,
        '/cdkb/querycdzyleftzhou?sf_request_type=ajax', fields));
      for (let i: number = 0; i < page.rooms.length; i++) {
        if (seen.has(page.rooms[i].id)) {
          throw new ClassroomQueryError('DATA', '教室列表分页异常，请到学校教务网站核对');
        }
        seen.add(page.rooms[i].id);
        rooms.push(page.rooms[i]);
      }
      if (page.total >= 0 ? rooms.length >= page.total : page.rooms.length < 500) {
        complete = true;
        break;
      }
      if (page.rooms.length === 0) {
        break;
      }
    }
    if (!complete) {
      throw new ClassroomQueryError('DATA', '教室列表未完整加载，请稍后重试');
    }
    fields.delete('pageNum');
    fields.delete('pageSize');
    const occupancy: string = await this.post(session, '/cdkb/querycdzyrightzhou?sf_request_type=ajax', fields);
    EmptyClassroomData.applyShenzhenOccupancy(rooms, occupancy);
    return rooms;
  }

  static isLoginResponse(body: string): boolean {
    const text: string = body.toLowerCase();
    return /会话(?:已失效|超时)|请(?:先|重新)登录|未登录/.test(text) ||
      text.indexOf('authentication/require') >= 0 ||
      (/<(?:html|form|script)\b/.test(text) &&
        (/name\s*=\s*["'](?:password|mm)["']/.test(text) || text.indexOf('/cas/login') >= 0 ||
          text.indexOf('trust.hitsz.edu.cn') >= 0 ||
          (text.indexOf('reauth') >= 0 && text.indexOf('reauth_success') < 0))) ||
      /["'](?:code|statusCode)["']\s*:\s*["']?(?:401|403)\b/.test(body);
  }

  private async post(session: EasSession, path: string, fields: Map<string, string>): Promise<string> {
    const options: EasApiClientOptions = new EasApiClientOptions();
    options.method = EasHttpMethod.POST;
    const parts: string[] = [];
    fields.forEach((value: string, key: string) => {
      parts.push(encodeURIComponent(key) + '=' + encodeURIComponent(value));
    });
    options.body = parts.join('&');
    options.extraHeaders.set('Content-Type', 'application/x-www-form-urlencoded; charset=UTF-8');
    options.extraHeaders.set('X-Requested-With', 'XMLHttpRequest');
    if (session.campus === EasCampus.SHENZHEN) {
      options.extraHeaders.set('RoleCode', '01');
    }
    options.extraHeaders.set('Accept-Language', 'zh-CN,zh-Hans;q=0.9');
    if (session.campus === EasCampus.WEIHAI) {
      options.extraHeaders.set('sec-fetch-site', 'same-origin');
      options.extraHeaders.set('sec-fetch-mode', 'cors');
      options.extraHeaders.set('sec-fetch-dest', 'empty');
    }
    options.extraHeaders.set('Accept', session.campus === EasCampus.BENBU && path === '/kjscx/queryKjs' ?
      'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8' :
      'application/json, text/javascript, */*; q=0.01');
    const base: string = session.campus === EasCampus.SHENZHEN ? session.webBaseUrl :
      session.campus === EasCampus.WEIHAI ? EasCampusUrls.WEIHAI_EAS_PREFIX : EasCampusUrls.JWTS_BASE;
    const originMatch: RegExpMatchArray | null = base.match(/^https?:\/\/[^/]+/);
    if (originMatch !== null) {
      options.extraHeaders.set('Origin', originMatch[0]);
    }
    options.extraHeaders.set('Referer', EasApiClient.joinUrl(base,
      session.campus === EasCampus.SHENZHEN ? '/cdkb/querycdzy' : '/kjscx/queryKjs'));
    const response: EasApiResponse = await this.api.request(session,
      easWebLoginConfigFor(session.campus, session.getStudentType()), path, options);
    if (response.statusCode === 401 || response.statusCode === 302 ||
      response.statusCode === 303 || EmptyClassroomService.isLoginResponse(response.body)) {
      throw new ClassroomQueryError('AUTH', '教务登录已过期，请重新登录后重试');
    }
    if (response.statusCode === 403) {
      // Refused, not signed out: the session stays as it is.
      throw new ClassroomQueryError('HTTP', '教务系统拒绝了访问，请稍后重试，必要时重新登录');
    }
    if (response.statusCode === 0) {
      throw new ClassroomQueryError('NETWORK', '无法连接教务系统，请检查网络后重试');
    }
    if (response.statusCode !== 200) {
      throw new ClassroomQueryError('HTTP', '教务系统暂时无法提供查询，请稍后重试');
    }
    return response.body;
  }
}
