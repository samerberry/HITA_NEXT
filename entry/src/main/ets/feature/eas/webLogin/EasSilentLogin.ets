/**
 * EasSilentLogin.ets — 在隐藏的 Web 组件中执行一次无界面校区登录（静默续期）。
 *
 * 页面推进与 Cookie 采集复用 EasWebLoginController。页面停在统一认证或二次认证，
 * 或出现可见的密码、验证码输入框时立即放弃；只读检查页面，绝不填写任何内容。
 */
import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { EasCampus, EasSession } from '../EasSession';
import { EasWebLoginController } from './EasWebLoginController';
import { EasCampusConfig, easWebLoginConfigFor } from './EasWebLoginConfig';
import { hostOf, ignoresLoginFormDuringRenewal, isCredentialPromptPage } from './EasWebLoginProbe';

const TAG: string = 'HitaSilentLogin';
const DOMAIN: number = 0x0000;

/** 本部本科登录后还要桥接实验教学与电子实验会话，最坏情况超过 30 秒。 */
export const SILENT_LOGIN_TIMEOUT_MS: number = 40000;
const PROMPT_PROBE_INTERVAL_MS: number = 1500;
const PROMPT_FOUND: string = 'hita-credential-prompt';

/** 认证门户多为单页应用，表单可能在 onPageEnd 之后才渲染，需要定时复查。 */
const PROMPT_PROBE_SCRIPT: string = `
  (function() {
    var codeField = /captcha|vcode|checkcode|verifycode|verify_code|smscode|sms_code|dynamiccode|验证码|校验码|动态码/i;
    var inputs = document.querySelectorAll('input');
    for (var i = 0; i < inputs.length; i++) {
      var input = inputs[i];
      var style = window.getComputedStyle ? window.getComputedStyle(input) : null;
      if (style && (style.display === 'none' || style.visibility === 'hidden')) continue;
      var rect = input.getBoundingClientRect ? input.getBoundingClientRect() : null;
      if (rect && (rect.width <= 0 || rect.height <= 0)) continue;
      if (String(input.type || '').toLowerCase() === 'password') return '${PROMPT_FOUND}';
      var label = [input.name, input.id, input.placeholder, input.getAttribute('aria-label')].join(' ');
      if (codeField.test(label)) return '${PROMPT_FOUND}';
    }
    return 'none';
  })();
`;

/** 挂载隐藏 Web 组件并返回释放函数。 */
export type EasSilentWebMount = (url: string, controller: webview.WebviewController,
  login: EasSilentLogin) => () => void;

export class EasSilentLogin {
  private readonly cfg: EasCampusConfig;
  private readonly webController: webview.WebviewController = new webview.WebviewController();
  private readonly loginController: EasWebLoginController = new EasWebLoginController();
  private resolveResult: (session: EasSession | undefined) => void = () => {};
  private release: () => void = () => {};
  private done: boolean = false;
  private started: boolean = false;
  private probing: boolean = false;
  private pageReady: boolean = false;
  private currentPageUrl: string = '';
  private timeoutTimer: number = -1;
  private probeTimer: number = -1;

  constructor(campus: EasCampus, studentType: string) {
    this.cfg = easWebLoginConfigFor(campus, studentType);
  }

  /** 结果为新的网页登录会话；需要用户介入、出错或超时则为 undefined。 */
  run(mount: EasSilentWebMount): Promise<EasSession | undefined> {
    return new Promise<EasSession | undefined>((resolve) => {
      this.resolveResult = resolve;
      this.loginController.onError = (message: string) => {
        if (message.length > 0) {
          this.fail('login flow error');
        }
      };
      this.loginController.onFinished = (session: EasSession) => {
        this.settle(session, 'renewed');
      };
      EasWebLoginController.configureWebCookies();
      this.timeoutTimer = setTimeout(() => {
        this.timeoutTimer = -1;
        this.fail('timeout');
      }, SILENT_LOGIN_TIMEOUT_MS);
      let release: () => void = () => {};
      try {
        release = mount(this.cfg.loginUrl, this.webController, this);
      } catch (e) {
        this.fail('web unavailable');
        return;
      }
      if (this.done) {
        EasSilentLogin.releaseLater(release);
      } else {
        this.release = release;
      }
    });
  }

  // ------------------------------------------------------------------
  // 隐藏 Web 组件回调（与 EasLoginPage 的页面事件转发一致）
  // ------------------------------------------------------------------

  attached(): void {
    if (this.done || this.started) {
      return;
    }
    this.started = true;
    this.activate();
    this.currentPageUrl = this.cfg.loginUrl;
    this.loginController.attachWeb(this.webController);
    this.loginController.start(this.cfg.campus.toString(), this.cfg.studentType);
    this.schedulePromptProbe();
  }

  pageBegin(url: string): void {
    if (this.done) {
      return;
    }
    this.activate();
    this.currentPageUrl = url;
    this.pageReady = false;
    this.loginController.notifyPageBegin(url);
  }

  pageEnd(url: string): void {
    if (this.done || url !== this.currentPageUrl) {
      return;
    }
    this.pageReady = true;
    if (isCredentialPromptPage(url)) {
      this.fail('sign-in required at ' + hostOf(url));
      return;
    }
    this.loginController.notifyPageEnd(url);
    this.probePrompt();
  }

  /** 本部页面的重定向和片段导航只在最终加载回调里出现。 */
  loadFinished(url: string): void {
    if (this.done || this.cfg.campus !== EasCampus.BENBU || url.length === 0) {
      return;
    }
    try {
      if (this.webController.getUrl() !== url) {
        return;
      }
    } catch (e) {
      return;
    }
    if (url === this.currentPageUrl && this.pageReady) {
      return;
    }
    if (url !== this.currentPageUrl) {
      this.currentPageUrl = url;
      this.loginController.notifyPageBegin(url);
    }
    this.pageEnd(url);
  }

  /** 主框架加载失败时登录无法推进，立即放弃；被新导航取消（UA 切换后重载）的不算。 */
  mainFrameError(errorInfo: string): void {
    if (this.done || /ABORTED/i.test(errorInfo)) {
      return;
    }
    this.fail('page load failed: ' + errorInfo);
  }

  windowNew(url: string): void {
    if (this.done || url.length === 0) {
      return;
    }
    try {
      this.webController.loadUrl(url);
    } catch (e) {}
  }

  // ------------------------------------------------------------------
  // 用户介入检测与收尾
  // ------------------------------------------------------------------

  /** 未挂到页面上的 Web 组件需要显式激活，否则不执行页面脚本。 */
  private activate(): void {
    try {
      this.webController.onActive();
    } catch (e) {}
  }

  private schedulePromptProbe(): void {
    if (this.done) {
      return;
    }
    this.probeTimer = setTimeout(() => {
      this.probeTimer = -1;
      this.probePrompt();
      this.schedulePromptProbe();
    }, PROMPT_PROBE_INTERVAL_MS);
  }

  private probePrompt(): void {
    if (this.done || !this.started || this.probing) {
      return;
    }
    let url: string = '';
    try {
      url = this.webController.getUrl();
    } catch (e) {
      return;
    }
    if (url === undefined || url === null || url.length === 0) {
      return;
    }
    if (isCredentialPromptPage(url)) {
      this.fail('sign-in required at ' + hostOf(url));
      return;
    }
    if (ignoresLoginFormDuringRenewal(url)) {
      return;
    }
    let probe: Promise<string>;
    try {
      probe = this.webController.runJavaScript(PROMPT_PROBE_SCRIPT);
    } catch (e) {
      return;
    }
    this.probing = true;
    probe.then((raw: string) => {
      this.probing = false;
      if (!this.done && raw !== undefined && raw !== null && raw.indexOf(PROMPT_FOUND) >= 0) {
        this.fail('credential input at ' + hostOf(url));
      }
    }).catch(() => {
      this.probing = false;
    });
  }

  private fail(reason: string): void {
    this.settle(undefined, reason);
  }

  private settle(session: EasSession | undefined, reason: string): void {
    if (this.done) {
      return;
    }
    this.done = true;
    hilog.info(DOMAIN, TAG, 'Silent login %{public}s: campus=%{public}s', reason, this.cfg.campus.toString());
    if (this.timeoutTimer >= 0) {
      clearTimeout(this.timeoutTimer);
      this.timeoutTimer = -1;
    }
    if (this.probeTimer >= 0) {
      clearTimeout(this.probeTimer);
      this.probeTimer = -1;
    }
    this.loginController.stop();
    try {
      this.webController.stop();
    } catch (e) {}
    const release: () => void = this.release;
    this.release = () => {};
    EasSilentLogin.releaseLater(release);
    this.resolveResult(session);
  }

  /** 不在 ArkWeb 自身的回调里同步销毁组件。 */
  private static releaseLater(release: () => void): void {
    setTimeout(() => {
      try {
        release();
      } catch (e) {}
    }, 0);
  }
}
