import { NextClassModel, NextClassView } from '../../feature/widget/NextClassModel';
import { AgendaRow, AgendaView, WidgetAgenda, WidgetTab } from '../../feature/widget/WidgetAgenda';
import { HitaDesign } from '../../common/theme/HitaDesign';

const storage: LocalStorage = new LocalStorage();
const MARQUEE_STEP: number = 2.5;

@Entry(storage)
@Component
struct NextClassCard {
  @LocalStorageProp('scheduleJson') @Watch('refreshDisplay') scheduleJson: string = '[]';
  @LocalStorageProp('examJson') @Watch('refreshDisplay') examJson: string = '';
  @LocalStorageProp('taskJson') @Watch('refreshDisplay') taskJson: string = '';
  @LocalStorageProp('hasTimetable') @Watch('refreshDisplay') hasTimetable: boolean = false;
  @LocalStorageProp('dataState') @Watch('refreshDisplay') dataState: string = 'loading';
  @LocalStorageProp('formDimension') dimension: number = 2;
  // Images the app baked at each card's aspect ratio; empty keeps the plain white surface.
  @LocalStorageProp('bgCompact') bgCompact: string = '';
  @LocalStorageProp('bgWide') bgWide: string = '';
  @State view: NextClassView = new NextClassView();
  @State activeTab: WidgetTab = WidgetTab.COURSE;
  @State agenda: AgendaView = new AgendaView();
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

  aboutToAppear(): void {
    this.refreshDisplay();
  }

  private startTicker(): void {
    this.ticker.reset();
    this.ticker.start();
  }

  private onTick(elapsedTime: number): void {
    if (this.activeTab === WidgetTab.COURSE || Date.now() >= this.agenda.nextChange) this.refreshDisplay();
    // A count-up timer is not meant to run for days on a launcher; restart it periodically.
    if (elapsedTime >= 43200) this.startTicker();
  }

  private refreshDisplay(): void {
    if (this.activeTab !== WidgetTab.COURSE) {
      this.agenda = WidgetAgenda.view(this.activeTab, this.activeTab === WidgetTab.EXAM ? this.examJson : this.taskJson,
        this.dataState === 'loading', Date.now());
      return;
    }
    const nextView: NextClassView = NextClassModel.view(
      this.scheduleJson, this.hasTimetable, this.dataState, Date.now());
    // Name, place, teacher and time are switched together from the same selected course.
    this.title = nextView.title;
    this.timeLabel = nextView.timeLabel;
    this.place = nextView.place;
    this.teacher = nextView.teacher;
    this.countdown = nextView.countdown;
    this.countdownUnit = nextView.countdownUnit;
    this.isOngoing = nextView.isOngoing;
    this.progressPercent = nextView.progressPercent;
    this.view = nextView;
  }

  private backgroundSource(): string {
    const name: string = this.dimension === 3 ? this.bgWide : this.bgCompact;
    return name.length > 0 ? 'memory://' + name : '';
  }

  private openApp(id: string = ''): void {
    const params: Record<string, string> = {};
    if (id && this.activeTab === WidgetTab.EXAM) params['hitaReminderEventId'] = id;
    if (id && this.activeTab === WidgetTab.TASK) params['hitaLearningTaskId'] = id;
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
  tabHeader(compact: boolean) {
    Row({ space: HitaDesign.space2xs }) {
      Image($r('app.media.app_icon'))
        .width(compact ? 16 : 18)
        .height(compact ? 16 : 18)
        .borderRadius(compact ? 5 : 6)
        .objectFit(ImageFit.Contain)
      this.tab('课程', WidgetTab.COURSE)
      this.tab('考试', WidgetTab.EXAM)
      this.tab('待办', WidgetTab.TASK)
    }
    .width('100%')
    .height(24)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  countdownHero(compact: boolean) {
    Row({ space: compact ? HitaDesign.space2xs : HitaDesign.spaceSm }) {
      // Keep the countdown on the left and reserve the right side for the fixed-size ring.
      Column({ space: 2 }) {
        Text() {
          if (this.view.hours) {
            Span(this.view.hours)
            Span('h').fontSize(compact ? HitaDesign.label : HitaDesign.caption)
          }
          if (this.view.minutes) {
            Span(this.view.minutes)
            Span('min').fontSize(compact ? HitaDesign.label : HitaDesign.caption)
          }
          if (!this.view.hasCourse) {
            Span(this.countdown)
          }
        }
          .fontSize(compact ? 32 : 40)
          .maxFontSize(compact ? 32 : 40)
          .minFontSize(HitaDesign.label)
          .maxLines(1)
          .fontWeight(FontWeight.Bold)
          .fontColor('#182230')
          .align(Alignment.Start)
          .width('100%')
          .height(compact ? 36 : 48)
          .accessibilityText(this.countdown)
        Text(this.countdownUnit)
          .maxFontSize(HitaDesign.dockLabel)
          .minFontSize(9)
          .maxLines(1)
          .fontWeight(FontWeight.Medium)
          .fontColor('#515A67')
          .align(Alignment.Start)
          .width('100%')
          .height(14)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      if (compact && this.isOngoing) {
        this.progressRing(compact)
      }
    }
    .alignItems(VerticalAlign.Center)
    .width('100%')
  }

  @Builder
  progressRing(compact: boolean) {
    Stack({ alignContent: Alignment.Center }) {
      Progress({ value: this.progressPercent, total: 100, type: ProgressType.Ring })
        .width(compact ? 44 : 52)
        .height(compact ? 44 : 52)
        .color('#2365B2')
      Text(Math.floor(this.progressPercent).toString() + '%')
        .fontSize(compact ? 10 : 12)
        .fontWeight(FontWeight.Bold)
        .fontColor('#182230')
        .maxLines(1)
        .textAlign(TextAlign.Center)
        .width(compact ? 44 : 52)
    }
    .width(compact ? 44 : 52)
    .height(compact ? 44 : 52)
    .flexShrink(0)
  }

  // Builder string arguments are passed by value and never re-render, so the row reads the
  // course fields from state itself; otherwise place/teacher stay on the first course shown.
  @Builder
  metadataRow(icon: Resource, isTeacher: boolean, compact: boolean) {
    Row({ space: compact ? 4 : 6 }) {
      SymbolGlyph(icon)
        .fontSize(compact ? 11 : 13)
        .fontColor(['#687180'])
        .width(compact ? 14 : 17)
        .height(compact ? 14 : 18)
      Marquee({ src: isTeacher ? this.teacher : this.place, start: true, step: MARQUEE_STEP })
        .fontSize(compact ? 10 : 12)
        .allowScale(true)
        .fontWeight(FontWeight.Medium)
        .fontColor('#515A67')
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
          .fontColor(['#687180'])
          .width(compact ? 14 : 17)
          .height(compact ? 18 : 20)
        Marquee({ src: this.title, start: true, step: MARQUEE_STEP })
          .fontSize(compact ? 14 : 16)
          .allowScale(true)
          .fontWeight(FontWeight.Bold)
          .fontColor('#182230')
          .align(Alignment.Start)
          .layoutWeight(1)
      }
      .width('100%')
      .height(compact ? 18 : 20)
      .alignItems(VerticalAlign.Center)
      if (this.view.hasCourse) {
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
            .fontColor(['#687180'])
            .width(compact ? 14 : 17)
            .height(compact ? 14 : 16)
          Marquee({ src: this.timeLabel, start: true, step: MARQUEE_STEP })
            .fontSize(compact ? 10 : 11)
            .allowScale(true)
            .fontWeight(FontWeight.Medium)
            .fontColor('#515A67')
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
      if (this.dimension === 3) {
        Row({ space: HitaDesign.spaceXs }) {
          Column() { this.countdownHero(false) }.layoutWeight(1)
          if (this.isOngoing) {
            this.progressRing(false)
          }
          Column() { this.courseInfo(false) }.layoutWeight(1.2)
        }
        .width('100%')
      } else {
        this.countdownHero(true)
        this.courseInfo(true)
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(this.dimension === 3 ? FlexAlign.Center : FlexAlign.SpaceAround)
    .onClick((): void => this.openApp())
  }

  @Builder
  taskList() {
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
            Text((row.status === '已逾期' ? '逾期 · ' : '') + row.when)
              .fontSize(HitaDesign.dockLabel)
              .fontColor(row.status === '已逾期' ? $r('app.color.widget_exam') : $r('app.color.widget_task'))
              .maxLines(1)
            if (this.dimension === 3) {
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
        ForEach(this.agenda.rows.slice(0, this.dimension === 3 ? 2 : 1), (row: AgendaRow) => {
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
      Column({ space: HitaDesign.space2xs }) {
        this.tabHeader(this.dimension !== 3)
        if (this.activeTab === WidgetTab.COURSE) {
          this.coursePage()
        } else if (this.activeTab === WidgetTab.TASK && this.agenda.rows.length > 0) {
          this.taskList()
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
    .backgroundColor('#FFFFFFFF')
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
