import { HitaDesign } from '../theme/HitaDesign';
import { HitaColors } from '../theme/HitaColors';

export enum HitaButtonVariant {
  PRIMARY = 0,
  SECONDARY = 1,
  DANGER = 2,
  /** Cancel and other dismissive actions beside a primary button. */
  NEUTRAL = 3
}

class HitaButtonStyle implements AttributeModifier<ButtonAttribute> {
  private variant: HitaButtonVariant;
  private buttonHeight: number;
  private disabled: boolean;

  constructor(variant: HitaButtonVariant, buttonHeight: number, disabled: boolean) {
    this.variant = variant;
    this.buttonHeight = buttonHeight;
    this.disabled = disabled;
  }

  applyNormalAttribute(instance: ButtonAttribute): void {
    instance.height(this.buttonHeight)
      .fontSize(this.buttonHeight >= HitaDesign.buttonHeight ? HitaDesign.body : HitaDesign.caption)
      .fontWeight(FontWeight.Medium)
      .fontColor(HitaButton.foreground(this.variant))
      .backgroundColor(HitaButton.fill(this.variant))
      .enabled(!this.disabled);
  }
}

/**
 * Page and sheet buttons: a capsule on a solid fill. By default it spans its container; fitContent sizes it to the
 * label for inline actions such as retry. White text only ever sits on the PRIMARY fill, and no material modifier is
 * accepted, because a material replaces the fill and leaves white text unreadable in light mode.
 */
@Component
export struct HitaButton {
  @Prop label: string = '';
  @Prop variant: HitaButtonVariant = HitaButtonVariant.PRIMARY;
  @Prop buttonHeight: number = HitaDesign.buttonHeight;
  @Prop disabled: boolean = false;
  @Prop fitContent: boolean = false;
  onTap: () => void = () => {};

  build() {
    if (this.fitContent) {
      Button(this.label, { type: ButtonType.Capsule })
        .padding({ left: HitaDesign.spaceLg, right: HitaDesign.spaceLg })
        .attributeModifier(new HitaButtonStyle(this.variant, this.buttonHeight, this.disabled))
        .onClick(() => {
          this.onTap();
        });
    } else {
      Button(this.label, { type: ButtonType.Capsule })
        .width('100%')
        .attributeModifier(new HitaButtonStyle(this.variant, this.buttonHeight, this.disabled))
        .onClick(() => {
          this.onTap();
        });
    }
  }

  static foreground(variant: HitaButtonVariant): ResourceColor {
    if (variant === HitaButtonVariant.PRIMARY) return HitaColors.onPrimary;
    if (variant === HitaButtonVariant.DANGER) return HitaColors.error;
    if (variant === HitaButtonVariant.NEUTRAL) return HitaColors.onSurface;
    return HitaColors.primary;
  }

  static fill(variant: HitaButtonVariant): ResourceColor {
    if (variant === HitaButtonVariant.PRIMARY) return HitaColors.primaryFill;
    if (variant === HitaButtonVariant.DANGER) return HitaColors.errorSurface;
    if (variant === HitaButtonVariant.NEUTRAL) return HitaColors.control;
    return HitaColors.selected;
  }
}
