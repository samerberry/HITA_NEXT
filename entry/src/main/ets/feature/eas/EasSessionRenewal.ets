/**
 * EasSessionRenewal.ets — 教务会话静默续期。
 *
 * 业务请求收到明确的认证失效后，借用网页内仍有效的统一认证/VPN 登录状态，
 * 无界面地重新走一遍校区登录。需要用户输入账号、验证码或二次认证时放弃，
 * 由 EasApiClient 照常标记过期。续期结果经 EasSessionStore.save 写入新一代会话，
 * 并且只替换发起续期的那一代，防止覆盖期间完成的手动登录或退出登录。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { EasCampus, EasSession } from './EasSession';
import { EasSessionStore } from './EasSessionStore';
import { EasApiClient } from './EasApiClient';

const TAG: string = 'HitaSessionRenewal';
const DOMAIN: number = 0x0000;

/** 执行一次无界面网页登录；无法静默完成时返回 undefined。 */
export type EasSilentLoginRunner = (campus: EasCampus, studentType: string) => Promise<EasSession | undefined>;

export class EasSessionRenewal {
  private static instance: EasSessionRenewal | undefined = undefined;
  private runner: EasSilentLoginRunner | undefined = undefined;
  private pending: Map<string, Promise<EasSession | undefined>> = new Map<string, Promise<EasSession | undefined>>();
  /** 静默续期已失败的会话代数；同一代不再重试，等待用户手动登录。 */
  private failedGenerations: Map<string, number> = new Map<string, number>();

  static getInstance(): EasSessionRenewal {
    if (EasSessionRenewal.instance === undefined) {
      EasSessionRenewal.instance = new EasSessionRenewal();
    }
    return EasSessionRenewal.instance;
  }

  /** 注册无界面登录实现，此后所有教务请求在认证失效时先尝试续期。 */
  attach(runner: EasSilentLoginRunner): void {
    this.runner = runner;
    EasApiClient.setDefaultReloginHandler((session: EasSession, reason: string) => this.renew(session, reason));
  }

  /**
   * 为认证失效的请求续期。返回 true 时已把新一代会话凭据写回 session，
   * 调用方可直接重试；同校区并发失效只执行一次网页登录。
   */
  async renew(session: EasSession, reason: string): Promise<boolean> {
    const runner: EasSilentLoginRunner | undefined = this.runner;
    if (runner === undefined) {
      return false;
    }
    const current: EasSession | undefined = await EasSessionStore.getInstance().load(session.campus);
    if (current === undefined || current.loginExpired ||
      current.getStudentType() !== session.getStudentType()) {
      return false;
    }
    if (current.sessionGeneration !== session.sessionGeneration) {
      // 期间已有续期或手动登录换上新会话，用它重试即可。
      session.adoptWebLogin(current);
      return true;
    }
    const key: string = EasSessionRenewal.keyOf(current);
    if (this.failedGenerations.get(key) === current.sessionGeneration) {
      return false;
    }
    let task: Promise<EasSession | undefined> | undefined = this.pending.get(key);
    if (task === undefined) {
      hilog.info(DOMAIN, TAG, 'Silent renewal started: campus=%{public}s reason=%{public}s', key, reason);
      const started: Promise<EasSession | undefined> = this.renewStored(current, runner);
      this.pending.set(key, started);
      started.then(() => {
        if (this.pending.get(key) === started) {
          this.pending.delete(key);
        }
      });
      task = started;
    }
    const renewed: EasSession | undefined = await task;
    if (renewed === undefined) {
      return false;
    }
    session.adoptWebLogin(renewed);
    return true;
  }

  private async renewStored(expected: EasSession, runner: EasSilentLoginRunner): Promise<EasSession | undefined> {
    const key: string = EasSessionRenewal.keyOf(expected);
    const store: EasSessionStore = EasSessionStore.getInstance();
    try {
      const login: EasSession | undefined = await runner(expected.campus, expected.getStudentType());
      if (login !== undefined) {
        const renewed: EasSession | undefined = EasSession.decode(expected.encode());
        if (renewed !== undefined) {
          renewed.adoptWebLogin(login);
          if (await store.save(renewed, expected)) {
            hilog.info(DOMAIN, TAG, 'Silent renewal saved: campus=%{public}s', key);
            return renewed;
          }
        }
      }
      // 续期失败或未写入时，如已有更新的登录则沿用它，否则保持过期。
      const latest: EasSession | undefined = await store.load(expected.campus);
      if (latest !== undefined && !latest.loginExpired &&
        latest.sessionGeneration !== expected.sessionGeneration &&
        latest.getStudentType() === expected.getStudentType()) {
        return latest;
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'Silent renewal error: %{public}s', String(e));
    }
    this.failedGenerations.set(key, expected.sessionGeneration);
    hilog.info(DOMAIN, TAG, 'Silent renewal unavailable: campus=%{public}s', key);
    return undefined;
  }

  private static keyOf(session: EasSession): string {
    return session.campus.toString() + ':' + session.getStudentType();
  }
}
