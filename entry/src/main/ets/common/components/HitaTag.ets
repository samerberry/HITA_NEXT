import { HitaDesign } from '../theme/HitaDesign';
import { HitaColors } from '../theme/HitaColors';

export enum HitaTagTone {
  BRAND = 0,
  SUCCESS = 1,
  DANGER = 2,
  /** The exam category color used by exam rows and countdowns. */
  EXAM = 3,
  NEUTRAL = 4,
  /** Light chip on the solid primary hero card. */
  ON_PRIMARY = 5
}

/** Capsule status label. Colors come from the tone only, so pages never pair foreground and background by hand. */
@Component
export struct HitaTag {
  @Prop text: string = '';
  @Prop tone: HitaTagTone = HitaTagTone.BRAND;

  build() {
    Text(this.text)
      .fontSize(HitaDesign.label)
      .fontWeight(FontWeight.Medium)
      .fontColor(HitaTag.foreground(this.tone))
      .backgroundColor(HitaTag.background(this.tone))
      .padding({ left: HitaDesign.spaceXs, right: HitaDesign.spaceXs, top: HitaDesign.space2xs,
        bottom: HitaDesign.space2xs })
      // A 12 fp line plus 4 vp above and below is 24 vp tall, so this radius draws a capsule.
      .borderRadius(HitaDesign.radiusMd)
      .maxLines(1)
      .flexShrink(0);
  }

  static foreground(tone: HitaTagTone): ResourceColor {
    if (tone === HitaTagTone.SUCCESS) return $r('app.color.hita_success');
    if (tone === HitaTagTone.DANGER) return HitaColors.error;
    if (tone === HitaTagTone.EXAM) return $r('app.color.hita_error_8a2e42');
    if (tone === HitaTagTone.NEUTRAL) return HitaColors.onSurfaceVariant;
    if (tone === HitaTagTone.ON_PRIMARY) return $r('app.color.hita_on_primary');
    return HitaColors.primary;
  }

  static background(tone: HitaTagTone): ResourceColor {
    if (tone === HitaTagTone.SUCCESS) return $r('app.color.hita_success_surface');
    if (tone === HitaTagTone.DANGER || tone === HitaTagTone.EXAM) return HitaColors.errorSurface;
    if (tone === HitaTagTone.NEUTRAL) return HitaColors.control;
    if (tone === HitaTagTone.ON_PRIMARY) return $r('app.color.hita_hero_chip');
    return HitaColors.selected;
  }
}
