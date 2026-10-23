import { common } from '@kit.AbilityKit';
import { HeaderBackButton } from '../common/components/HeaderBackButton';
import { ImmersiveHeader } from '../common/components/ImmersiveHeader';
import { HeaderFadeMask } from '../common/components/HeaderFadeMask';
import { HeaderFade } from '../common/theme/HeaderFade';
import { CompatibleMaterialModifier } from '../common/theme/CompatibleMaterialModifier';
import { CompatibleLightModifier } from '../common/theme/CompatibleLightModifier';
import { CompatibleSheetMaterial } from '../common/theme/CompatibleSheetMaterial';
import { NAV_BAR_INSET_FALLBACK, STATUS_BAR_INSET_FALLBACK } from '../common/theme/StatusBarInset';
import { EasCampus, EasSession } from '../feature/eas/EasSession';
import { EasSessionStore } from '../feature/eas/EasSessionStore';
import { EasDataProvider } from '../feature/eas/EasDataProvider';
import { EasApiClient } from '../feature/eas/EasApiClient';
import { EasCourseScoreItem, EasTermItem } from '../feature/eas/model/EasModels';
import { ScoreService } from '../feature/eas/ScoreService';
import { ScoreTestType, OfficialScoreSummary, LocalScoreStatistics, localScoreStatistics,
  numericScore, scoreErrorMessage } from '../feature/eas/data/ScoreData';

const CAMPUSES: EasCampus[] = [EasCampus.SHENZHEN, EasCampus.BENBU, EasCampus.WEIHAI];
const CAMPUS_NAMES: string[] = ['深圳', '本部', '威海'];
const TYPES: ScoreTestType[] = [ScoreTestType.NORMAL, ScoreTestType.MIDTERM, ScoreTestType.ALL, ScoreTestType.RETAKE];
const TYPE_NAMES: string[] = ['期末', '期中', '全部', '重修'];
const HEADER_HEIGHT: number = 60;

@Entry
@Component
export struct ScorePage {
  @Prop presentedAsSheet: boolean = false;
  onClose: () => void = () => {};
  @State campusIndex: number = 0;
  @State termIndex: number = 0;
  @State typeIndex: number = 0;
  @State terms: EasTermItem[] = [];
  @State scores: EasCourseScoreItem[] = [];
  @State summary: OfficialScoreSummary = new OfficialScoreSummary();
  @State statistics: LocalScoreStatistics = new LocalScoreStatistics();
  @State loading: boolean = true;
  @State queried: boolean = false;
  @State errorText: string = '';
  @State summaryMessage: string = '';
  @State fadeOpacity: number = 0;
  @StorageProp('hita_status_bar_vp') statusBarInset: number = STATUS_BAR_INSET_FALLBACK;
  @StorageProp('hita_nav_bar_vp') navBarInset: number = NAV_BAR_INSET_FALLBACK;
  private session: EasSession | undefined = undefined;
  private generation: number = 0;
  private initialized: boolean = false;
  private sheetLoadStarted: boolean = false;
  private service: ScoreService = new ScoreService();
  private pageScroller: Scroller = new Scroller();

  async aboutToAppear(): Promise<void> {
    if (this.presentedAsSheet && !this.sheetLoadStarted) await this.onPageShow();
  }

  async onPageShow(): Promise<void> {
    if (this.presentedAsSheet) {
      if (this.sheetLoadStarted) return;
      this.sheetLoadStarted = true;
    }
    const generation = ++this.generation;
    const store = EasSessionStore.getInstance();
    await store.init(this.getUIContext().getHostContext() as common.Context);
    if (!this.initialized) {
      const preferred = await store.loadPreferred();
      if (generation !== this.generation) return;
      if (preferred !== undefined) this.campusIndex = CAMPUSES.indexOf(preferred.campus);
      this.initialized = true;
    }
    if (generation === this.generation) await this.loadTerms();
  }

  onPageHide(): void { this.generation++; this.sheetLoadStarted = false; }
  aboutToDisappear(): void { this.generation++; this.sheetLoadStarted = false; }

  private resetResult(): void {
    this.scores = []; this.summary = new OfficialScoreSummary();
    this.statistics = new LocalScoreStatistics();
    this.errorText = ''; this.summaryMessage = ''; this.queried = false;
    this.fadeOpacity = 0;
  }

  private async loadTerms(): Promise<void> {
    const generation = ++this.generation;
    const oldCode = this.terms[this.termIndex]?.getCode() ?? '';
    this.resetResult(); this.loading = true; this.terms = [];
    try {
      const session = await EasSessionStore.getInstance().load(CAMPUSES[this.campusIndex]);
      if (generation !== this.generation) return;
      this.session = session;
      if (session === undefined || !session.isLogin()) {
        throw new Error('请先在“更多 → 教务账号”登录' + CAMPUS_NAMES[this.campusIndex] + '教务');
      }
      if (session.campus !== EasCampus.SHENZHEN && session.getStudentType() === '2') {
        throw new Error('该校区研究生成绩接口暂未接入，请到教务网站查询');
      }
      const terms = await new EasDataProvider(new EasApiClient()).getAllTerms(session);
      if (generation !== this.generation) return;
      if (terms.length === 0) throw new Error('未获取到学期列表，请稍后重试');
      this.terms = terms;
      const oldIndex = terms.findIndex((term: EasTermItem) => term.getCode() === oldCode);
      const currentIndex = terms.findIndex((term: EasTermItem) => term.isCurrent);
      this.termIndex = oldIndex >= 0 ? oldIndex : Math.max(0, currentIndex);
      await this.queryReal();
    } catch (error) {
      if (generation === this.generation) this.errorText = scoreErrorMessage(error instanceof Error ? error.message : '');
    } finally {
      if (generation === this.generation) this.loading = false;
    }
  }

  private async queryReal(): Promise<void> {
    const session = this.session;
    const term = this.terms[this.termIndex];
    if (session === undefined || term === undefined) { await this.loadTerms(); return; }
    const generation = ++this.generation;
    this.resetResult(); this.loading = true;
    try {
      const result = await this.service.query(session, term, TYPES[this.typeIndex]);
      if (generation !== this.generation) return;
      this.scores = result.items; this.summary = result.summary;
      this.statistics = localScoreStatistics(result.items, TYPES[this.typeIndex] !== ScoreTestType.MIDTERM);
      this.summaryMessage = result.summaryMessage; this.queried = true;
    } catch (error) {
      if (generation === this.generation) this.errorText = scoreErrorMessage(error instanceof Error ? error.message : '');
    } finally {
      if (generation === this.generation) this.loading = false;
    }
  }

  private details(item: EasCourseScoreItem): void {
    this.getUIContext().getPromptAction().showDialog({
      title: item.courseName,
      message: '成绩：' + item.displayScore() + '\n课程代码：' + (item.courseCode || '—') +
        '\n学分：' + item.credits + '\n学时：' + item.hours + '\n学期：' + item.termName +
        '\n课程性质：' + (item.courseProperty || '—') + '\n课程类别：' + (item.courseCategory || '—') +
        '\n考核方式：' + (item.assessMethod || '—') + '\n开课单位：' + (item.schoolName || '—'),
      buttons: [{ text: '知道了', color: '#3390EC' }]
    });
  }

  private number(value: number): string { return value < 0 ? '—' : Number(value.toFixed(2)).toString(); }

  @Builder
  metric(label: string, value: string) {
    Column({ space: 5 }) {
      Text(value || '—').fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.hita_text'))
      Text(label).fontSize(12).fontColor($r('app.color.hita_text_secondary'))
    }.layoutWeight(1).alignItems(HorizontalAlign.Center)
  }

  @Builder
  statisticsCard() {
    if (this.summary.available()) {
      Column({ space: 14 }) {
        Text(this.summary.scope).fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.hita_text'))
        Row() {
          this.metric('学分绩', this.summary.weightedAverage)
          this.metric('GPA', this.summary.gpa)
          this.metric('排名', this.summary.rank ? this.summary.rank + (this.summary.total ? '/' + this.summary.total : '') : '')
        }.width('100%')
        if (this.summary.earnedCredits || this.summary.passedCourses) {
          Text('获得学分 ' + (this.summary.earnedCredits || '—') + ' · 通过课程 ' + (this.summary.passedCourses || '—'))
            .fontSize(12).fontColor($r('app.color.hita_text_secondary'))
        }
        if (this.summary.allCourseWeightedAverage || this.summary.allPassedCourseGpa) {
          Text('全部课程学分绩 ' + (this.summary.allCourseWeightedAverage || '—') +
            ' · 全部及格课程 GPA ' + (this.summary.allPassedCourseGpa || '—'))
            .fontSize(12).fontColor($r('app.color.hita_text_secondary'))
        }
      }.width('100%').padding(16).borderRadius(16).backgroundColor($r('app.color.hita_surface'))
    }
    if (this.summaryMessage) {
      Text(this.summaryMessage).fontSize(12).fontColor($r('app.color.hita_text_secondary')).width('100%')
    }
    Column({ space: 12 }) {
      Text('当前列表统计 · ' + this.statistics.count + ' 门').fontSize(14).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.hita_text')).width('100%')
      if (TYPES[this.typeIndex] !== ScoreTestType.MIDTERM) {
        Row() {
          this.metric('通过', this.statistics.passed.toString())
          this.metric('未通过', this.statistics.failed.toString())
          this.metric('待定 / 未识别', this.statistics.pending.toString())
        }.width('100%')
      }
      Row() {
        this.metric('平均分', this.number(this.statistics.average))
        this.metric('学分加权均分', this.number(this.statistics.weightedAverage))
      }.width('100%')
      Text('学分合计 ' + this.number(this.statistics.credits) + (TYPES[this.typeIndex] === ScoreTestType.MIDTERM ? '' :
        ' · 通过学分 ' + this.number(this.statistics.passedCredits)))
        .fontSize(12).fontColor($r('app.color.hita_text_secondary')).width('100%')
      Text(TYPES[this.typeIndex] === ScoreTestType.MIDTERM ?
        '期中按原始数值计算，不判定课程是否通过。不同课程可能采用不同满分或折算方式，均分仅供参考。' :
        '均分只统计 0～100 的数值成绩，等级制不换算分数；按百分制及格线估算通过情况。此处不等于教务 GPA、毕业学分或官方排名。')
        .fontSize(11).lineHeight(18).fontColor($r('app.color.hita_text_secondary')).width('100%')
    }.width('100%').padding(16).borderRadius(16).backgroundColor($r('app.color.hita_surface'))
  }

  @Builder
  private queryFilters() {
    Column() {
      Row({ space: 12 }) {
        Select(CAMPUS_NAMES.map((name: string): SelectOption => ({ value: name })))
          .selected(this.campusIndex).value(CAMPUS_NAMES[this.campusIndex]).layoutWeight(1)
          .onSelect((index: number) => {
            if (index === this.campusIndex) return;
            this.campusIndex = index; this.typeIndex = 0; this.terms = []; this.loadTerms();
          })
        Select(TYPE_NAMES.slice(0, this.campusIndex === 0 ? 2 : 4).map((name: string): SelectOption => ({ value: name })))
          .selected(this.typeIndex).value(TYPE_NAMES[this.typeIndex]).layoutWeight(1).enabled(this.terms.length > 0)
          .onSelect((index: number) => { this.typeIndex = index; this.queryReal(); })
      }.width('100%').padding({ top: 8, bottom: 8 })
      Select(this.terms.map((term: EasTermItem): SelectOption => ({ value: term.name })))
        .selected(this.termIndex).value(this.terms[this.termIndex]?.name ?? '学期').enabled(this.terms.length > 0)
        .onSelect((index: number) => { this.termIndex = index; this.queryReal(); })
        .width('100%').margin({ bottom: 12 })
    }.width('100%')
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      if (this.loading || this.errorText) {
        Column() {
          this.queryFilters()
          if (this.loading) {
            Column({ space: 12 }) {
              LoadingProgress().width(40).height(40)
              Text('正在查询成绩…').fontSize(14).fontColor($r('app.color.hita_text_secondary'))
            }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
          } else if (this.errorText) {
            Column({ space: 18 }) {
              Text(this.errorText).fontSize(15).fontColor($r('app.color.hita_text')).textAlign(TextAlign.Center)
              Column() {
                ImmersiveHeader({ barHeight: 52 }) {
                  Row() {
                    Button('重新查询', { type: ButtonType.Capsule })
                      .width('100%').height(40).fontSize(14).fontWeight(FontWeight.Medium)
                      .fontColor(CompatibleMaterialModifier.foreground('#FFFFFF'))
                      .backgroundColor($r('app.color.hita_primary_fill'))
                      .attributeModifier(new CompatibleMaterialModifier($r('app.color.hita_primary_fill')))
                      .onClick(() => this.loadTerms())
                  }.width('100%').height(52)
                }
              }.width(128).height(52)
            }.width('100%').layoutWeight(1).padding(28).justifyContent(FlexAlign.Center)
          }
        }.width('100%').height('100%')
          .padding({ left: 16, right: 16, top: HEADER_HEIGHT, bottom: 16 + this.navBarInset })
      } else if (this.queried) {
        Scroll(this.pageScroller) {
          Column({ space: 12 }) {
            this.queryFilters()
            this.statisticsCard()
            if (this.scores.length === 0) {
              Text('所选学期及成绩类型暂无成绩').fontSize(14).fontColor($r('app.color.hita_text_secondary')).margin(24)
            }
            ForEach(this.scores, (item: EasCourseScoreItem) => {
              Column({ space: 8 }) {
                Row({ space: 12 }) {
                  Text(item.courseName).fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.hita_text')).layoutWeight(1)
                  Text(item.displayScore()).fontSize(22).fontWeight(FontWeight.Bold)
                    .fontColor(numericScore(item.displayScore()) >= 0 && numericScore(item.displayScore()) < 60 ?
                      $r('app.color.hita_error') : $r('app.color.hita_primary'))
                }.width('100%')
                Text([item.courseCode, item.courseProperty, item.credits + ' 学分'].filter((v: string) => v.length > 0).join(' · '))
                  .fontSize(12).fontColor($r('app.color.hita_text_secondary')).width('100%')
              }.width('100%').padding(16).borderRadius(14).backgroundColor($r('app.color.hita_surface'))
                .onClick(() => this.details(item))
            })
          }.width('100%').padding({ left: 16, right: 16, top: HEADER_HEIGHT, bottom: 16 + this.navBarInset })
        }.width('100%').height('100%').align(Alignment.Top).scrollBar(BarState.Off)
          .onDidScroll(() => {
            this.fadeOpacity = HeaderFade.opacity(this.pageScroller.currentOffset().yOffset);
          })
      }

      HeaderFadeMask({ maskOpacity: this.fadeOpacity, headerHeight: HEADER_HEIGHT })

      ImmersiveHeader({ barHeight: HEADER_HEIGHT, materialEnabled: !this.presentedAsSheet ||
        CompatibleSheetMaterial.isEnabled() }) {
        Row({ space: 12 }) {
          HeaderBackButton({ onBack: () => {
            if (this.presentedAsSheet) this.onClose();
            else this.getUIContext().getRouter().back();
          } })
          Text('成绩与统计').fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.hita_text'))
            .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Button('刷新', { type: ButtonType.Capsule })
            .height(34).fontSize(13).fontWeight(FontWeight.Medium)
            .padding({ left: 12, right: 12 })
            .fontColor(CompatibleMaterialModifier.foreground('#FFFFFF'))
            .backgroundColor($r('app.color.hita_primary_fill'))
            .attributeModifier(new CompatibleMaterialModifier($r('app.color.hita_primary_fill'), false,
              !this.presentedAsSheet || CompatibleSheetMaterial.isEnabled()))
            .enabled(!this.loading).onClick(() => this.loadTerms())
        }.width('100%').height(HEADER_HEIGHT).padding({ left: 16, right: 16 })
          .alignItems(VerticalAlign.Center).hitTestBehavior(HitTestMode.Transparent)
      }
    }.width('100%').height('100%')
      .padding({ top: this.presentedAsSheet ? 0 : this.statusBarInset })
      .backgroundColor(this.presentedAsSheet ? CompatibleSheetMaterial.bodyColor($r('app.color.hita_page')) :
        $r('app.color.hita_page'))
      .attributeModifier(new CompatibleLightModifier(24, this.presentedAsSheet &&
        CompatibleSheetMaterial.isEnabled(), true))
  }
}
