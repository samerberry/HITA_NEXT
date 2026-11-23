import { HitaDesign } from '../../common/theme/HitaDesign';
import { WeekCalendar } from '../../feature/widget/WeekCalendar';
import { WidgetBrand } from '../../feature/widget/WidgetBrand';
import { AgendaRow, AgendaView, WidgetAgenda, WidgetTab } from '../../feature/widget/WidgetAgenda';
import { WeekItem, WidgetDay, WidgetWeek } from '../../feature/widget/WidgetWeek';

const storage = new LocalStorage();
const weekdays: string[] = ['一', '二', '三', '四', '五', '六', '日'];
const COMPACT_FORM: number = 3;
const COMPACT_TRACK_INSET: number = HitaDesign.space2xs / 2;

@Entry(storage)
@Component
struct WeekTimetableCard {
  @LocalStorageProp('formDimension') @Watch('changeDimension') dimension: number = 4;
  @LocalStorageProp('weekJson') @Watch('updateWeek') weekJson: string = '';
  @LocalStorageProp('hasTimetable') @Watch('refresh') hasTimetable: boolean = false;
  @LocalStorageProp('dataState') @Watch('refresh') dataState: string = 'loading';
  @LocalStorageProp('taskJson') @Watch('updateTasks') taskJson: string = '';
  @State week: WidgetWeek = new WidgetWeek();
  @State agenda: AgendaView = new AgendaView();
  @State tasks: boolean = false;
  @State selectedDay: number = 0;
  private lastDay: number = -1;
  private requestedWeek: number = -1;
  private ticker: TextTimerController = new TextTimerController();

  aboutToAppear(): void {
    this.refresh();
  }

  private updateWeek(): void {
    const now = Date.now();
    const day = WidgetWeek.dayOffset(now, 0);
    const week = WidgetWeek.view(this.weekJson, this.hasTimetable, this.dataState, now, this.dimension !== COMPACT_FORM);
    if (day !== this.lastDay) this.selectedDay = week.today;
    this.lastDay = day;
    this.week = week;
    const monday = WidgetWeek.monday(now);
    if (week.stale && this.requestedWeek !== monday) {
      this.requestedWeek = monday;
      postCardAction(this, { action: 'message', params: { refresh: 'week' } });
    }
  }

  private updateTasks(): void {
    if (this.dimension !== COMPACT_FORM) return;
    this.agenda = WidgetAgenda.view(WidgetTab.TASK, this.taskJson, this.dataState === 'loading', Date.now());
  }

  private refresh(): void {
    this.updateWeek();
    this.updateTasks();
  }

  private changeDimension(): void {
    this.lastDay = -1;
    this.refresh();
  }

  private openItem(id: string, task: boolean): void {
    const params: Record<string, string> = {};
    params[task ? 'hitaLearningTaskId' : 'hitaReminderEventId'] = id;
    postCardAction(this, { action: 'router', abilityName: 'EntryAbility', params: params });
  }

  @Builder
  segment(label: string, tasks: boolean) {
    Text(label)
      .fontSize(HitaDesign.label)
      .fontWeight(this.tasks === tasks ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.tasks === tasks ? $r('app.color.hita_primary') : $r('app.color.hita_text_secondary'))
      .backgroundColor(this.tasks === tasks ? $r('app.color.hita_surface') : Color.Transparent)
      .borderRadius(HitaDesign.radiusSm)
      .padding({ left: 12, right: 12 })
      .height('100%')
      .textAlign(TextAlign.Center)
      .onClick((): void => { this.tasks = tasks; })
  }

  @Builder
  header() {
    Row() {
      WidgetBrand({ followsSystemSurface: true })
      Text(this.tasks ? (this.agenda.rows.length > 0 ? this.agenda.rows.length + ' 项未完成' : '') : this.week.range)
        .fontSize(HitaDesign.label).fontColor($r('app.color.hita_text_secondary')).maxLines(1)
        .layoutWeight(1).textAlign(TextAlign.Center)
      Row() {
        Row() {
          this.segment('课表', false)
          this.segment('待办', true)
        }.padding(COMPACT_TRACK_INSET).height(28).borderRadius(HitaDesign.radiusMd).backgroundColor($r('app.color.hita_control'))
      }.justifyContent(FlexAlign.End)
    }.width('100%')
    .padding({ left: HitaDesign.spaceSm, right: HitaDesign.spaceSm })
  }

  @Builder
  notice() {
    Text(this.tasks ? this.agenda.message : (this.week.message || '当天没有课程或考试'))
      .fontSize(HitaDesign.caption)
      .fontColor($r('app.color.hita_text_secondary'))
      .textAlign(TextAlign.Center)
      .width('100%').layoutWeight(1)
  }

  @Builder
  dates() {
    Row({ space: COMPACT_TRACK_INSET }) {
      ForEach(this.week.days, (day: WidgetDay) => {
        Column() {
          Text(weekdays[day.index]).fontSize(HitaDesign.dockLabel)
            .fontColor($r('app.color.hita_text_secondary'))
          Text(day.numeral).fontSize(HitaDesign.caption).fontWeight(FontWeight.Bold)
            .fontColor(day.index === this.week.today ? $r('app.color.hita_primary') : $r('app.color.hita_text'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
        .borderRadius(HitaDesign.radiusSm)
        .backgroundColor(day.index === this.selectedDay ?
          $r('app.color.hita_selected') : Color.Transparent)
        .accessibilityText('周' + weekdays[day.index] + '，' + day.numeral + '日，' + day.items.length + '项安排')
        .onClick((): void => { this.selectedDay = day.index; })
      }, (day: WidgetDay): string => day.date.toString() + ':' + day.items.length)
    }.width('100%').padding({ left: HitaDesign.spaceXs, right: HitaDesign.spaceXs })
  }

  @Builder
  compactRow(item: WeekItem) {
    Row({ space: 8 }) {
      Text(WidgetWeek.clock(item.start)).fontSize(HitaDesign.label)
        .fontWeight(FontWeight.Medium).fontColor($r('app.color.hita_text_secondary'))
      Text((item.exam ? '考试 · ' : '') + item.name).layoutWeight(1)
        .fontSize(HitaDesign.caption).fontWeight(FontWeight.Medium)
        .fontColor(item.exam ? $r('app.color.hita_error') : $r('app.color.hita_text'))
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      if (item.place) {
        Text(item.place).constraintSize({ maxWidth: '28%' }).fontSize(HitaDesign.label)
          .fontColor($r('app.color.hita_text_secondary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }.width('100%').constraintSize({ minHeight: 28 }).onClick((): void => this.openItem(item.id, false))
  }

  @Builder
  dayAgenda() {
    List({ space: HitaDesign.space2xs }) {
      ForEach(this.week.days[this.selectedDay]?.items ?? [], (item: WeekItem) => {
        ListItem() { this.compactRow(item) }
      }, (item: WeekItem): string => JSON.stringify(item))
    }.width('100%').layoutWeight(1).scrollBar(BarState.Auto)
    .padding({ left: HitaDesign.spaceSm, right: HitaDesign.spaceSm })
  }

  @Builder
  taskAgenda() {
    List({ space: 4 }) {
      ForEach(this.agenda.rows, (row: AgendaRow) => {
        ListItem() {
          Column({ space: 4 }) {
            Text(row.title).fontSize(HitaDesign.caption).fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.hita_text')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            Text((row.status === '已逾期' ? '逾期 · ' : '') + row.when + ' · ' + row.detail)
              .fontSize(HitaDesign.label).fontColor(row.status === '已逾期' ?
                $r('app.color.hita_error') : $r('app.color.hita_text_secondary'))
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }.alignItems(HorizontalAlign.Start).width('100%').padding({ top: 4, bottom: 4 })
          .onClick((): void => this.openItem(row.id, true))
        }
      }, (row: AgendaRow): string => JSON.stringify(row))
    }.width('100%').layoutWeight(1).scrollBar(BarState.Auto)
    .padding({ left: HitaDesign.spaceSm, right: HitaDesign.spaceSm })
  }

  build() {
    Stack() {
      if (this.dimension !== COMPACT_FORM) {
        WeekCalendar({ week: this.week, selectedDay: this.selectedDay,
          selectDay: (index: number): void => { this.selectedDay = index; },
          openItem: (id: string): void => this.openItem(id, false) })
      } else {
        Column({ space: 4 }) {
          this.header()
          if (this.tasks) {
            if (this.agenda.rows.length) { this.taskAgenda() } else { this.notice() }
          } else {
            this.dates()
            if (!this.week.message && this.week.days[this.selectedDay]?.items.length) {
              this.dayAgenda()
            } else {
              this.notice()
            }
          }
        }.width('100%').height('100%').padding({ top: HitaDesign.spaceXs, bottom: HitaDesign.spaceXs })
      }
      TextTimer({ isCountDown: false, controller: this.ticker }).format('mm')
        .width(12).height(12).fontSize(HitaDesign.dockLabel).opacity(0.01).position({ x: 0, y: 0 })
        .accessibilityLevel('no').hitTestBehavior(HitTestMode.None)
        .onAppear((): void => { this.ticker.start(); })
        .onTimer((): void => {
          const now = Date.now();
          if (now >= this.week.nextChange || this.lastDay !== WidgetWeek.dayOffset(now, 0)) this.updateWeek();
          if (this.dimension === COMPACT_FORM && now >= this.agenda.nextChange) this.updateTasks();
        })
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.hita_surface'))
    .borderRadius($r('sys.float.ohos_id_corner_radius_card')).clip(true)
    .onAppear((): void => this.refresh())
  }
}
