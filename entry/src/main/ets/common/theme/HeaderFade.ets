/**
 * HeaderFade.ets — 抬头渐隐层的共享参数：列表滚入抬头下方时随滚动淡入，
 * 由下至上不透明度渐高（与功能中心抬头一致），供 HeaderFadeMask 组件使用。
 */
export class HeaderFade {
  /** 抬头下方渐隐区的高度（vp）。 */
  static readonly HEIGHT: number = 28;
  /** 滚动超过该距离（vp）后遮罩完全显现。 */
  static readonly DISTANCE: number = 24;
  /** 渐隐条（贴在不透明抬头下方）的色标，offset 与 alpha 一一对应。 */
  static readonly OFFSETS: number[] = [0, 0.3, 0.68, 1];
  static readonly ALPHAS: number[] = [1, 0.82, 0.36, 0];
  /** 透明抬头的色标（遮罩覆盖抬头 + 下方渐隐区），标题区几乎完全遮住下层内容。 */
  static readonly HEADER_OFFSETS: number[] = [0, 0.55, 0.78, 1];
  static readonly HEADER_ALPHAS: number[] = [1, 0.96, 0.6, 0];

  static opacity(scrollOffset: number): number {
    return Math.max(0, Math.min(1, scrollOffset / HeaderFade.DISTANCE));
  }

  /** ARGB 颜色叠在 rgb（'r,g,b'）底色上的合成结果，同样以 'r,g,b' 返回。 */
  static blendRgb(rgb: string, argb: number): string {
    const base: number[] = rgb.split(',').map((part: string): number => Number(part.trim()));
    const alpha: number = ((argb >>> 24) & 255) / 255;
    const top: number[] = [(argb >>> 16) & 255, (argb >>> 8) & 255, argb & 255];
    const mixed: number[] = [];
    for (let i: number = 0; i < 3; i++) {
      mixed.push(Math.round(top[i] * alpha + base[i] * (1 - alpha)));
    }
    return mixed.join(',');
  }

  /** rgb 形如 '245,246,248'。 */
  static rgba(rgb: string, alpha: number): string {
    return 'rgba(' + rgb + ',' + alpha.toFixed(3) + ')';
  }
}
