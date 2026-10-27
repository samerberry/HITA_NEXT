import { HitaDesign } from '../common/theme/HitaDesign';
/**
 * WebBrowserPage.ets — 应用内浏览器：打开资讯文章与校园入口链接。
 */
import { webview } from '@kit.ArkWeb';
import { HeaderBackButton } from '../common/components/HeaderBackButton';
import { ImmersiveHeader } from '../common/components/ImmersiveHeader';
import { STATUS_BAR_INSET_FALLBACK } from '../common/theme/StatusBarInset';

@Entry
@Component
struct WebBrowserPage {
  @StorageProp('hita_appearance_dark') darkMode: boolean = false;
  @StorageProp('hita_status_bar_vp') statusBarInset: number = STATUS_BAR_INSET_FALLBACK;
  @State url: string = '';
  @State titleText: string = '详情';
  @State progress: number = 0;
  @State failed: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void {
    const params: Object | undefined = this.getUIContext().getRouter().getParams();
    if (params !== undefined && params !== null) {
      const record: Record<string, string> = params as Record<string, string>;
      this.url = record['url'] === undefined ? '' : String(record['url']);
      if (record['title'] !== undefined && String(record['title']).length > 0) {
        this.titleText = String(record['title']);
      }
    }
  }

  private goBack(): void {
    try {
      if (this.controller.accessBackward()) {
        this.controller.backward();
        return;
      }
    } catch (e) {
      // The web view may not be attached yet; fall back to leaving the page.
    }
    this.getUIContext().getRouter().back();
  }

  onBackPress(): boolean {
    try {
      if (this.controller.accessBackward()) {
        this.controller.backward();
        return true;
      }
    } catch (e) {
    }
    return false;
  }

  build() {
    Column() {
      ImmersiveHeader({ barHeight: 60 }) {
        Row() {
          HeaderBackButton({
            onBack: () => this.goBack()
          })
            .margin({ right: 12 })
          Text(this.titleText)
            .fontSize(HitaDesign.section)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.hita_text_1a1a1a'))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.arrow_clockwise'))
              .fontSize(HitaDesign.iconMd)
              .fontColor([$r('app.color.hita_primary')])
          }
          .width(40)
          .height(40)
          .backgroundColor($r('app.color.hita_control'))
          .accessibilityText('刷新')
          .onClick(() => {
            this.failed = false;
            try {
              this.controller.refresh();
            } catch (e) {
            }
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .backgroundColor($r('app.color.hita_surface'))
        .alignItems(VerticalAlign.Center)
      }

      if (this.progress > 0 && this.progress < 100) {
        Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(2)
          .color($r('app.color.hita_primary'))
      }

      if (this.url.length === 0) {
        Text('没有可打开的链接')
          .fontSize(HitaDesign.caption)
          .fontColor($r('app.color.hita_text_secondary_5a6880'))
          .margin({ top: 60 })
      } else {
        Stack() {
          Web({ src: this.url, controller: this.controller })
            .darkMode(this.darkMode ? WebDarkMode.On : WebDarkMode.Off)
            .forceDarkAccess(this.darkMode)
            .width('100%')
            .height('100%')
            .javaScriptAccess(true)
            .domStorageAccess(true)
            .onlineImageAccess(true)
            .mixedMode(MixedMode.All)
            .onProgressChange((event) => {
              if (event !== undefined) {
                this.progress = event.newProgress;
              }
            })
            .onErrorReceive((event) => {
              if (event !== undefined && event.request.isMainFrame()) {
                this.failed = true;
              }
            })
          if (this.failed) {
            Column() {
              Text('页面加载失败，请检查网络后点右上角刷新')
                .fontSize(HitaDesign.caption)
                .fontColor($r('app.color.hita_text_secondary'))
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .backgroundColor($r('app.color.hita_page_f6f7fa'))
          }
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.statusBarInset })
    .backgroundColor($r('app.color.hita_surface'))
  }
}
