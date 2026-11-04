import { NextClassModel, NextClassView } from '../../feature/widget/NextClassModel';

const storage: LocalStorage = new LocalStorage();
const MARQUEE_STEP: number = 2.5;

@Entry(storage)
@Component
struct NextClassCard {
  @LocalStorageProp('scheduleJson') @Watch('refreshDisplay') scheduleJson: string = '[]';
  @LocalStorageProp('hasTimetable') @Watch('refreshDisplay') hasTimetable: boolean = false;
  @LocalStorageProp('dataState') @Watch('refreshDisplay') dataState: string = 'loading';
  @LocalStorageProp('formDimension') dimension: number = 2;
  // Images the app baked at each card's aspect ratio; empty keeps the plain white surface.
  @LocalStorageProp('bgCompact') bgCompact: string = '';
  @LocalStorageProp('bgWide') bgWide: string = '';
  @State view: NextClassView = new NextClassView();
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
    this.refreshDisplay();
    // A count-up timer is not meant to run for days on a launcher; restart it periodically.
    if (elapsedTime >= 43200) this.startTicker();
  }

  private refreshDisplay(): void {
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

  private openApp(): void {
    postCardAction(this, {
      action: 'router',
      abilityName: 'EntryAbility',
      params: {}
    });
  }

  @Builder
  brandHeader(compact: boolean) {
    Row() {
      Image($r('app.media.app_icon'))
        .width(compact ? 16 : 18)
        .height(compact ? 16 : 18)
        .borderRadius(compact ? 5 : 6)
        .objectFit(ImageFit.Contain)
      Text('HITA NEXT')
        .fontSize(10)
        .fontWeight(FontWeight.Medium)
        .fontColor('#515A67')
        .maxLines(1)
        .margin({ left: 6 })
    }
    .width('100%')
    .height(18)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  countdownHero(compact: boolean) {
    Row({ space: compact ? 8 : 12 }) {
      // Keep the countdown on the left and reserve the right side for the fixed-size ring.
      Column({ space: 2 }) {
        Marquee({ src: this.countdown, start: true, step: MARQUEE_STEP })
          .fontSize(compact ? 24 : 32)
          .allowScale(true)
          .fontWeight(FontWeight.Bold)
          .fontColor('#182230')
          .align(Alignment.Start)
          .width('100%')
          .height(compact ? 28 : 38)
        Marquee({ src: this.countdownUnit, start: true, step: MARQUEE_STEP })
          .fontSize(10)
          .allowScale(true)
          .fontWeight(FontWeight.Medium)
          .fontColor('#515A67')
          .align(Alignment.Start)
          .width('100%')
          .height(14)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      if (this.isOngoing) {
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

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column({ space: 4 }) {
        this.brandHeader(this.dimension !== 3)
        if (this.dimension === 3) {
          Row({ space: 14 }) {
            Column() {
              this.countdownHero(false)
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Column() {
              this.courseInfo(false)
            }
            .layoutWeight(1.2)
            .alignItems(HorizontalAlign.Start)
          }
          .layoutWeight(1)
          .width('100%')
          .alignItems(VerticalAlign.Center)
        } else {
          this.countdownHero(true)
          this.courseInfo(true)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.SpaceBetween)
      .padding(12)
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
    .onClick((): void => this.openApp())
    .onAppear((): void => this.refreshDisplay())
  }
}
