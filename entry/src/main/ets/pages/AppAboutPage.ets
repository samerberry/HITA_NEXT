import { HitaDesign } from '../common/theme/HitaDesign';
/**
 * AppAboutPage.ets — 关于：应用信息、制作者、鸣谢与隐私政策入口。
 * 结构参考 HITA Aura 的“关于 HITA Aura”与 HITA Android 的关于页，文案集中在 AboutContent。
 */
import { bundleManager } from '@kit.AbilityKit';
import { HeaderBackButton } from '../common/components/HeaderBackButton';
import { ImmersiveHeader } from '../common/components/ImmersiveHeader';
import { HeaderFadeMask } from '../common/components/HeaderFadeMask';
import { HeaderFade } from '../common/theme/HeaderFade';
import { STATUS_BAR_INSET_FALLBACK } from '../common/theme/StatusBarInset';
import { AboutContent, AboutContributor, AboutCredit } from '../feature/about/AboutContent';

const HEADER_HEIGHT: number = 60;
const PAGE_BG: ResourceColor = $r('app.color.hita_page_f6f7fa');
const PAGE_BG_RGB: string = '245,246,248';
const CARD_BG: ResourceColor = $r('app.color.hita_surface');
const TEXT_PRIMARY: ResourceColor = $r('app.color.hita_text_1a1a1a');
const TEXT_SECONDARY: ResourceColor = $r('app.color.hita_text_secondary_566276');
const PRIMARY: ResourceColor = $r('app.color.hita_primary');

@Entry
@Component
struct AppAboutPage {
  @State fadeOpacity: number = 0;
  @StorageProp('hita_status_bar_vp') statusBarInset: number = STATUS_BAR_INSET_FALLBACK;
  private scroller: Scroller = new Scroller();
  private version: string = AppAboutPage.versionName();

  private static versionName(): string {
    try {
      const info: bundleManager.BundleInfo =
        bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      return info.versionName;
    } catch (e) {
      return '';
    }
  }

  private openLink(title: string, url: string): void {
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/WebBrowserPage',
      params: { 'url': url, 'title': title }
    });
  }

  private openPolicy(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/PrivacyPolicyPage' });
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Scroll(this.scroller) {
        Column() {
          Blank().height(HEADER_HEIGHT);
          this.hero();

          this.sectionTitle('制作者');
          Column() {
            ForEach(AboutContent.contributors(), (person: AboutContributor) => {
              this.contributorRow(person);
            }, (person: AboutContributor) => person.name);
          }
          .width('100%')
          .padding({ top: 4, bottom: 4 })
          .backgroundColor(CARD_BG)
          .borderRadius(16);

          this.sectionTitle('鸣谢');
          Column() {
            ForEach(AboutContent.projectCredits(), (credit: AboutCredit) => {
              this.creditRow(credit);
            }, (credit: AboutCredit) => credit.title);
          }
          .width('100%')
          .padding({ top: 4, bottom: 4 })
          .backgroundColor(CARD_BG)
          .borderRadius(16);

          Text(AboutContent.DISCLAIMER)
            .fontSize(HitaDesign.label)
            .fontColor(TEXT_SECONDARY)
            .margin({ top: 24, bottom: 32 });
        }
        .width('100%')
        .padding({ left: 16, right: 16 });
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .onDidScroll(() => {
        this.fadeOpacity = HeaderFade.opacity(this.scroller.currentOffset().yOffset);
      });

      HeaderFadeMask({ maskOpacity: this.fadeOpacity, rgb: PAGE_BG_RGB, headerHeight: HEADER_HEIGHT })

      ImmersiveHeader({ barHeight: HEADER_HEIGHT }) {
        Row() {
          HeaderBackButton({
            onBack: () => this.getUIContext().getRouter().back()
          })
            .margin({ right: 12 })
          Text('关于')
            .fontSize(HitaDesign.title)
            .fontWeight(FontWeight.Medium)
            .fontColor(TEXT_PRIMARY)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .height(HEADER_HEIGHT)
        .padding({ left: 16, right: 16 })
        .alignItems(VerticalAlign.Center)
        .hitTestBehavior(HitTestMode.Transparent)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.statusBarInset })
    .backgroundColor(PAGE_BG)
  }

  @Builder
  hero() {
    Column() {
      Image($r('app.media.app_icon'))
        .width(84)
        .height(84)
        .borderRadius(HitaDesign.cardRadius)
        .shadow({ radius: 12, color: '#1A000000', offsetY: 4 });
      Text(AboutContent.APP_NAME)
        .fontSize(HitaDesign.title)
        .fontWeight(FontWeight.Medium)
        .fontColor(TEXT_PRIMARY)
        .margin({ top: 14 });
      if (this.version.length > 0) {
        Text('版本 ' + this.version)
          .fontSize(HitaDesign.caption)
          .fontColor(TEXT_SECONDARY)
          .margin({ top: 4 });
      }
      Text(AboutContent.TAGLINE)
        .fontSize(HitaDesign.caption)
        .fontColor(TEXT_SECONDARY)
        .margin({ top: 10 });
      Text('隐私政策')
        .fontSize(HitaDesign.caption)
        .fontWeight(FontWeight.Medium)
        .fontColor(PRIMARY)
        .backgroundColor($r('app.color.hita_selected'))
        .borderRadius(16)
        .padding({ left: 14, right: 14, top: 7, bottom: 7 })
        .margin({ top: 14 })
        .onClick(() => this.openPolicy());
    }
    .width('100%')
    .padding({ top: 20, bottom: 8 })
    .alignItems(HorizontalAlign.Center);
  }

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(HitaDesign.section)
      .fontWeight(FontWeight.Medium)
      .fontColor(TEXT_PRIMARY)
      .margin({ top: 20, bottom: 8 })
      .alignSelf(ItemAlign.Start);
  }

  @Builder
  contributorRow(person: AboutContributor) {
    Row() {
      Image(person.avatar)
        .width(42)
        .height(42)
        .borderRadius(21)
        .objectFit(ImageFit.Cover)
        .backgroundColor($r('app.color.hita_control'))
        .alt($r('app.media.app_icon'))
        .accessibilityText(person.name + ' 的头像');
      Column() {
        Text(person.name)
          .fontSize(HitaDesign.body)
          .fontWeight(FontWeight.Medium)
          .fontColor(TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(person.github)
          .fontSize(HitaDesign.label)
          .fontColor(TEXT_SECONDARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 4 });
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12, right: 8 });
      Text('GitHub')
        .fontSize(HitaDesign.label)
        .fontColor(PRIMARY);
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => this.openLink(person.name, person.url));
  }

  @Builder
  creditRow(credit: AboutCredit) {
    Row() {
      Column() {
        Text(credit.title)
          .fontSize(HitaDesign.caption)
          .fontColor(TEXT_PRIMARY);
        Text(credit.detail)
          .fontSize(HitaDesign.label)
          .fontColor(TEXT_SECONDARY)
          .margin({ top: 4 });
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start);
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(12)
        .fontColor([TEXT_SECONDARY])
        .width(16).height(24).flexShrink(0)
        .accessibilityLevel('no');
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => this.openLink(credit.title, credit.url));
  }
}
