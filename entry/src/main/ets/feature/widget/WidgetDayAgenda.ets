import { HitaDesign } from '../../common/theme/HitaDesign';
import { HitaTag, HitaTagTone } from '../../common/components/HitaTag';
import { WeekItem, WidgetDay, WidgetWeek } from './WidgetWeek';

@Component
export struct WidgetDayAgenda {
  @Prop day: WidgetDay = new WidgetDay();
  @Prop message: string = '';
  @Prop emptyLabel: string = '这一天没有课程或考试';
  @Prop compact: boolean = false;
  @Prop followsSystemSurface: boolean = true;
  openItem: (id: string) => void = (): void => {};

  @Builder
  compactEvent(item: WeekItem) {
    Column({ space: HitaDesign.space2xs }) {
      Text((item.exam ? '考试 · ' : '') + item.name).width('100%')
        .fontSize(HitaDesign.label).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.hita_text')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      Row({ space: HitaDesign.space2xs }) {
        Text(WidgetWeek.clock(item.start) + '–' + WidgetWeek.clock(item.end) + (item.place ? ' · ' + item.place : ''))
          .fontSize(HitaDesign.widgetLabel).fontColor($r('app.color.hita_text_secondary')).layoutWeight(1)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(item.status ?? '').fontSize(HitaDesign.widgetLabel).maxLines(1).flexShrink(0)
          .fontColor(item.status === '进行中' ? $r('app.color.hita_primary') : $r('app.color.hita_text_secondary'))
      }.width('100%')
    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
  }

  @Builder
  fullEvent(item: WeekItem) {
    Column({ space: HitaDesign.space2xs }) {
      Text(WidgetWeek.clock(item.start)).fontSize(HitaDesign.caption).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.hita_text'))
      Text(WidgetWeek.clock(item.end)).fontSize(HitaDesign.label).fontColor($r('app.color.hita_text_secondary'))
    }.alignItems(HorizontalAlign.Start).flexShrink(0)
    Column({ space: HitaDesign.space2xs }) {
      Text((item.exam ? '考试 · ' : '') + item.name).fontSize(HitaDesign.caption).fontWeight(FontWeight.Medium)
        .lineHeight(HitaDesign.body)
        .fontColor($r('app.color.hita_text')).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      if (item.place || item.teacher) {
        Text(WidgetWeek.subtitle(item)).fontSize(HitaDesign.label).fontColor($r('app.color.hita_text_secondary'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    Column({ space: HitaDesign.space2xs }) {
      HitaTag({ text: item.status ?? '', compact: true,
        tone: item.status === '进行中' ? HitaTagTone.BRAND : HitaTagTone.NEUTRAL })
      if (item.period) {
        Text(item.period).fontSize(HitaDesign.widgetLabel).fontColor($r('app.color.hita_text_secondary')).maxLines(1)
      }
    }.alignItems(HorizontalAlign.End).flexShrink(0)
  }

  @Builder
  eventRow(item: WeekItem) {
    Row({ space: this.compact ? HitaDesign.space2xs : HitaDesign.spaceXs }) {
      Row().width(HitaDesign.space2xs).height(this.compact ? HitaDesign.spaceLg : HitaDesign.controlHeight)
        .borderRadius(HitaDesign.radiusSm)
        .backgroundColor($r('app.color.hita_primary')).opacity(item.status === '已结束' ? 0.6 : 1)
      if (this.compact) {
        this.compactEvent(item)
      } else {
        this.fullEvent(item)
      }
    }.width('100%').height(this.compact ? HitaDesign.minTouchTarget : HitaDesign.rowMinHeight)
    .alignItems(VerticalAlign.Center)
    .padding({ left: this.compact ? HitaDesign.space2xs : HitaDesign.spaceSm,
      right: this.compact ? HitaDesign.spaceXs : HitaDesign.spaceSm,
      top: HitaDesign.space2xs, bottom: HitaDesign.space2xs })
    .backgroundColor($r('app.color.hita_surface'))
    .borderRadius(this.compact ? HitaDesign.radiusMd : HitaDesign.cardRadius)
    .border({ width: HitaDesign.hairline, color: $r('app.color.hita_divider') })
    .accessibilityText((item.exam ? '考试，' : '课程，') + item.name + '，' + (item.period ? item.period + '，' : '') +
      WidgetWeek.clock(item.start) + '至' + WidgetWeek.clock(item.end) + '，' + (item.status ?? '') +
      (item.place || item.teacher ? '，' + WidgetWeek.subtitle(item) : ''))
    .onClick((): void => this.openItem(item.id))
  }

  build() {
    Column() {
      if (this.message || !this.day.items.length) {
        Column({ space: HitaDesign.spaceXs }) {
          if (!this.compact) {
            Image($r('app.media.widget_empty_calendar')).width(112).aspectRatio(1.6)
              .objectFit(ImageFit.Contain).accessibilityLevel('no')
          }
          Text(this.message || this.emptyLabel).fontSize(HitaDesign.caption).textAlign(TextAlign.Center)
            .fontColor(this.followsSystemSurface ? $r('app.color.hita_text_secondary') : $r('app.color.widget_muted'))
        }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        List({ space: this.compact ? HitaDesign.space2xs : HitaDesign.spaceXs }) {
          ForEach(this.day.items, (item: WeekItem) => {
            ListItem() { this.eventRow(item) }
          }, (item: WeekItem): string => JSON.stringify(item))
        }.width('100%').layoutWeight(1).scrollBar(BarState.Auto)
      }
    }.width('100%').layoutWeight(1)
  }
}
