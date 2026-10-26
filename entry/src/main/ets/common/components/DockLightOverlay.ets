import { FrameCallback } from '@kit.ArkUI';
import { DockFlowMotion, DockLightController, DockLightPlayer } from '../util/DockLightEffect';
import { ImmersiveLightEnvelope } from '../util/ImmersiveLightEffect';

class DockLightFrame extends FrameCallback {
  private draw: (timeMs: number) => void;

  constructor(draw: (timeMs: number) => void) {
    super();
    this.draw = draw;
  }

  onFrame(timeNs: number): void {
    this.draw(timeNs / 1000000);
  }
}

/** A small, input-transparent light layer over the native glass and glyphs. */
@Component
export struct DockLightOverlay {
  controller: DockLightController = new DockLightController();
  /** Side rail: draw the same 212 vp track top-to-bottom instead of rotating a horizontal canvas. */
  vertical: boolean = false;
  private canvas: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private generation: number = 0;
  private ready: boolean = false;
  private running: boolean = false;
  private envelope: ImmersiveLightEnvelope = new ImmersiveLightEnvelope();
  private motion: DockFlowMotion = new DockFlowMotion();
  private pressed: boolean = false;
  private player: DockLightPlayer = {
    transfer: (from: number, to: number) => this.transfer(from, to),
    stop: () => this.stop(),
    press: (source: number) => this.press(source),
    move: (x: number) => this.follow(x),
    release: (cancelled: boolean) => this.release(cancelled)
  };

  aboutToAppear(): void {
    this.controller.register(this.player);
  }

  aboutToDisappear(): void {
    this.controller.unregister(this.player);
    this.stop();
    this.ready = false;
  }

  private stop(): void {
    this.generation++;
    this.running = false;
    this.pressed = false;
    this.envelope.reset();
    this.motion.settle();
    if (this.ready) {
      this.canvas.clearRect(0, 0, 212, 212);
    }
  }

  private transfer(from: number, to: number): void {
    const nowMs: number = Date.now();
    if (!this.envelope.needsFrame(nowMs)) {
      this.envelope.press(nowMs);
      this.envelope.release(nowMs);
    }
    // A light still flowing keeps its position and velocity and turns toward the new tab.
    if (!this.motion.isMoving()) this.motion.jump(DockLightOverlay.slot(from));
    this.motion.retarget(DockLightOverlay.slot(to), nowMs);
    this.animate();
  }

  private press(source: number): void {
    // A rapid second tap must not snap the travelling light back onto the tapped tab.
    if (!this.motion.isMoving()) this.motion.jump(DockLightOverlay.slot(source));
    this.pressed = true;
    this.envelope.press(Date.now());
    this.animate();
  }

  private follow(x: number): void {
    if (this.motion.isMoving()) {
      this.motion.retarget(x, Date.now());
      this.animate();
    } else {
      this.motion.jump(x);
    }
  }

  private static slot(index: number): number {
    return (index + 0.5) * 212 / 3;
  }

  private release(cancelled: boolean): void {
    this.pressed = false;
    this.envelope.release(Date.now(), cancelled);
    this.animate();
  }

  private animate(): void {
    if (this.running || !this.ready) return;
    this.running = true;
    const generation: number = this.generation;
    const frame: DockLightFrame = new DockLightFrame((_timeMs: number) => {
      if (generation !== this.generation || !this.ready) {
        return;
      }
      const nowMs: number = Date.now();
      this.canvas.clearRect(0, 0, 212, 212);
      const center: number = this.motion.step(nowMs);
      this.canvas.save();
      // Map the track (x along 0-212, y across 0-56) onto the upright rail: slot 0 at the top.
      if (this.vertical) this.canvas.setTransform(0, 1, -1, 0, 56, 0);
      this.clipCapsule();
      this.drawGlow(center, this.envelope.sample(nowMs), 45);
      this.canvas.restore();
      if (this.pressed || this.envelope.needsFrame(nowMs) || this.motion.isMoving()) {
        this.getUIContext().postFrameCallback(frame);
      } else {
        this.running = false;
      }
    });
    this.getUIContext().postFrameCallback(frame);
  }

  private clipCapsule(): void {
    this.canvas.beginPath();
    this.canvas.moveTo(28, 0);
    this.canvas.lineTo(184, 0);
    this.canvas.arc(184, 28, 28, -Math.PI / 2, Math.PI / 2);
    this.canvas.lineTo(28, 56);
    this.canvas.arc(28, 28, 28, Math.PI / 2, Math.PI * 1.5);
    this.canvas.closePath();
    this.canvas.clip();
  }

  private drawGlow(x: number, alpha: number, radius: number): void {
    const glow: CanvasGradient = this.canvas.createRadialGradient(x, 28, 0, x, 28, radius);
    glow.addColorStop(0, 'rgba(255,255,255,' + alpha.toString() + ')');
    glow.addColorStop(0.35, 'rgba(255,255,255,' + (alpha * 0.65).toString() + ')');
    glow.addColorStop(1, 'rgba(255,255,255,0)');
    this.canvas.fillStyle = glow;
    this.canvas.fillRect(x - radius, 0, radius * 2, 56);
  }

  build() {
    Canvas(this.canvas)
      .width(this.vertical ? 56 : 212)
      .height(this.vertical ? 212 : 56)
      .hitTestBehavior(HitTestMode.None)
      .accessibilityLevel('no-hide-descendants')
      .onReady(() => {
        this.ready = true;
        if (this.pressed || this.envelope.needsFrame(Date.now()) || this.motion.isMoving()) this.animate();
      })
  }
}
