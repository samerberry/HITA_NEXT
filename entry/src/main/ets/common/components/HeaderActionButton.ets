import { HitaDesign } from '../theme/HitaDesign';
import { HitaColors } from '../theme/HitaColors';
import { CompatibleMaterialModifier } from '../theme/CompatibleMaterialModifier';

/**
 * Text action on the trailing side of a page or sheet header. Pass the host header's materialEnabled: on a material
 * the label follows the system foreground, otherwise it is brand text on the brand tint.
 */
@Component
export struct HeaderActionButton {
  @Prop label: string = '';
  @Prop disabled: boolean = false;
  @Prop materialEnabled: boolean = true;
  onTap: () => void = () => {};

  build() {
    Button(this.label, { type: ButtonType.Capsule })
      .height(HitaDesign.compactControlHeight)
      .padding({ left: HitaDesign.spaceMd, right: HitaDesign.spaceMd })
      .fontSize(HitaDesign.caption)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.materialEnabled ? CompatibleMaterialModifier.foreground(HitaColors.primary) : HitaColors.primary)
      .backgroundColor(HitaColors.selected)
      .attributeModifier(new CompatibleMaterialModifier(HitaColors.selected, false, this.materialEnabled))
      .flexShrink(0)
      .responseRegion({ x: 0, y: (HitaDesign.compactControlHeight - HitaDesign.minTouchTarget) / 2, width: '100%',
        height: HitaDesign.minTouchTarget })
      .enabled(!this.disabled)
      .onClick(() => {
        this.onTap();
      });
  }
}
