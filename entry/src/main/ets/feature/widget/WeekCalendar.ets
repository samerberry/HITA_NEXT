import { HitaDesign } from '../../common/theme/HitaDesign';
import { HitaTag, HitaTagTone } from '../../common/components/HitaTag';
import { WidgetBrand } from './WidgetBrand';
import { WeekItem, WidgetDay, WidgetWeek } from './WidgetWeek';

const WEEKDAYS: string[] = ['日', '一', '二', '三', '四', '五', '六'];

@Component
export struct WeekCalendar {
  @Prop week: WidgetWeek = new WidgetWeek();
  @Prop selectedDay: number = 0;
  selectDay: (index: number) => void = (): void => {};
  openItem: (id: string) => void = (): void => {};

  private dateLabel(day: WidgetDay): string {
    const date = new Date(day.date);
    return (date.getMonth() + 1) + '月' + day.numeral + '日，星期' + WEEKDAYS[day.index % 7] +
      (day.index === this.week.today ? '，今天' : '') + (day.index === this.selectedDay ? '，已选择' : '') +
      (day.hasEvents ? '，有日程' : '');
  }

  private termLabel(): string {
    const day = this.week.days[this.selectedDay];
    if (!day) return '';
    return (new Date(day.date).getMonth() + 1) + '月' + (day.teachingWeek > 0 ? '  ·  第' + day.teachingWeek + '周' : '');
  }

  private dayInk(day: WidgetDay, ordinary: ResourceColor): ResourceColor {
    if (day.index === this.selectedDay) {
      return day.index === this.week.today ? $r('app.color.hita_on_primary') : $r('app.color.hita_primary');
    }
    return day.index === this.week.today ? $r('app.color.hita_primary') : ordinary;
  }

  @Builder
  brandHeader() {
    Row() {
      WidgetBrand({ followsSystemSurface: true })
      Text(this.termLabel()).fontSize(HitaDesign.caption).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.hita_text_secondary')).maxLines(1)
    }.width('100%').justifyContent(FlexAlign.SpaceBetween)
  }

  @Builder
  dateStrip() {
    Row() {
      ForEach(this.week.days, (day: WidgetDay) => {
        Column() {
          Column() {
            Text(WEEKDAYS[day.index % 7]).fontSize(HitaDesign.widgetLabel).maxLines(1)
              .fontColor(this.dayInk(day, $r('app.color.hita_text_secondary')))
            Text(day.numeral).fontSize(HitaDesign.body).fontWeight(FontWeight.Bold)
              .fontColor(this.dayInk(day, $r('app.color.hita_text'))).maxLines(1)
            Row().width(HitaDesign.spaceXs).height(HitaDesign.space2xs).borderRadius(HitaDesign.radiusSm)
              .backgroundColor(day.hasEvents ? this.dayInk(day, $r('app.color.hita_primary')) : Color.Transparent)
          }.width('100%').height(HitaDesign.compactControlHeight).justifyContent(FlexAlign.Center)
          .borderRadius(HitaDesign.radiusSm)
          .backgroundColor(day.index !== this.selectedDay ? Color.Transparent : (day.index === this.week.today ?
            $r('app.color.hita_primary_fill') : $r('app.color.hita_selected')))
        }.layoutWeight(1).height(HitaDesign.minTouchTarget).justifyContent(FlexAlign.Center)
        .accessibilityText(this.dateLabel(day)).onClick((): void => this.selectDay(day.index))
      }, (day: WidgetDay): string => day.date + ':' + day.hasEvents + ':' + (day.index === this.selectedDay) +
        ':' + (day.index === this.week.today))
    }.width('100%').padding({ left: HitaDesign.space2xs, right: HitaDesign.space2xs })
    .backgroundColor($r('app.color.hita_surface'))
    .borderRadius(HitaDesign.cardRadius)
  }

  @Builder
  eventRow(item: WeekItem) {
    Row({ space: HitaDesign.spaceXs }) {
      Row().width(HitaDesign.space2xs).height(HitaDesign.controlHeight).borderRadius(HitaDesign.radiusSm)
        .backgroundColor($r('app.color.hita_primary')).opacity(item.status === '已结束' ? 0.6 : 1)
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
    }.width('100%').height(HitaDesign.rowMinHeight).alignItems(VerticalAlign.Center)
    .padding({ left: HitaDesign.spaceSm, right: HitaDesign.spaceSm, top: HitaDesign.space2xs, bottom: HitaDesign.space2xs })
    .backgroundColor($r('app.color.hita_surface')).borderRadius(HitaDesign.cardRadius)
    .border({ width: HitaDesign.hairline, color: $r('app.color.hita_divider') })
    .accessibilityText((item.exam ? '考试，' : '课程，') + item.name + '，' + (item.period ? item.period + '，' : '') +
      WidgetWeek.clock(item.start) + '至' + WidgetWeek.clock(item.end) + '，' + (item.status ?? '') +
      (item.place || item.teacher ? '，' + WidgetWeek.subtitle(item) : ''))
    .onClick((): void => this.openItem(item.id))
  }

  @Builder
  emptyDay() {
    Column({ space: HitaDesign.spaceXs }) {
      Image($r('app.media.widget_empty_calendar')).width(112).aspectRatio(1.6)
        .objectFit(ImageFit.Contain).accessibilityLevel('no')
      Text(this.week.message || '这一天没有课程或考试')
        .fontSize(HitaDesign.caption).fontColor($r('app.color.hita_text_secondary')).textAlign(TextAlign.Center)
    }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
  }

  @Builder
  dayPage(day: WidgetDay) {
    Column() {
      if (this.week.message || !day.items.length) {
        this.emptyDay()
      } else {
        List({ space: HitaDesign.spaceXs }) {
          ForEach(day.items, (item: WeekItem) => {
            ListItem() { this.eventRow(item) }
          }, (item: WeekItem): string => JSON.stringify(item))
        }.width('100%').layoutWeight(1).scrollBar(BarState.Auto)
      }
    }.width('100%').layoutWeight(1)
  }

  build() {
    Column({ space: HitaDesign.spaceXs }) {
      this.brandHeader()
      this.dateStrip()
      // A different day starts its list at the top, even if the previous day's list was scrolled.
      ForEach(this.week.days.slice(this.selectedDay, this.selectedDay + 1), (day: WidgetDay) => {
        this.dayPage(day)
      }, (day: WidgetDay): string => JSON.stringify(day) + this.week.message + ':' + this.week.today)
    }.width('100%').height('100%').padding(HitaDesign.spaceSm).backgroundColor($r('app.color.hita_page'))
  }
}
