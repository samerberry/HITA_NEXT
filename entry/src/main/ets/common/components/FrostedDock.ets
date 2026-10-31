import { HitaDesign } from '../theme/HitaDesign';
import { DOCK_WIDTH, DOCK_ACTION_SIZE, dockItemCenter } from '../util/DockHandedness';
import { CompatibleRailModifier } from '../theme/CompatibleRailModifier';
import { AssistantDockItem } from '../../feature/assistant/AssistantDockItem';
/** API 23 dock: backdrop blur and alpha-preserving foreground inversion. */
@Component
export struct FrostedDock {
  @Prop selectedIndex: number = 0;
  @Prop bottomInset: number = 24;
  @Prop darkMode: boolean = false;
  @Prop hideMask: boolean = false;
  /** Horizontal shift toward the holding hand; the parent animates it. */
  @Prop sideOffset: number = 0;
  onSelect: (index: number) => void = () => {};
  onDockTouch: (event: TouchEvent) => void = () => {};
  onDockAreaChanged: (area: Area) => void = () => {};
  private areaWidth: number = 0;
  private areaHeight: number = 0;
  private readonly unselectedColor: ResourceColor = '#B8FFFFFF';

  @Builder
  item(icon: Resource, label: string, index: number) {
    Column({ space: HitaDesign.dockIconLabelGap }) {
      SymbolGlyph(icon)
        .fontSize(HitaDesign.iconMd)
        .fontColor([this.selectedIndex === index ? '#FFFFFFFF' : this.unselectedColor])
      Text(label)
        .fontSize(HitaDesign.dockLabel)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.selectedIndex === index ? '#FFFFFFFF' : this.unselectedColor)
    }
    .layoutWeight(1)
    .height(48)
    .justifyContent(FlexAlign.Center)
    .borderRadius(24)
    .accessibilityText(label)
    .accessibilitySelected(this.selectedIndex === index)
    .onClick(() => this.onSelect(index))
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (!this.hideMask) {
        Column()
          .width('100%')
          .height(92 + this.bottomInset)
          .linearGradient({
            angle: 0,
            colors: [[this.darkMode ? '#99101214' : '#66F1F3F5', 0], [Color.Transparent, 1]]
          })
          .hitTestBehavior(HitTestMode.None)
      }
      Stack({ alignContent: Alignment.TopStart }) {
        Column()
          .width(dockItemCenter(2, 4) - dockItemCenter(0, 4) + DOCK_ACTION_SIZE)
          .height(DOCK_ACTION_SIZE)
          .position({ x: dockItemCenter(0, 4) - DOCK_ACTION_SIZE / 2, y: 0 })
          .borderRadius(DOCK_ACTION_SIZE / 2)
          .attributeModifier(new CompatibleRailModifier(this.darkMode))
          .hitTestBehavior(HitTestMode.None)
        Column()
          .width(DOCK_ACTION_SIZE)
          .height(DOCK_ACTION_SIZE)
          .position({ x: dockItemCenter(3, 4) - DOCK_ACTION_SIZE / 2, y: 0 })
          .borderRadius(DOCK_ACTION_SIZE / 2)
          .attributeModifier(new CompatibleRailModifier(this.darkMode))
          .hitTestBehavior(HitTestMode.None)
        Column()
          .width(DOCK_ACTION_SIZE)
          .height(48)
          .borderRadius(24)
          .backgroundColor(this.darkMode ? '#18FFFFFF' : '#10000000')
          .position({ x: dockItemCenter(this.selectedIndex, 4) - DOCK_ACTION_SIZE / 2, y: 4 })
          .animation({ duration: 300, curve: Curve.FastOutSlowIn })
          .hitTestBehavior(HitTestMode.None)
        Row() {
          this.item($r('sys.symbol.calendar'), '今日', 0)
          this.item($r('sys.symbol.doc_plaintext'), '时间表', 1)
          this.item($r('sys.symbol.more'), '更多', 2)
          AssistantDockItem({ glyphTint: this.unselectedColor }).layoutWeight(1)
        }
        .width(DOCK_WIDTH - 8)
        .height(48)
        .position({ x: 4, y: 4 })
        // One foreground inversion pass for all four transparent Dock items.
        .blendMode(BlendMode.DIFFERENCE, BlendApplyType.OFFSCREEN)
      }
      .width(DOCK_WIDTH)
      .height(56)
      .margin({ bottom: 12 + this.bottomInset })
      .offset({ x: this.sideOffset, y: 0 })
      .onAreaChange((_old: Area, area: Area) => this.onDockAreaChanged(area))
      .onTouch((event: TouchEvent) => this.onDockTouch(event))
    }
    .width('100%')
    .height(92 + this.bottomInset)
    .onAreaChange((oldValue: Area, newValue: Area) => {
      this.areaWidth = newValue.width as number;
      this.areaHeight = newValue.height as number;
    })
    .onTouchIntercept((event: TouchEvent) => {
      if (event.touches.length === 0) {
        return HitTestMode.Transparent;
      }
      const touch: TouchObject = event.touches[0];
      const left: number = (this.areaWidth - DOCK_WIDTH) / 2 + this.sideOffset;
      const bottom: number = this.areaHeight - 12 - this.bottomInset;
      // Consume only capsule hits; never send a dock tap to the course/list
      // behind it, while the rest of this bottom strip stays touch-transparent.
      return touch.x >= left && touch.x <= left + DOCK_WIDTH && touch.y >= bottom - 56 && touch.y <= bottom
        ? HitTestMode.Default : HitTestMode.Transparent;
    })
  }
}
