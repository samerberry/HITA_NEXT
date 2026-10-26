import { deviceInfo } from '@kit.BasicServicesKit';
import { HitaDesign } from '../theme/HitaDesign';
import { CompatibleRailModifier } from '../theme/CompatibleRailModifier';
import { ImmersiveHeader } from './ImmersiveHeader';
import { DOCK_RAIL_THICKNESS, DOCK_WIDTH } from '../util/DockHandedness';

const RAIL_PADDING: number = 4;
/** Room around the capsule inside its host for the material shadow and press deformation. */
const RAIL_OVERFLOW: number = 16;

/** Tablet / tri-fold navigation: the dock capsule stood upright on one screen edge. */
@Component
export struct DockRail {
  @Prop selectedIndex: number = 0;
  @Prop darkMode: boolean = false;
  onSelect: (index: number) => void = () => {};
  onRailTouch: (event: TouchEvent) => void = () => {};
  onRailAreaChanged: (area: Area) => void = () => {};
  /** API 26+ glass inverts its own foreground; older blur relies on a difference blend. */
  private systemGlass: boolean = deviceInfo.apiAvailable('26.0.0');

  private glyphColor(index: number): ResourceColor {
    if (this.systemGlass) {
      return this.selectedIndex === index ? $r('sys.color.ohos_id_color_text_primary') :
        $r('sys.color.ohos_id_color_text_secondary');
    }
    return this.selectedIndex === index ? '#FFFFFFFF' : '#B8FFFFFF';
  }

  @Builder
  item(icon: Resource, label: string, index: number) {
    Column({ space: 3 }) {
      SymbolGlyph(icon)
        .fontSize(HitaDesign.iconMd)
        .fontColor([this.glyphColor(index)])
      Text(label)
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.glyphColor(index))
        .maxLines(1)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .borderRadius(24)
    .accessibilityText(label)
    .accessibilitySelected(this.selectedIndex === index)
    .onClick(() => this.onSelect(index))
  }

  @Builder
  items() {
    this.item($r('sys.symbol.calendar'), '今日', 0)
    this.item($r('sys.symbol.doc_plaintext'), '时间表', 1)
    this.item($r('sys.symbol.more'), '更多', 2)
  }

  @Builder
  capsule() {
    Stack({ alignContent: Alignment.Top }) {
      if (this.systemGlass) {
        Column() { this.items() }
          .width('100%')
          .height('100%')
      } else {
        Column() { this.items() }
          .width('100%')
          .height('100%')
          // Same single offscreen inversion pass as the API 23 bottom dock.
          .blendMode(BlendMode.DIFFERENCE, BlendApplyType.OFFSCREEN)
      }
    }
    .width(DOCK_RAIL_THICKNESS)
    .height(DOCK_WIDTH)
    .padding(RAIL_PADDING)
    .borderRadius(DOCK_RAIL_THICKNESS / 2)
    .attributeModifier(new CompatibleRailModifier(this.darkMode))
    .onAreaChange((_old: Area, area: Area) => this.onRailAreaChanged(area))
    .onTouch((event: TouchEvent) => this.onRailTouch(event))
  }

  /**
   * API 26 renders an ordinary component's systemMaterial only inside a Navigation title bar or a
   * horizontal Tabs bottom bar, so the upright capsule is hosted in a native title region, enlarged
   * on every side for the shadow while the rail keeps its own layout bounds.
   */
  build() {
    if (this.systemGlass) {
      Stack({ alignContent: Alignment.TopStart }) {
        Column() {
          ImmersiveHeader({ barHeight: DOCK_WIDTH + RAIL_OVERFLOW * 2 }) {
            Column() {
              this.capsule();
            }
            .width('100%')
            .height(DOCK_WIDTH + RAIL_OVERFLOW * 2)
            .padding(RAIL_OVERFLOW)
            .clip(false)
            .hitTestBehavior(HitTestMode.Transparent)
          }
        }
        .width(DOCK_RAIL_THICKNESS + RAIL_OVERFLOW * 2)
        .height(DOCK_WIDTH + RAIL_OVERFLOW * 2)
        .position({ x: -RAIL_OVERFLOW, y: -RAIL_OVERFLOW })
        .clip(false)
        .hitTestBehavior(HitTestMode.Transparent)
      }
      .width(DOCK_RAIL_THICKNESS)
      .height(DOCK_WIDTH)
      .clip(false)
      .hitTestBehavior(HitTestMode.Transparent)
    } else {
      this.capsule();
    }
  }
}
