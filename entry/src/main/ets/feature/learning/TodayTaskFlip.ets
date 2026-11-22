import { matrix4 } from '@kit.ArkUI';

function unit(value: number): number {
  return Math.max(0, Math.min(1, value));
}

// Slot 0 faces the viewer; positive depths are behind it. The same path runs
// backwards when the user swipes up or releases an incomplete turn.
export function taskFlipProjection(depth: number, width: number, height: number): matrix4.Matrix4Transit {
  if (width <= 0 || height <= 0 || depth === 0) return matrix4.identity();
  const fold: number = unit(-depth);
  const back: number = unit(depth);
  const hidden: number = unit(depth - 1);
  // In the reference the lower edge dips only slightly. The upper edge travels
  // nearly the full height, and the lower corners converge more than the upper ones.
  const top: number = height * (0.97 * fold - 0.04 * back + 0.13 * hidden);
  const bottom: number = height * (1 + 0.11 * Math.sin(Math.PI * fold) -
    0.14 * back + 0.13 * hidden);
  const topInset: number = width * (0.055 * fold + 0.050 * back);
  const bottomInset: number = topInset + width * (0.070 * Math.sin(Math.PI * fold));
  return matrix4.identity().setPolyToPoly({
    src: [{ x: 0, y: 0 }, { x: width, y: 0 }, { x: 0, y: height }, { x: width, y: height }],
    dst: [{ x: topInset, y: top }, { x: width - topInset, y: top },
      { x: bottomInset, y: bottom }, { x: width - bottomInset, y: bottom }],
    srcIndex: 0, dstIndex: 0, pointCount: 4
  });
}

export function taskFlipOpacity(depth: number): number {
  if (depth >= 0) return 1 - unit(depth - 1);
  // The lower card remains legible while the next title is being revealed.
  const fade: number = unit((-depth - 0.32) / 0.68);
  return 1 - fade * fade * (3 - 2 * fade);
}

// Cubic Hermite interpolation: match the release speed, stop at rest, and do
// not overshoot. The geometry and the fade are sampled from this same progress.
export function taskFlipRelease(time: number, initialSlope: number): number {
  const t: number = unit(time);
  return t * t * (3 - 2 * t) + initialSlope * t * (1 - t) * (1 - t);
}
