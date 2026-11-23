import { HitaDesign } from '../../common/theme/HitaDesign';

@Component
export struct WidgetBrand {
  @Prop scaleFactor: number = 1;
  @Prop followsSystemSurface: boolean = false;
  @Prop showName: boolean = true;

  build() {
    Row({ space: HitaDesign.space2xs * this.scaleFactor }) {
      Image($r('app.media.app_icon'))
        .width(HitaDesign.iconSm * this.scaleFactor).height(HitaDesign.iconSm * this.scaleFactor)
        .objectFit(ImageFit.Contain)
      if (this.showName) {
        Text($r('app.string.app_name'))
          .fontSize(HitaDesign.dockLabel * this.scaleFactor).fontWeight(FontWeight.Medium)
          .fontColor(this.followsSystemSurface ? $r('app.color.hita_text_secondary') : $r('app.color.widget_muted'))
          .maxLines(1)
      }
    }
    .alignItems(VerticalAlign.Center)
    .hitTestBehavior(HitTestMode.None)
  }
}
