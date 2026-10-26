import { HitaDesign } from '../common/theme/HitaDesign';
/**
 * PrivacyPolicyPage.ets — 隐私政策。条款见 AboutContent.policy()。
 */
import { HeaderBackButton } from '../common/components/HeaderBackButton';
import { ImmersiveHeader } from '../common/components/ImmersiveHeader';
import { HeaderFadeMask } from '../common/components/HeaderFadeMask';
import { HeaderFade } from '../common/theme/HeaderFade';
import { STATUS_BAR_INSET_FALLBACK } from '../common/theme/StatusBarInset';
import { AboutContent, PolicySection } from '../feature/about/AboutContent';

const HEADER_HEIGHT: number = 60;
const PAGE_BG: ResourceColor = $r('app.color.hita_page_f6f7fa');
const PAGE_BG_RGB: string = '245,246,248';
const TEXT_PRIMARY: ResourceColor = $r('app.color.hita_text_1a1a1a');
const TEXT_SECONDARY: ResourceColor = $r('app.color.hita_text_secondary_566276');

@Entry
@Component
struct PrivacyPolicyPage {
  @State fadeOpacity: number = 0;
  @StorageProp('hita_status_bar_vp') statusBarInset: number = STATUS_BAR_INSET_FALLBACK;
  private scroller: Scroller = new Scroller();

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Scroll(this.scroller) {
        Column({ space: 12 }) {
          Blank().height(HEADER_HEIGHT);
          Column() {
            Text(AboutContent.POLICY_TITLE)
              .fontSize(HitaDesign.section)
              .fontWeight(FontWeight.Medium)
              .fontColor(TEXT_PRIMARY);
            Text('更新日期：' + AboutContent.POLICY_UPDATED)
              .fontSize(HitaDesign.label)
              .fontColor(TEXT_SECONDARY)
              .margin({ top: 8 });
            ForEach(AboutContent.policyIntro(), (paragraph: string) => {
              Text(paragraph)
                .fontSize(HitaDesign.caption)
                .lineHeight(21)
                .fontColor(TEXT_SECONDARY)
                .width('100%')
                .margin({ top: 10 });
            }, (paragraph: string) => paragraph);
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(16)
          .backgroundColor($r('app.color.hita_surface'))
          .borderRadius(16);
          ForEach(AboutContent.policy(), (section: PolicySection) => {
            this.sectionCard(section);
          }, (section: PolicySection) => section.title);
          Text('生效日期：' + AboutContent.POLICY_EFFECTIVE)
            .fontSize(HitaDesign.label)
            .fontColor(TEXT_SECONDARY)
            .alignSelf(ItemAlign.Start)
            .margin({ left: 4 });
          Text('查看托管在华为协议服务上的原文')
            .fontSize(HitaDesign.caption)
            .fontColor($r('app.color.hita_primary'))
            .alignSelf(ItemAlign.Start)
            .margin({ left: 4 })
            .onClick(() => {
              this.getUIContext().getRouter().pushUrl({
                url: 'pages/WebBrowserPage',
                params: { 'url': AboutContent.PRIVACY_POLICY_URL, 'title': '隐私政策' }
              });
            });
          Blank().height(24);
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
          Text('隐私政策')
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
  sectionCard(section: PolicySection) {
    Column() {
      Text(section.title)
        .fontSize(HitaDesign.body)
        .fontWeight(FontWeight.Medium)
        .fontColor(TEXT_PRIMARY);
      ForEach(section.items, (item: string) => {
        Row() {
          Text('•')
            .fontSize(HitaDesign.caption)
            .lineHeight(21)
            .fontColor(TEXT_SECONDARY)
            .width(12);
          Text(item)
            .fontSize(HitaDesign.caption)
            .lineHeight(21)
            .fontColor(TEXT_SECONDARY)
            .layoutWeight(1);
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
        .margin({ top: 8 });
      }, (item: string) => item);
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor($r('app.color.hita_surface'))
    .borderRadius(16);
  }
}
