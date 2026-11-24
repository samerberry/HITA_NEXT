import { HitaDesign } from '../../common/theme/HitaDesign';
import { WidgetBrand } from './WidgetBrand';
import { WidgetDayAgenda } from './WidgetDayAgenda';
import { WidgetDay, WidgetWeek } from './WidgetWeek';

const WEEKDAYS: string[] = ['日', '一', '二', '三', '四', '五', '六'];

@Component
export struct WeekCalendarHeader {
  @Prop termLabel: string = '';

  build() {
    Row() {
      WidgetBrand({ followsSystemSurface: true })
      Text(this.termLabel).fontSize(HitaDesign.caption).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.hita_text_secondary')).maxLines(1)
    }.width('100%').justifyContent(FlexAlign.SpaceBetween)
  }
}

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

  private dayInk(day: WidgetDay, ordinary: ResourceColor): ResourceColor {
    if (day.index === this.selectedDay) {
      return day.index === this.week.today ? $r('app.color.hita_on_primary') : $r('app.color.hita_primary');
    }
    return day.index === this.week.today ? $r('app.color.hita_primary') : ordinary;
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

  build() {
    Column({ space: HitaDesign.spaceXs }) {
      WeekCalendarHeader({ termLabel: WidgetWeek.termLabel(this.week.days[this.selectedDay]) })
      this.dateStrip()
      // A different day starts its list at the top, even if the previous day's list was scrolled.
      ForEach(this.week.days.slice(this.selectedDay, this.selectedDay + 1), (day: WidgetDay) => {
        WidgetDayAgenda({ day: day, message: this.week.message, openItem: this.openItem })
      }, (day: WidgetDay): string => JSON.stringify(day) + this.week.message + ':' + this.week.today)
    }.width('100%').height('100%').padding(HitaDesign.spaceSm).backgroundColor($r('app.color.hita_page'))
  }
}
