import { ColorMetrics, LengthMetrics, SegmentButtonV2ItemOptions, SegmentButtonV2Items,
  TabSegmentButtonV2 } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import lazy { ImmersiveCourseModeSegment } from './ImmersiveCourseModeSegment';
import { CourseControlHost } from './CourseControlHost';

@Component
export struct CourseModeSegment {
  @Prop labels: string[] = [];
  @Prop selectedIndex: number = 0;
  onSelect: (index: number) => void = () => {};
  onControlPressingChanged: (pressing: boolean) => void = (_pressing: boolean) => {};
  private items: SegmentButtonV2Items = new SegmentButtonV2Items([]);

  aboutToAppear(): void {
    this.items = new SegmentButtonV2Items(this.labels.map((label: string): SegmentButtonV2ItemOptions => {
      return { text: label, accessibilityText: label };
    }));
  }

  build() {
    if (deviceInfo.apiAvailable('26.0.0') && !deviceInfo.apiAvailable('27.0.0')) {
      CourseControlHost({ barHeight: 44, onPressingChanged: this.onControlPressingChanged }) {
        ImmersiveCourseModeSegment({
          labels: this.labels, selectedIndex: this.selectedIndex, onSelect: this.onSelect
        })
      }
    } else {
      TabSegmentButtonV2({
        items: this.items,
        selectedIndex: this.selectedIndex,
        $selectedIndex: (index: number) => this.onSelect(index),
        enableStateAnimation: true,
        buttonBackgroundColor: ColorMetrics.resourceColor($r('app.color.hita_surface_soft')),
        buttonPadding: LengthMetrics.vp(4),
        buttonMinHeight: LengthMetrics.vp(44),
        buttonBorderRadius: LengthMetrics.vp(22),
        itemMinHeight: LengthMetrics.vp(36),
        itemBorderRadius: LengthMetrics.vp(18),
        itemSpace: LengthMetrics.vp(0),
        itemPadding: { top: LengthMetrics.vp(0), bottom: LengthMetrics.vp(0),
          start: LengthMetrics.vp(12), end: LengthMetrics.vp(12) },
        itemFontSize: LengthMetrics.fp(14),
        itemSelectedFontSize: LengthMetrics.fp(14),
        itemFontColor: ColorMetrics.resourceColor($r('app.color.hita_text_202b45')),
        itemSelectedFontColor: ColorMetrics.resourceColor($r('app.color.hita_on_primary')),
        itemSelectedBackgroundColor: ColorMetrics.resourceColor($r('app.color.hita_primary_fill')),
        itemShadow: { radius: 0, color: Color.Transparent, offsetX: 0, offsetY: 0 }
      })
        .width('100%');
    }
  }
}
