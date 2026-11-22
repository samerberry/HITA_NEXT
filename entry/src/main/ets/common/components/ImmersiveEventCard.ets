import { ImmersiveHeader } from './ImmersiveHeader';
import { CompatibleMaterialModifier } from '../theme/CompatibleMaterialModifier';
import { HitaDesign } from '../theme/HitaDesign';

@Component
export struct ImmersiveEventCard {
  @StorageProp('hita_appearance_dark') private darkMode: boolean = false;
  // The hero supplies its own blue material inside an ImmersiveHeader.
  @Prop hero: boolean = false;
  @BuilderParam content: () => void;
  @State private contentHeight: number = 0;
  @State private lightX: number = 0;
  @State private lightY: number = 0;
  @State private lightOpacity: number = 0;
  private pointer: number = -1;

  private trackLight(event: TouchEvent): void {
    const touch = event.touches[0];
    if (event.type === TouchType.Down && event.touches.length === 1) {
      this.pointer = touch.id;
      this.lightX = touch.x;
      this.lightY = touch.y;
      this.getUIContext().animateTo({ duration: 160, curve: Curve.EaseOut }, () => {
        this.lightOpacity = this.hero || this.darkMode ? 0.38 : 0.85;
      });
    } else if (this.pointer >= 0) {
      if (event.type === TouchType.Move && event.touches.length === 1 && touch.id === this.pointer) {
        this.lightX = touch.x;
        this.lightY = touch.y;
      } else {
        this.pointer = -1;
        this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => { this.lightOpacity = 0; });
      }
    }
  }

  private updateHeight(height: number): void {
    if (Number.isFinite(height) && height > 0) {
      const next: number = Math.ceil(height);
      if (next !== this.contentHeight) {
        this.contentHeight = next;
      }
    }
  }

  @Builder
  private pressHalo() {
    Row()
      .width('100%').height(this.contentHeight)
      .radialGradient({ center: [this.lightX, this.lightY], radius: Math.max(48, Math.min(80, this.contentHeight)),
        colors: [[Color.White, 0], [this.hero || this.darkMode ? Color.White : $r('app.color.hita_selected_cfe3fa'), 0.3],
          [$r('app.color.hita_press_glow_edge'), 1]] })
      .opacity(this.lightOpacity)
      .borderRadius(this.hero ? HitaDesign.heroRadius : HitaDesign.cardRadius).clip(true)
      .position({ x: 0, y: 0 })
      .accessibilityLevel('no').hitTestBehavior(HitTestMode.None);
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.contentHeight > 0 && !this.hero) {
        // The material is translucent and takes the page color in light mode, so a solid card face sits beneath it.
        // The face is transparent in dark mode, where the material alone already separates from the page.
        Row()
          .width('100%')
          .height(this.contentHeight)
          .backgroundColor($r('app.color.hita_immersive_card_base'))
          .borderRadius(HitaDesign.cardRadius)
          .position({ x: 0, y: 0 })
          .accessibilityLevel('no')
          .hitTestBehavior(HitTestMode.Transparent);
        // A positioned title host supplies material without constraining the card's content height.
        Column() {
          ImmersiveHeader({ barHeight: this.contentHeight }) {
            Row()
              .width('100%')
              .height(this.contentHeight)
              .backgroundColor($r('app.color.hita_surface'))
              .borderRadius(HitaDesign.cardRadius)
              .attributeModifier(new CompatibleMaterialModifier($r('app.color.hita_surface')));
          }
        }
        .width('100%')
        .height(this.contentHeight)
        .position({ x: 0, y: 0 })
        .accessibilityLevel('no-hide-descendants')
        .hitTestBehavior(HitTestMode.None);
        this.pressHalo();
      }
      Column() {
        this.content();
      }
      .width('100%')
      .onAreaChange((oldArea: Area, area: Area) => { this.updateHeight(Number(area.height)); })
      // The content keeps its own click action; the card observes touches as they bubble up.
      .hitTestBehavior(HitTestMode.Transparent);
      if (this.hero && this.contentHeight > 0) {
        this.pressHalo();
      }
    }
    .width('100%')
    .backgroundColor(this.contentHeight > 0 ? Color.Transparent : $r('app.color.hita_surface'))
    .borderRadius(HitaDesign.cardRadius)
    .onTouch((event: TouchEvent) => this.trackLight(event))
    .onDisAppear(() => { this.pointer = -1; this.lightOpacity = 0; });
  }
}
