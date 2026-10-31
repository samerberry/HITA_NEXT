/** Three page tabs followed by the native assistant action. */
export const DOCK_ITEM_COUNT: number = 4;
export const DOCK_WIDTH: number = 280;
/** Centre the navigation capsule, gap and independent action as one 280 vp group. */
export const DOCK_NAV_WIDTH: number = 216;
export const DOCK_NATIVE_PADDING: number = 12;
export const DOCK_ACTION_SIZE: number = 56;
export const DOCK_ACTION_START: number = 224;

export function dockItemCenter(index: number, padding: number = DOCK_NATIVE_PADDING): number {
  if (padding === DOCK_NATIVE_PADDING && index === 3) return DOCK_ACTION_START + DOCK_ACTION_SIZE / 2;
  return padding + (index + 0.5) * (DOCK_WIDTH - padding * 2) / DOCK_ITEM_COUNT;
}
/** Distance from the screen edge when the dock follows the holding hand. */
export const DOCK_SIDE_MARGIN: number = 16;
export const DOCK_HANDEDNESS_DURATION: number = 300;
/** The side rail reuses the dock capsule, turned upright. */
export const DOCK_RAIL_THICKNESS: number = 56;
/** Content keeps clear of the rail: edge margin + rail + 8 vp breathing room. */
export const DOCK_RAIL_INSET: number = DOCK_SIDE_MARGIN + DOCK_RAIL_THICKNESS + 8;
/** Tablet windows narrower than this (split screen, floating window) keep the bottom dock. */
export const DOCK_RAIL_MIN_TABLET_WIDTH: number = 600;

/** -1 = left hand, 0 = centered, 1 = right hand. */
export function dockSideOffset(containerWidth: number, side: number): number {
  if (side === 0 || !Number.isFinite(containerWidth)) return 0;
  const travel: number = Math.max(0, (containerWidth - DOCK_WIDTH) / 2 - DOCK_SIDE_MARGIN);
  if (travel === 0) return 0;
  return side < 0 ? -travel : travel;
}

/**
 * Tablets and fully unfolded tri-folds use a side rail. Phones in landscape and
 * dual-folds keep the bottom dock, which their width alone cannot distinguish.
 */
export function dockRailMode(width: number, height: number, tablet: boolean, foldRail: boolean): boolean {
  if (!Number.isFinite(width) || !Number.isFinite(height) || height < DOCK_WIDTH + DOCK_SIDE_MARGIN * 2) {
    return false;
  }
  // Portrait keeps the phone-style bottom dock; the rail only takes the long edge of a landscape screen.
  if (width <= height) return false;
  return foldRail || (tablet && width >= DOCK_RAIL_MIN_TABLET_WIDTH);
}

/** The rail has no centred position: it starts on the left and follows the hand. */
/** Same depth as the bottom bar's 92 vp mask, measured from the rail's edge. */
export const DOCK_RAIL_MASK_WIDTH: number = 92;
/** An opened wide fold has a landscape inner screen; book-style folds open close to square. */
export const DOCK_WIDE_FOLD_RATIO: number = 1.4;

export function dockWideFoldScreen(width: number, height: number): boolean {
  if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) return false;
  return Math.max(width, height) / Math.min(width, height) >= DOCK_WIDE_FOLD_RATIO;
}

/** Rail travel that fully clears the screen edge, including the material shadow. */
export const DOCK_RAIL_EXIT: number = DOCK_SIDE_MARGIN + DOCK_RAIL_THICKNESS + 16;

/** Floating timetable controls centred on the rail column, inside the side gutter. */
export const DOCK_GUTTER_ACTION_EDGE: number = DOCK_SIDE_MARGIN + DOCK_RAIL_THICKNESS / 2 - 24;

export function dockRailOnRight(side: number): boolean {
  return side > 0;
}
