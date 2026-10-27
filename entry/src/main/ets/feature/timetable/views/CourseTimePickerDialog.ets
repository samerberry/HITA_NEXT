import { HitaDesign } from '../../../common/theme/HitaDesign';
import { ImmersiveHeader } from '../../../common/components/ImmersiveHeader';
import { CompatibleMaterialModifier } from '../../../common/theme/CompatibleMaterialModifier';
import { CompatiblePickerMaterial } from '../../../common/theme/CompatiblePickerMaterial';
import { CompatibleLightModifier } from '../../../common/theme/CompatibleLightModifier';

/** Time-only picker: no calendar title or unrelated date is displayed. */
@CustomDialog
export struct CourseTimePickerDialog {
  controller: CustomDialogController;
  initialHour: number = 0;
  initialMinute: number = 0;
  title: string = '';
  immersive: boolean = false;
  onAccept: (hour: number, minute: number) => boolean = () => true;
  @State private hour: number = 0;
  @State private minute: number = 0;

  aboutToAppear(): void {
    this.hour = this.initialHour;
    this.minute = this.initialMinute;
  }

  build() {
    Column({ space: 12 }) {
      Text(this.title)
        .fontSize(HitaDesign.section)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.hita_text_202b45'))
      TimePicker({ selected: new Date(2000, 0, 1, this.hour, this.minute), format: TimePickerFormat.HOUR_MINUTE })
        .useMilitaryTime(true)
        .width('100%')
        .height(216)
        .onChange((value: TimePickerResult) => {
          this.hour = value.hour;
          this.minute = value.minute;
        })
      ImmersiveHeader({ barHeight: 44, materialEnabled: this.immersive && CompatiblePickerMaterial.isEnabled() }) {
        Row({ space: 12 }) {
          Button('取消', { type: ButtonType.Capsule })
            .layoutWeight(1).height(44)
            .backgroundColor($r('app.color.hita_surface_soft'))
            .fontColor($r('app.color.hita_text_202b45'))
            .attributeModifier(new CompatibleMaterialModifier($r('app.color.hita_surface_soft'), false,
              this.immersive && CompatiblePickerMaterial.isEnabled()))
            .onClick(() => this.controller.close())
          Button('确定', { type: ButtonType.Capsule })
            .layoutWeight(1).height(44)
            .backgroundColor($r('app.color.hita_primary_fill'))
            .fontColor(this.immersive && CompatiblePickerMaterial.isEnabled() ?
              $r('sys.color.ohos_id_color_text_primary') : $r('app.color.hita_on_primary'))
            .attributeModifier(new CompatibleMaterialModifier($r('app.color.hita_primary_fill'), false,
              this.immersive && CompatiblePickerMaterial.isEnabled()))
            .onClick(() => {
              if (this.onAccept(this.hour, this.minute)) this.controller.close();
            })
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(20)
    .attributeModifier(new CompatibleLightModifier(24, this.immersive && CompatiblePickerMaterial.isEnabled(), true))
  }
}
