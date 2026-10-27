import { HitaDesign } from '../theme/HitaDesign';
import { HitaColors } from '../theme/HitaColors';

export enum HitaRowAccessory {
  CHEVRON = 0,
  /** Expandable row: the arrow turns with expanded and the state is announced. */
  DISCLOSURE = 1
}

/**
 * Row for settings and feature lists. Inside a grouped card, every row after the first passes divider; the divider
 * starts where the text starts, so the icon column stays open. Text arrives through @Prop, so labels bound to page
 * state refresh in place.
 */
@Component
export struct HitaListRow {
  symbol: Resource = $r('sys.symbol.chevron_right');
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop divider: boolean = false;
  @Prop expanded: boolean = false;
  accessory: HitaRowAccessory = HitaRowAccessory.CHEVRON;
  onTap: () => void = () => {};

  build() {
    Column() {
      if (this.divider) {
        Divider()
          .strokeWidth(HitaDesign.hairline)
          .color(HitaColors.divider)
          .margin({ left: HitaDesign.listTextInset, right: HitaDesign.inset });
      }
      Row() {
        Stack() {
          SymbolGlyph(this.symbol)
            .fontSize(HitaDesign.iconMd)
            .fontColor([HitaColors.primary]);
        }
        .width(HitaDesign.listIconSize)
        .height(HitaDesign.listIconSize)
        .borderRadius(HitaDesign.listIconSize / 2)
        .alignContent(Alignment.Center)
        .backgroundColor(HitaColors.selected);
        Column() {
          Text(this.title)
            .fontSize(HitaDesign.body)
            .fontColor(HitaColors.onSurface)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
          if (this.subtitle.length > 0) {
            Text(this.subtitle)
              .fontSize(HitaDesign.caption)
              .fontColor(HitaColors.onSurfaceVariant)
              .margin({ top: HitaDesign.space2xs })
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis });
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ left: HitaDesign.spaceSm });
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(HitaDesign.iconXs)
          .fontColor([HitaColors.onSurfaceVariant])
          .width(HitaDesign.iconSm)
          .height(HitaDesign.iconMd)
          .flexShrink(0)
          .accessibilityLevel('no')
          .rotate({ angle: this.accessory === HitaRowAccessory.DISCLOSURE && this.expanded ? 90 : 0 });
      }
      .width('100%')
      .constraintSize({ minHeight: HitaDesign.rowMinHeight })
      .padding({ left: HitaDesign.inset, right: HitaDesign.inset })
      .alignItems(VerticalAlign.Center)
      .accessibilityDescription(this.accessory === HitaRowAccessory.DISCLOSURE ?
        (this.expanded ? '已展开' : '已收起') : '')
      .onClick(() => {
        this.onTap();
      });
    }
    .width('100%');
  }
}
