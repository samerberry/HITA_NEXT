import { HitaDesign } from '../../common/theme/HitaDesign';
import { HitaTag, HitaTagTone } from '../../common/components/HitaTag';
import { WidgetBrand } from '../../feature/widget/WidgetBrand';
import { AgendaRow, AgendaView, WidgetAgenda, WidgetTab } from '../../feature/widget/WidgetAgenda';
import { WeekItem, WidgetDay, WidgetWeek } from '../../feature/widget/WidgetWeek';

const storage = new LocalStorage();
const weekdays: string[] = ['一', '二', '三', '四', '五', '六', '日'];
const TALL_FORM: number = 7; // 系统的 6×4（四列六行）
const SQUARE_SCROLL_FROM: number = 6;
const EXAM_ROW_HEIGHT: number = 28;

@Entry(storage)
@Component
struct WeekTimetableCard {
  @LocalStorageProp('formDimension') @Watch('fitCourses') dimension: number = 4;
  @LocalStorageProp('weekJson') @Watch('updateWeek') weekJson: string = '';
  @LocalStorageProp('hasTimetable') @Watch('refresh') hasTimetable: boolean = false;
  @LocalStorageProp('dataState') @Watch('refresh') dataState: string = 'loading';
  @LocalStorageProp('taskJson') @Watch('updateTasks') taskJson: string = '';
  @State @Watch('fitCourses') week: WidgetWeek = new WidgetWeek();
  @State agenda: AgendaView = new AgendaView();
  @State tasks: boolean = false;
  @State @Watch('fitCourses') selectedDay: number = 0;
  @State fittedCourseHeight: number = 0; // Zero preserves the original, content-sized course card.
  @State courseListGap: number = HitaDesign.spaceXs;
  @State coursesFirst: boolean = false;
  private agendaHeight: number = 0;
  @State currentMinute: number = Math.floor(Date.now() / 60000);
  private lastDay: number = -1;
  private requestedWeek: number = -1;
  private ticker: TextTimerController = new TextTimerController();

  aboutToAppear(): void {
    this.refresh();
  }

  private updateWeek(): void {
    const now = Date.now();
    const day = WidgetWeek.dayOffset(now, 0);
    const week = WidgetWeek.view(this.weekJson, this.hasTimetable, this.dataState, now);
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
    this.agenda = WidgetAgenda.view(WidgetTab.TASK, this.taskJson, this.dataState === 'loading', Date.now());
  }

  private refresh(): void {
    this.currentMinute = Math.floor(Date.now() / 60000);
    this.updateWeek();
    this.updateTasks();
  }

  private openItem(id: string, task: boolean): void {
    const params: Record<string, string> = {};
    params[task ? 'hitaLearningTaskId' : 'hitaReminderEventId'] = id;
    postCardAction(this, { action: 'router', abilityName: 'EntryAbility', params: params });
  }

  private fitCourses(): void {
    const day = this.week.days[this.selectedDay];
    let height: number = 0;
    let gap = this.dimension === 3 ? HitaDesign.space2xs : HitaDesign.spaceXs;
    let coursesFirst: boolean = false;
    if (day && this.agendaHeight > 0 && this.dimension !== 3) {
      const courses = day.items.filter((item: WeekItem): boolean => !item.exam).length;
      const exams = day.items.length - courses;
      const tall = this.dimension === TALL_FORM;
      if (courses > (tall ? 4 : 2)) {
        const slots = Math.min(courses, tall ? 8 : SQUARE_SCROLL_FROM - 1);
        gap = !tall && courses >= SQUARE_SCROLL_FROM ? HitaDesign.spaceXs : HitaDesign.space2xs;
        const available = this.agendaHeight - (slots - 1) * HitaDesign.space2xs;
        const examSpace = exams * (EXAM_ROW_HEIGHT + HitaDesign.space2xs);
        // An unusually exam-heavy day must not push a course off screen. Keep exams reachable below.
        coursesFirst = exams > 0 && available - examSpace < slots * HitaDesign.spaceLg;
        height = Math.max(1, Math.min(HitaDesign.rowMinHeight,
          Math.floor((available - (coursesFirst ? 0 : examSpace)) / slots)));
      } else if (courses > 0 && exams > 0) {
        // Allow for two lines, the status tag and the active course's progress bar at the original size.
        coursesFirst = courses * 92 + exams * EXAM_ROW_HEIGHT +
          (day.items.length - 1) * HitaDesign.spaceXs > this.agendaHeight;
      }
    }
    if (this.coursesFirst !== coursesFirst) this.coursesFirst = coursesFirst;
    if (this.courseListGap !== gap) this.courseListGap = gap;
    if (this.fittedCourseHeight !== height) this.fittedCourseHeight = height;
  }

  private dayItems(): WeekItem[] {
    const items = this.week.days[this.selectedDay]?.items ?? [];
    if (!this.coursesFirst) return items;
    return items.filter((item: WeekItem): boolean => !item.exam)
      .concat(items.filter((item: WeekItem): boolean => item.exam));
  }

  private courseDetails(item: WeekItem): string {
    return item.teacher ? (item.place ? item.place + ' · ' : '') + item.teacher : item.place;
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
      Row() { WidgetBrand({ followsSystemSurface: true }) }
        .layoutWeight(1).justifyContent(FlexAlign.Start)
      Text(this.tasks ? (this.agenda.rows.length > 0 ? this.agenda.rows.length + ' 项未完成' : '') : this.week.range)
        .fontSize(HitaDesign.label).fontColor($r('app.color.hita_text_secondary')).maxLines(1)
        .textAlign(TextAlign.Center)
      Row() {
        Row() {
          this.segment('课表', false)
          this.segment('待办', true)
        }.padding(2).height(28).borderRadius(HitaDesign.radiusMd).backgroundColor($r('app.color.hita_control'))
      }.layoutWeight(1).justifyContent(FlexAlign.End)
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
    Row({ space: 2 }) {
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
    }.width('100%').height(this.fittedCourseHeight > 0 ? EXAM_ROW_HEIGHT : undefined)
    .constraintSize({ minHeight: EXAM_ROW_HEIGHT }).onClick((): void => this.openItem(item.id, false))
  }

  private ongoing(item: WeekItem): boolean {
    const now = this.currentMinute * 60000;
    return item.start <= now && now < item.end;
  }

  private courseStatus(item: WeekItem): string {
    const now = this.currentMinute * 60000;
    if (now >= item.end) return '已结束';
    if (now >= item.start) return '进行中';
    const minutes = Math.ceil((item.start - now) / 60000);
    return minutes <= 30 ? minutes + '分钟后' : '';
  }

  @Builder
  courseCard(item: WeekItem) {
    Row({ space: HitaDesign.spaceSm }) {
      Row().width(HitaDesign.space2xs).height(HitaDesign.controlHeight)
        .borderRadius(HitaDesign.space2xs / 2)
        .backgroundColor(item.railColor ?? $r('app.color.hita_primary'))
      Column({ space: HitaDesign.space2xs }) {
        Text(WidgetWeek.clock(item.start)).fontSize(HitaDesign.body).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.hita_text')).maxLines(1)
        Text(WidgetWeek.clock(item.end)).fontSize(HitaDesign.caption)
          .fontColor($r('app.color.hita_text_hint')).maxLines(1)
      }.width(52).alignItems(HorizontalAlign.Start)
      Column() {
        Row({ space: HitaDesign.spaceXs }) {
          Text(item.name).fontSize(HitaDesign.body).fontWeight(FontWeight.Medium).layoutWeight(1)
            .fontColor($r('app.color.hita_text')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.courseStatus(item)) {
            HitaTag({ text: this.courseStatus(item),
              tone: item.end <= this.currentMinute * 60000 ? HitaTagTone.NEUTRAL : HitaTagTone.BRAND })
          }
        }.width('100%')
        if (item.place || item.teacher) {
          Text(this.courseDetails(item))
            .fontSize(HitaDesign.caption).fontColor($r('app.color.hita_text_secondary'))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).margin({ top: HitaDesign.space2xs })
        }
        if (this.ongoing(item)) {
          Progress({ value: (this.currentMinute * 60000 - item.start) / (item.end - item.start) * 100,
            total: 100, type: ProgressType.Linear })
            .width('100%').height(HitaDesign.space2xs).color($r('app.color.hita_primary'))
            .backgroundColor($r('app.color.hita_selected_e8f1fb')).margin({ top: HitaDesign.spaceXs })
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    }
    .width('100%').padding(HitaDesign.inset).alignItems(VerticalAlign.Center)
    .backgroundColor($r('app.color.hita_surface')).borderRadius(HitaDesign.cardRadius)
    .border({ width: this.ongoing(item) ? 1.5 : 1,
      color: this.ongoing(item) ? $r('app.color.hita_focus') : $r('app.color.hita_divider_edf1f7') })
    .onClick((): void => this.openItem(item.id, false))
  }

  @Builder
  fittedCourseCard(item: WeekItem) {
    Row({ space: HitaDesign.spaceXs }) {
      Row().width(HitaDesign.space2xs).height(Math.max(1, Math.min(HitaDesign.controlHeight, this.fittedCourseHeight - 8)))
        .borderRadius(HitaDesign.space2xs / 2).backgroundColor(item.railColor ?? $r('app.color.hita_primary'))
      if (this.fittedCourseHeight >= 40) {
        Column() {
          Text(WidgetWeek.clock(item.start)).fontSize(HitaDesign.caption).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.hita_text')).maxLines(1)
          Text(WidgetWeek.clock(item.end)).fontSize(HitaDesign.label)
            .fontColor($r('app.color.hita_text_hint')).maxLines(1)
        }.width(48).alignItems(HorizontalAlign.Start)
      } else {
        Text(WidgetWeek.clock(item.start) + '–' + WidgetWeek.clock(item.end)).fontSize(HitaDesign.label)
          .fontColor($r('app.color.hita_text_secondary')).maxLines(1)
      }
      Column() {
        Text() {
          Span(item.name)
          if (this.fittedCourseHeight < 40 && (item.place || item.teacher)) {
            Span(' · ' + this.courseDetails(item)).fontSize(HitaDesign.label).fontColor($r('app.color.hita_text_secondary'))
          }
        }.fontSize(HitaDesign.caption).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.hita_text')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.fittedCourseHeight >= 40 && (item.place || item.teacher)) {
          Text(this.courseDetails(item))
            .fontSize(HitaDesign.label).fontColor($r('app.color.hita_text_secondary'))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        if (this.ongoing(item)) {
          Progress({ value: (this.currentMinute * 60000 - item.start) / (item.end - item.start) * 100,
            total: 100, type: ProgressType.Linear })
            .width('100%').height(2).color($r('app.color.hita_primary')).backgroundColor($r('app.color.hita_selected_e8f1fb'))
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      if (this.courseStatus(item)) {
        HitaTag({ text: this.courseStatus(item),
          tone: item.end <= this.currentMinute * 60000 ? HitaTagTone.NEUTRAL : HitaTagTone.BRAND })
      }
    }.width('100%').height(this.fittedCourseHeight)
    .padding({ left: HitaDesign.spaceXs, right: HitaDesign.spaceXs }).alignItems(VerticalAlign.Center)
    .backgroundColor($r('app.color.hita_surface')).borderRadius(HitaDesign.radiusMd)
    .border({ width: this.ongoing(item) ? 1.5 : 1,
      color: this.ongoing(item) ? $r('app.color.hita_focus') : $r('app.color.hita_divider_edf1f7') })
    .onClick((): void => this.openItem(item.id, false))
  }

  @Builder
  dayAgenda() {
    List({ space: this.courseListGap }) {
      ForEach(this.dayItems(), (item: WeekItem) => {
        ListItem() {
          if (this.fittedCourseHeight > 0 && !item.exam) {
            this.fittedCourseCard(item)
          } else if (this.dimension !== 3 && !item.exam) {
            this.courseCard(item)
          } else {
            this.compactRow(item)
          }
        }
      }, (item: WeekItem): string => JSON.stringify(item))
    }.width('100%').layoutWeight(1).scrollBar(BarState.Auto)
    .padding({ left: HitaDesign.spaceSm, right: HitaDesign.spaceSm })
    .onSizeChange((_old: SizeOptions, size: SizeOptions): void => {
      const height = Math.floor(Number(size.height));
      if (height > 0 && height !== this.agendaHeight) {
        this.agendaHeight = height;
        this.fitCourses();
      }
    })
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
      TextTimer({ isCountDown: false, controller: this.ticker }).format('mm')
        .width(12).height(12).fontSize(8).opacity(0.01).position({ x: 0, y: 0 })
        .accessibilityLevel('no').hitTestBehavior(HitTestMode.None)
        .onAppear((): void => { this.ticker.start(); })
        .onTimer((): void => {
          const now = Date.now();
          if (this.dimension !== 3) this.currentMinute = Math.floor(now / 60000);
          if (this.lastDay !== WidgetWeek.dayOffset(now, 0)) this.updateWeek();
          if (now >= this.agenda.nextChange) this.updateTasks();
        })
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.hita_surface'))
    .borderRadius($r('sys.float.ohos_id_corner_radius_card')).clip(true)
    .onAppear((): void => this.refresh())
  }
}
