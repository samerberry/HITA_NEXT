import { HitaDesign } from '../theme/HitaDesign';
import { HitaColors } from '../theme/HitaColors';
import { CompatibleMaterialModifier } from '../theme/CompatibleMaterialModifier';

@Component
export struct HeaderBackButton {
  @Prop accessibilityLabel: string = '返回';
  onBack: () => void = () => {};

  build() {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph($r('sys.symbol.chevron_left'))
        .fontSize(HitaDesign.iconMd)
        .fontWeight(FontWeight.Regular)
        .fontColor([CompatibleMaterialModifier.foreground(HitaColors.onSurface)]);
    }
    .width(44)
    .height(44)
    .padding(0)
    .flexShrink(0)
    .backgroundColor($r('app.color.hita_control'))
    .attributeModifier(new CompatibleMaterialModifier($r('app.color.hita_control')))
    .accessibilityText(this.accessibilityLabel)
    .onClick(() => {
      this.onBack();
    });
  }
}
