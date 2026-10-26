import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import lazy { motion } from '@kit.MultimodalAwarenessKit';

export const HOLDING_HAND_STABLE_DELAY: number = 80;

/** Subscribe only while actions are available; capability detection also covers foldables. */
export class HoldingHandObserver {
  private started: boolean = false;
  private generation: number = 0;
  private timer: number = -1;
  private callback: ((status: motion.HoldingHandStatus) => void) | undefined = undefined;

  /** Returns whether grip readings will be delivered; otherwise `onUnavailable` runs once. */
  start(onSide: (left: boolean) => void, onUnavailable?: () => void): boolean {
    if (this.started) return this.callback !== undefined;
    this.started = true;
    if (deviceInfo.sdkApiVersion < 20 || !canIUse('SystemCapability.MultimodalAwareness.Motion')) {
      if (onUnavailable !== undefined) onUnavailable(); else onSide(false);
      return false;
    }
    const generation = ++this.generation;
    const callback = (status: motion.HoldingHandStatus): void => {
      if (!this.started || generation !== this.generation) return;
      if (this.timer >= 0) clearTimeout(this.timer);
      this.timer = -1;
      // Both hands, no grip and unknown readings retain the last stable side.
      if (status !== motion.HoldingHandStatus.LEFT_HAND_HELD &&
        status !== motion.HoldingHandStatus.RIGHT_HAND_HELD) return;
      this.timer = setTimeout(() => {
        this.timer = -1;
        if (this.started && generation === this.generation) {
          onSide(status === motion.HoldingHandStatus.LEFT_HAND_HELD);
        }
      }, HOLDING_HAND_STABLE_DELAY);
    };
    try {
      motion.on('holdingHandChanged', callback);
      this.callback = callback;
      return true;
    } catch (error) {
      // 801: unsupported model / setting, 201: permission denied. Never block timetable actions.
      const code = (error as BusinessError).code;
      if (code !== 801 && code !== 201) console.warn('Holding-hand subscription unavailable: ' + code);
      this.generation++;
      if (this.timer >= 0) clearTimeout(this.timer);
      this.timer = -1;
      if (onUnavailable !== undefined) onUnavailable(); else onSide(false);
      return false;
    }
  }

  stop(): void {
    this.started = false;
    this.generation++;
    if (this.timer >= 0) clearTimeout(this.timer);
    this.timer = -1;
    const callback = this.callback;
    this.callback = undefined;
    if (callback !== undefined) {
      try {
        // Only remove this page's callback, never another consumer's subscription.
        motion.off('holdingHandChanged', callback);
      } catch (_) {
        // The generation gate still prevents stale deliveries after teardown.
      }
    }
  }
}
