/**
 * EasSessionStore.ets — 使用 Preferences 持久化教务会话。
 *
 * Cookie 和 token 当前以 JSON 保存，尚未接入 HUKS 加密。
 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { EasCampus, EasSession } from './EasSession';

const STORE_NAME: string = 'hitanext_store';
const SESSION_PREFIX: string = 'eas_session_';
const LAST_CAMPUS_KEY: string = 'eas_last_campus';
export const EAS_SESSION_REVISION_KEY: string = 'hita_eas_session_revision';

export class EasSessionStore {
  private static instance: EasSessionStore | undefined = undefined;
  private store: preferences.Preferences | undefined = undefined;
  private mutation: Promise<void> = Promise.resolve();

  private enqueue(action: () => Promise<void>): Promise<void> {
    const pending = this.mutation.then(action);
    this.mutation = pending.catch(() => {});
    return pending;
  }

  private notifyChanged(): void {
    const revision: number = AppStorage.get<number>(EAS_SESSION_REVISION_KEY) ?? 0;
    AppStorage.setOrCreate(EAS_SESSION_REVISION_KEY, revision + 1);
  }

  static getInstance(): EasSessionStore {
    if (EasSessionStore.instance === undefined) {
      EasSessionStore.instance = new EasSessionStore();
    }
    return EasSessionStore.instance;
  }

  /** 必须在 Ability/UIAbility 上下文可用后调用一次。 */
  async init(context: common.Context): Promise<void> {
    try {
      this.store = await preferences.getPreferences(context, { name: STORE_NAME });
    } catch (e) {
      this.store = undefined;
    }
  }

  private keyOf(campus: EasCampus): string {
    return SESSION_PREFIX + campus.toString();
  }

  /** 读取某校区会话；无则返回 undefined。 */
  async load(campus: EasCampus): Promise<EasSession | undefined> {
    if (this.store === undefined) {
      return undefined;
    }
    try {
      const raw: preferences.ValueType = await this.store.get(this.keyOf(campus), '');
      const text: string = raw === undefined || raw === null ? '' : String(raw);
      if (text.length === 0) {
        return undefined;
      }
      return EasSession.decode(text);
    } catch (e) {
      return undefined;
    }
  }

  /** 课表使用最近登录的校区；无可用会话时按本部、威海、深圳回退。 */
  async loadPreferred(): Promise<EasSession | undefined> {
    const preferred: EasCampus | undefined = await this.loadLastCampus();
    const order: EasCampus[] = [EasCampus.BENBU, EasCampus.WEIHAI, EasCampus.SHENZHEN];
    if (preferred !== undefined) {
      const index: number = order.indexOf(preferred);
      if (index > 0) {
        order.splice(index, 1);
        order.unshift(preferred);
      }
    }
    for (let i: number = 0; i < order.length; i++) {
      const session: EasSession | undefined = await this.load(order[i]);
      if (session !== undefined && session.isLogin()) {
        return session;
      }
    }
    return undefined;
  }

  /**
   * 仅在网页登录成功后调用；与失效标记串行，避免旧请求覆盖新登录。
   * 静默续期传入 replacing：只有存储中仍是发起续期的那一代会话时才写入，
   * 且不改变当前校区选择。返回是否已写入。
   */
  async save(session: EasSession, replacing?: EasSession): Promise<boolean> {
    let saved: boolean = false;
    await this.enqueue(async () => {
      if (this.store === undefined) return;
      try {
        const previous = await this.load(session.campus);
        if (replacing !== undefined && (previous === undefined ||
          previous.sessionGeneration !== replacing.sessionGeneration ||
          previous.getStudentType() !== replacing.getStudentType())) return;
        session.sessionGeneration = Math.max(Date.now(), (previous?.sessionGeneration ?? 0) + 1);
        session.loginExpired = false;
        await this.store.put(this.keyOf(session.campus), session.encode());
        if (replacing === undefined) {
          await this.store.put(LAST_CAMPUS_KEY, session.campus.toString());
        }
        await this.store.flush();
        this.notifyChanged();
        saved = true;
      } catch (_) {}
    });
    return saved;
  }

  /** 只修改发起该请求的同一会话；保留身份资料、凭据和当前校区选择。 */
  async markExpired(requestSession: EasSession): Promise<void> {
    return this.enqueue(async () => {
      if (this.store === undefined) return;
      try {
        const current = await this.load(requestSession.campus);
        if (current === undefined || current.loginExpired ||
          current.sessionGeneration !== requestSession.sessionGeneration ||
          current.getStudentType() !== requestSession.getStudentType() ||
          current.webBaseUrl !== requestSession.webBaseUrl ||
          current.accessToken !== requestSession.accessToken ||
          EasSession.buildCookieHeader(current.webCookies) !== EasSession.buildCookieHeader(requestSession.webCookies)) return;
        current.loginExpired = true;
        await this.store.put(this.keyOf(current.campus), current.encode());
        await this.store.flush();
        this.notifyChanged();
      } catch (_) {}
    });
  }

  /** 最近一次完成登录的校区，用于多校区并存时选择正确的数据会话。 */
  async loadLastCampus(): Promise<EasCampus | undefined> {
    if (this.store === undefined) {
      return undefined;
    }
    try {
      const raw: preferences.ValueType = await this.store.get(LAST_CAMPUS_KEY, '');
      const value: string = raw === undefined || raw === null ? '' : String(raw);
      if (value === EasCampus.SHENZHEN.toString()) {
        return EasCampus.SHENZHEN;
      }
      if (value === EasCampus.BENBU.toString()) {
        return EasCampus.BENBU;
      }
      if (value === EasCampus.WEIHAI.toString()) {
        return EasCampus.WEIHAI;
      }
    } catch (e) {
    }
    return undefined;
  }

  /** 清除某校区会话（退出登录）。 */
  async clear(campus: EasCampus): Promise<void> {
    return this.enqueue(async () => {
      if (this.store === undefined) return;
      try {
        await this.store.delete(this.keyOf(campus));
        const last = await this.loadLastCampus();
        if (last === campus) await this.store.delete(LAST_CAMPUS_KEY);
        await this.store.flush();
        this.notifyChanged();
      } catch (_) {}
    });
  }
}
