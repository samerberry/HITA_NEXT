import { NextClassModel, NextClassView } from '../../feature/widget/NextClassModel';
import { WidgetBrand } from '../../feature/widget/WidgetBrand';
import { AgendaRow, AgendaView, WidgetAgenda, WidgetTab } from '../../feature/widget/WidgetAgenda';
import { WidgetDayAgenda } from '../../feature/widget/WidgetDayAgenda';
import { WidgetWeek } from '../../feature/widget/WidgetWeek';
import { HitaDesign } from '../../common/theme/HitaDesign';

const storage: LocalStorage = new LocalStorage();
const MARQUEE_STEP: number = 2.5;
const COMPACT_COUNTDOWN_SIZE: number = 32;
const COMPACT_RING_DIAMETER: number = 48;
const SMALL_FORM: number = 2;
const WIDE_FORM: number = 3;
const LARGE_FORM: number = 4;
// Space below the visible 后下课 glyphs inside the compact caption's 14 vp line.
const COMPACT_CAPTION_BOTTOM_INSET: number = 2.5;

@Entry(storage)
@Component
struct NextClassCard {
  @LocalStorageProp('scheduleJson') @Watch('refreshDisplay') scheduleJson: string = '[]';
  @LocalStorageProp('weekJson') @Watch('refreshDisplay') weekJson: string = '';
  @LocalStorageProp('examJson') @Watch('refreshDisplay') examJson: string = '';
  @LocalStorageProp('taskJson') @Watch('refreshDisplay') taskJson: string = '';
  @LocalStorageProp('hasTimetable') @Watch('refreshDisplay') hasTimetable: boolean = false;
  @LocalStorageProp('dataState') @Watch('refreshDisplay') dataState: string = 'loading';
  @LocalStorageProp('formDimension') dimension: number = SMALL_FORM;
  @LocalStorageProp('courseOnly') @Watch('refreshDisplay') courseOnly: boolean = false;
  // Images are baked at each card's aspect ratio; an empty name keeps the themed surface.
  @LocalStorageProp('bgCompact') bgCompact: string = '';
  @LocalStorageProp('bgWide') bgWide: string = '';
  @State hasCourse: boolean = false;
  @State hours: string = '';
  @State minutes: string = '';
  @State activeTab: WidgetTab = WidgetTab.COURSE;
  @State agenda: AgendaView = new AgendaView();
  @State todaySchedule: WidgetWeek = new WidgetWeek();
  @State title: string = '还没有课表';
  @State timeLabel: string = '';
  @State place: string = '地点待定';
  @State teacher: string = '教师待定';
  @State countdown: string = '—';
  @State countdownUnit: string = '打开应用添加课表';
  @State isOngoing: boolean = false;
  @State progressPercent: number = 0;
  // TextTimer never runs on its own: without start() onTimer is never dispatched.
  private ticker: TextTimerController = new TextTimerController();
  private requestedWeek: number = -1;

  aboutToAppear(): void {
    this.refreshDisplay();
  }

  private startTicker(): void {
    this.ticker.reset();
    this.ticker.start();
  }

  private onTick(elapsedTime: number): void {
    const nextChange = this.activeTab === WidgetTab.COURSE ? this.todaySchedule.nextChange : this.agenda.nextChange;
    if (this.courseOnly || Date.now() >= nextChange) this.refreshDisplay();
    // A count-up timer is not meant to run for days on a launcher; restart it periodically.
    if (elapsedTime >= 43200) this.startTicker();
  }

  private refreshDisplay(): void {
    const now = Date.now();
    if (this.activeTab !== WidgetTab.COURSE) {
      this.agenda = WidgetAgenda.view(this.activeTab, this.activeTab === WidgetTab.EXAM ? this.examJson : this.taskJson,
        this.dataState === 'loading', now);
      return;
    }
    if (!this.courseOnly) {
      this.refreshToday(now);
      return;
    }
    const nextView: NextClassView = NextClassModel.view(this.scheduleJson, this.hasTimetable, this.dataState, now);
    // Name, place, teacher and time are switched together from the same selected course.
    this.title = nextView.title;
    this.timeLabel = nextView.timeLabel;
    this.place = nextView.place;
    this.teacher = nextView.teacher;
    this.countdown = nextView.countdown;
    this.countdownUnit = nextView.countdownUnit;
    this.isOngoing = nextView.isOngoing;
    this.progressPercent = nextView.progressPercent;
    this.hasCourse = nextView.hasCourse;
    this.hours = nextView.hours;
    this.minutes = nextView.minutes;
  }

  private refreshToday(now: number): void {
    // An existing card from before the update may still have only the countdown data.
    const needsWeek = !this.weekJson && this.hasTimetable && this.dataState === 'ready';
    this.todaySchedule = WidgetWeek.view(this.weekJson, this.hasTimetable, needsWeek ? 'loading' : this.dataState,
      now, true);
    const monday = WidgetWeek.monday(now);
    if ((needsWeek || this.todaySchedule.stale) && this.requestedWeek !== monday) {
      this.requestedWeek = monday;
      postCardAction(this, { action: 'message', params: { refresh: 'week' } });
    }
  }

  private backgroundSource(): string {
    const name: string = this.dimension === WIDE_FORM ? this.bgWide : this.bgCompact;
    return name.length > 0 ? 'memory://' + name : '';
  }

  private openApp(id: string = ''): void {
    const params: Record<string, string> = {};
    if (id) params[this.activeTab === WidgetTab.TASK ? 'hitaLearningTaskId' : 'hitaReminderEventId'] = id;
    postCardAction(this, {
      action: 'router',
      abilityName: 'EntryAbility',
      params: params
    });
  }

  @Builder
  tab(label: string, page: WidgetTab) {
    Text(label)
      .fontSize(HitaDesign.dockLabel)
      .fontWeight(this.activeTab === page ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.activeTab === page ? $r('app.color.widget_accent') : $r('app.color.widget_muted'))
      .backgroundColor(this.activeTab === page ? $r('app.color.widget_selected') : Color.Transparent)
      .borderRadius(HitaDesign.radiusSm)
      .textAlign(TextAlign.Center)
      .maxLines(1)
      .layoutWeight(1)
      .height('100%')
      .onClick((): void => {
        this.activeTab = page;
        this.refreshDisplay();
      })
  }

  @Builder
  tabHeader() {
    Row({ space: HitaDesign.space2xs }) {
      this.tab('课程', WidgetTab.COURSE)
      this.tab('考试', WidgetTab.EXAM)
      this.tab('待办', WidgetTab.TASK)
    }
    .width('100%')
    .height(24)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  cardHeader() {
    Row() {
      WidgetBrand({ showName: this.courseOnly || this.dimension !== SMALL_FORM })
      if (!this.courseOnly) {
        if (this.dimension !== SMALL_FORM) {
          Row() { this.tabHeader() }.layoutWeight(1).margin({ left: HitaDesign.spaceSm })
        } else {
          Row() {
            Row() { this.tabHeader() }.width('100%').constraintSize({ maxWidth: 112 })
          }.layoutWeight(1).margin({ left: HitaDesign.spaceXs }).justifyContent(FlexAlign.End)
        }
      }
    }
    .width('100%')
    .justifyContent(!this.courseOnly && this.dimension === SMALL_FORM ? FlexAlign.SpaceBetween : FlexAlign.Start)
  }

  @Builder
  countdownHero(compact: boolean) {
    Column({ space: 2 }) {
      Row({ space: HitaDesign.space2xs }) {
        if (compact && this.hours.length > 2) {
          Marquee({ src: this.countdown, start: true, step: MARQUEE_STEP })
            .fontSize(COMPACT_COUNTDOWN_SIZE)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.widget_ink'))
            .align(Alignment.Start)
            .layoutWeight(1)
            .height('100%')
            .accessibilityText(this.countdown)
        } else {
          Text() {
            if (this.hours) {
              Span(this.hours)
              Span('时').fontSize(compact ? HitaDesign.label : HitaDesign.caption)
            }
            if (this.minutes) {
              Span(this.minutes)
              Span('分').fontSize(compact ? HitaDesign.label : HitaDesign.caption)
            }
            if (!this.hasCourse) {
              Span(this.countdown)
            }
          }
            .fontSize(compact ? COMPACT_COUNTDOWN_SIZE : 40)
            .maxFontSize(compact ? COMPACT_COUNTDOWN_SIZE : 40)
            .minFontSize(HitaDesign.label)
            .maxLines(1)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.widget_ink'))
            .align(Alignment.Start)
            .layoutWeight(1)
            .height('100%')
            .accessibilityText(this.countdown)
        }
      }
      .width('100%').height(compact ? 36 : 48).alignItems(VerticalAlign.Center)
      Text(this.countdownUnit)
        .maxFontSize(HitaDesign.dockLabel)
        .minFontSize(9)
        .maxLines(1)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.widget_muted'))
        .align(Alignment.Start)
        .width('100%')
        .height(14)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  progressRing(compact: boolean) {
    Stack({ alignContent: Alignment.Center }) {
      Progress({ value: this.progressPercent, total: 100, type: ProgressType.Ring })
        .width('100%').height('100%')
        .color($r('app.color.hita_widget_accent'))
        .backgroundColor($r('app.color.widget_ring_track'))
      Text(Math.floor(this.progressPercent).toString() + '%')
        .fontSize(HitaDesign.label)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.widget_ink'))
        .maxLines(1)
        .textAlign(TextAlign.Center)
        .width('100%')
    }
    .width(compact ? COMPACT_RING_DIAMETER : 52)
    .height(compact ? COMPACT_RING_DIAMETER : 52)
    .margin({ bottom: compact ? COMPACT_CAPTION_BOTTOM_INSET : 0 })
    .flexShrink(0)
  }

  // Builder string arguments are passed by value and never re-render, so the row reads the
  // course fields from state itself; otherwise place/teacher stay on the first course shown.
  @Builder
  metadataRow(icon: Resource, isTeacher: boolean, compact: boolean) {
    Row({ space: compact ? 4 : 6 }) {
      SymbolGlyph(icon)
        .fontSize(compact ? 11 : 13)
        .fontColor([$r('app.color.widget_muted')])
        .width(compact ? 14 : 17)
        .height(compact ? 14 : 18)
      Marquee({ src: isTeacher ? this.teacher : this.place, start: true, step: MARQUEE_STEP })
        .fontSize(compact ? 10 : 12)
        .allowScale(true)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.widget_muted'))
        .align(Alignment.Start)
        .layoutWeight(1)
    }
    .width('100%')
    .height(compact ? 14 : 18)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  courseInfo(compact: boolean) {
    Column({ space: compact ? 3 : 4 }) {
      Row({ space: compact ? 4 : 6 }) {
        SymbolGlyph($r('sys.symbol.calendar'))
          .fontSize(compact ? 12 : 14)
          .fontColor([$r('app.color.widget_muted')])
          .width(compact ? 14 : 17)
          .height(compact ? 18 : 20)
        Marquee({ src: this.title, start: true, step: MARQUEE_STEP })
          .fontSize(compact ? 14 : 16)
          .allowScale(true)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.widget_ink'))
          .align(Alignment.Start)
          .layoutWeight(1)
      }
      .width('100%')
      .height(compact ? 18 : 20)
      .alignItems(VerticalAlign.Center)
      if (this.hasCourse) {
        if (compact) {
          Row({ space: 6 }) {
            Column() {
              this.metadataRow($r('sys.symbol.pin'), false, true)
            }
            .layoutWeight(1)
            Column() {
              this.metadataRow($r('sys.symbol.person_crop_circle_fill'), true, true)
            }
            .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        } else {
          this.metadataRow($r('sys.symbol.pin'), false, false)
          this.metadataRow($r('sys.symbol.person_crop_circle_fill'), true, false)
        }
        Row({ space: compact ? 4 : 6 }) {
          SymbolGlyph($r('sys.symbol.clock'))
            .fontSize(compact ? 11 : 13)
            .fontColor([$r('app.color.widget_muted')])
            .width(compact ? 14 : 17)
            .height(compact ? 14 : 16)
          Marquee({ src: this.timeLabel, start: true, step: MARQUEE_STEP })
            .fontSize(compact ? 10 : 11)
            .allowScale(true)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.widget_muted'))
            .align(Alignment.Start)
            .layoutWeight(1)
        }
        .width('100%')
        .height(compact ? 14 : 16)
        .alignItems(VerticalAlign.Center)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  coursePage() {
    Column() {
      if (this.dimension === WIDE_FORM) {
        Row({ space: HitaDesign.spaceXs }) {
          Column() { this.countdownHero(false) }.layoutWeight(this.hours && this.minutes ? 1.65 : 1)
          if (this.isOngoing) {
            this.progressRing(false)
          }
          Column() { this.courseInfo(false) }.layoutWeight(1.2)
        }
        .width('100%')
      } else {
        Row({ space: HitaDesign.space2xs }) {
          Column() { this.countdownHero(true) }.layoutWeight(1)
          if (this.isOngoing) { this.progressRing(true) }
        }
        .width('100%')
        .alignItems(VerticalAlign.Bottom)
        this.courseInfo(true)
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(this.dimension === WIDE_FORM ? FlexAlign.Center : FlexAlign.SpaceAround)
    .onClick((): void => this.openApp())
  }

  @Builder
  todayPage() {
    if (this.todaySchedule.days.length) {
      if (this.dimension === LARGE_FORM) {
        Row() {
          Text('今日课表').fontSize(HitaDesign.caption).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.widget_ink'))
          Text(WidgetWeek.shortDate(this.todaySchedule.days[this.todaySchedule.today].date))
            .fontSize(HitaDesign.label).fontColor($r('app.color.widget_muted'))
        }
        .width('100%').justifyContent(FlexAlign.SpaceBetween)
        .padding({ top: HitaDesign.space2xs, bottom: HitaDesign.space2xs })
      }
      WidgetDayAgenda({ day: this.todaySchedule.days[this.todaySchedule.today],
        message: this.todaySchedule.stale ? '正在更新今日课表' : this.todaySchedule.message,
        emptyLabel: '今天没有课程或考试', compact: this.dimension !== LARGE_FORM,
        openItem: (id: string): void => this.openApp(id) })
    }
  }

  @Builder
  agendaList() {
    List({ space: HitaDesign.space2xs }) {
      ForEach(this.agenda.rows, (row: AgendaRow) => {
        ListItem() {
          Column({ space: HitaDesign.space2xs }) {
            Text(row.title)
              .fontSize(HitaDesign.caption)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.widget_ink'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text((this.activeTab === WidgetTab.EXAM ? row.status + ' · ' :
              row.status === '已逾期' ? '逾期 · ' : '') + row.when)
              .fontSize(HitaDesign.dockLabel)
              .fontColor(this.activeTab === WidgetTab.EXAM || row.status === '已逾期' ?
                $r('app.color.widget_exam') : $r('app.color.widget_task'))
              .maxLines(1)
            if (this.dimension !== SMALL_FORM) {
              Text(row.detail)
                .fontSize(HitaDesign.dockLabel)
                .fontColor($r('app.color.widget_muted'))
                .maxLines(1)
            }
          }
          .padding({ top: HitaDesign.space2xs, bottom: HitaDesign.space2xs, right: HitaDesign.spaceXs })
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .onClick((): void => this.openApp(row.id))
        }
      }, (row: AgendaRow): string => JSON.stringify(row))
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
    .divider({ strokeWidth: HitaDesign.hairline, color: $r('app.color.widget_selected') })
  }

  @Builder
  agendaPage() {
    Row({ space: HitaDesign.spaceSm }) {
      if (this.agenda.rows.length === 0) {
        Column({ space: HitaDesign.space2xs }) {
          Text(this.agenda.message)
            .fontSize(HitaDesign.caption)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.widget_ink'))
          Text(this.agenda.hint)
            .fontSize(HitaDesign.dockLabel)
            .fontColor($r('app.color.widget_muted'))
        }
        .alignItems(HorizontalAlign.Start)
        .onClick((): void => this.openApp())
      } else {
        ForEach(this.agenda.rows.slice(0, this.dimension === SMALL_FORM ? 1 : 2), (row: AgendaRow) => {
          Column({ space: HitaDesign.space2xs }) {
            Text(row.status)
              .fontSize(HitaDesign.dockLabel)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.widget_exam'))
            Marquee({ src: row.title, start: true, step: MARQUEE_STEP })
              .fontSize(HitaDesign.body)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.widget_ink'))
              .width('100%')
              .align(Alignment.Start)
            Text(row.when)
              .maxFontSize(HitaDesign.label)
              .minFontSize(9)
              .maxLines(1)
              .width('100%')
              .height(HitaDesign.spaceMd)
              .fontColor($r('app.color.widget_muted'))
            Marquee({ src: row.detail, start: true, step: MARQUEE_STEP })
              .fontSize(HitaDesign.dockLabel)
              .fontColor($r('app.color.widget_muted'))
              .width('100%')
              .align(Alignment.Start)
          }
          .alignItems(HorizontalAlign.Start)
          .justifyContent(FlexAlign.Center)
          .height('100%')
          .layoutWeight(1)
          .onClick((): void => this.openApp(row.id))
        }, (row: AgendaRow): string => JSON.stringify(row))
      }
    }
    .width('100%')
    .layoutWeight(1)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.backgroundSource()) {
        Column()
          .width('100%').height('100%')
          .backgroundColor($r('app.color.widget_image_scrim'))
          .hitTestBehavior(HitTestMode.None)
      }
      Column({ space: HitaDesign.space2xs }) {
        this.cardHeader()
        if (this.activeTab === WidgetTab.COURSE) {
          if (this.courseOnly) {
            this.coursePage()
          } else {
            this.todayPage()
          }
        } else if (this.agenda.rows.length > 0 && (this.activeTab === WidgetTab.TASK || this.dimension === LARGE_FORM)) {
          this.agendaList()
        } else {
          this.agendaPage()
        }
      }
      .alignItems(HorizontalAlign.Start)
      .padding({ left: HitaDesign.spaceSm, right: HitaDesign.spaceSm,
        top: HitaDesign.spaceXs, bottom: HitaDesign.spaceXs })
      .width('100%')
      .height('100%')
      // The second ticker for the progress ring. It must keep a real render area and
      // non-zero opacity, otherwise the form engine treats it as invisible and stops it.
      TextTimer({ isCountDown: false, controller: this.ticker })
        .format('ss')
        .fontSize(8)
        .fontColor('#01000001')
        .width(12)
        .height(12)
        .position({ x: 0, y: 0 })
        .hitTestBehavior(HitTestMode.None)
        .onAppear((): void => this.startTicker())
        .onTimer((_utc: number, elapsedTime: number): void => this.onTick(elapsedTime))
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.widget_background'))
    // The framing is already baked to this card's ratio: Cover only absorbs launcher rounding.
    .backgroundImage(this.backgroundSource())
    .backgroundImageSize(ImageSize.Cover)
    .backgroundImagePosition(Alignment.Center)
    // A single opaque surface and clip share the same outline. No inset backplate.
    .borderRadius($r('sys.float.ohos_id_corner_radius_card'))
    .clip(true)
    .onAppear((): void => this.refreshDisplay())
  }
}
