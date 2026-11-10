import { HeaderBackButton } from '../common/components/HeaderBackButton';
import { ImmersiveHeader } from '../common/components/ImmersiveHeader';
import { HitaColors } from '../common/theme/HitaColors';
import { HitaDesign } from '../common/theme/HitaDesign';
import { STATUS_BAR_INSET_FALLBACK } from '../common/theme/StatusBarInset';
import { AboutContent, AboutExplanation } from '../feature/about/AboutContent';

@Entry
@Component
struct AppExplanationPage {
  @StorageProp('hita_status_bar_vp') statusBarInset: number = STATUS_BAR_INSET_FALLBACK;
  @State explanations: AboutExplanation[] = AboutContent.explanations();

  aboutToAppear(): void {
    const params: Record<string, string> | undefined =
      this.getUIContext().getRouter().getParams() as Record<string, string> | undefined;
    const selected = this.explanations.find((explanation: AboutExplanation) => explanation.id === params?.['sectionId']);
    if (selected !== undefined) {
      this.explanations = [selected];
    }
  }

  build() {
    Column() {
      ImmersiveHeader({ barHeight: HitaDesign.headerHeight }) {
        Row({ space: HitaDesign.gap }) {
          HeaderBackButton({ onBack: () => this.getUIContext().getRouter().back() });
          Text('说明')
            .fontSize(HitaDesign.title)
            .fontWeight(FontWeight.Medium)
            .fontColor(HitaColors.onSurface);
        }
        .width('100%')
        .height(HitaDesign.headerHeight)
        .padding({ left: HitaDesign.inset, right: HitaDesign.inset })
      }

      Scroll() {
        Column({ space: HitaDesign.gap }) {
          ForEach(this.explanations, (explanation: AboutExplanation) => {
            this.explanationCard(explanation.title, explanation.detail);
          }, (explanation: AboutExplanation) => explanation.id);
        }
        .width('100%')
        .constraintSize({ maxWidth: HitaDesign.contentMaxWidth })
        .padding({ left: HitaDesign.inset, right: HitaDesign.inset, bottom: HitaDesign.spaceLg })
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off);
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.statusBarInset })
    .backgroundColor($r('app.color.hita_page_f6f7fa'));
  }

  @Builder
  explanationCard(title: string, detail: string) {
    Column({ space: HitaDesign.spaceXs }) {
      Text(title)
        .fontSize(HitaDesign.body)
        .fontWeight(FontWeight.Medium)
        .fontColor(HitaColors.onSurface);
      Text(detail)
        .fontSize(HitaDesign.caption)
        .fontColor(HitaColors.onSurfaceVariant);
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(HitaDesign.inset)
    .backgroundColor($r('app.color.hita_surface'))
    .borderRadius(HitaDesign.cardRadius);
  }
}
