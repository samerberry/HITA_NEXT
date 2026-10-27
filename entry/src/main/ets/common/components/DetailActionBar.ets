import { HitaDesign } from '../theme/HitaDesign';
import { CompatibleMaterialModifier } from '../theme/CompatibleMaterialModifier';
import { CompatibleSheetMaterial } from '../theme/CompatibleSheetMaterial';
import { ImmersiveHeader } from './ImmersiveHeader';

/** Compact, trailing actions shared by course and exam detail sheets. */
@Component
export struct DetailActionBar {
  @Prop deleteLabel: string = '删除';
  @Prop busy: boolean = false;
  onEdit: () => void = () => {};
  onDelete: () => void = () => {};

  build() {
    Column() {
      ImmersiveHeader({ barHeight: 44, materialEnabled: CompatibleSheetMaterial.isEnabled() }) {
        Row({ space: 8 }) {
          Button('编辑', { type: ButtonType.Capsule })
            .height(36).padding({ left: 16, right: 16 }).fontSize(HitaDesign.caption)
            .responseRegion({ x: 0, y: -4, width: '100%', height: 44 })
            .fontWeight(FontWeight.Medium)
            .fontColor(CompatibleSheetMaterial.isEnabled() ?
              CompatibleMaterialModifier.foreground($r('app.color.hita_primary')) : $r('app.color.hita_primary'))
            .backgroundColor($r('app.color.hita_selected'))
            .attributeModifier(new CompatibleMaterialModifier($r('app.color.hita_selected'), false,
              CompatibleSheetMaterial.isEnabled()))
            .enabled(!this.busy).onClick(() => this.onEdit());
          Button(this.deleteLabel, { type: ButtonType.Capsule })
            .height(36).padding({ left: 16, right: 16 }).fontSize(HitaDesign.caption)
            .responseRegion({ x: 0, y: -4, width: '100%', height: 44 })
            .fontWeight(FontWeight.Medium).fontColor($r('app.color.hita_on_primary'))
            .backgroundColor($r('app.color.hita_error_fill'))
            .attributeModifier(new CompatibleMaterialModifier($r('app.color.hita_error_fill'), true,
              CompatibleSheetMaterial.isEnabled(), $r('app.color.hita_error_fill'), false))
            .enabled(!this.busy).onClick(() => this.onDelete());
        }
        .width('100%').height(44).justifyContent(FlexAlign.End);
      }
    }
    .width('100%').margin({ top: 12 });
  }
}
