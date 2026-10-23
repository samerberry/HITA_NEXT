/**
 * AppNoticeCenter.ets — 公告中心。
 *
 * 数据源：NOTICES_URL 指向的 JSON 文件（格式 {"notices":[...]}）。
 * kind: version(版本提醒) / service(服务公告) / incident(故障通知)
 * severity: critical(重要，红底置顶) / info(普通)
 * 拉取成功后写偏好缓存；离线时回落缓存。生效过滤：时间窗 + 版本上下限
 * （min_app_version / max_app_version、affected_min_version / affected_max_version），
 * critical 排前。
 */
import { bundleManager } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

/**
 * 公告来源：一个返回 {"notices":[...]} 的 JSON 文件的 URL。
 * 换成你自己的地址即可（Gitee/GitHub raw、对象存储、自己的服务器都行）。
 * 修改这个文件并保存，应用下次打开公告页就会显示新内容，无需重新安装。
 */
const NOTICES_URL: string = 'https://gitee.com/samerberry/hitanext-notices/raw/master/notices.json';
const CACHE_PREFS: string = 'app_notice';
const CACHE_KEY: string = 'cached_notices_v1';

export class AppNotice {
  id: string = '';
  kind: string = 'service';
  severity: string = 'info';
  title: string = '公告';
  body: string = '';
  minAppVersion: number = -1;
  maxAppVersion: number = -1;
  affectedMinVersion: number = -1;
  affectedMaxVersion: number = -1;
  startsAt: number = -1;
  endsAt: number = -1;

  isCritical(): boolean {
    return this.severity === 'critical';
  }

  isVersionKind(): boolean {
    return this.kind === 'version';
  }
}

export class AppNoticeCenter {
  private static cacheStore: preferences.Preferences | undefined = undefined;

  private static versionName(): string {
    try {
      const info: bundleManager.BundleInfo =
        bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      return info.versionName;
    } catch (e) {
      return '0.0.0';
    }
  }

  private static versionCode(): number {
    try {
      const info: bundleManager.BundleInfo =
        bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      return info.versionCode;
    } catch (e) {
      return 0;
    }
  }

  private static async store(context: common.Context): Promise<preferences.Preferences | undefined> {
    if (AppNoticeCenter.cacheStore !== undefined) {
      return AppNoticeCenter.cacheStore;
    }
    try {
      AppNoticeCenter.cacheStore =
        await preferences.getPreferences(context, { name: CACHE_PREFS });
    } catch (e) {
      return undefined;
    }
    return AppNoticeCenter.cacheStore;
  }

  /** 异步拉取公告并写缓存；失败时返回缓存（都没有则空）。 */
  static async fetch(context: common.Context): Promise<AppNotice[]> {
    let fetched: AppNotice[] | undefined = undefined;
    try {
      fetched = await AppNoticeCenter.requestNotices();
    } catch (e) {
      fetched = undefined;
    }
    const cached: AppNotice[] = await AppNoticeCenter.cachedNotices(context);
    if (fetched !== undefined) {
      await AppNoticeCenter.cacheNotices(context, fetched);
      return fetched;
    }
    return cached;
  }

  static async cachedNotices(context: common.Context): Promise<AppNotice[]> {
    const store: preferences.Preferences | undefined = await AppNoticeCenter.store(context);
    if (store === undefined) {
      return [];
    }
    try {
      const raw: preferences.ValueType = await store.get(CACHE_KEY, '');
      const text: string = raw === undefined || raw === null ? '' : String(raw);
      if (text.length === 0) {
        return [];
      }
      // 缓存是 JSON 文本，解析出的是没有方法的原生对象，必须重建为 AppNotice 实例，
      // 否则 activeNotices/页面里调用 isCritical() 会直接抛异常（表现为一直加载）。
      const parsed: Array<Record<string, Object>> | undefined =
        JSON.parse(text) as Array<Record<string, Object>> | undefined;
      if (parsed === undefined || !Array.isArray(parsed)) {
        return [];
      }
      const out: AppNotice[] = [];
      for (let i: number = 0; i < parsed.length; i++) {
        const record: Record<string, Object> = parsed[i] as Record<string, Object>;
        if (record === undefined || record === null) {
          continue;
        }
        const notice: AppNotice | undefined = AppNoticeCenter.parseNotice(record);
        if (notice !== undefined) {
          out.push(notice);
        }
      }
      return out;
    } catch (e) {
      return [];
    }
  }

  private static async cacheNotices(context: common.Context, notices: AppNotice[]): Promise<void> {
    const store: preferences.Preferences | undefined = await AppNoticeCenter.store(context);
    if (store === undefined) {
      return;
    }
    try {
      await store.put(CACHE_KEY, JSON.stringify(notices));
      await store.flush();
    } catch (e) {
    }
  }

  /** 命中当前时间窗且版本在上下限范围内的公告，critical 排前。 */
  static activeNotices(notices: AppNotice[], now: number = Date.now()): AppNotice[] {
    const currentVersion: number = AppNoticeCenter.versionCode();
    const out: AppNotice[] = notices.filter((notice: AppNotice): boolean => {
      const started: boolean = notice.startsAt < 0 ? true : now >= notice.startsAt;
      const ended: boolean = notice.endsAt < 0 ? true : now <= notice.endsAt;
      const supported: boolean = notice.minAppVersion < 0 ? true : currentVersion >= notice.minAppVersion;
      const withinMax: boolean = notice.maxAppVersion < 0 ? true : currentVersion <= notice.maxAppVersion;
      const affected: boolean = notice.affectedMinVersion < 0 ? true : currentVersion >= notice.affectedMinVersion;
      const withinAffectedMax: boolean =
        notice.affectedMaxVersion < 0 ? true : currentVersion <= notice.affectedMaxVersion;
      return started && ended && supported && withinMax && affected && withinAffectedMax;
    });
    out.sort((a: AppNotice, b: AppNotice): number => {
      const av: number = a.isCritical() ? 0 : 1;
      const bv: number = b.isCritical() ? 0 : 1;
      return av - bv;
    });
    return out;
  }

  private static async requestNotices(): Promise<AppNotice[]> {
    const versionName: string = AppNoticeCenter.versionName();
    const httpRequest: http.HttpRequest = http.createHttp();
    try {
      const resp: http.HttpResponse = await httpRequest.request(NOTICES_URL, {
        method: http.RequestMethod.GET,
        connectTimeout: 10000,
        readTimeout: 15000,
        expectDataType: http.HttpDataType.STRING,
        header: {
          'User-Agent': 'HITA-Next/' + versionName
        }
      } as http.HttpRequestOptions);
      if (resp.responseCode < 200 || resp.responseCode > 299) {
        throw new Error('公告请求失败: HTTP ' + resp.responseCode.toString());
      }
      const body: string = typeof resp.result === 'string' ? resp.result : JSON.stringify(resp.result);
      const root: Record<string, Object> = JSON.parse(body) as Record<string, Object>;
      const array: Array<Record<string, Object>> | undefined =
        root['notices'] as Array<Record<string, Object>> | undefined;
      if (array === undefined || !Array.isArray(array)) {
        throw new Error('公告响应缺少 notices 数组');
      }
      const out: AppNotice[] = [];
      for (let i: number = 0; i < array.length; i++) {
        const notice: AppNotice | undefined = AppNoticeCenter.parseNotice(array[i]);
        if (notice !== undefined) {
          out.push(notice);
        }
      }
      return out;
    } finally {
      httpRequest.destroy();
    }
  }

  private static parseNotice(obj: Record<string, Object>): AppNotice | undefined {
    if (obj === undefined || obj === null) {
      return undefined;
    }
    const id: string = AppNoticeCenter.textOf(obj['id']);
    if (id.length === 0) {
      return undefined;
    }
    const notice: AppNotice = new AppNotice();
    notice.id = id;
    notice.kind = AppNoticeCenter.textOr(obj['kind'], 'service');
    notice.severity = AppNoticeCenter.textOr(obj['severity'], 'info');
    notice.title = AppNoticeCenter.textOr(obj['title'], '公告');
    notice.body = AppNoticeCenter.textOf(obj['body']);
    notice.minAppVersion = AppNoticeCenter.numOr(
      AppNoticeCenter.firstOf(obj, 'min_app_version', 'minAppVersion'), -1);
    notice.maxAppVersion = AppNoticeCenter.numOr(
      AppNoticeCenter.firstOf(obj, 'max_app_version', 'maxAppVersion'), -1);
    notice.affectedMinVersion = AppNoticeCenter.numOr(
      AppNoticeCenter.firstOf(obj, 'affected_min_version', 'affectedMinVersion'), -1);
    notice.affectedMaxVersion = AppNoticeCenter.numOr(
      AppNoticeCenter.firstOf(obj, 'affected_max_version', 'affectedMaxVersion'), -1);
    notice.startsAt = AppNoticeCenter.numOr(
      AppNoticeCenter.firstOf(obj, 'starts_at', 'startsAt'), -1);
    notice.endsAt = AppNoticeCenter.numOr(
      AppNoticeCenter.firstOf(obj, 'ends_at', 'endsAt'), -1);
    return notice;
  }

  private static firstOf(obj: Record<string, Object>, primary: string, fallback: string): Object | undefined {
    const value: Object | undefined = obj[primary];
    return value === undefined || value === null ? obj[fallback] : value;
  }

  private static textOf(value: Object | undefined): string {
    return value === undefined || value === null ? '' : String(value);
  }

  private static textOr(value: Object | undefined, fallback: string): string {
    const text: string = AppNoticeCenter.textOf(value);
    return text.length > 0 ? text : fallback;
  }

  private static numOr(value: Object | undefined, fallback: number): number {
    if (value === undefined || value === null) {
      return fallback;
    }
    const n: number = Number(value);
    return Number.isNaN(n) ? fallback : n;
  }
}
