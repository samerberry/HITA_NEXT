import { HitaColors } from '../theme/HitaColors';
import { HitaDesign } from '../theme/HitaDesign';

export interface SelectionSheetOption {
  id: string;
  title: string;
  subtitle: string;
}

@Component
export struct SelectionSheetList {
  @Prop title: string = '';
  @Prop options: SelectionSheetOption[] = [];
  onSelect: (id: string) => void = (_id: string) => {};

  build() {
    Column() {
      Text(this.title)
        .width('100%')
        .padding({ left: HitaDesign.inset, right: HitaDesign.inset, bottom: HitaDesign.spaceXs })
        .fontSize(HitaDesign.title)
        .fontWeight(FontWeight.Medium)
        .fontColor(HitaColors.onSurface)
      List() {
        ForEach(this.options, (option: SelectionSheetOption) => {
          ListItem() {
            Column({ space: HitaDesign.space2xs }) {
              Text(option.title)
                .fontSize(HitaDesign.body)
                .fontColor(HitaColors.onSurface)
              if (option.subtitle.length > 0) {
                Text(option.subtitle)
                  .fontSize(HitaDesign.caption)
                  .fontColor(HitaColors.onSurfaceVariant)
              }
            }
            .width('100%')
            .constraintSize({ minHeight: HitaDesign.rowMinHeight })
            .padding({ left: HitaDesign.inset, right: HitaDesign.inset,
              top: HitaDesign.spaceXs, bottom: HitaDesign.spaceXs })
            .alignItems(HorizontalAlign.Start)
            .justifyContent(FlexAlign.Center)
          }
          .accessibilityGroup(true)
          .onClick(() => this.onSelect(option.id))
        }, (option: SelectionSheetOption): string => option.id)
      }
      .width('100%')
      .layoutWeight(1)
      .divider({ strokeWidth: HitaDesign.hairline, color: HitaColors.divider,
        startMargin: HitaDesign.inset, endMargin: HitaDesign.inset })
      .contentEndOffset(HitaDesign.spaceMd)
      .nestedScroll({ scrollForward: NestedScrollMode.SELF_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST })
    }
    .width('100%')
    .layoutWeight(1)
  }
}
