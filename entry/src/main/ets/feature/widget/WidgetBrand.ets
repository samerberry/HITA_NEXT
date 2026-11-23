import { HitaDesign } from '../../common/theme/HitaDesign';

@Component
export struct WidgetBrand {
  @Prop scaleFactor: number = 1;
  @Prop followsSystemSurface: boolean = false;
  @Prop showName: boolean = true;

  build() {
    Row({ space: HitaDesign.spaceXs * this.scaleFactor }) {
      Image($r('app.media.app_icon'))
        .width(HitaDesign.iconLg * this.scaleFactor).height(HitaDesign.iconLg * this.scaleFactor)
        .borderRadius(HitaDesign.radiusSm * this.scaleFactor).clip(true).objectFit(ImageFit.Cover)
        .accessibilityText($r('app.string.app_name')).accessibilityLevel(this.showName ? 'no' : 'yes')
      if (this.showName) {
        Text($r('app.string.app_name'))
          .fontSize(HitaDesign.caption * this.scaleFactor).fontWeight(FontWeight.Bold)
          .fontColor(this.followsSystemSurface ? $r('app.color.hita_text') : $r('app.color.widget_ink'))
          .maxLines(1)
      }
    }
    .alignItems(VerticalAlign.Center)
    .hitTestBehavior(HitTestMode.None)
  }
}
