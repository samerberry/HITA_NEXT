import { matrix4 } from '@kit.ArkUI';

function unit(value: number): number {
  return Math.max(0, Math.min(1, value));
}

// Negative depths fold toward the left edge. Positive depths sit behind the
// front card and move in from the right. Reversing progress reverses both paths.
export function taskFlipProjection(depth: number, width: number, height: number,
  spacing: number): matrix4.Matrix4Transit {
  if (width <= 0 || height <= 0 || depth === 0) return matrix4.identity();
  const fold: number = unit(-depth);
  const back: number = Math.max(0, depth);
  const scale: number = Math.pow(0.95, back);
  const inset: number = width * (1 - scale) / 2;
  const shift: number = width * (0.065 * Math.sin(Math.PI * unit(back)) - 0.18 * fold);
  const left: number = inset + shift;
  const right: number = width - inset + shift - width * 0.78 * fold;
  const bottom: number = height + back * spacing;
  const top: number = bottom - height * scale;
  const nearInset: number = height * 0.025 * fold;
  const farInset: number = height * (0.045 * fold + 0.12 * Math.sin(Math.PI * fold));
  return matrix4.identity().setPolyToPoly({
    src: [{ x: 0, y: 0 }, { x: width, y: 0 }, { x: 0, y: height }, { x: width, y: height }],
    dst: [{ x: left, y: top + nearInset }, { x: right, y: top + farInset },
      { x: left, y: bottom - nearInset }, { x: right, y: bottom - farInset }],
    srcIndex: 0, dstIndex: 0, pointCount: 4
  });
}

export function taskFlipOpacity(depth: number, maxDepth: number): number {
  if (depth >= 0) return 1 - unit(depth - maxDepth);
  // The front card remains legible while revealing the card behind it.
  const fade: number = unit((-depth - 0.32) / 0.68);
  return 1 - fade * fade * (3 - 2 * fade);
}

export function taskFlipTarget(offset: number, width: number, velocity: number, minFlingDistance: number): number {
  const threshold: number = Math.max(48, Math.min(96, width * 0.20));
  const direction: number = Math.sign(offset);
  const distance: number = Math.abs(offset);
  return distance >= threshold || (distance >= minFlingDistance && direction * velocity >= 500) ? direction : 0;
}

// Match the release speed and stop at rest. The geometry and the fade are sampled from the same progress.
export function taskFlipRelease(time: number, initialSlope: number): number {
  const t: number = unit(time);
  return t * t * (3 - 2 * t) + initialSlope * t * (1 - t) * (1 - t);
}
