/**
 * EasWebLoginController.ets — ArkWeb 网页登录状态机。
 *
 * 1:1 对齐 Android HITA (WebViewLoginActivity.kt, ShenzhenWebAutoLogin.kt, WebLoginSuccessPolicy.kt)：
 *  1. 页面推进完全由 ArkWeb 生命周期事件（onPageBegin / onPageEnd）驱动，杜绝定时器打断网络加载。
 *  2. 深圳校区：
 *     - 初始为桌面 UA，进入 CAS 自动切回移动 UA（保留真实系统 UA，不留空）；
 *     - 自动执行 aTrust shortcut forceWeb 模式；
 *     - 注入视口修正 CSS/JS（aTrust 门户、深圳教务桌面视图、MFA 视口）；
 *     - 自动执行 ShenzhenWebAutoLogin 点击脚本（自动点击“统一身份认证登录”/培养层次）。
 *  3. Cookie 采集与收尾：仅在检测到已认证成功页或进入目标教务系统时启动轮询收尾。
 */
import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { http } from '@kit.NetworkKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { LegacyCookieReader } from './LegacyCookieReader';
import { EasCampus, EasSession } from '../EasSession';
import {
  EasCampusConfig,
  EasCampusUrls,
  easWebLoginConfigFor,
  EasUserAgent
} from './EasWebLoginConfig';
import {
  hasRequiredCookiesFor,
  hasWeihaiVpnTicket,
  hostOf,
  isAuthenticationPage,
  isBenbuEasPage,
  isBlank,
  isJwtsPage,
  isIvpnRedirectPage,
  isMfaPage,
  isPortalHomePage,
  isShenzhenProxyJwPage,
  isSuccessPageFor,
  isTrustPortalPage,
  parseCookiesHeader,
  pathOf,
  reauthenticationUrl
} from './EasWebLoginProbe';
import { EasApiClient, EasApiResponse, EasHttpMethod } from '../EasApiClient';
import { EasLegacyTimetableParser } from '../data/EasLegacyTimetableParser';

const TAG: string = 'HitaLogin';
const DOMAIN: number = 0x0000;

/** 状态机阶段 */
export enum EasLoginPhase {
  IDLE = 'IDLE',
  LOADING = 'LOADING',
  SUCCESS_PROBE = 'SUCCESS_PROBE',
  DONE = 'DONE',
  ERROR = 'ERROR'
}

const COOKIE_RETRY_COUNT_MAX: number = 30;
const COOKIE_RETRY_DELAY_MS: number = 500;
const EELAB_NAV_TIMEOUT_MS: number = 10000;
const SJJX_NAV_TIMEOUT_MS: number = 4000;
const EXPERIMENT_TOTAL_TIMEOUT_MS: number = 8000;
const EELAB_USER_AGENT: string =
  'Mozilla/5.0 (Linux; Android 16; sdk_gphone64_arm64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.6998.135 Mobile Safari/537.36';

export class EasWebLoginController {
  // —— UI 回调 ——
  onPhaseChanged: (phase: string, detail: string) => void = () => {};
  onProgress: (percent: number) => void = () => {};
  onError: (message: string) => void = () => {};
  onFinished: (session: EasSession) => void = () => {};

  private webController: webview.WebviewController | undefined = undefined;
  private cfg: EasCampusConfig | undefined = undefined;
  private phase: EasLoginPhase = EasLoginPhase.IDLE;
  private finished: boolean = false;
  private loginGeneration: number = 0;
  private navigationGeneration: number = 0;
  private completing: boolean = false;
  private weihaiExchangeAttempts: number = 0;
  private benbuVerificationAttempts: number = 0;

  // —— 会话状态 ——
  private session: EasSession = new EasSession();
  private lastUrl: string = '';
  private mobileUa: string = EasUserAgent.ANDROID_MOBILE_REF;
  private shenzhenDesktopUaApplied: boolean = false;
  private shenzhenReauthenticationStarted: boolean = false;
  private shenzhenForceWebModeApplied: boolean = false;
  private autoOpeningJwts: boolean = false;
  private portalOpenAttempts: number = 0;

  // —— 深圳校区自动点击推进 ——
  private shenzhenAutoAdvanceGeneration: number = 0;
  private shenzhenAutoAdvanceScheduledGeneration: number = -1;
  private shenzhenUnifiedLoginClicked: boolean = false;
  private shenzhenRoleSelectionClicked: boolean = false;

  // —— Cookie 轮询 ——
  private cookieRetryCount: number = 0;
  private cookiePollingGeneration: number = 0;
  private cookiePollingActive: boolean = false;

  // —— BENBU 本科 sjjx（实验教学）桥接流程 ——
  private navigatingToSjjx: boolean = false;
  private sjjxFetching: boolean = false;
  private sjjxFetchTimer: number = -1;
  private sjjxTimeoutTimer: number = -1;
  private pendingSjjxCookies: Map<string, string> = new Map<string, string>();
  private experimentTimeoutTimer: number = -1;

  // —— BENBU 本科 EELAB token 流程 ——
  private navigatingToEelab: boolean = false;
  private eelabTokenFetching: boolean = false;
  private collectedEasCookies: Map<string, string> = new Map<string, string>();
  private eelabTimeoutTimer: number = -1;
  private eelabFetchTimer: number = -1;

  attachWeb(controller: webview.WebviewController): void {
    this.webController = controller;
  }

  start(campusCode: string, studentType: string): void {
    this.stop();
    const campus: EasCampus = EasWebLoginController.campusOfCode(campusCode);
    this.cfg = easWebLoginConfigFor(campus, studentType);
    this.finished = false;
    this.cookieRetryCount = 0;
    this.weihaiExchangeAttempts = 0;
    this.benbuVerificationAttempts = 0;
    this.cookiePollingActive = false;
    this.cookiePollingGeneration++;
    this.shenzhenDesktopUaApplied = false;
    this.shenzhenReauthenticationStarted = false;
    this.shenzhenForceWebModeApplied = false;
    this.shenzhenUnifiedLoginClicked = false;
    this.shenzhenRoleSelectionClicked = false;
    this.shenzhenAutoAdvanceScheduledGeneration = -1;
    this.autoOpeningJwts = false;
    this.portalOpenAttempts = 0;
    this.pendingSjjxCookies = new Map<string, string>();
    this.navigatingToEelab = false;
    this.eelabTokenFetching = false;
    this.eelabFetchTimer = -1;
    this.collectedEasCookies = new Map<string, string>();
    this.lastUrl = '';
    this.session = new EasSession();
    this.session.campus = campus;
    this.session.setStudentType(this.cfg.studentType);
    this.setError('');
    this.setPhase(EasLoginPhase.LOADING, '正在进入 ' + this.cfg.displayName + ' 统一认证…');
    this.setProgress(10);

    const wc: webview.WebviewController | undefined = this.webController;
    if (wc === undefined) {
      hilog.error(DOMAIN, TAG, 'Web controller not attached');
      return;
    }

    EasWebLoginController.applyItpBypass();

    // Android 登录流程不会在 WebView 开始导航后清理 Cookie。ArkWeb 的 Web 组件
    // 可能在 controller attached 前已经开始加载，清理会打断 CAS 的跳转链。

    // 记录系统默认 UA
    try {
      const defaultUa: string = wc.getUserAgent();
      if (!isBlank(defaultUa)) {
        this.mobileUa = defaultUa;
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'Failed to get default user agent: %{public}s', String(e));
    }

    if (campus === EasCampus.SHENZHEN) {
      // 对齐 Android: setupWebView 对 SHENZHEN 初始即设置桌面 UA
      try {
        wc.setCustomUserAgent(EasUserAgent.SHENZHEN_DESKTOP);
        this.shenzhenDesktopUaApplied = true;
        hilog.info(DOMAIN, TAG, 'Shenzhen desktop UA applied');
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'Failed to set desktop UA: %{public}s', String(e));
      }
    }
  }

  stop(): void {
    this.finished = true;
    this.loginGeneration++;
    this.navigationGeneration++;
    this.shenzhenAutoAdvanceGeneration++;
    this.completing = false;
    this.cookiePollingGeneration++;
    this.cookiePollingActive = false;
    this.stopSjjxBridge();
    this.navigatingToEelab = false;
    if (this.experimentTimeoutTimer >= 0) {
      clearTimeout(this.experimentTimeoutTimer);
      this.experimentTimeoutTimer = -1;
    }
    if (this.eelabFetchTimer >= 0) {
      clearTimeout(this.eelabFetchTimer);
      this.eelabFetchTimer = -1;
    }
    if (this.eelabTimeoutTimer >= 0) {
      clearTimeout(this.eelabTimeoutTimer);
      this.eelabTimeoutTimer = -1;
    }
    this.phase = EasLoginPhase.IDLE;
  }

  // ------------------------------------------------------------------
  // ArkWeb 生命周期回调（纯事件驱动）
  // ------------------------------------------------------------------

  notifyPageBegin(url: string): void {
    if (this.finished) {
      return;
    }
    hilog.info(DOMAIN, TAG, 'notifyPageBegin: %{public}s', url);
    this.lastUrl = url;
    // 实验系统是主教务验证成功后的可选补充，不再要求用户完成第二次认证。
    if ((this.navigatingToSjjx || this.navigatingToEelab) &&
      (isAuthenticationPage(url) || isMfaPage(url) || isIvpnRedirectPage(url, EasCampus.BENBU))) {
      this.finish(this.collectedEasCookies, url, '');
      return;
    }
    this.navigationGeneration++;
    this.completing = false;
    this.stopCookiePolling();
    if (this.cfg !== undefined && this.cfg.campus === EasCampus.BENBU) {
      this.benbuVerificationAttempts = 0;
    }
    this.shenzhenAutoAdvanceGeneration++;

    if (isAuthenticationPage(url) || isMfaPage(url)) {
      this.autoOpeningJwts = false;
    }

    if (this.cfg !== undefined && this.cfg.campus === EasCampus.SHENZHEN) {
      if (this.switchShenzhenUserAgentForNavigation(url)) {
        return;
      }
    }
  }

  async notifyPageEnd(url: string): Promise<void> {
    if (this.finished || this.cfg === undefined) {
      return;
    }
    hilog.info(DOMAIN, TAG, 'notifyPageEnd: %{public}s', url);
    this.lastUrl = url;
    const generation: number = this.navigationGeneration;
    const loginGeneration: number = this.loginGeneration;
    const wc: webview.WebviewController | undefined = this.webController;
    if (wc === undefined) {
      return;
    }

    // 1. 本部本科 sjjx 桥接中转处理
    if (this.navigatingToSjjx) {
      this.advanceSjjxIfReady();
      return;
    }

    // 2. 本部本科 EELAB 流程中转处理
    if (this.navigatingToEelab) {
      this.advanceEelabIfReady();
      return;
    }
    if (this.completing) {
      return;
    }

    // Authentication, code delivery and verification stay in the school page.
    // Do not apply desktop EAS helpers or probe old cookies on these forms.
    if (isAuthenticationPage(url) || isMfaPage(url)) {
      if (this.cfg.campus === EasCampus.SHENZHEN && isMfaPage(url)) {
        this.applyMfaViewportFix(wc);
      }
      return;
    }

    // 2. 深圳校区专属推进（forceWeb、过期重认证、视口修正、自动点击）
    if (this.cfg.campus === EasCampus.SHENZHEN) {
      // 2.1 aTrust shortcut forceWeb 模式注入（对齐 Android applyShenzhenForceWebMode）
      if (!this.shenzhenForceWebModeApplied &&
        hostOf(url) === 'trust.hitsz.edu.cn' &&
        pathOf(url).toLowerCase().indexOf('/portal/shortcut.html') >= 0) {
        this.shenzhenForceWebModeApplied = true;
        hilog.info(DOMAIN, TAG, 'Injecting aTrust forceWeb mode...');
        EasWebLoginController.runJs(wc, EasWebLoginController.FORCE_WEB_MODE_SCRIPT).then(() => {
          if (!this.finished && generation === this.navigationGeneration) {
            wc.loadUrl(url);
          }
        }).catch(() => {
          if (!this.finished && generation === this.navigationGeneration) {
            wc.loadUrl(url);
          }
        });
        return;
      }

      // 2.2 会话过期重定向（对齐 Android redirectExpiredShenzhenSession）
      if (!this.shenzhenReauthenticationStarted) {
        const redirectCas: string = reauthenticationUrl(url, EasCampusUrls.SHENZHEN_DIRECT_BASE,
          EasCampusUrls.SHENZHEN_PROXY_BASE);
        if (redirectCas.length > 0) {
          this.shenzhenReauthenticationStarted = true;
          hilog.info(DOMAIN, TAG, 'Redirecting expired Shenzhen session to CAS: %{public}s', redirectCas);
          wc.loadUrl(redirectCas);
          return;
        }
      }

      // 2.3 视口尺寸适配（对齐 Android applyWorkarounds）
      if (isTrustPortalPage(url)) {
        this.applyTrustPortalViewportFix(wc);
      } else if (isShenzhenProxyJwPage(url)) {
        this.applyShenzhenJwDesktopViewportFix(wc);
        this.scheduleShenzhenAutoAdvance(wc, url);
      }
    }

    // 不在普通 page-end 上仅凭 Cookie 直接收尾。Android 端只在明确成功页
    // 或已经进入目标教务系统后通过轮询收尾，避免 CAS 中间页提前返回。

    // 3. 通用页面判定（门户首页、认证成功、目标系统打开）
    if (isPortalHomePage(url, this.cfg.campus)) {
      hilog.info(DOMAIN, TAG, 'Portal home detected, auto opening JWTS...');
      this.autoOpenJwts(wc);
      return;
    }

    const cookies: Map<string, string> = await this.collectCookies(url);
    if (this.finished || generation !== this.navigationGeneration || loginGeneration !== this.loginGeneration) {
      return;
    }
    if (this.cfg.campus === EasCampus.BENBU && this.cfg.studentType !== '2' &&
      isBenbuEasPage(url, this.cfg.studentType)) {
      if (!isBlank(cookies.get('JSESSIONID'))) {
        this.verifyBenbuCookies(cookies, url);
      } else {
        this.startCookiePolling();
      }
      return;
    }
    // WebVPN can keep the inner JSESSIONID server-side, outside ArkWeb's cookie jar.
    if (this.canExchangeWeihaiCookies(url, cookies)) {
      this.handleSuccessPage(url, cookies);
      return;
    }
    if (isSuccessPageFor(url, cookies, this.cfg.campus, this.cfg.studentType) &&
      hasRequiredCookiesFor(cookies, url, this.cfg.campus, this.cfg.studentType)) {
      hilog.info(DOMAIN, TAG, 'Success page detected: %{public}s', url);
      this.stopCookiePolling();
      this.handleSuccessPage(url, cookies);
      return;
    }

    if (this.autoOpeningJwts) {
      const isTargetHost: boolean = hostOf(url).indexOf('jwts') >= 0 ||
        (this.cfg.campus === EasCampus.SHENZHEN && isShenzhenProxyJwPage(url)) ||
        (this.cfg.campus === EasCampus.WEIHAI && (url.indexOf('/http/') >= 0 || hostOf(url) === 'webvpn.hitwh.edu.cn'));
      if (isTargetHost) {
        this.autoOpeningJwts = false;
        hilog.info(DOMAIN, TAG, 'Target domain reached via auto-open, starting cookie polling');
        this.startCookiePolling();
      }
    }

    // 针对各校区教务系统页面，开启 Cookie 轮询
    // 注意：不在认证/登录页面上启动轮询
    if (this.cfg.campus === EasCampus.SHENZHEN && isShenzhenProxyJwPage(url) &&
      !isAuthenticationPage(url) && pathOf(url).indexOf('/authentication/') < 0) {
      this.startCookiePolling();
    } else if (this.cfg.campus === EasCampus.WEIHAI && (url.indexOf('/http/') >= 0 || url.indexOf('jwts') >= 0)) {
      this.startCookiePolling();
    } else if ((this.cfg.campus === EasCampus.BENBU && isBenbuEasPage(url, this.cfg.studentType)) ||
      isJwtsPage(url, this.cfg.campus, this.cfg.studentType)) {
      hilog.info(DOMAIN, TAG, 'JWTS login page detected, starting cookie polling');
      this.startCookiePolling();
      return;
    }
  }

  notifyProgress(percent: number): void {
    this.setProgress(percent);
  }

  notifyLoadError(message: string, isMainFrame: boolean = false): boolean {
    hilog.warn(DOMAIN, TAG, 'notifyLoadError: %{public}s', message);
    if (!this.finished && isMainFrame && (this.navigatingToSjjx || this.navigatingToEelab)) {
      this.finish(this.collectedEasCookies, this.lastUrl, '');
      return true;
    }
    return false;
  }

  // ------------------------------------------------------------------
  // 深圳校区 User-Agent 切换（对齐 Android switchShenzhenUserAgentForNavigation）
  // ------------------------------------------------------------------

  private switchShenzhenUserAgentForNavigation(url: string): boolean {
    const wc: webview.WebviewController | undefined = this.webController;
    if (wc === undefined || this.cfg === undefined || this.cfg.campus !== EasCampus.SHENZHEN) {
      return false;
    }
    const host: string = hostOf(url);
    const proxyHost: string = hostOf(EasCampusUrls.SHENZHEN_PROXY_BASE);
    const needsDesktopUserAgent: boolean =
      host === proxyHost || host === 'trust.hitsz.edu.cn';
    const generation: number = this.navigationGeneration;

    if (!needsDesktopUserAgent && this.shenzhenDesktopUaApplied) {
      this.shenzhenDesktopUaApplied = false;
      try {
        wc.setCustomUserAgent(this.mobileUa);
        // ArkWeb 在 onPageBegin 中立即 loadUrl 会取消当前重定向；异步提交与 Android post 一致。
        setTimeout(() => {
          if (!this.finished && generation === this.navigationGeneration && this.webController !== undefined) {
            try {
              this.webController.loadUrl(url);
            } catch (e) {}
          }
        }, 0);
        hilog.info(DOMAIN, TAG, 'Switching Shenzhen navigation back to mobile UA (host=%{public}s)', host);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'Failed to switch to mobile UA: %{public}s', String(e));
      }
      return true;
    }

    if (needsDesktopUserAgent && !this.shenzhenDesktopUaApplied) {
      this.shenzhenDesktopUaApplied = true;
      try {
        wc.setCustomUserAgent(EasUserAgent.SHENZHEN_DESKTOP);
        setTimeout(() => {
          if (!this.finished && generation === this.navigationGeneration && this.webController !== undefined) {
            try {
              this.webController.loadUrl(url);
            } catch (e) {}
          }
        }, 0);
        hilog.info(DOMAIN, TAG, 'Switching Shenzhen navigation to desktop UA (host=%{public}s)', host);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'Failed to switch to desktop UA: %{public}s', String(e));
      }
      return true;
    }

    return false;
  }

  // ------------------------------------------------------------------
  // 深圳校区自动点击脚本（对齐 Android scheduleShenzhenAutoAdvance）
  // ------------------------------------------------------------------

  private scheduleShenzhenAutoAdvance(wc: webview.WebviewController, url: string): void {
    if (this.finished || this.cfg === undefined || this.cfg.campus !== EasCampus.SHENZHEN) {
      return;
    }
    const generation: number = this.shenzhenAutoAdvanceGeneration;
    if (this.shenzhenAutoAdvanceScheduledGeneration === generation) {
      return;
    }
    this.shenzhenAutoAdvanceScheduledGeneration = generation;

    const attempt = (index: number): void => {
      if (this.finished || generation !== this.shenzhenAutoAdvanceGeneration) {
        return;
      }
      const allowUnified: boolean = !this.shenzhenUnifiedLoginClicked;
      const allowRole: boolean = !this.shenzhenRoleSelectionClicked;
      if (!allowUnified && !allowRole) {
        return;
      }

      const script: string = EasWebLoginController.buildShenzhenClickScript(
        this.cfg ? this.cfg.studentType : '1',
        allowUnified,
        allowRole
      );

      EasWebLoginController.runJs(wc, script).then((raw: string) => {
        if (this.finished || generation !== this.shenzhenAutoAdvanceGeneration) {
          return;
        }
        try {
          const res: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
          if (res['clicked'] === true) {
            const action: string = String(res['action']);
            if (action === 'unified-login') {
              this.shenzhenUnifiedLoginClicked = true;
            } else if (action === 'undergrad-role' || action === 'postgrad-role') {
              this.shenzhenRoleSelectionClicked = true;
            }
            hilog.info(DOMAIN, TAG, 'Shenzhen auto advance clicked: %{public}s', action);
            return;
          }
        } catch (e) {}

        if (index < 12) {
          setTimeout(() => {
            attempt(index + 1);
          }, 300);
        }
      }).catch(() => {
        if (index < 12) {
          setTimeout(() => {
            attempt(index + 1);
          }, 300);
        }
      });
    };

    attempt(0);
  }

  // ------------------------------------------------------------------
  // 页面视口修正脚本（对齐 Android applyWorkarounds）
  // ------------------------------------------------------------------

  private applyTrustPortalViewportFix(wc: webview.WebviewController): void {
    const script: string = `
      (function() {
        var height = Math.round(window.innerHeight || (document.documentElement && document.documentElement.clientHeight) || 0);
        if (height <= 0) return JSON.stringify({ok:false});
        var style = document.getElementById('hita-trust-viewport-fix');
        if (!style) {
          style = document.createElement('style');
          style.id = 'hita-trust-viewport-fix';
          (document.head || document.documentElement).appendChild(style);
        }
        style.textContent =
          'html,body,#app{height:' + height + 'px!important;min-height:' + height + 'px!important;}' +
          '.h-screen,.login{height:' + height + 'px!important;min-height:' + height + 'px!important;}' +
          '.login{width:100%!important;min-width:0!important;overflow-x:hidden!important;}' +
          '.login-head,.login-body{width:100%!important;}' +
          '.login-head__content{width:auto!important;}' +
          '.login-content{left:0!important;right:0!important;width:100%!important;margin-left:0!important;margin-right:0!important;justify-content:center!important;}' +
          '.login-notice{display:none!important;}' +
          '.login-panel{box-sizing:border-box!important;max-width:calc(100vw - 24px)!important;}';
        return JSON.stringify({ok:true, height:height});
      })();
    `;
    EasWebLoginController.runJs(wc, script).catch(() => {});
  }

  private applyShenzhenJwDesktopViewportFix(wc: webview.WebviewController): void {
    const script: string = `
      (function() {
        var desktopWidth = 1200;
        var deviceWidth = Math.round(
          (window.screen && (window.screen.availWidth || window.screen.width)) ||
          (window.visualViewport && window.visualViewport.width) ||
          window.innerWidth || desktopWidth
        );
        var initialScale = Math.min(1, Math.max(0.2, deviceWidth / desktopWidth));
        var content = 'width=' + desktopWidth + ', initial-scale=' + initialScale.toFixed(4) + ', minimum-scale=0.2, maximum-scale=3.0, user-scalable=yes';
        var viewport = document.querySelector('meta[name=viewport]');
        if (!viewport) {
          viewport = document.createElement('meta');
          viewport.name = 'viewport';
          (document.head || document.documentElement).appendChild(viewport);
        }
        if (viewport.content !== content) viewport.content = content;
        var height = Math.round(window.innerHeight || (document.documentElement && document.documentElement.clientHeight) || 0);
        if (height > 0) {
          var style = document.getElementById('hita-shenzhen-jw-viewport-fix');
          if (!style) {
            style = document.createElement('style');
            style.id = 'hita-shenzhen-jw-viewport-fix';
            (document.head || document.documentElement).appendChild(style);
          }
          style.textContent = 'html,body,#app,.towlg_body,.towlg_submain{height:' + height + 'px!important;min-height:' + height + 'px!important;}';
        }
        return JSON.stringify({ok:true});
      })();
    `;
    EasWebLoginController.runJs(wc, script).catch(() => {});
  }

  private applyMfaViewportFix(wc: webview.WebviewController): void {
    const script: string = `
      (function() {
        var height = Math.round(window.innerHeight || (document.documentElement && document.documentElement.clientHeight) || 0);
        if (height <= 0) return JSON.stringify({ok:false});
        var style = document.getElementById('hita-mfa-viewport-fix');
        if (!style) {
          style = document.createElement('style');
          style.id = 'hita-mfa-viewport-fix';
          (document.head || document.documentElement).appendChild(style);
        }
        var centerHeight = Math.max(0, height - 44);
        var whiteBoxHeight = Math.max(0, height - 112);
        style.textContent =
          'html,body{min-height:' + height + 'px!important;}' +
          '.mobile-page-center-box{height:' + centerHeight + 'px!important;}' +
          '.mobile-page-content-box{max-height:' + centerHeight + 'px!important;}' +
          '.mobile-page-white-box{min-height:' + whiteBoxHeight + 'px!important;}';
        return JSON.stringify({ok:true, height:height});
      })();
    `;
    EasWebLoginController.runJs(wc, script).catch(() => {});
  }

  // ------------------------------------------------------------------
  // 成功判定与 Cookie 轮询收尾（对齐 Android handleSuccessPage / checkCookiesAndFinish）
  // ------------------------------------------------------------------

  private autoOpenJwts(wc: webview.WebviewController): void {
    if (this.autoOpeningJwts || this.cfg === undefined) {
      return;
    }
    if (++this.portalOpenAttempts > 3) {
      this.setPhase(EasLoginPhase.ERROR, '认证跳转未完成');
      this.setError('认证反复返回登录入口，请重置网页登录后重试');
      return;
    }
    this.autoOpeningJwts = true;
    hilog.info(DOMAIN, TAG, 'autoOpenJwts: loading %{public}s', this.cfg.jwtsUrl);
    wc.loadUrl(this.cfg.jwtsUrl);
  }

  private startCookiePolling(): void {
    if (this.cookiePollingActive) {
      return;
    }
    this.cookiePollingActive = true;
    const generation: number = ++this.cookiePollingGeneration;
    this.cookieRetryCount = 0;
    setTimeout(() => {
      this.checkCookiesAndFinish(generation);
    }, COOKIE_RETRY_DELAY_MS);
  }

  private stopCookiePolling(): void {
    this.cookiePollingActive = false;
    this.cookiePollingGeneration++;
  }

  private async checkCookiesAndFinish(generation: number): Promise<void> {
    if (this.finished || generation !== this.cookiePollingGeneration || this.cfg === undefined) {
      return;
    }
    const url: string = this.lastUrl;
    const navigation: number = this.navigationGeneration;
    const cookies: Map<string, string> = await this.collectCookies(url);
    if (this.finished || generation !== this.cookiePollingGeneration ||
      navigation !== this.navigationGeneration) {
      return;
    }
    if (this.cookieRetryCount === 0 || this.cookieRetryCount % 5 === 0) {
      hilog.info(DOMAIN, TAG, 'Cookie probe retry=%{public}d keys=%{public}s vpn=%{public}s jsession=%{public}s url=%{public}s',
        this.cookieRetryCount, EasWebLoginController.cookieKeys(cookies),
        String(hasWeihaiVpnTicket(cookies)), String(!isBlank(cookies.get('JSESSIONID'))), url);
    }

    if (this.canExchangeWeihaiCookies(url, cookies)) {
      this.handleSuccessPage(url, cookies);
      return;
    }
    if (this.cfg.campus === EasCampus.BENBU && this.cfg.studentType !== '2' &&
      isBenbuEasPage(url, this.cfg.studentType) && !isBlank(cookies.get('JSESSIONID'))) {
      this.verifyBenbuCookies(cookies, url);
      return;
    }

    // A stale cookie jar is not proof that the current authentication has finished.
    if (hasRequiredCookiesFor(cookies, url, this.cfg.campus, this.cfg.studentType) &&
      isSuccessPageFor(url, cookies, this.cfg.campus, this.cfg.studentType)) {
      hilog.info(DOMAIN, TAG, 'Required cookies acquired during polling!');
      this.handleSuccessPage(url, cookies);
      return;
    }


    this.cookieRetryCount++;
    if (this.cookieRetryCount >= COOKIE_RETRY_COUNT_MAX) {
      this.cookiePollingActive = false;
      hilog.warn(DOMAIN, TAG, 'Cookie polling reached retry limit');
      this.setPhase(EasLoginPhase.ERROR, '登录验证超时');
      this.setError('登录验证超时，请确认教务页面已完成登录后重试');
      return;
    }

    setTimeout(() => {
      this.checkCookiesAndFinish(generation);
    }, COOKIE_RETRY_DELAY_MS);
  }

  private handleSuccessPage(url: string, cookies: Map<string, string>): void {
    if (this.finished || this.completing || this.cfg === undefined) {
      return;
    }
    this.completing = true;
    this.stopCookiePolling();

    if (this.cfg.campus === EasCampus.BENBU && this.cfg.studentType !== '2') {
      // 本部本科：先经 jwts 桥接取得 sjjx 实验教学会话，再走 EELAB token
      this.setPhase(EasLoginPhase.SUCCESS_PROBE, '登录成功，正在获取实验教学会话…');
      // 全流程共用时限，跳转、Cookie 读取和 Token 请求均不得延长主登录等待。
      const generation: number = this.loginGeneration;
      this.experimentTimeoutTimer = setTimeout(() => {
        this.experimentTimeoutTimer = -1;
        if (!this.finished && generation === this.loginGeneration) {
          this.finish(this.collectedEasCookies, this.lastUrl, '');
        }
      }, EXPERIMENT_TOTAL_TIMEOUT_MS);
      this.enterSjjxBridgeFlow(cookies);
      return;
    }

    if (this.cfg.campus === EasCampus.WEIHAI && hasWeihaiVpnTicket(cookies)) {
      this.setPhase(EasLoginPhase.SUCCESS_PROBE, '登录成功，正在同步威海教务会话…');
      this.fetchWeihaiVpnCookies(cookies, url);
      return;
    }

    this.setPhase(EasLoginPhase.SUCCESS_PROBE, '登录成功，正在采集会话…');
    this.finish(cookies, url, '');
  }

  private async verifyBenbuCookies(cookies: Map<string, string>, url: string): Promise<void> {
    if (this.finished || this.completing || this.benbuVerificationAttempts >= 3) {
      return;
    }
    this.completing = true;
    this.stopCookiePolling();
    const generation: number = this.loginGeneration;
    const navigation: number = this.navigationGeneration;
    const attempt: number = ++this.benbuVerificationAttempts;
    this.setPhase(EasLoginPhase.SUCCESS_PROBE, '正在验证本部教务会话…');
    const headers: Map<string, string> = new Map<string, string>();
    headers.set('Cookie', EasSession.buildCookieHeader(cookies));
    headers.set('User-Agent', 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15');
    headers.set('Accept', 'text/html,application/xhtml+xml,*/*');
    let timer: number = -1;
    let response: EasApiResponse = new EasApiResponse();
    try {
      const timeout: Promise<EasApiResponse> = new Promise<EasApiResponse>((resolve) => {
        timer = setTimeout(() => resolve(new EasApiResponse()), 10000);
      });
      response = await Promise.race([
        EasApiClient.doHttp(EasCampusUrls.JWTS_BASE + '/kbcx/queryGrkb',
          EasHttpMethod.GET, headers, '', 10000),
        timeout
      ]);
    } catch (e) {
      // A failed verification must leave the login page recoverable.
    } finally {
      if (timer >= 0) {
        clearTimeout(timer);
      }
    }
    if (this.finished || generation !== this.loginGeneration || navigation !== this.navigationGeneration) {
      return;
    }
    const loginForm: boolean = /<input\b[^>]*\btype\s*=\s*["']?password\b/i.test(response.body);
    const terms: number = response.statusCode === 200 && !loginForm ?
      EasLegacyTimetableParser.parseTerms(response.body).length : 0;
    hilog.info(DOMAIN, TAG, 'Benbu EAS verification attempt=%{public}d status=%{public}d terms=%{public}d jsession=%{public}s hit=%{public}s',
      attempt, response.statusCode, terms, String(!isBlank(cookies.get('JSESSIONID'))),
      String(!isBlank(cookies.get('HIT'))));
    this.completing = false;
    if (terms > 0) {
      this.setError('');
      this.handleSuccessPage(url, cookies);
    } else if (attempt < 3) {
      this.startCookiePolling();
    } else {
      this.setPhase(EasLoginPhase.ERROR, '本部教务会话验证未完成');
      this.setError('本部教务会话尚未就绪，请确认已进入教务后刷新；仍失败可重置登录');
    }
  }

  private canExchangeWeihaiCookies(url: string, cookies: Map<string, string>): boolean {
    return this.cfg !== undefined && this.cfg.campus === EasCampus.WEIHAI &&
      url.startsWith(EasCampusUrls.WEIHAI_EAS_PREFIX + '/') &&
      !isAuthenticationPage(url) && !isMfaPage(url) && hasWeihaiVpnTicket(cookies);
  }

  private fetchWeihaiVpnCookies(cookies: Map<string, string>, url: string): void {
    const generation: number = this.loginGeneration;
    const navigation: number = this.navigationGeneration;
    this.weihaiExchangeAttempts++;
    const cookieHeader: string = EasSession.buildCookieHeader(cookies);
    hilog.info(DOMAIN, TAG, 'Starting Weihai VPN cookie exchange header=%{public}s',
      EasWebLoginController.cookieKeys(cookies));
    const easHost: string = 'jwts.hitwh.edu.cn';
    const easPath: string = '/loginCAS';
    const apiUrl: string = `https://webvpn.hitwh.edu.cn/wengine-vpn/cookie?method=get&host=${easHost}&scheme=http&path=${easPath}&vpn_timestamp=${Date.now()}`;

    const req: http.HttpRequest = http.createHttp();
    const reqOptions: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: {
        'Cookie': cookieHeader,
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15',
        'Accept': '*/*'
      },
      readTimeout: 10000,
      connectTimeout: 10000,
      expectDataType: http.HttpDataType.STRING
    };

    req.request(apiUrl, reqOptions).then(async (resp: http.HttpResponse) => {
      if (this.finished || generation !== this.loginGeneration || navigation !== this.navigationGeneration) {
        return;
      }
      try {
        if (resp.responseCode === 200) {
          let raw: string = resp.result === undefined ? '' : String(resp.result);
          if (raw.trim().startsWith('"')) {
            const decoded: Object = JSON.parse(raw) as Object;
            if (typeof decoded === 'string') {
              raw = decoded;
            }
          }
          hilog.info(DOMAIN, TAG, 'Weihai VPN cookie API response length=%{public}d keys=%{public}s',
            raw.length, EasWebLoginController.cookieKeys(parseCookiesHeader(raw)));
          const parts: string[] = raw.split(';');
          for (let i = 0; i < parts.length; i++) {
            const seg: string = parts[i].trim();
            const eq: number = seg.indexOf('=');
            if (eq > 0) {
              const k: string = seg.substring(0, eq).trim();
              const v: string = seg.substring(eq + 1).trim();
              if (k.length > 0 && v.length > 0) {
                if (k === 'JSESSIONID' || k === 'HIT' || k === 'TWFID') {
                  cookies.set(k, v);
                }
              }
            }
          }
        }
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'Failed to parse Weihai VPN cookie response: %{public}s', String(e));
      }
      // The cookie endpoint is not consistent across WebVPN versions.  If it
      // did not return the inner EAS session, read the browser cookie jar from
      // the concrete timetable URL before finishing the login flow.
      await this.verifyWeihaiCookies(cookies, url, generation, navigation);
    }).catch(async (err: Object) => {
      if (this.finished || generation !== this.loginGeneration || navigation !== this.navigationGeneration) {
        return;
      }
      hilog.warn(DOMAIN, TAG, 'Weihai VPN cookie API request failed: %{public}s', JSON.stringify(err));
      await this.verifyWeihaiCookies(cookies, url, generation, navigation);
    }).finally(() => {
      req.destroy();
    });
  }

  private async verifyWeihaiCookies(cookies: Map<string, string>, url: string,
    generation: number, navigation: number): Promise<void> {
    await this.mergeWeihaiBrowserCookies(cookies);
    if (this.finished || generation !== this.loginGeneration || navigation !== this.navigationGeneration) {
      return;
    }
    // A VPN ticket alone, or an old inner cookie, cannot establish an EAS session.
    const header: Map<string, string> = new Map<string, string>();
    header.set('Cookie', EasSession.buildCookieHeader(cookies));
    header.set('User-Agent', 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15');
    header.set('Accept', 'text/html,application/xhtml+xml,*/*');
    const response = await EasApiClient.doHttp(EasCampusUrls.WEIHAI_EAS_PREFIX + '/kbcx/queryGrkb',
      EasHttpMethod.GET, header, '', 10000);
    if (this.finished || generation !== this.loginGeneration || navigation !== this.navigationGeneration) {
      return;
    }
    const termCount: number = response.statusCode === 200 ?
      EasLegacyTimetableParser.parseTermsBySelect(response.body, 'xnxq').length : 0;
    hilog.info(DOMAIN, TAG, 'Weihai EAS verification attempt=%{public}d status=%{public}d terms=%{public}d jsession=%{public}s',
      this.weihaiExchangeAttempts, response.statusCode, termCount, String(!isBlank(cookies.get('JSESSIONID'))));
    if (termCount > 0) {
      this.finish(cookies, url, '');
      return;
    }
    this.completing = false;
    if (this.weihaiExchangeAttempts < 3 && response.statusCode !== 401 && response.statusCode !== 403) {
      setTimeout(async () => {
        if (this.finished || generation !== this.loginGeneration || navigation !== this.navigationGeneration) {
          return;
        }
        const latest: Map<string, string> = await this.collectCookies(url);
        if (!this.finished && generation === this.loginGeneration && navigation === this.navigationGeneration &&
          this.canExchangeWeihaiCookies(url, latest)) {
          this.handleSuccessPage(url, latest);
        }
      }, 1000);
      return;
    }
    this.setPhase(EasLoginPhase.ERROR, '威海教务会话验证未完成');
    this.setError('已连接威海网关，但教务会话尚未就绪，请刷新或重置网页登录后重试');
  }

  private async mergeWeihaiBrowserCookies(cookies: Map<string, string>): Promise<void> {
    const urls: string[] = [
      EasCampusUrls.WEIHAI_EAS_PREFIX + '/kbcx/queryGrkb',
      EasCampusUrls.WEIHAI_EAS_PREFIX + '/reAuth'
    ];
    for (let i = 0; i < urls.length; i++) {
      EasWebLoginController.mergePutIfAbsent(cookies,
        parseCookiesHeader(await EasWebLoginController.tryFetchCookieWithPartitioned(urls[i], this.lastUrl)));
    }
    hilog.info(DOMAIN, TAG, 'Weihai browser cookie merge keys=%{public}s',
      EasWebLoginController.cookieKeys(cookies));
  }

  private async collectCookies(url: string): Promise<Map<string, string>> {
    const out: Map<string, string> = new Map<string, string>();
    if (this.cfg === undefined) {
      return out;
    }
    // Prefer the current page over old cookies from another EAS host or path.
    const urls: string[] = url.startsWith('http') ? [url] : [];
    for (let i: number = 0; i < this.cfg.cookieProbeUrls.length; i++) {
      if (urls.indexOf(this.cfg.cookieProbeUrls[i]) < 0) {
        urls.push(this.cfg.cookieProbeUrls[i]);
      }
    }
    const headers: string[] = await Promise.all(urls.map((probe: string): Promise<string> =>
      EasWebLoginController.tryFetchCookieWithPartitioned(probe, url)));
    for (let i = 0; i < urls.length; i++) {
      EasWebLoginController.mergePutIfAbsent(out, parseCookiesHeader(headers[i]));
    }
    if (!out.has('JSESSIONID')) {
      const fromUrl: string = EasWebLoginController.extractJsessionid(url);
      if (fromUrl.length > 0) {
        out.set('JSESSIONID', fromUrl);
      }
    }
    return out;
  }

  private finish(cookies: Map<string, string>, url: string, eelabToken: string): void {
    if (this.finished || this.cfg === undefined) {
      return;
    }
    this.finished = true;
    this.stop();
    const s: EasSession = this.session;
    s.webCookies = cookies;
    if (this.cfg.campus === EasCampus.SHENZHEN) {
      const host: string = hostOf(url);
      if (host === 'jw.hitsz.edu.cn') {
        s.webBaseUrl = EasCampusUrls.SHENZHEN_DIRECT_BASE.replace(/\/+$/, '');
      } else {
        s.webBaseUrl = EasCampusUrls.SHENZHEN_PROXY_BASE.replace(/\/+$/, '');
      }
    }
    if (eelabToken.length > 0) {
      s.electronicExpToken = eelabToken;
    }
    if (this.pendingSjjxCookies.size > 0) {
      s.sjjxCookies = this.pendingSjjxCookies;
    }
    this.setPhase(EasLoginPhase.DONE, '登录成功');
    this.setProgress(100);
    this.onFinished(s);
  }

  // ------------------------------------------------------------------
  // 本部本科 sjjx（实验教学）桥接：jwts /loginsysj/loginSygl → sjjx 会话
  // ------------------------------------------------------------------

  private stopSjjxBridge(): void {
    this.navigatingToSjjx = false;
    this.sjjxFetching = false;
    if (this.sjjxFetchTimer >= 0) {
      clearTimeout(this.sjjxFetchTimer);
      this.sjjxFetchTimer = -1;
    }
    if (this.sjjxTimeoutTimer >= 0) {
      clearTimeout(this.sjjxTimeoutTimer);
      this.sjjxTimeoutTimer = -1;
    }
  }

  private enterSjjxBridgeFlow(cookies: Map<string, string>): void {
    this.collectedEasCookies = cookies;
    const wc: webview.WebviewController | undefined = this.webController;
    if (wc === undefined || this.navigatingToSjjx) {
      this.enterEelabTokenFlow(cookies);
      return;
    }
    this.navigatingToSjjx = true;
    this.collectedEasCookies = cookies;
    this.sjjxTimeoutTimer = setTimeout(() => {
      this.sjjxTimeoutTimer = -1;
      if (this.navigatingToSjjx && !this.finished) {
        this.stopSjjxBridge();
        hilog.warn(DOMAIN, TAG, 'sjjx bridge timeout; continuing without experiment session');
        this.enterEelabTokenFlow(this.collectedEasCookies);
      }
    }, SJJX_NAV_TIMEOUT_MS);
    try {
      wc.loadUrl(EasCampusUrls.JWTS_BASE + '/loginsysj/loginSygl');
      hilog.info(DOMAIN, TAG, 'sjjx bridge navigation started');
    } catch (e) {
      this.stopSjjxBridge();
      this.enterEelabTokenFlow(cookies);
    }
  }

  private async advanceSjjxIfReady(): Promise<void> {
    const sjjxHost: string = hostOf(EasCampusUrls.SJJX_BASE);
    if (hostOf(this.lastUrl) !== sjjxHost) {
      return;
    }
    if (this.sjjxFetching || this.sjjxFetchTimer >= 0) {
      return;
    }
    this.sjjxFetchTimer = setTimeout(() => {
      this.sjjxFetchTimer = -1;
      if (!this.finished && this.navigatingToSjjx) {
        this.fetchSjjxCookies();
      }
    }, 1000);
  }

  private async fetchSjjxCookies(): Promise<void> {
    if (this.finished || !this.navigatingToSjjx || this.sjjxFetching) {
      return;
    }
    const generation: number = this.loginGeneration;
    this.sjjxFetching = true;
    try {
      const raw: string = await EasWebLoginController.tryFetchCookie(EasCampusUrls.SJJX_BASE);
      if (this.finished || !this.navigatingToSjjx || generation !== this.loginGeneration) {
        return;
      }
      const cookies: Map<string, string> = parseCookiesHeader(raw);
      hilog.info(DOMAIN, TAG, 'sjjx cookie probe keys=%{public}s', EasWebLoginController.cookieKeys(cookies));
      if (EasSession.isNotBlank(EasSession.cookieValue(cookies, 'JSESSIONID'))) {
        this.pendingSjjxCookies = cookies;
        hilog.info(DOMAIN, TAG, 'sjjx session captured');
      } else {
        hilog.warn(DOMAIN, TAG, 'sjjx session missing JSESSIONID');
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'sjjx cookie probe failed');
    }
    if (this.finished || !this.navigatingToSjjx || generation !== this.loginGeneration) {
      return;
    }
    this.stopSjjxBridge();
    this.enterEelabTokenFlow(this.collectedEasCookies);
  }

  // ------------------------------------------------------------------
  // 本部本科 EELAB Token 流程（对齐 Android fetchEelabTokenViaHttp）
  // ------------------------------------------------------------------

  private enterEelabTokenFlow(cookies: Map<string, string>): void {
    const wc: webview.WebviewController | undefined = this.webController;
    if (wc === undefined) {
      this.finish(cookies, this.lastUrl, '');
      return;
    }
    if (this.navigatingToEelab) {
      return;
    }
    this.navigatingToEelab = true;
    this.eelabTokenFetching = false;
    this.collectedEasCookies = cookies;
    this.eelabTimeoutTimer = setTimeout(() => {
      this.eelabTimeoutTimer = -1;
      if (this.navigatingToEelab && !this.finished) {
        this.navigatingToEelab = false;
        this.finish(this.collectedEasCookies, this.lastUrl, '');
      }
    }, EELAB_NAV_TIMEOUT_MS);
    try {
      wc.loadUrl(EasCampusUrls.EELABINFO_URL + '/api/cas/loginSuccess');
    } catch (e) {
      this.navigatingToEelab = false;
      this.finish(this.collectedEasCookies, this.lastUrl, '');
    }
  }

  private async advanceEelabIfReady(): Promise<void> {
    const url: string = this.lastUrl;
    const eelabHost: string = hostOf(EasCampusUrls.EELABINFO_URL);
    if (hostOf(url) !== eelabHost) {
      // Android 在离开 EELAB 且尚未开始取 Token 时立即完成登录。
      if (this.eelabFetchTimer >= 0) {
        clearTimeout(this.eelabFetchTimer);
        this.eelabFetchTimer = -1;
      }
      if (!this.eelabTokenFetching) {
        this.navigatingToEelab = false;
        this.finish(this.collectedEasCookies, this.lastUrl, '');
      }
      return;
    }
    if (this.eelabTokenFetching || this.eelabFetchTimer >= 0) {
      return;
    }
    // Android 在 EELAB 页面完成后延迟 1 秒再取 Cookie/Token，避免页面刚跳转
    // 完成时 ArkWeb 尚未把 Set-Cookie 写入 CookieStore。
    this.eelabFetchTimer = setTimeout(() => {
      this.eelabFetchTimer = -1;
      if (!this.finished && this.navigatingToEelab) {
        this.fetchEelabTokenFromPage();
      }
    }, 1000);
  }

  private async fetchEelabTokenFromPage(): Promise<void> {
    const generation: number = this.loginGeneration;
    this.eelabTokenFetching = true;
    const raw: string = await EasWebLoginController.tryFetchCookie(EasCampusUrls.EELABINFO_URL);
    if (this.finished || generation !== this.loginGeneration) {
      return;
    }
    const eelabCookies: Map<string, string> = parseCookiesHeader(raw);
    const hasJs: boolean = eelabCookies.has('JSESSIONID') &&
      (eelabCookies.get('JSESSIONID') as string).trim().length > 0;
    if (!hasJs) {
      this.navigatingToEelab = false;
      this.finish(this.collectedEasCookies, this.lastUrl, '');
      return;
    }
    let token: string = '';
    try {
      token = await this.fetchEelabToken(eelabCookies);
    } catch (_) {
      hilog.warn(DOMAIN, TAG, 'optional electronic experiment token request failed');
    }
    if (this.finished || generation !== this.loginGeneration) {
      return;
    }
    this.navigatingToEelab = false;
    this.finish(this.collectedEasCookies, this.lastUrl, token);
  }

  private async fetchEelabToken(eelabCookies: Map<string, string>): Promise<string> {
    const header: Map<string, string> = new Map<string, string>();
    header.set('User-Agent', EELAB_USER_AGENT);
    header.set('Accept', '*/*');
    header.set('Origin', EasCampusUrls.EELABINFO_URL);
    header.set('Referer', EasCampusUrls.EELABINFO_URL + '/login.html?t=suc');
    header.set('Content-Type', 'application/x-www-form-urlencoded');
    header.set('X-Requested-With', 'XMLHttpRequest');
    header.set('Accept-Language', 'zh-CN,zh-Hans;q=0.9');
    const cookieHeader: string = EasSession.buildCookieHeader(eelabCookies);
    if (cookieHeader.length > 0) {
      header.set('Cookie', cookieHeader);
    }
    const url: string = EasCampusUrls.EELABINFO_URL + '/api/cas/login?sf_request_type=ajax';
    const resp = await EasApiClient.doHttp(url, EasHttpMethod.POST, header, '', 10000);
    if (resp.statusCode !== 200 || resp.body.length === 0) {
      return '';
    }
    try {
      const parsed: Record<string, Object> = JSON.parse(resp.body) as Record<string, Object>;
      if (Number(parsed['code']) !== 0) {
        return '';
      }
      const data: Record<string, Object> = parsed['data'] as Record<string, Object>;
      if (data === undefined || data === null) {
        return '';
      }
      const token: string = data['token'] === undefined || data['token'] === null ? '' :
        String(data['token']);
      return token.length >= 50 ? token : '';
    } catch (e) {
      return '';
    }
  }

  // ------------------------------------------------------------------
  // 状态发布
  // ------------------------------------------------------------------

  private setPhase(phase: EasLoginPhase, detail: string): void {
    this.phase = phase;
    this.onPhaseChanged(phase, detail);
  }

  private setProgress(p: number): void {
    this.onProgress(Math.max(0, Math.min(100, p)));
  }

  private setError(message: string): void {
    this.onError(message === undefined || message === null ? '' : message);
  }

  // ------------------------------------------------------------------
  // 静态工具与脚本
  // ------------------------------------------------------------------

  private static async runJs(controller: webview.WebviewController, script: string): Promise<string> {
    // Portal navigation/viewport helpers must not wait forever on a stalled page.
    return new Promise<string>((resolve) => {
      const timer: number = setTimeout(() => resolve(''), 5000);
      try {
        controller.runJavaScript(script).then((result: string) => {
          clearTimeout(timer);
          resolve(result === undefined || result === null ? '' : result);
        }).catch(() => {
          clearTimeout(timer);
          resolve('');
        });
      } catch (e) {
        clearTimeout(timer);
        resolve('');
      }
    });
  }

  static campusOfCode(code: string): EasCampus {
    if (code === 'BENBU') {
      return EasCampus.BENBU;
    }
    if (code === 'WEIHAI') {
      return EasCampus.WEIHAI;
    }
    return EasCampus.SHENZHEN;
  }

  static applyItpBypass(): void {
    try {
      webview.WebviewController.addIntelligentTrackingPreventionBypassingList([
        'jw.hitsz.edu.cn',
        'jw-hitsz-edu-cn.hitsz.edu.cn',
        'trust.hitsz.edu.cn',
        'authserver.hitsz.edu.cn',
        'ids.hit.edu.cn',
        'hit.edu.cn',
        'i-hit-edu-cn.vpn.hit.edu.cn',
        'jwts-hit-edu-cn.vpn.hit.edu.cn',
        'sjjx-hit-edu-cn.vpn.hit.edu.cn',
        'yjsgl-hit-edu-cn.vpn.hit.edu.cn',
        'eelabinfo-hit-edu-cn.vpn.hit.edu.cn',
        'webvpn.hitwh.edu.cn'
      ]);
    } catch (e) {}
  }

  static tryFetchCookie(url: string, partitioned: boolean = false): Promise<string> {
    // Keep slow/corrupt Web cookie storage off the UI thread and bound each probe.
    return new Promise<string>((resolve) => {
      const timer: number = setTimeout(() => resolve(''), 3000);
      try {
        const result: Promise<string> = partitioned && deviceInfo.apiAvailable('26.0.0') ?
          webview.WebCookieManager.fetchCookie(url, false, true) :
          webview.WebCookieManager.fetchCookie(url);
        result.then((value: string) => {
          clearTimeout(timer);
          resolve(value === undefined || value === null ? '' : value);
        }).catch(() => {
          clearTimeout(timer);
          resolve('');
        });
      } catch (e) {
        clearTimeout(timer);
        resolve('');
      }
    });
  }
  static async tryFetchCookieWithPartitioned(url: string, topLevelUrl: string = url): Promise<string> {
    let includePartitioned: boolean = false;
    try {
      includePartitioned = deviceInfo.apiAvailable('26.0.0');
    } catch (e) {}
    if (!includePartitioned) {
      const legacy: string[] = await Promise.all([
        EasWebLoginController.tryFetchCookie(url),
        LegacyCookieReader.read(url, topLevelUrl)
      ]);
      return LegacyCookieReader.merge(legacy[0], legacy[1]);
    }
    const values: string[] = await Promise.all([
      EasWebLoginController.tryFetchCookie(url),
      includePartitioned ? EasWebLoginController.tryFetchCookie(url, true) : Promise.resolve('')
    ]);
    return values[1].length > 0 && values[1] !== values[0] ?
      values[0] + '; ' + values[1] : values[0];
  }
  static cookieKeys(cookies: Map<string, string>): string {
    const keys: string[] = [];
    cookies.forEach((value: string, key: string) => {
      if (!isBlank(key)) {
        const length: number = value === undefined || value === null ? 0 : value.length;
        keys.push(key + ':' + length.toString());
      }
    });
    return '[' + keys.join(',') + ']';
  }

  static mergePutIfAbsent(dst: Map<string, string>, src: Map<string, string>): void {
    src.forEach((value: string, key: string) => {
      if (!dst.has(key)) {
        dst.set(key, value);
      }
    });
  }

  static extractJsessionid(url: string): string {
    const m1: RegExpExecArray | null = /;jsessionid=([^;&?]*)/i.exec(url);
    if (m1 !== null && m1[1] !== undefined) {
      return m1[1];
    }
    const m2: RegExpExecArray | null = /[?&]jsessionid=([^;&]*)/i.exec(url);
    if (m2 !== null && m2[1] !== undefined) {
      return m2[1];
    }
    return '';
  }

  /** aTrust forceWeb 注入脚本（对齐 Android applyShenzhenForceWebMode） */
  static readonly FORCE_WEB_MODE_SCRIPT: string =
    '(function() {\n' +
    '  try {\n' +
    "    sessionStorage.setItem('forceWeb', 'true');\n" +
    "    var mapKey = '__Prefix_map__';\n" +
    "    var prefixMap = JSON.parse(sessionStorage.getItem(mapKey) || '[]');\n" +
    '    if (!Array.isArray(prefixMap)) prefixMap = [];\n' +
    '    var origin = window.location.origin;\n' +
    '    var entry = prefixMap.find(function(item) { return item && item.addr === origin; });\n' +
    '    if (!entry) {\n' +
    '      var maxPrefix = prefixMap.reduce(function(max, item) {\n' +
    "        var match = item && String(item.pre || '').match(/^\\\\[(\\\\d+)\\\\]$/);\n" +
    '        return match ? Math.max(max, Number(match[1])) : max;\n' +
    '      }, 0);\n' +
    "      entry = {pre: '[' + (maxPrefix + 1) + ']', addr: origin};\n" +
    '      prefixMap.unshift(entry);\n' +
    '    }\n' +
    '    sessionStorage.setItem(mapKey, JSON.stringify(prefixMap));\n' +
    "    sessionStorage.setItem(entry.pre + 'forceWeb', 'true');\n" +
    '    return true;\n' +
    '  } catch (e) {\n' +
    '    return false;\n' +
    '  }\n' +
    '})();';

  /** 深圳教务统一认证与身份点击脚本（对齐 Android ShenzhenWebAutoLogin.buildClickScript） */
  static buildShenzhenClickScript(studentType: string, allowUnifiedLogin: boolean, allowRoleSelection: boolean): string {
    const prefType = studentType === '2' ? '2' : '1';
    return `
      (function() {
        function normalized(value) {
          return String(value || '').replace(/\\s+/g, '');
        }
        function visible(element) {
          if (!element || typeof element.click !== 'function') return false;
          var style = window.getComputedStyle ? window.getComputedStyle(element) : null;
          if (style && (style.display === 'none' || style.visibility === 'hidden')) return false;
          var rect = element.getBoundingClientRect ? element.getBoundingClientRect() : null;
          return !rect || (rect.width > 0 && rect.height > 0);
        }
        function labelOf(element) {
          return normalized(
            element.innerText || element.textContent || element.value ||
            element.getAttribute('aria-label') || element.getAttribute('title') || ''
          );
        }
        function candidates() {
          return Array.prototype.slice.call(document.querySelectorAll(
            'button,a,[role="button"],input[type="button"],input[type="submit"],' +
            '[onclick],[tabindex],div,span,p'
          )).filter(visible);
        }
        function shortestMatch(items, predicate) {
          return items.filter(function(element) {
            return predicate(labelOf(element));
          }).sort(function(left, right) {
            return labelOf(left).length - labelOf(right).length;
          })[0] || null;
        }
        function click(element, action) {
          if (!element) return null;
          element.click();
          return JSON.stringify({clicked:true, action:action, label:labelOf(element)});
        }

        var items = candidates();
        if (${allowUnifiedLogin}) {
          var unified = shortestMatch(items, function(label) {
            return label === '统一身份认证登录' || label === '统一身份认证';
          });
          var unifiedResult = click(unified, 'unified-login');
          if (unifiedResult) return unifiedResult;
        }

        if (${allowRoleSelection}) {
          var pageText = normalized(document.body && document.body.innerText);
          if (pageText.indexOf('本科') >= 0 && pageText.indexOf('研究生') >= 0) {
            var preferred = '${prefType}';
            var role = shortestMatch(items, function(label) {
              if (preferred === '2') {
                return label.indexOf('研究生') >= 0 &&
                  (label.length <= 5 || label.indexOf('登录') >= 0 ||
                    label.indexOf('入口') >= 0 || label.indexOf('教务') >= 0);
              }
              return label.indexOf('本科') >= 0 &&
                (label.length <= 5 || label.indexOf('登录') >= 0 ||
                  label.indexOf('入口') >= 0 || label.indexOf('教务') >= 0);
            });
            var roleResult = click(role, preferred === '2' ? 'postgrad-role' : 'undergrad-role');
            if (roleResult) return roleResult;
          }
        }
        return JSON.stringify({clicked:false, action:'none'});
      })();
    `;
  }
  /** 对齐 Android CookieManager 配置：CAS/WebVPN 会跨站写入认证 Cookie。 */
  static configureWebCookies(): void {
    try {
      webview.WebCookieManager.putAcceptCookieEnabled(true);
      webview.WebCookieManager.putAcceptThirdPartyCookieEnabled(true);
      hilog.info(DOMAIN, TAG, 'Web cookies enabled, thirdParty=%{public}s',
        String(webview.WebCookieManager.isThirdPartyCookieAllowed()));
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'Failed to configure Web cookies: %{public}s', String(e));
    }
  }
}
