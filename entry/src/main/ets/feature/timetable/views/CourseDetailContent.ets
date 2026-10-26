import { HitaDesign } from '../../../common/theme/HitaDesign';
import { EasEventItem, EasEventType } from '../../../common/model/timetable/TimetableModels';
import { EasTimeTools } from '../../../common/util/EasTimeTools';
import { ImmersiveHeader } from '../../../common/components/ImmersiveHeader';
import { CirclePaintModifier } from '../../../common/theme/CirclePaintModifier';
import { CompatibleMaterialModifier } from '../../../common/theme/CompatibleMaterialModifier';
import { CompatibleSheetMaterial } from '../../../common/theme/CompatibleSheetMaterial';
import { CompatibleLightModifier } from '../../../common/theme/CompatibleLightModifier';
import { CourseColorEditor } from './CourseColorEditor';
import { timetableBlockColor } from './TimetableWeekDraw';
const COURSE_DETAIL_ICON_SIZE: number = 38;
const COURSE_DETAIL_TEXT_GAP: number = 12;
const COLOR_TEXT_PRIMARY: ResourceColor = $r('app.color.hita_text');
const COLOR_TEXT_SECONDARY: ResourceColor = $r('app.color.hita_text_secondary');
const COLOR_PRIMARY: ResourceColor = $r('app.color.hita_primary');
const COLOR_NAV_ACTIVE: ResourceColor = $r('app.color.hita_selected');

/** Shared course details for the timetable and its management page. */
@Component
export struct CourseDetailContent {
  @Prop event: EasEventItem = new EasEventItem();
  @Prop endTime: number = 0;
  @Prop periodText: string = '';
  @Prop dateText: string = '';
  @Prop progressText: string = '';
  @Prop deleteLabel: string = '翘课';
  @Prop textColor: string = '#FFFFFF';
  @Prop busy: boolean = false;
  @Link courseColorEditing: boolean;
  @Link courseColorPreview: number;
  onSaveColor: (color: number) => Promise<void> = async (_color: number) => {};
  onEdit: () => void = () => {};
  onDelete: () => void = () => {};
  build() {
    Column() {
      Row() {
        Circle()
          .width(COURSE_DETAIL_ICON_SIZE)
          .height(COURSE_DETAIL_ICON_SIZE)
          .flexShrink(0)
          .attributeModifier(new CirclePaintModifier(CourseDetailContent.canvasColorCss(timetableBlockColor(
            this.courseColorEditing ? this.courseColorPreview : this.event.color))));
        Column() {
          Text(this.event.name === 'NULL' || this.event.name.length === 0 ? '未命名课程' : this.event.name)
            .fontSize(HitaDesign.title)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLOR_TEXT_PRIMARY)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
          Text(this.event.type === EasEventType.EXAM ? '考试详情' : '课程详情')
            .fontSize(HitaDesign.caption)
            .fontColor(COLOR_TEXT_SECONDARY)
            .margin({ top: 4 });
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ left: COURSE_DETAIL_TEXT_GAP });
        if (this.event.type === EasEventType.EXAM ||
          (this.event.type === EasEventType.CLASS && this.event.subjectId.length > 0)) {
          Column() {
            ImmersiveHeader({ barHeight: 44, materialEnabled: CompatibleSheetMaterial.isEnabled() }) {
              Button({ type: ButtonType.Circle }) {
                SymbolGlyph($r('sys.symbol.paintpalette')).fontSize(HitaDesign.title)
                  .fontColor([CompatibleSheetMaterial.isEnabled() ? CompatibleMaterialModifier.foreground(COLOR_PRIMARY) :
                    COLOR_PRIMARY]);
              }
              .width(44).height(44).padding(0).flexShrink(0)
              .backgroundColor(COLOR_NAV_ACTIVE)
              .attributeModifier(new CompatibleMaterialModifier(COLOR_NAV_ACTIVE, false, CompatibleSheetMaterial.isEnabled()))
              .accessibilityText(this.event.type === EasEventType.EXAM ? '修改考试颜色' : '修改课程颜色')
              .onClick(() => {
                this.courseColorPreview = this.event.color;
                this.courseColorEditing = !this.courseColorEditing;
              });
            }
          }
          .width(44).height(44).flexShrink(0);
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ bottom: 14 });

      if (this.courseColorEditing) {
        CourseColorEditor({
          initialColor: this.event.color,
          immersiveControls: true,
          examMode: this.event.type === EasEventType.EXAM,
          textColor: this.textColor,
          onPreview: (color: number) => { this.courseColorPreview = color; },
          onSave: async (color: number) => { await this.onSaveColor(color); },
          onCancel: () => { this.courseColorEditing = false; }
        })
      } else {
      this.courseDetailRow($r('sys.symbol.person_crop_circle_fill'), '老师',
        this.event.teacher.trim().length > 0 ? this.event.teacher : '无');
      this.courseDetailRow($r('sys.symbol.pin'), this.event.type === EasEventType.EXAM ? '考场' : '教室',
        this.event.place.trim().length > 0 ? this.event.place : '无');
      this.courseDetailRow($r('sys.symbol.clock'), '时间',
        EasTimeTools.printTime(this.event.from) + ' - ' + EasTimeTools.printTime(this.endTime));
      if (this.event.type !== EasEventType.EXAM) {
        this.courseDetailRow($r('sys.symbol.doc_plaintext'), '节次', this.periodText);
      }
      this.courseDetailRow($r('sys.symbol.calendar'), '日期', this.dateText);
      if (this.event.type === EasEventType.EXAM) {
        this.courseDetailRow($r('sys.symbol.checkmark'), '类型', '考试');
      } else {
        this.courseDetailRow($r('sys.symbol.repeat_1'), '课程进度', this.progressText);
      }
      if (this.event.type === EasEventType.CLASS) {
        Column() {
          ImmersiveHeader({ barHeight: 56, materialEnabled: CompatibleSheetMaterial.isEnabled() }) {
            Row({ space: 8 }) {
              Button('编辑', { type: ButtonType.Capsule })
                .height(HitaDesign.buttonHeight).padding({ left: 20, right: 20 }).fontSize(HitaDesign.body)
                .fontWeight(FontWeight.Medium).fontColor(CompatibleSheetMaterial.isEnabled() ?
                  CompatibleMaterialModifier.foreground(COLOR_PRIMARY) : COLOR_PRIMARY)
                .backgroundColor(COLOR_NAV_ACTIVE)
                .attributeModifier(new CompatibleMaterialModifier(COLOR_NAV_ACTIVE, false, CompatibleSheetMaterial.isEnabled()))
                .enabled(!this.busy).onClick(() => this.onEdit());
              Button(this.deleteLabel, { type: ButtonType.Capsule })
                .height(HitaDesign.buttonHeight)
                .padding({ left: 20, right: 20 })
                .fontSize(HitaDesign.body)
                .fontWeight(FontWeight.Medium)
                .fontColor('#FFFFFF')
                .backgroundColor($r('app.color.hita_error_fill'))
                .attributeModifier(new CompatibleMaterialModifier($r('app.color.hita_error_fill'), true,
                  CompatibleSheetMaterial.isEnabled(), $r('app.color.hita_error_fill'), false))
                .enabled(!this.busy)
                .onClick(() => { this.onDelete(); });
            }
            .width('100%')
            .height(56)
            .justifyContent(FlexAlign.End);
          }
        }
        .width('100%')
        .margin({ top: 12 });
      }
      }
    }
    .width('100%')
    .padding({ left: HitaDesign.inset, right: HitaDesign.inset, top: 0, bottom: 24 })
    .attributeModifier(new CompatibleLightModifier(24, CompatibleSheetMaterial.isEnabled(), true));
  }

  @Builder
  courseDetailRow(symbol: Resource, label: string, value: string) {
    Row() {
      Stack() {
        SymbolGlyph(symbol)
          .fontSize(20)
          .fontColor([COLOR_PRIMARY]);
      }
      .width(COURSE_DETAIL_ICON_SIZE)
      .height(COURSE_DETAIL_ICON_SIZE)
      .borderRadius(COURSE_DETAIL_ICON_SIZE / 2)
      .flexShrink(0)
      .backgroundColor(COLOR_NAV_ACTIVE)
      .alignContent(Alignment.Center);
      Column() {
        Text(label)
          .fontSize(HitaDesign.label)
          .fontColor(COLOR_TEXT_SECONDARY);
        Text(value)
          .fontSize(HitaDesign.body)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT_PRIMARY)
          .margin({ top: 2 })
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: COURSE_DETAIL_TEXT_GAP });
    }
    .width('100%')
    .constraintSize({ minHeight: 64 })
    .padding({ top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center);
  }

  private static canvasColorCss(argb: number): string {
    return 'rgb(' + ((argb >> 16) & 255).toString() + ',' + ((argb >> 8) & 255).toString() + ',' + (argb & 255).toString() + ')';
  }
}
