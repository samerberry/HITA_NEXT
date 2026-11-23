import { HitaDesign } from '../theme/HitaDesign';
import { HitaColors } from '../theme/HitaColors';

export enum HitaButtonVariant {
  PRIMARY = 0,
  SECONDARY = 1,
  DANGER = 2,
  /** Cancel and other dismissive actions beside a primary button. */
  NEUTRAL = 3
}

// Native attributes also run in the launcher form renderer, where attributeModifier is unavailable.
@Extend(Button)
function hitaButtonStyle(variant: HitaButtonVariant, buttonHeight: number, disabled: boolean) {
  .height(buttonHeight)
  .fontSize(buttonHeight >= HitaDesign.buttonHeight ? HitaDesign.body : HitaDesign.caption)
  .fontWeight(FontWeight.Medium)
  .fontColor(HitaButton.foreground(variant))
  .backgroundColor(HitaButton.fill(variant))
  .enabled(!disabled)
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
        .hitaButtonStyle(this.variant, this.buttonHeight, this.disabled)
        .onClick(() => {
          this.onTap();
        });
    } else {
      Button(this.label, { type: ButtonType.Capsule })
        .width('100%')
        .hitaButtonStyle(this.variant, this.buttonHeight, this.disabled)
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
