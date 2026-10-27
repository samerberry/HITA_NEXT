import { CourseDateSelection } from '../CourseDateSelection';
import { HitaDesign } from '../../../common/theme/HitaDesign';
import { COURSE_CONTROL_OVERFLOW, CourseControlHost } from './CourseControlHost';
import { CompatibleMaterialModifier } from '../../../common/theme/CompatibleMaterialModifier';
import { CompatibleSheetMaterial } from '../../../common/theme/CompatibleSheetMaterial';

/** Horizontal strokes paint selection; vertical gestures belong to the page Scroll. */
@Component
export struct CourseWeekPicker {
  @Prop weekdayMode: boolean = false;
  @Prop weeks: number[] = [];
  @Link chosen: number[];
  @State activeWeek: number = -1;
  onAddWeeks: () => void = () => {};
  onChoosingChanged: (choosing: boolean) => void = (_choosing: boolean) => {};
  private gridWidth: number = 0;
  private painting: boolean = false;
  private paintSelected: boolean = false;
  private lastIndex: number = -1;

  aboutToDisappear(): void {
    this.finishStroke();
  }

  private indexAt(x: number, y: number): number {
    const padding = CompatibleSheetMaterial.isEnabled() ? COURSE_CONTROL_OVERFLOW : 0;
    const columns = this.weekdayMode ? 7 : 5;
    const gap = this.weekdayMode ? 4 : 8;
    const height = this.weekdayMode ? 38 : 44;
    const width = this.gridWidth - padding * 2;
    x -= padding;
    y -= padding;
    if (width <= 0 || x < 0 || x >= width || y < 0) return -1;
    const stride = (width + gap) / columns;
    const column = Math.floor(x / stride);
    const row = Math.floor(y / (height + 8));
    if (column >= columns || x - column * stride >= stride - gap || y % (height + 8) >= height) return -1;
    const index = row * columns + column;
    return index < this.weeks.length ? index : -1;
  }

  private beginStroke(x: number, y: number): void {
    const index = this.indexAt(x, y);
    if (index < 0) return;
    this.painting = true;
    this.paintSelected = !this.chosen.includes(this.weeks[index]);
    this.lastIndex = index;
    this.onChoosingChanged(true);
    this.select(this.weeks[index], this.paintSelected);
  }

  private continueStroke(x: number, y: number): void {
    if (!this.painting) return;
    const index = this.indexAt(x, y);
    if (index < 0) return;
    const columns = this.weekdayMode ? 7 : 5;
    // Fill skipped cells on a fast horizontal stroke, without filling unrelated rows.
    const start = Math.floor(index / columns) === Math.floor(this.lastIndex / columns) ? this.lastIndex : index;
    for (let i = Math.min(start, index); i <= Math.max(start, index); i++) {
      this.select(this.weeks[i], this.paintSelected);
    }
    this.lastIndex = index;
    this.activeWeek = this.weeks[index];
  }

  private finishStroke(): void {
    this.painting = false;
    this.lastIndex = -1;
    this.activeWeek = -1;
    this.onChoosingChanged(false);
  }

  private select(week: number, selected: boolean): void {
    this.chosen = CourseDateSelection.toggle(this.chosen, week, selected);
  }

  @Builder
  cell(week: number) {
    CourseControlHost({
      barHeight: this.weekdayMode ? 38 : 44,
      onPressingChanged: (pressing: boolean) => {
        if (pressing) this.activeWeek = week;
        else if (this.activeWeek === week) this.activeWeek = -1;
      }
    }) {
      Text(this.weekdayMode ? ['一', '二', '三', '四', '五', '六', '日'][week - 1] : week.toString())
        .fontSize(this.weekdayMode ? HitaDesign.caption : HitaDesign.body)
        .fontWeight(FontWeight.Medium)
        .width('100%')
        .height(this.weekdayMode ? HitaDesign.controlHeight : HitaDesign.minTouchTarget)
        .textAlign(TextAlign.Center)
        .borderRadius(HitaDesign.radiusMd)
        .backgroundColor(this.chosen.includes(week) ? $r('app.color.hita_primary_fill') :
          $r('app.color.hita_surface_soft'))
        .fontColor(this.chosen.includes(week) ?
          (CompatibleSheetMaterial.isEnabled() ? $r('app.color.hita_primary_3390ec') : $r('app.color.hita_on_primary')) :
          $r('app.color.hita_text_202b45'))
        .attributeModifier(new CompatibleMaterialModifier(this.chosen.includes(week) ?
          $r('app.color.hita_primary_fill') : $r('app.color.hita_surface_soft'),
          this.chosen.includes(week), CompatibleSheetMaterial.isEnabled(),
          $r('app.color.hita_immersive_segment_selected'), false))
        .accessibilityText(this.weekdayMode ? '星期' + ['一', '二', '三', '四', '五', '六', '日'][week - 1] :
          '第' + week.toString() + '周')
        .accessibilitySelected(this.chosen.includes(week))
    }
  }

  @Builder
  addWeekCell() {
    CourseControlHost({
      barHeight: 44,
      onPressingChanged: (pressing: boolean) => {
        if (pressing) this.activeWeek = 0;
        else if (this.activeWeek === 0) this.activeWeek = -1;
      }
    }) {
      Button('+', { type: ButtonType.Normal })
        .width('100%')
        .height(44)
        .padding(0)
        .borderRadius(HitaDesign.radiusMd)
        .fontSize(HitaDesign.iconLg)
        .fontWeight(FontWeight.Medium)
        .backgroundColor($r('app.color.hita_surface_soft'))
        .fontColor($r('app.color.hita_primary_3390ec'))
        .attributeModifier(new CompatibleMaterialModifier($r('app.color.hita_surface_soft'), false,
          CompatibleSheetMaterial.isEnabled()))
        .accessibilityText('增加 5 个教学周')
        .onClick(() => this.onAddWeeks())
    }
  }

  build() {
    Grid() {
      ForEach(this.weeks, (week: number) => {
        GridItem() { this.cell(week) }
          .height(this.weekdayMode ? HitaDesign.controlHeight : HitaDesign.minTouchTarget)
          .clip(false)
          .zIndex(this.activeWeek === week ? 3 : 1)
          .onClick(() => this.select(week, !this.chosen.includes(week)))
      }, (week: number) => week.toString())
      if (!this.weekdayMode) {
        GridItem() { this.addWeekCell() }
          .height(44)
          .clip(false)
          .zIndex(this.activeWeek === 0 ? 3 : 1)
      }
    }
    .columnsTemplate(this.weekdayMode ? '1fr 1fr 1fr 1fr 1fr 1fr 1fr' : '1fr 1fr 1fr 1fr 1fr')
    .rowsGap(8)
    .columnsGap(this.weekdayMode ? 4 : 8)
    .width(CompatibleSheetMaterial.isEnabled() ?
      'calc(100% + ' + (COURSE_CONTROL_OVERFLOW * 2).toString() + 'vp)' : '100%')
    .padding(CompatibleSheetMaterial.isEnabled() ? COURSE_CONTROL_OVERFLOW : 0)
    .margin(CompatibleSheetMaterial.isEnabled() ? -COURSE_CONTROL_OVERFLOW : 0)
    // One vertical scroller owns the whole form, including every teaching week.
    .height((this.weekdayMode ? 38 : Math.ceil((this.weeks.length + 1) / 5) * 52 - 8) +
      (CompatibleSheetMaterial.isEnabled() ? COURSE_CONTROL_OVERFLOW * 2 : 0))
    .scrollBar(BarState.Off)
    .enableScrollInteraction(false)
    .clipContent(ContentClipMode.BOUNDARY)
    .onAreaChange((_old: Area, area: Area) => { this.gridWidth = Number(area.width); })
    .gesture(
      PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 8 })
        .onActionStart((event: GestureEvent) => {
          if (event.fingerList.length === 0) return;
          const finger = event.fingerList[0];
          this.beginStroke(finger.localX - event.offsetX, finger.localY - event.offsetY);
          this.continueStroke(finger.localX, finger.localY);
        })
        .onActionUpdate((event: GestureEvent) => {
          if (event.fingerList.length === 0) return;
          this.continueStroke(event.fingerList[0].localX, event.fingerList[0].localY);
        })
        .onActionEnd(() => this.finishStroke())
        .onActionCancel(() => this.finishStroke())
    )
  }
}
