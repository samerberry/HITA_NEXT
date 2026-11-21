import { CompatibleMaterialModifier } from '../../../common/theme/CompatibleMaterialModifier';
import { HitaDesign } from '../../../common/theme/HitaDesign';
/**
 * EasLoginPage.ets — ArkWeb 网页登录页（对应 Android WebViewLoginActivity / WebViewLoginScreen）。
 *
 * UI 布局对齐安卓：
 *  - 顶部标题栏：左侧返回应用，右侧网页回退和刷新，各自占用独立布局空间。
 *  - 线性进度条：3vp 高度，仅在加载中展示。
 *  - Web 组件：直接绑定登录 URL，并在控制器附着后完成登录状态初始化。
 *  - 验证码的发送、输入和提交均使用认证网页自身的控件。
 */
import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { EasSession } from '../EasSession';
import { EasSessionStore } from '../EasSessionStore';
import { EasWebLoginController } from './EasWebLoginController';
import { easWebLoginConfigFor, EasCampusConfig, isWeihaiDirect } from './EasWebLoginConfig';
import { resolveEasLoginRoute } from './EasLoginRoute';
import { HitaColors } from '../../../common/theme/HitaColors';
import { HeaderBackButton } from '../../../common/components/HeaderBackButton';
import { ImmersiveHeader } from '../../../common/components/ImmersiveHeader';
import { CompatibleSheetMaterial } from '../../../common/theme/CompatibleSheetMaterial';

const TAG: string = 'HitaLoginPage';
const DOMAIN: number = 0x0000;

@Component
export struct EasLoginPage {
  @StorageProp('hita_appearance_dark') darkMode: boolean = false;
  @Prop campusCode: string = 'SHENZHEN';
  @Prop studentType: string = '1';
  @Prop @Watch('onActiveChanged') active: boolean = true;
  onCancel: () => void = () => {};
  onLoggedIn: (session: EasSession) => void = () => {};

  private webController: webview.WebviewController = new webview.WebviewController();
  private loginController: EasWebLoginController = new EasWebLoginController();
  private attachStarted: boolean = false;
  private pageActive: boolean = false;
  private loginCompleted: boolean = false;
  private callbackGeneration: number = 0;
  private pageLoadTimer: number = -1;
  private recoveryTimer: number = -1;
  private recoveryPending: boolean = false;
  private currentPageUrl: string = '';
  private config: EasCampusConfig | undefined = undefined;
  private firstPageLoaded: boolean = false;

  @State progressValue: number = 0;
  @State errorText: string = '';
  @State initialUrl: string = '';
  @State campusDisplayName: string = '统一认证登录';
  @State webReady: boolean = false;
  @State canGoBack: boolean = false;
  @State recoveryBusy: boolean = false;

  aboutToAppear(): void {
    this.pageActive = this.active;
    this.callbackGeneration++;
    // 必须在 Web 组件开始导航前开启 Cookie。安卓版在 loadUrl 前完成同样的初始化，
    // 否则 WebVPN/CAS 的跨站 Set-Cookie 可能被 ArkWeb 丢弃。
    EasWebLoginController.configureWebCookies();
    const campus = EasWebLoginController.campusOfCode(this.campusCode);
    const cfg: EasCampusConfig = easWebLoginConfigFor(campus, this.studentType);
    this.config = cfg;
    this.firstPageLoaded = false;
    this.campusDisplayName = cfg.displayName;
    if (this.campusCode === 'WEIHAI') {
      const generation: number = this.callbackGeneration;
      resolveEasLoginRoute(campus, this.studentType).then((selected: EasCampusConfig) => {
        if (!this.pageActive || generation !== this.callbackGeneration) return;
        this.config = selected;
        this.initialUrl = selected.loginUrl;
      });
    } else {
      this.initialUrl = cfg.loginUrl;
    }

    hilog.info(DOMAIN, TAG, 'EasLoginPage aboutToAppear: campus=%{public}s, initialUrl=%{public}s',
      this.campusCode, this.initialUrl);

    const ctrl: EasWebLoginController = this.loginController;
    ctrl.onProgress = (p: number) => {
      if (this.pageActive && !this.loginCompleted) this.progressValue = p;
    };
    ctrl.onError = (message: string) => {
      if (this.pageActive && !this.loginCompleted) this.errorText = message;
    };
    ctrl.onFinished = (session: EasSession) => {
      if (!this.pageActive || this.loginCompleted) return;
      this.loginCompleted = true;
      const generation: number = this.callbackGeneration;
      this.clearPageLoadTimer();
      const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
      EasSessionStore.getInstance().init(ctx).then(() => {
        if (!this.pageActive || generation !== this.callbackGeneration) {
          return Promise.resolve(false);
        }
        return EasSessionStore.getInstance().save(session);
      }).then((saved: boolean) => {
        if (this.pageActive && generation === this.callbackGeneration && saved) {
          this.onLoggedIn(session);
        } else if (this.pageActive && generation === this.callbackGeneration) {
          this.loginCompleted = false;
          this.errorText = '无法保存登录状态，请刷新后重试';
        }
      }).catch(() => {
        if (this.pageActive && generation === this.callbackGeneration) {
          this.loginCompleted = false;
          this.errorText = '无法保存登录状态，请刷新后重试';
        }
      });
    };
  }

  aboutToDisappear(): void {
    this.deactivate();
  }

  private onActiveChanged(): void {
    if (!this.active) this.deactivate();
  }

  private deactivate(): void {
    if (!this.pageActive) return;
    this.loginController.stop();
    try { this.webController.stop(); } catch (_) {}
    this.pageActive = false;
    this.callbackGeneration++;
    this.clearPageLoadTimer();
    if (this.recoveryTimer >= 0) {
      clearTimeout(this.recoveryTimer);
      this.recoveryTimer = -1;
    }
  }

  private clearPageLoadTimer(): void {
    if (this.pageLoadTimer >= 0) {
      clearTimeout(this.pageLoadTimer);
      this.pageLoadTimer = -1;
    }
  }

  private watchPageLoad(url: string): void {
    this.clearPageLoadTimer();
    this.currentPageUrl = url;
    this.webReady = false;
    this.pageLoadTimer = setTimeout(() => {
      this.pageLoadTimer = -1;
      if (!this.pageActive) {
        return;
      }
      if (this.fallbackToWeihaiVpn()) return;
      this.webReady = true;
      this.recoveryPending = false;
      this.recoveryBusy = false;
      this.errorText = '页面加载时间较长，可刷新或重置网页登录';
    }, 20000);
  }

  private fallbackToWeihaiVpn(): boolean {
    if (this.config === undefined || !isWeihaiDirect(this.config.dataBaseUrl) ||
      this.firstPageLoaded || this.recoveryBusy || this.recoveryPending) return false;
    const fallback: EasCampusConfig = easWebLoginConfigFor(this.config.campus, this.config.studentType);
    this.config = fallback;
    try {
      this.loginController.start(this.campusCode, this.studentType, fallback);
      this.watchPageLoad(fallback.loginUrl);
      this.webController.loadUrl(fallback.loginUrl);
      return true;
    } catch (_) {
      this.clearPageLoadTimer();
      return false;
    }
  }

  private pageEnded(url: string): void {
    if (!this.pageActive || this.loginCompleted) {
      return;
    }
    if (this.recoveryPending && url === 'about:blank') {
      this.completeRecovery();
      return;
    }
    if (this.recoveryBusy || url !== this.currentPageUrl) {
      return;
    }
    this.clearPageLoadTimer();
    this.firstPageLoaded = true;
    this.webReady = true;
    this.updateWebNavigation();
    this.loginController.notifyPageEnd(url);
  }

  private pageLoadFinished(url: string): void {
    if ((this.campusCode !== 'BENBU' && this.campusCode !== 'WEIHAI') ||
      !this.pageActive || this.loginCompleted || this.recoveryBusy || url.length === 0) {
      return;
    }
    // ArkWeb's final main-frame callback also covers redirects and fragment navigation.
    // Compare against the live URL so a late callback cannot finish an earlier page.
    try {
      if (this.webController.getUrl() !== url) {
        return;
      }
    } catch (e) {
      return;
    }
    if (url === this.currentPageUrl && this.webReady) {
      return;
    }
    if (url !== this.currentPageUrl) {
      this.currentPageUrl = url;
      this.loginController.notifyPageBegin(url);
    }
    this.pageEnded(url);
  }

  private confirmRecovery(): void {
    if (this.recoveryBusy) {
      return;
    }
    this.getUIContext().getPromptAction().showDialog({
      title: '重置网页登录',
      message: '将清除本应用内网页的登录状态和缓存。',
      buttons: [{ text: '取消', color: $r('app.color.hita_text_secondary_6b7a90') }, { text: '重置登录', color: $r('app.color.hita_primary') }]
    }).then((result) => {
      if (result.index === 1 && this.pageActive) {
        this.beginRecovery();
      }
    }).catch(() => {});
  }

  private beginRecovery(): void {
    if (this.recoveryBusy || !this.pageActive) {
      return;
    }
    this.callbackGeneration++;
    this.loginController.stop();
    this.recoveryBusy = true;
    this.recoveryPending = true;
    this.errorText = '';
    try {
      // Leave the authentication document before clearing storage, so its scripts
      // cannot recreate old cookies while the reset is in progress.
      this.webController.stop();
      this.watchPageLoad('about:blank');
      this.webController.loadUrl('about:blank');
    } catch (e) {
      this.clearPageLoadTimer();
      this.recoveryPending = false;
      this.recoveryBusy = false;
      this.webReady = true;
      this.errorText = '无法重置网页登录，请退出登录窗口后重试';
    }
  }

  private async completeRecovery(): Promise<void> {
    if (!this.recoveryPending || !this.pageActive) {
      return;
    }
    this.recoveryPending = false;
    this.clearPageLoadTimer();
    const generation: number = this.callbackGeneration;
    this.recoveryTimer = setTimeout(() => {
      this.recoveryTimer = -1;
      if (this.pageActive && generation === this.callbackGeneration) {
        this.callbackGeneration++;
        this.recoveryBusy = false;
        this.webReady = true;
        this.errorText = '重置网页登录超时，请退出登录窗口后重试';
      }
    }, 15000);
    try {
      await webview.WebCookieManager.clearAllCookies();
      if (!this.pageActive || generation !== this.callbackGeneration) {
        return;
      }
      webview.WebStorage.deleteAllData();
      this.webController.removeCache(true);
      this.recoveryBusy = false;
      const startUrl: string = this.config?.loginUrl ?? this.initialUrl;
      this.firstPageLoaded = false;
      this.loginController.start(this.campusCode, this.studentType, this.config);
      this.watchPageLoad(startUrl);
      this.webController.loadUrl(startUrl);
    } catch (e) {
      if (this.pageActive && generation === this.callbackGeneration) {
        this.recoveryBusy = false;
        this.webReady = true;
        this.errorText = '无法重置网页登录，请退出登录窗口后重试';
      }
    } finally {
      if (generation === this.callbackGeneration && this.recoveryTimer >= 0) {
        clearTimeout(this.recoveryTimer);
        this.recoveryTimer = -1;
      }
    }
  }

  private updateWebNavigation(): void {
    try {
      this.canGoBack = this.webController.accessBackward();
    } catch (e) {
      this.canGoBack = false;
    }
  }

  private navigateWebBack(): void {
    try {
      if (this.webController.accessBackward()) {
        this.webController.backward();
      }
    } catch (e) {}
    this.updateWebNavigation();
  }

  private cancelLogin(): void {
    this.deactivate();
    this.onCancel();
  }

  build() {
    Column() {
      // Android WebViewLoginActivity uses a compact white app bar with a thin
      // brand accent, leaving the authentication page itself visually calm.
      ImmersiveHeader({ barHeight: 62 }) {
        Row({ space: 8 }) {
          HeaderBackButton({
            accessibilityLabel: '返回应用',
            onBack: () => this.cancelLogin()
          });

          Column() {
            Text('统一认证登录')
              .fontSize(HitaDesign.section)
              .fontWeight(FontWeight.Medium)
              .fontColor(HitaColors.onSurface)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis });
            Text(this.campusDisplayName)
              .fontSize(HitaDesign.caption)
              .fontColor(HitaColors.primary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: HitaDesign.space2xs });
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start);

          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.arrow_left'))
              .fontSize(HitaDesign.iconMd)
              .fontColor([HitaColors.onSurface]);
          }
          .width(44)
          .height(44)
          .padding(0)
          .flexShrink(0)
          .backgroundColor(Color.Transparent)
          .attributeModifier(new CompatibleMaterialModifier(Color.Transparent))
          .enabled(this.canGoBack)
          .opacity(this.canGoBack ? 1 : 0.35)
          .accessibilityText('返回上一网页')
          .onClick(() => {
            this.navigateWebBack();
          });

          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.repeat_1'))
              .fontSize(HitaDesign.iconMd)
              .fontColor([HitaColors.primary]);
          }
          .width(44)
          .height(44)
          .padding(0)
          .flexShrink(0)
          .backgroundColor(Color.Transparent)
          .attributeModifier(new CompatibleMaterialModifier(Color.Transparent))
          .accessibilityText('刷新认证网页')
          .enabled(!this.recoveryBusy)
          .onClick(() => {
            try {
              this.loginController.start(this.campusCode, this.studentType, this.config);
              this.watchPageLoad(this.currentPageUrl);
              this.progressValue = 0;
              this.webController.refresh();
            } catch (e) {}
          });

        }
        .width('100%')
        .height(62)
        .padding({ left: 16, right: 16 })
        .backgroundColor(CompatibleSheetMaterial.bodyColor($r('app.color.hita_surface')))
        .border({ width: { bottom: 1 }, color: HitaColors.divider })
        .alignItems(VerticalAlign.Center)
      }

      // ═══════════════ 线性进度条（对齐安卓 LinearProgressIndicator） ═══════════════
      Progress({ value: this.progressValue, total: 100, type: ProgressType.Linear })
        .width('100%')
        .height(3)
        .color(HitaColors.primary)
        .backgroundColor($r('app.color.hita_selected_e8f1fb'))
        .visibility(this.webReady ? Visibility.None : Visibility.Visible)

      // 错误提示条
      if (this.errorText.length > 0 || this.recoveryBusy) {
        Row() {
          Text(this.recoveryBusy ? '正在重置网页登录' : this.errorText)
            .fontSize(HitaDesign.caption)
            .fontColor($r('app.color.hita_error_b91c1c'))
            .layoutWeight(1)
          if (!this.recoveryBusy) {
            Button('重置登录')
              .fontSize(HitaDesign.caption)
              .fontColor(HitaColors.primary)
              .backgroundColor(Color.Transparent)
              .attributeModifier(new CompatibleMaterialModifier(Color.Transparent))
              .onClick(() => this.confirmRecovery())
          }
          Text('✕')
            .fontSize(HitaDesign.caption)
            .fontColor($r('app.color.hita_error_b91c1c'))
            .onClick(() => {
              this.errorText = '';
            })
        }
        .width('100%')
        .padding({ left: HitaDesign.inset, right: HitaDesign.inset, top: HitaDesign.spaceXs, bottom: HitaDesign.spaceXs })
        .backgroundColor($r('app.color.hita_error_surface_fff1f0'))
        .border({ width: { bottom: 1 }, color: $r('app.color.hita_error_border') })
      }

      // ═══════════════ Web 容器（占满全屏剩余空间） ═══════════════
      Stack({ alignContent: Alignment.Center }) {
        if (this.initialUrl.length > 0) {
          Web({ src: this.initialUrl, controller: this.webController })
            .darkMode(this.darkMode ? WebDarkMode.On : WebDarkMode.Off)
            // Authentication pages own their CAPTCHA/QR colors; never invert them.
            .forceDarkAccess(false)
            .domStorageAccess(true)
            .javaScriptAccess(true)
            .databaseAccess(true)
            .fileAccess(true)
            .imageAccess(true)
            .onlineImageAccess(true)
            .mixedMode(MixedMode.All)
            // 安卓版启用了多窗口；CAS/WebVPN 部分页面会通过新窗口继续认证。
            .multiWindowAccess(true)
            .allowWindowOpenMethod(true)
            .onWindowNew((event) => {
              if (!this.pageActive || this.loginCompleted || this.recoveryBusy) return;
              if (event && event.targetUrl && event.targetUrl.length > 0) {
                try {
                  this.webController.loadUrl(event.targetUrl);
                } catch (e) {}
              }
            })
            .onControllerAttached(() => {
              if (this.attachStarted || !this.pageActive || this.loginCompleted) {
                return;
              }
              this.attachStarted = true;
              hilog.info(DOMAIN, TAG, 'Web controller attached, starting EAS login: %{public}s', this.initialUrl);
              this.loginController.attachWeb(this.webController);
              this.loginController.start(this.campusCode, this.studentType);
              this.watchPageLoad(this.initialUrl);
            })
            .onPageBegin((event) => {
              if (!this.pageActive || this.loginCompleted) {
                return;
              }
              const u: string = event !== undefined && event !== null ? event.url : '';
              this.progressValue = 0;
              if (this.recoveryBusy && u !== 'about:blank') {
                return;
              }
              this.watchPageLoad(u);
              this.updateWebNavigation();
              this.loginController.notifyPageBegin(u);
            })
            .onPageEnd((event) => {
              const u: string = event !== undefined && event !== null ? event.url : '';
              this.pageEnded(u);
            })
            .onLoadFinished((event) => {
              if (event) {
                this.pageLoadFinished(event.url);
              }
            })
            .onProgressChange((event) => {
              if (!this.pageActive || this.loginCompleted) return;
              const p: number = event !== undefined && event !== null ? event.newProgress : 0;
              this.progressValue = p;
              this.loginController.notifyProgress(p);
            })
            .onErrorReceive((event) => {
              if (!this.pageActive || this.loginCompleted) return;
              if (event !== undefined && event !== null && event.error !== undefined && event.error !== null) {
                let errStr: string = '';
                try {
                  errStr = event.error.getErrorInfo ? event.error.getErrorInfo() : String(event.error);
                } catch (e) {
                  errStr = String(event.error);
                }
                if (/ABORTED/i.test(errStr)) return;
                if (event.request !== undefined && event.request.isMainFrame() &&
                  event.request.getRequestUrl() !== this.currentPageUrl) return;
                if (this.loginController.notifyLoadError(errStr,
                  event.request !== undefined && event.request.isMainFrame())) {
                  return;
                }
                if (event.request !== undefined && event.request.isMainFrame()) {
                  if (this.fallbackToWeihaiVpn()) return;
                  this.clearPageLoadTimer();
                  if (this.recoveryPending) {
                    this.recoveryPending = false;
                    this.recoveryBusy = false;
                  }
                  this.webReady = true;
                  this.errorText = '认证页面加载失败，可刷新或重置网页登录';
                }
              }
            })
            // School scripts can log submitted fields; do not forward their console output.
            .onConsole(() => true)
            .width('100%')
            .height('100%')
        }

        if (!this.webReady) {
          Column() {
            Image($r('app.media.app_icon'))
              .width(54)
              .height(54)
              .objectFit(ImageFit.Contain)
              .borderRadius(HitaDesign.radiusLg)
              .backgroundColor($r('app.color.hita_surface'))
              .shadow({ radius: 12, color: '#14000000', offsetY: 4 });
            LoadingProgress()
              .width(28)
              .height(28)
              .color(HitaColors.primary)
              .margin({ top: HitaDesign.spaceMd, bottom: HitaDesign.spaceSm });
            Text('正在打开统一认证页面')
              .fontSize(HitaDesign.body)
              .fontWeight(FontWeight.Medium)
              .fontColor(HitaColors.onSurface);
          }
          .padding(HitaDesign.spaceLg)
          .borderRadius(HitaDesign.cardRadius)
          .backgroundColor($r('app.color.hita_surface'))
          .hitTestBehavior(HitTestMode.None)
          .shadow({ radius: 18, color: '#18000000', offsetY: 6 });
        }

      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(CompatibleSheetMaterial.bodyColor($r('app.color.hita_surface')))
  }
}
