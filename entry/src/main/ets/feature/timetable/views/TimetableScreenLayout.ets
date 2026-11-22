import { display } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';

const COMPACT_PANEL_SHORT_EDGE_VP: number = 600;

/** Use the active panel, not the app window: rotation and split screen do not change the form factor. */
export function usesPhoneTimetable(): boolean {
  if (deviceInfo.deviceType !== 'phone') return false;
  try {
    if (!display.isFoldable()) return true;
    const mode = display.getFoldDisplayMode();
    // MAIN is a book fold's cover, a flip's inner screen, or a tri-fold's single panel.
    if (mode === display.FoldDisplayMode.FOLD_DISPLAY_MODE_MAIN ||
      mode === display.FoldDisplayMode.FOLD_DISPLAY_MODE_SUB) return true;
    // Book folds and multi-panel tri-folds are wide. Keep a compact, phone-shaped
    // inner panel readable even when the device reports it as a full display.
    const screen = display.getDefaultDisplaySync();
    const shortEdge = Math.min(screen.width, screen.height);
    const longEdge = Math.max(screen.width, screen.height);
    return shortEdge / screen.densityPixels < COMPACT_PANEL_SHORT_EDGE_VP && longEdge > shortEdge * 1.5;
  } catch (_) {
    return true;
  }
}

export function observeTimetableFoldMode(redraw: () => void): (() => void) | undefined {
  try {
    if (!display.isFoldable()) return undefined;
    display.on('foldDisplayModeChange', redraw);
    return () => { display.off('foldDisplayModeChange', redraw); };
  } catch (_) {
    return undefined;
  }
}
