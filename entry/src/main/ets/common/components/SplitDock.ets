import { HitaDesign } from '../theme/HitaDesign';
import { CompatibleRailModifier } from '../theme/CompatibleRailModifier';
import { ImmersiveHeader } from './ImmersiveHeader';
import { AssistantDockButton } from '../../feature/assistant/AssistantDockButton';
import { DOCK_WIDTH, DOCK_NAV_WIDTH, DOCK_NATIVE_PADDING, DOCK_ACTION_SIZE,
  DOCK_ACTION_START } from '../util/DockHandedness';

/** Two glass surfaces in one coordinate space; Home moves their common parent. */
@Component
export struct SplitDock {
  @Prop selectedIndex: number = 0;
  @Prop darkMode: boolean = false;
  onSelect: (index: number) => void = () => {};

  private glyphColor(index: number): ResourceColor {
    return this.selectedIndex === index ? $r('sys.color.ohos_id_color_text_primary') :
      $r('sys.color.ohos_id_color_text_secondary');
  }

  @Builder
  item(icon: Resource, label: string, index: number) {
    Column({ space: HitaDesign.dockIconLabelGap }) {
      SymbolGlyph(icon)
        .fontSize(HitaDesign.iconMd)
        .fontColor([this.glyphColor(index)]);
      Text(label)
        .fontSize(HitaDesign.dockLabel)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.glyphColor(index))
        .maxLines(1);
    }
    .layoutWeight(1)
    .height(HitaDesign.buttonHeight)
    .justifyContent(FlexAlign.Center)
    .accessibilityText(label)
    .accessibilitySelected(this.selectedIndex === index)
    .onClick(() => this.onSelect(index));
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // Keep room for native material shadows without enlarging the hit area.
      Column() {
        ImmersiveHeader({ barHeight: DOCK_ACTION_SIZE + HitaDesign.spaceMd * 2 }) {
          Column() {
            Row() {
              this.item($r('sys.symbol.calendar'), '今日', 0);
              this.item($r('sys.symbol.doc_plaintext'), '时间表', 1);
              this.item($r('sys.symbol.more'), '更多', 2);
            }
            .width(DOCK_NAV_WIDTH)
            .height(DOCK_ACTION_SIZE)
            .padding({ left: DOCK_NATIVE_PADDING, right: DOCK_NATIVE_PADDING })
            .borderRadius(DOCK_ACTION_SIZE / 2)
            .attributeModifier(new CompatibleRailModifier(this.darkMode));
          }
          .width('100%')
          .height(DOCK_ACTION_SIZE + HitaDesign.spaceMd * 2)
          .padding(HitaDesign.spaceMd)
          .clip(false)
          .hitTestBehavior(HitTestMode.Transparent);
        }
      }
      .width(DOCK_NAV_WIDTH + HitaDesign.spaceMd * 2)
      .height(DOCK_ACTION_SIZE + HitaDesign.spaceMd * 2)
      .position({ x: -HitaDesign.spaceMd, y: -HitaDesign.spaceMd })
      .clip(false)
      .hitTestBehavior(HitTestMode.Transparent);

      AssistantDockButton({ darkMode: this.darkMode })
        .position({ x: DOCK_ACTION_START, y: 0 });
    }
    .width(DOCK_WIDTH)
    .height(DOCK_ACTION_SIZE)
    .clip(false)
    .hitTestBehavior(HitTestMode.Default);
  }
}
