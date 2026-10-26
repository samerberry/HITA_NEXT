export const DOCK_HOLD_DELAY_MS: number = 180;

/** Keep content fixed while scrubbing the dock; authorize one target on release. */
export class DockNavigationGuard {
  private sequence: number = 0;
  private dock: boolean = false;
  private dockPointer: boolean = false;
  private pressed: boolean = false;
  private hasTouch: boolean = false;
  private rejected: boolean = false;
  private consumed: boolean = false;
  private moved: boolean = false;
  private holding: boolean = false;
  private pointerId: number = -1;
  private downTimestamp: number = -1;
  private observedEvent: TouchEvent | undefined = undefined;
  private downTimeMs: number = 0;
  private startX: number = 0;
  private startY: number = 0;
  private targetIndex: number = -1;
  private authorizedIndex: number = -1;
  private left: number = 0;
  private top: number = 0;
  private width: number = 0;
  private height: number = 0;
  private padding: number = 0;
  /** The tablet side rail lays its three items out top to bottom. */
  private vertical: boolean = false;

  setBounds(left: number, top: number, width: number, height: number, padding: number = 0,
    vertical: boolean = false): void {
    if (!Number.isFinite(left) || !Number.isFinite(top) || !Number.isFinite(width) ||
      !Number.isFinite(height) || (vertical ? height : width) <= padding * 2 || (vertical ? width : height) <= 0) {
      return;
    }
    this.left = left;
    this.top = top;
    this.width = width;
    this.height = height;
    this.padding = padding;
    this.vertical = vertical;
  }

  private length(): number {
    return this.vertical ? this.height : this.width;
  }

  /** Distance along the item axis from the first item's leading edge. */
  private along(touch: TouchObject): number {
    return this.vertical ? touch.windowY - this.top - this.padding : touch.windowX - this.left - this.padding;
  }

  begin(event: TouchEvent, fromDock: boolean, nowMs: number = Date.now()): void {
    if (event.type !== TouchType.Down || event.touches.length === 0) {
      return;
    }
    const touch: TouchObject = event.touches[0];
    if (!this.hasTouch || !this.pressed ||
      (event.touches.length === 1 && event.timestamp !== this.downTimestamp)) {
      this.reset();
      this.hasTouch = true;
      this.pressed = true;
      this.downTimestamp = event.timestamp;
      this.downTimeMs = nowMs;
      this.pointerId = touch.id;
      this.startX = touch.windowX;
      this.startY = touch.windowY;
    }
    if (event.touches.length !== 1 || touch.id !== this.pointerId) {
      this.rejected = true;
    }
    // Parent and bar hit tests visit the same Down. Preserve its dock origin.
    this.dock = this.dock || fromDock;
    this.dockPointer = this.dockPointer || fromDock;
  }

  observe(event: TouchEvent, nowMs: number = Date.now()): boolean {
    if (!this.hasTouch || !this.pressed || event === this.observedEvent) {
      return false;
    }
    this.observedEvent = event;
    if (event.type === TouchType.Cancel) {
      this.rejected = true;
      this.pressed = false;
      return this.dock;
    }
    if (!this.dock || this.rejected) {
      if (event.type === TouchType.Up) {
        this.pressed = false;
      }
      return this.dock;
    }
    if (event.touches.length > 1) {
      this.rejected = true;
    }
    this.activateHold(nowMs);
    // Inspect coalesced motion so a short out-and-back cannot become a tap.
    for (const point of event.getHistoricalPoints()) {
      this.checkPoint(point.touchObject);
    }
    for (const touch of event.changedTouches) {
      this.checkPoint(touch);
    }
    for (const touch of event.touches) {
      this.checkPoint(touch);
    }
    if (event.type === TouchType.Up) {
      this.pressed = false;
    }
    return true;
  }

  private checkPoint(touch: TouchObject): void {
    if (touch.id !== this.pointerId) {
      this.rejected = true;
      return;
    }
    const dx: number = touch.windowX - this.startX;
    const dy: number = touch.windowY - this.startY;
    this.moved = this.moved || dx * dx + dy * dy > 64;
    if (this.length() <= this.padding * 2 || (this.vertical ? this.width : this.height) <= 0) {
      return;
    }
    // Leaving the capsule clears the current target. Re-entering while held
    // can select an icon again; never clamp an outside release to an edge tab.
    // The 8 vp tolerance applies across the capsule, never along its items.
    const outside: boolean = this.vertical ?
      touch.windowY < this.top || touch.windowY > this.top + this.height ||
        touch.windowX < this.left - 8 || touch.windowX > this.left + this.width + 8 :
      touch.windowX < this.left || touch.windowX > this.left + this.width ||
        touch.windowY < this.top - 8 || touch.windowY > this.top + this.height + 8;
    if (outside) {
      this.targetIndex = -1;
      return;
    }
    const itemLength: number = (this.length() - this.padding * 2) / 3;
    this.targetIndex = Math.max(0, Math.min(2, Math.floor(this.along(touch) / itemLength)));
  }

  activateHold(nowMs: number = Date.now()): boolean {
    if (this.dock && this.pressed && !this.rejected && nowMs - this.downTimeMs >= DOCK_HOLD_DELAY_MS) {
      this.holding = true;
    }
    return this.isHolding();
  }

  isHolding(): boolean {
    return this.holding && !this.rejected;
  }

  isDock(): boolean {
    return this.dock;
  }

  hasDockPointer(): boolean {
    return this.dockPointer;
  }

  isRejected(): boolean {
    return this.rejected;
  }

  lightPosition(event: TouchEvent): number | undefined {
    const point: TouchObject | undefined = event.touches.find((touch: TouchObject): boolean =>
      touch.id === this.pointerId) ?? event.changedTouches.find((touch: TouchObject): boolean =>
      touch.id === this.pointerId);
    if (point === undefined || this.length() <= this.padding * 2) return undefined;
    return Math.max(0, Math.min(212, this.along(point) * 212 / (this.length() - this.padding * 2)));
  }

  releaseTarget(): number {
    return this.dockPointer && !this.pressed && !this.rejected && !this.consumed &&
      (this.holding || !this.moved) ? this.targetIndex : -1;
  }

  requestClick(): number {
    if (!this.dockPointer && !this.pressed) {
      this.consumed = false;
    }
    this.dock = true;
    // Supersede duplicate native callbacks in the same input dispatch.
    return ++this.sequence;
  }

  commitClick(sequence: number, index: number, changeIndex: (index: number) => void): void {
    if (sequence !== this.sequence || this.pressed || this.rejected || this.consumed ||
      (this.moved && !this.holding)) {
      return;
    }
    // Native item indices are authoritative for taps. Only a held release
    // needs geometry, because a long press may suppress the item click.
    const target: number = this.holding ? this.targetIndex : index;
    if (target < 0 || target >= 3 || (this.holding && this.length() <= 0)) {
      return;
    }
    this.consumed = true;
    this.authorizedIndex = target;
    try {
      changeIndex(target);
    } catch (error) {
      this.authorizedIndex = -1;
      throw error as Error;
    }
  }

  allowsChange(index: number): boolean {
    if (!this.dock) {
      return true;
    }
    if (this.authorizedIndex !== index) {
      return false;
    }
    // The native controller can ask onContentWillChange after changeIndex
    // returns. Consume the grant here instead of revoking it on the JS stack.
    this.authorizedIndex = -1;
    return true;
  }

  reset(): void {
    this.sequence++;
    this.dock = false;
    this.dockPointer = false;
    this.pressed = false;
    this.hasTouch = false;
    this.rejected = false;
    this.consumed = false;
    this.moved = false;
    this.holding = false;
    this.targetIndex = -1;
    this.authorizedIndex = -1;
    this.observedEvent = undefined;
  }
}
