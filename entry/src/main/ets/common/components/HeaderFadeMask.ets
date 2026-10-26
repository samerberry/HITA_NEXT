/**
 * HeaderFadeMask.ets — 抬头渐隐遮罩，透明度随列表滚动偏移淡入，不拦截触摸。
 *
 * headerHeight > 0 时为透明抬头模式（同功能中心）：遮罩覆盖整个抬头并向下延伸渐隐；
 * 否则只在不透明抬头下方画一条渐隐条。
 * fromBottom 时方向反过来，用于输入栏等底部抬头。
 * highlight 为非零 ARGB 时，从 highlightTop 往下、[highlightLeft, highlightLeft + highlightWidth)
 * 这一块改用“底色 + 高亮”的合成色。下方固定的同色高亮列被遮住时，合成结果仍是同一层颜色，
 * 不会被洗白，也不会叠出第二层。
 */
import { HeaderFade } from '../theme/HeaderFade';

@Component
export struct HeaderFadeMask {
  @StorageProp('hita_appearance_dark') darkMode: boolean = false;
  @Prop maskOpacity: number = 0;
  /** 与遮罩下方页面底色一致的 RGB 分量。 */
  @Prop rgb: string = '245,246,248';
  @Prop headerHeight: number = 0;
  @Prop fromBottom: boolean = false;
  @Prop highlight: number = 0;
  @Prop highlightLeft: number = 0;
  @Prop highlightWidth: number = 0;
  @Prop highlightTop: number = 0;
  @Prop maskWidth: number = 0;

  build() {
    if (this.hasHighlight()) {
      Stack({ alignContent: Alignment.TopStart }) {
        // Four non-overlapping windows onto the same full-height gradient.
        this.slice(0, 0, this.highlightLeft, this.fullHeight(), false)
        this.slice(this.highlightLeft, 0, this.highlightWidth, this.highlightTop, false)
        this.slice(this.highlightLeft, this.highlightTop, this.highlightWidth,
          this.fullHeight() - this.highlightTop, true)
        this.slice(this.highlightLeft + this.highlightWidth, 0,
          Math.max(0, this.maskWidth - this.highlightLeft - this.highlightWidth), this.fullHeight(), false)
      }
      .width('100%')
      .height(this.fullHeight())
      .opacity(this.maskOpacity)
      .hitTestBehavior(HitTestMode.None)
    } else {
      Column()
        .width('100%')
        .height(this.fullHeight())
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: this.stops(this.baseRgb())
        })
        .opacity(this.maskOpacity)
        .hitTestBehavior(HitTestMode.None)
    }
  }

  @Builder
  slice(x: number, y: number, w: number, h: number, highlighted: boolean) {
    Column() {
      Column()
        .width(w)
        .height(this.fullHeight())
        .position({ x: 0, y: -y })
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: this.stops(highlighted ? HeaderFade.blendRgb(this.baseRgb(), this.highlight) : this.baseRgb())
        })
    }
    .position({ x: x, y: y })
    .width(w)
    .height(Math.max(0, h))
    .clip(true)
  }

  private hasHighlight(): boolean {
    return this.highlight !== 0 && this.highlightWidth > 0 && this.maskWidth > 0 &&
      this.highlightTop >= 0 && this.highlightTop < this.fullHeight();
  }

  private fullHeight(): number {
    return this.headerHeight + HeaderFade.HEIGHT;
  }

  private baseRgb(): string {
    return this.darkMode ? '16,18,20' : this.rgb;
  }

  private stops(rgb: string = this.baseRgb()): Array<[ResourceColor, number]> {
    const offsets: number[] = this.headerHeight > 0 ? HeaderFade.HEADER_OFFSETS : HeaderFade.OFFSETS;
    const alphas: number[] = this.headerHeight > 0 ? HeaderFade.HEADER_ALPHAS : HeaderFade.ALPHAS;
    const stops: Array<[ResourceColor, number]> = [];
    if (this.fromBottom) {
      for (let i: number = offsets.length - 1; i >= 0; i--) {
        stops.push([HeaderFade.rgba(rgb, alphas[i]), 1 - offsets[i]]);
      }
    } else {
      for (let i: number = 0; i < offsets.length; i++) {
        stops.push([HeaderFade.rgba(rgb, alphas[i]), offsets[i]]);
      }
    }
    return stops;
  }
}
