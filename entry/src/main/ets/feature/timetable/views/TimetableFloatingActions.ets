import { HitaDesign } from '../../../common/theme/HitaDesign';
import { curves, FrameCallback } from '@kit.ArkUI';
import { CompatibleMaterialModifier } from '../../../common/theme/CompatibleMaterialModifier';
import { HoldingHandObserver } from '../data/HoldingHandObserver';
import { CourseControlHost } from './CourseControlHost';
import { FLOATING_ACTION_EXIT, FLOATING_ACTION_EXIT_DURATION, FLOATING_ACTION_GAP, floatingActionExitProgress,
  FloatingActionsFrame, FloatingActionsMotion } from './FloatingActionsMotion';

class FloatingActionFrameCallback extends FrameCallback {
  private callback: () => void;
  constructor(callback: () => void) {
    super();
    this.callback = callback;
  }
  onFrame(): void { this.callback(); }
}

@Component
export struct TimetableFloatingActions {
  @Prop @Watch('sync') active: boolean = false;
  @Prop @Watch('sync') eveningVisible: boolean = false;
  @Prop @Watch('sync') returnVisible: boolean = false;
  @Prop @Watch('sync') interactionBlocked: boolean = false;
  @Prop returnEnabled: boolean = true;
  @Prop bottomInset: number = 0;
  /** Room kept for the tablet side rail on each edge. */
  @Prop leftInset: number = 0;
  @Prop rightInset: number = 0;
  /** Distance from the screen edge; a tri-fold rail layout moves the controls into its gutter. */
  @Prop edgeMargin: number = 18;
  onEvening: () => void = () => {};
  onReturn: () => void = () => {};
  @State private frame: FloatingActionsFrame = new FloatingActionsFrame();
  private alive: boolean = false;
  private observer: HoldingHandObserver = new HoldingHandObserver();
  private movement: FloatingActionsMotion = new FloatingActionsMotion(
    (frame: FloatingActionsFrame) => { this.prepareFrame(frame); },
    (frame: FloatingActionsFrame, stiffness: number, exiting: boolean, generation: number, finish: () => void) => {
      // Render the offscreen start/anchor before submitting a native render-thread animation.
      this.getUIContext().postFrameCallback(new FloatingActionFrameCallback(() => {
        if (!this.alive || !this.movement.isCurrent(generation)) return;
        this.getUIContext().animateTo({
          // A physics spring ignores duration; a bounded exit ends as soon as it is offscreen.
          duration: FLOATING_ACTION_EXIT_DURATION,
          curve: exiting ? curves.customCurve(floatingActionExitProgress) :
            curves.interpolatingSpring(0, 1, stiffness, 17),
          onFinish: finish
        }, () => { this.frame = frame; });
      }));
    });

  private prepareFrame(frame: FloatingActionsFrame): void {
    // Mounting another control must not snap an animation queued for the next frame.
    if (frame.side === this.frame.side) {
      if (frame.eveningMounted && this.frame.eveningMounted) frame.eveningX = this.frame.eveningX;
      if (frame.returnMounted && this.frame.returnMounted) {
        frame.returnX = this.frame.returnX;
        frame.returnLift = this.frame.returnLift;
      }
    }
    this.frame = frame;
  }

  aboutToAppear(): void {
    this.alive = true;
    this.sync();
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.observer.stop();
    this.movement.stop();
  }

  private sync(): void {
    if (!this.alive) return;
    this.movement.update(this.active, this.eveningVisible, this.returnVisible, this.interactionBlocked);
    if (this.active && (this.eveningVisible || this.returnVisible)) {
      this.observer.start((left: boolean) => this.movement.setSide(left));
    } else {
      this.observer.stop();
    }
  }

  private touch(control: number, event: TouchEvent): void {
    if (event.type === TouchType.Down) this.movement.setPressed(control, true);
    else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.movement.setPressed(control, false);
    }
  }

  private edgePosition(): Edges {
    return this.frame.side < 0 ? { left: this.edgeMargin + this.leftInset, bottom: this.bottomInset + 20 } :
      { right: this.edgeMargin + this.rightInset, bottom: this.bottomInset + 20 };
  }

  /** Stretch the exit travel so a hidden control also clears a rail on its edge. */
  private travel(x: number): number {
    const inset: number = this.frame.side < 0 ? this.leftInset : this.rightInset;
    return x * (FLOATING_ACTION_EXIT + inset) / FLOATING_ACTION_EXIT;
  }

  @Builder
  action(evening: boolean) {
    CourseControlHost({ barHeight: 48 }) {
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph(evening ? $r('sys.symbol.chevron_down') : $r('sys.symbol.arrow_clockwise'))
          .fontSize(HitaDesign.iconLg)
          .fontColor([CompatibleMaterialModifier.foreground($r('app.color.hita_primary'))])
      }
      .id(evening ? 'timetable-evening-hint' : 'timetable-return-current-week')
      .width(48)
      .height(48)
      .backgroundColor($r('app.color.hita_selected'))
      .attributeModifier(new CompatibleMaterialModifier($r('app.color.hita_selected')))
      .accessibilityText(evening ? '下方还有晚间课程或考试，点击查看' : '回到本周')
      // Week transitions block input separately so the button keeps its normal color.
      .enabled(this.active && (evening ? this.eveningVisible : this.returnVisible))
      .onClick(() => {
        if (evening) this.onEvening();
        else if (this.returnEnabled) this.onReturn();
      })
    }
  }

  build() {
    Stack({ alignContent: Alignment.BottomStart }) {
      Row() { this.action(true); }
        .width(48)
        .height(48)
        .visibility(this.frame.eveningMounted ? Visibility.Visible : Visibility.Hidden)
        .translate({ x: this.travel(this.frame.eveningX), y: 0 })
        .hitTestBehavior(this.active && this.eveningVisible ? HitTestMode.Transparent : HitTestMode.None)
        .onTouch((event: TouchEvent) => this.touch(1, event))
      Row() { this.action(false); }
        .width(48)
        .height(48)
        .visibility(this.frame.returnMounted ? Visibility.Visible : Visibility.Hidden)
        .translate({ x: this.travel(this.frame.returnX), y: -this.frame.returnLift })
        .hitTestBehavior(this.active && this.returnVisible && this.returnEnabled ?
          HitTestMode.Transparent : HitTestMode.None)
        .onTouch((event: TouchEvent) => this.touch(2, event))
    }
    .width(48)
    .height(48 + FLOATING_ACTION_GAP)
    .position(this.edgePosition())
    .clip(false)
    .hitTestBehavior(HitTestMode.Transparent)
  }
}
