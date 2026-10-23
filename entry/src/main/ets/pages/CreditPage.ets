import { common } from '@kit.AbilityKit';
import { RdbHelper } from '../common/db/RdbHelper';
import { EasSubjectType, EasTermSubject } from '../common/model/timetable/TimetableModels';
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
import { EasTermItem } from '../feature/eas/model/EasModels';
import { CreditGoalStore } from '../feature/credit/CreditGoalStore';
import { CreditGoalDialog } from '../feature/credit/CreditGoalDialog';
import { CreditService, creditErrorMessage } from '../feature/credit/CreditService';
import { CreditField, LocalCreditCategory, LocalCreditSummary, CreditRequirement, CreditGroup,
  CreditGroupCourse, CreditCourseRecord, OfficialCreditProgress } from '../feature/credit/CreditModels';
import { aggregateLocalCredits, creditTypeName, creditTypeColor, creditNumber, creditPercent } from '../feature/credit/LocalCreditData';

const HEADER_HEIGHT: number = 60;

@Entry
@Component
export struct CreditPage {
  @Prop presentedAsSheet: boolean = false;
  onClose: () => void = () => {};
  @State official: boolean = false;
  @State loading: boolean = true;
  @State ready: boolean = false;
  @State errorText: string = '';
  @State fadeOpacity: number = 0;
  @State terms: EasTermItem[] = [];
  @State termIndex: number = -1;
  @State termNotice: string = '';
  @State progress: OfficialCreditProgress = new OfficialCreditProgress();
  @State local: LocalCreditSummary = new LocalCreditSummary();
  @State expanded: string[] = [];
  @State groupLoading: string[] = [];
  @State groupLoaded: string[] = [];
  @State groupErrors: Map<string, string> = new Map<string, string>();
  @State visibleRecords: number = 10;
  @StorageProp('hita_status_bar_vp') statusBarInset: number = STATUS_BAR_INSET_FALLBACK;
  @StorageProp('hita_nav_bar_vp') navBarInset: number = NAV_BAR_INSET_FALLBACK;
  private generation: number = 0;
  private sheetLoadStarted: boolean = false;
  private session: EasSession | undefined = undefined;
  private service: CreditService = new CreditService();
  private goalStore: CreditGoalStore = new CreditGoalStore();
  private goals: Map<string, number> = new Map<string, number>();
  private subjects: EasTermSubject[] = [];
  private pageScroller: Scroller = new Scroller();
  private goalDialog: CustomDialogController | undefined = undefined;

  async aboutToAppear(): Promise<void> {
    if (this.presentedAsSheet && !this.sheetLoadStarted) await this.onPageShow();
  }

  async onPageShow(): Promise<void> {
    if (this.presentedAsSheet) {
      if (this.sheetLoadStarted) return;
      this.sheetLoadStarted = true;
    }
    await this.load();
  }

  onPageHide(): void { this.generation++; this.sheetLoadStarted = false; this.goalDialog?.close(); }
  aboutToDisappear(): void { this.generation++; this.sheetLoadStarted = false; this.goalDialog?.close(); }

  private reset(): void {
    this.loading = true;
    this.ready = false;
    this.errorText = '';
    this.fadeOpacity = 0;
    this.expanded = [];
    this.groupLoading = [];
    this.groupLoaded = [];
    this.groupErrors = new Map<string, string>();
    this.visibleRecords = 10;
  }

  private async load(): Promise<void> {
    const generation = ++this.generation;
    const previousTerm = this.terms[this.termIndex]?.getCode() ?? '';
    const previousSession = this.session?.sessionGeneration;
    this.reset();
    this.termNotice = '';
    try {
      const context = this.getUIContext().getHostContext() as common.Context;
      const store = EasSessionStore.getInstance();
      await store.init(context);
      const session = await store.loadPreferred();
      if (generation !== this.generation) return;
      this.session = session;
      this.official = session?.campus === EasCampus.SHENZHEN;
      if (this.official && session !== undefined) {
        this.terms = [];
        this.termIndex = -1;
        try {
          const terms = await new EasDataProvider(new EasApiClient()).getAllTerms(session);
          if (generation !== this.generation) return;
          this.terms = terms;
          const old = previousSession === session.sessionGeneration ?
            terms.findIndex((term: EasTermItem) => term.getCode() === previousTerm) : -1;
          this.termIndex = old >= 0 ? old : Math.max(0, terms.findIndex((term: EasTermItem) => term.isCurrent));
        } catch (error) {
          if (generation !== this.generation) return;
          if (error instanceof Error && error.message.includes('会话已失效')) throw error;
          this.termNotice = '学期列表暂不可用，按教务当前学期查询';
        }
        await this.queryOfficial(generation);
      } else {
        const db = RdbHelper.getInstance();
        await db.init(context);
        const subjects = await db.getAllSubjects();
        await this.goalStore.init(context);
        const goals = await this.goalStore.load();
        if (generation !== this.generation) return;
        this.subjects = subjects;
        this.goals = goals;
        this.local = aggregateLocalCredits(subjects, goals);
        this.ready = true;
      }
    } catch (error) {
      if (generation === this.generation) {
        this.errorText = creditErrorMessage(error instanceof Error ? error.message : '');
        this.ready = false;
      }
    } finally {
      if (generation === this.generation) this.loading = false;
    }
  }

  private async queryOfficial(generation: number): Promise<void> {
    const session = this.session;
    if (session === undefined) return;
    const result = await this.service.query(session, this.terms[this.termIndex], (progress: OfficialCreditProgress) => {
      if (generation !== this.generation) return;
      this.progress = progress.snapshot();
      this.ready = true;
    }, () => generation === this.generation);
    if (generation !== this.generation) return;
    this.progress = result;
    this.ready = true;
  }

  private async selectTerm(index: number): Promise<void> {
    if (index === this.termIndex || index < 0 || index >= this.terms.length) return;
    const generation = ++this.generation;
    this.termIndex = index;
    this.reset();
    this.pageScroller.scrollTo({ xOffset: 0, yOffset: 0 });
    try {
      await this.queryOfficial(generation);
    } catch (error) {
      if (generation === this.generation) {
        this.errorText = creditErrorMessage(error instanceof Error ? error.message : '');
        this.ready = false;
      }
    } finally {
      if (generation === this.generation) this.loading = false;
    }
  }

  private toggle(id: string): boolean {
    const opening = !this.expanded.includes(id);
    this.expanded = opening ? this.expanded.concat(id) : this.expanded.filter((value: string) => value !== id);
    return opening;
  }

  private async toggleGroup(group: CreditGroup): Promise<void> {
    if (this.loading) return;
    if (!this.toggle(group.id) || this.groupLoaded.includes(group.id) || this.groupLoading.includes(group.id)) return;
    await this.loadGroup(group);
  }

  private async loadGroup(group: CreditGroup): Promise<void> {
    const session = this.session;
    if (session === undefined || this.groupLoading.includes(group.id)) return;
    const generation = this.generation;
    this.groupLoading = this.groupLoading.concat(group.id);
    const errors = new Map<string, string>(this.groupErrors);
    errors.delete(group.id);
    this.groupErrors = errors;
    try {
      const courses = await this.service.groupCourses(session, this.progress.context, group, () => generation === this.generation);
      if (generation !== this.generation) return;
      const next = this.progress.snapshot();
      const selected = next.groups.find((item: CreditGroup) => item.id === group.id);
      if (selected !== undefined) selected.courses = courses;
      this.progress = next;
      this.groupLoaded = this.groupLoaded.concat(group.id);
    } catch (error) {
      if (generation === this.generation) {
        const next = new Map<string, string>(this.groupErrors);
        next.set(group.id, creditErrorMessage(error instanceof Error ? error.message : ''));
        this.groupErrors = next;
      }
    } finally {
      if (generation === this.generation) this.groupLoading = this.groupLoading.filter((id: string) => id !== group.id);
    }
  }

  private editGoal(category: LocalCreditCategory): void {
    this.goalDialog?.close();
    const generation = this.generation;
    const type: EasSubjectType = category.type;
    this.goalDialog = new CustomDialogController({
      builder: CreditGoalDialog({
        categoryName: creditTypeName(type),
        initialValue: category.goal || category.credits,
        onSave: async (value: number) => {
          await this.goalStore.save(type, value);
          if (generation !== this.generation) return;
          if (value > 0) this.goals.set(type, value);
          else this.goals.delete(type);
          this.local = aggregateLocalCredits(this.subjects, this.goals);
        }
      }),
      customStyle: true,
      autoCancel: false,
      alignment: DialogAlignment.Center
    });
    this.goalDialog.open();
  }

  private groupDetail(group: CreditGroup): string {
    const parts: string[] = [];
    if (group.required !== undefined) parts.push(creditNumber(group.completed) + ' / ' + creditNumber(group.required) + ' 学分');
    if (group.requiredCourses !== undefined) parts.push(group.completedCourses + ' / ' + group.requiredCourses + ' 门');
    return parts.join(' · ');
  }

  private courseCounts(): string {
    const parts: string[] = [];
    if (this.progress.completedCourses !== undefined) parts.push('已完成 ' + this.progress.completedCourses + ' 门');
    if (this.progress.requiredCourses !== undefined) parts.push('要求 ' + this.progress.requiredCourses + ' 门');
    if (this.progress.remainingCourses !== undefined) parts.push('还需 ' + this.progress.remainingCourses + ' 门');
    return parts.join(' · ');
  }

  @Builder
  private metric(label: string, value: string, valueSize: number = 18, accent: boolean = false) {
    Column({ space: 4 }) {
      Text(label).fontSize(valueSize >= 24 ? 14 : 12).fontColor($r('app.color.hita_text_secondary'))
      Text(value).fontSize(valueSize).fontWeight(FontWeight.Bold)
        .fontColor(accent ? $r('app.color.hita_primary') : $r('app.color.hita_text'))
    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
  }

  @Builder
  private section(title: string, count: string) {
    Row({ space: 12 }) {
      Text(title).fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.hita_text')).layoutWeight(1)
      Text(count).fontSize(13).fontColor($r('app.color.hita_text_secondary'))
    }.width('100%').padding({ top: 14, bottom: 4 })
  }

  @Builder
  private officialSummary() {
    Column({ space: 16 }) {
      Row({ space: 8 }) {
        Text(creditNumber(this.progress.completed)).fontSize(32).fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.hita_primary'))
        Text('/ ' + creditNumber(this.progress.required) + ' 学分').fontSize(15).fontColor($r('app.color.hita_text_secondary'))
          .layoutWeight(1)
        if (this.progress.required !== undefined && this.progress.required > 0 && this.progress.completed !== undefined) {
          Text(Math.floor(creditPercent(this.progress.completed, this.progress.required)) + '%')
            .fontSize(18).fontWeight(FontWeight.Medium).fontColor($r('app.color.hita_text'))
        }
      }.width('100%')
      if (this.progress.required !== undefined && this.progress.required > 0 && this.progress.completed !== undefined) {
        Progress({ value: creditPercent(this.progress.completed, this.progress.required), total: 100, type: ProgressType.Linear })
          .width('100%').color($r('app.color.hita_primary')).backgroundColor($r('app.color.hita_surface_soft'))
      }
      Row({ space: 8 }) {
        this.metric('培养要求', creditNumber(this.progress.required))
        this.metric('已经完成', creditNumber(this.progress.completed))
        this.metric('仍需完成', creditNumber(this.progress.remaining))
      }.width('100%')
      if (this.courseCounts()) {
        Text(this.courseCounts()).fontSize(13).fontColor($r('app.color.hita_text_secondary')).width('100%')
      }
      if (this.progress.average !== undefined || this.progress.rank !== undefined) {
        Text('平均学分绩 ' + creditNumber(this.progress.average) + (this.progress.rank !== undefined ?
          ' · 专业排名 ' + creditNumber(this.progress.rank) + ' / ' + creditNumber(this.progress.cohortSize) : ''))
          .fontSize(13).fontColor($r('app.color.hita_text_secondary')).width('100%')
      }
    }.width('100%').padding(18).borderRadius(16).backgroundColor($r('app.color.hita_surface'))
  }

  @Builder
  private requirementCard(item: CreditRequirement) {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Text(item.name).fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.hita_text')).layoutWeight(1)
        Text(item.passed ? '已完成要求' : '还需 ' + creditNumber(item.remaining) + ' 学分').fontSize(12)
          .fontColor(item.passed ? $r('app.color.hita_primary') : $r('app.color.hita_text_secondary')).constraintSize({ maxWidth: 128 })
      }.width('100%')
      Text(['方向：' + (item.direction || '无'), item.language, item.nature].filter((value: string) => value.length > 0).join(' · '))
        .fontSize(12).fontColor($r('app.color.hita_text_secondary')).width('100%')
      Row({ space: 8 }) {
        this.metric('要求学分', creditNumber(item.required))
        this.metric('完成学分', creditNumber(item.completed))
        this.metric('剩余学分', creditNumber(item.remaining))
      }.width('100%')
      if (item.hours !== undefined) {
        Text('完成学时 ' + item.hours).fontSize(12).fontColor($r('app.color.hita_text_secondary')).width('100%')
      }
      if (item.earnedMooc > 0 || item.creditedMooc > 0) {
        Text('MOOC 实修 ' + creditNumber(item.earnedMooc) + ' 学分 · 计入 ' + creditNumber(item.creditedMooc) + ' 学分')
          .fontSize(12).fontColor($r('app.color.hita_text_secondary')).width('100%')
      }
    }.width('100%').padding(16).borderRadius(12).backgroundColor($r('app.color.hita_surface'))
  }

  @Builder
  private groupCard(group: CreditGroup) {
    Column() {
      Row({ space: 12 }) {
        Column({ space: 5 }) {
          Text(group.name).fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.hita_text'))
          if (this.groupDetail(group)) {
            Text(this.groupDetail(group)).fontSize(13).fontColor($r('app.color.hita_text_secondary'))
          }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Text(group.passed ? '已完成要求' : '仍需完成').fontSize(12)
          .fontColor(group.passed ? $r('app.color.hita_primary') : $r('app.color.hita_text_secondary'))
        if (!group.hasChildren) {
          SymbolGlyph(this.expanded.includes(group.id) ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
            .fontSize(16).fontColor([$r('app.color.hita_text_secondary')])
        }
      }.width('100%').padding(16).onClick(() => { if (!group.hasChildren) this.toggleGroup(group); })
        .accessibilityText(group.name + '，' + this.groupDetail(group) + (group.hasChildren ? '' : '，展开课程'))
      if (this.expanded.includes(group.id)) {
        if (this.groupLoading.includes(group.id)) {
          LoadingProgress().width(28).height(28).margin(12)
        } else if (this.groupErrors.has(group.id)) {
          Text(this.groupErrors.get(group.id) ?? '').fontSize(13).fontColor($r('app.color.hita_error')).padding(16)
            .onClick(() => this.loadGroup(group)).accessibilityText('重新查询课组课程')
        } else if (this.groupLoaded.includes(group.id) && group.courses.length === 0) {
          Text('暂无课组课程').fontSize(13).fontColor($r('app.color.hita_text_secondary')).padding(16)
        }
        ForEach(group.courses, (course: CreditGroupCourse) => {
          Divider().color($r('app.color.hita_surface_soft'))
          Row({ space: 12 }) {
            Column({ space: 5 }) {
              Text(course.name).fontSize(14).fontColor($r('app.color.hita_text'))
              Text([course.code, course.term, course.nature].filter((v: string) => v.length > 0).join(' · '))
                .fontSize(12).fontColor($r('app.color.hita_text_secondary'))
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            Column({ space: 5 }) {
              Text(creditNumber(course.credits) + ' 学分').fontSize(13).fontColor($r('app.color.hita_text'))
              Text(course.completed ? '已修' : '未修').fontSize(12)
                .fontColor(course.completed ? $r('app.color.hita_primary') : $r('app.color.hita_text_secondary'))
            }.alignItems(HorizontalAlign.End)
          }.width('100%').padding(16)
        }, (course: CreditGroupCourse) => course.code || course.name)
      }
    }.width('100%').borderRadius(12).backgroundColor($r('app.color.hita_surface'))
  }

  @Builder
  private recordRow(course: CreditCourseRecord) {
    Row({ space: 12 }) {
      Column({ space: 6 }) {
        Text(course.name).fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.hita_text'))
        Text([course.code, course.term, course.teacher].filter((value: string) => value.length > 0).join(' · '))
          .fontSize(12).fontColor($r('app.color.hita_text_secondary'))
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Column({ space: 5 }) {
        Text(creditNumber(course.credits) + ' 学分').fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.hita_primary'))
        if (course.score) {
          Text(course.score).fontSize(13).fontColor($r('app.color.hita_text_secondary'))
        }
      }.alignItems(HorizontalAlign.End)
    }.width('100%').padding({ top: 12, bottom: 12 })
  }

  @Builder
  private localSummary() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        this.metric('课表总学分', creditNumber(this.local.credits), 24, true)
        this.metric('课程数', this.local.count.toString(), 24)
      }.width('100%')
      Divider().color($r('app.color.hita_surface_soft'))
      Row({ space: 12 }) {
        this.metric('计入平均学分绩', creditNumber(this.local.spaCredits), 14)
        this.metric('不计入', creditNumber(this.local.nonSpaCredits), 14)
      }.width('100%')
    }.width('100%').padding(16).backgroundColor($r('app.color.hita_surface')).borderRadius(16)
  }

  @Builder
  private categoryCard(category: LocalCreditCategory) {
    Column({ space: 8 }) {
      Row({ space: 10 }) {
        Row().width(10).height(10).borderRadius(5).backgroundColor(creditTypeColor(category.type))
        Text(creditTypeName(category.type)).fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.hita_text')).layoutWeight(1)
        Text(creditNumber(category.credits) + ' 学分').fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.hita_primary'))
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.pencil_line')).fontSize(18).fontColor([$r('app.color.hita_text_secondary')])
        }.width(32).height(32).backgroundColor($r('app.color.hita_surface_soft'))
          .accessibilityText('设置' + creditTypeName(category.type) + '学分目标').onClick(() => this.editGoal(category))
      }.width('100%')
      if (category.goal > 0) {
        Progress({ value: creditPercent(category.credits, category.goal), total: 100, type: ProgressType.Linear })
          .width('100%').color(creditTypeColor(category.type)).backgroundColor($r('app.color.hita_surface_soft'))
        Text(creditNumber(category.credits) + ' / ' + creditNumber(category.goal) + ' 学分')
          .fontSize(12).fontColor($r('app.color.hita_text_secondary')).width('100%')
      }
      Row() {
        Text(category.subjects.length + ' 门课程').fontSize(13).fontColor($r('app.color.hita_text_secondary')).layoutWeight(1)
        Text(this.expanded.includes(category.type) ? '收起明细' : '查看明细').fontSize(13).fontColor($r('app.color.hita_primary'))
        SymbolGlyph(this.expanded.includes(category.type) ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
          .fontSize(14).fontColor([$r('app.color.hita_primary')]).margin({ left: 6 })
      }.width('100%').height(36).onClick(() => this.toggle(category.type))
      if (this.expanded.includes(category.type)) {
        ForEach(category.fields, (field: CreditField) => {
          Row({ space: 12 }) {
            Text(field.name).layoutWeight(1).fontSize(13).fontColor($r('app.color.hita_text_secondary'))
            Text(creditNumber(field.credits) + ' 学分').fontSize(13).fontColor($r('app.color.hita_text_secondary'))
          }.width('100%')
        }, (field: CreditField) => field.name)
        Divider().color($r('app.color.hita_surface_soft'))
        ForEach(category.subjects, (subject: EasTermSubject) => {
          Row({ space: 12 }) {
            Text(subject.name).fontSize(14).fontColor($r('app.color.hita_text')).layoutWeight(1)
            Text(creditNumber(subject.credit) + ' 学分').fontSize(13).fontColor($r('app.color.hita_text_secondary'))
          }.width('100%').padding({ top: 4, bottom: 4 })
        }, (subject: EasTermSubject) => subject.id)
      }
    }.width('100%').padding(16).backgroundColor($r('app.color.hita_surface')).borderRadius(16)
  }

  @Builder
  private content() {
    if (this.official) {
      Select(this.terms.map((term: EasTermItem): SelectOption => ({ value: term.name })))
        .selected(this.termIndex).value(this.terms[this.termIndex]?.name || this.progress.term || '教务当前学期')
        .width('100%').enabled(this.terms.length > 0).onSelect((index: number) => this.selectTerm(index))
      if (this.termNotice) {
        Text(this.termNotice).fontSize(12).fontColor($r('app.color.hita_text_secondary')).width('100%')
      }
      this.officialSummary()
      ForEach(this.progress.notices, (notice: string) => {
        Text(notice).fontSize(13).fontColor($r('app.color.hita_text_secondary')).width('100%')
      })
      if (this.progress.categories.length > 0) {
        this.section('学分类别要求', this.progress.categories.length + ' 项')
        ForEach(this.progress.categories, (item: CreditRequirement) => {
          this.requirementCard(item)
        }, (item: CreditRequirement) => item.id)
      }
      if (this.progress.groups.length > 0) {
        this.section('培养课组', '')
        ForEach(this.progress.groups.filter((group: CreditGroup) => group.depth > 0 || group.name !== '无'), (group: CreditGroup) => {
          this.groupCard(group)
        }, (group: CreditGroup) => group.id)
      }
      if (this.progress.records.length > 0) {
        this.section('课程成绩明细', this.progress.records.length + ' 条')
        ForEach(this.progress.records.slice(0, this.visibleRecords), (course: CreditCourseRecord) => {
          this.recordRow(course)
        }, (course: CreditCourseRecord) => course.id)
        if (this.visibleRecords < this.progress.records.length) {
          Text('展开更多明细').fontSize(14).fontColor($r('app.color.hita_primary')).width('100%').height(44)
            .textAlign(TextAlign.Center).onClick(() => { this.visibleRecords += 50; })
        } else if (this.progress.records.length > 10) {
          Text('收起课程明细').fontSize(14).fontColor($r('app.color.hita_primary')).width('100%').height(44)
            .textAlign(TextAlign.Center).onClick(() => { this.visibleRecords = 10; })
        }
      }
      if (this.loading) {
        Row({ space: 8 }) {
          LoadingProgress().width(20).height(20)
          Text('正在读取详细信息…').fontSize(13).fontColor($r('app.color.hita_text_secondary'))
        }.width('100%').justifyContent(FlexAlign.Center)
      }
      Text('数据来源：深圳教务个人培养方案').fontSize(12).fontColor($r('app.color.hita_text_secondary')).width('100%').margin({ top: 8 })
    } else {
      this.localSummary()
      ForEach(this.local.categories, (category: LocalCreditCategory) => {
        this.categoryCard(category)
      }, (category: LocalCreditCategory) => category.type)
      Text('数据来源于全部本地课表科目，重复课程只计一次。课表学分不代表已获学分或毕业审核结果。')
        .fontSize(12).lineHeight(20).fontColor($r('app.color.hita_text_secondary')).width('100%').margin({ top: 8 })
    }
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      if (this.ready && (this.official || this.local.count > 0)) {
        Scroll(this.pageScroller) {
          Column({ space: 12 }) { this.content() }
            .width('100%').padding({ top: HEADER_HEIGHT + 12, left: 16, right: 16, bottom: this.navBarInset + 24 })
        }.width('100%').height('100%').align(Alignment.Top).scrollBar(BarState.Off)
          .onDidScroll(() => { this.fadeOpacity = HeaderFade.opacity(this.pageScroller.currentOffset().yOffset); })
      } else {
        Column({ space: 16 }) {
          if (this.loading) {
            LoadingProgress().width(32).height(32)
            Text('正在读取学分…').fontSize(14).fontColor($r('app.color.hita_text_secondary'))
          } else {
            Text(this.errorText || '暂无科目数据，请先导入课表').fontSize(16)
              .fontColor($r('app.color.hita_text_secondary')).textAlign(TextAlign.Center)
          }
        }.width('100%').justifyContent(FlexAlign.Start)
          .padding({ left: 24, right: 24, top: HEADER_HEIGHT + 48, bottom: this.navBarInset })
      }
      HeaderFadeMask({ maskOpacity: this.fadeOpacity, headerHeight: HEADER_HEIGHT })
      ImmersiveHeader({ barHeight: HEADER_HEIGHT, materialEnabled: !this.presentedAsSheet ||
        CompatibleSheetMaterial.isEnabled() }) {
        Row({ space: 12 }) {
          HeaderBackButton({ onBack: () => {
            if (this.presentedAsSheet) this.onClose();
            else this.getUIContext().getRouter().back();
          } })
          Text(this.official ? '培养方案完成度' : '学分统计').fontSize(20).fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.hita_text')).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(20)
              .fontColor([CompatibleMaterialModifier.foreground('#FFFFFF')])
          }.width(36).height(36).backgroundColor($r('app.color.hita_primary_fill'))
            .attributeModifier(new CompatibleMaterialModifier($r('app.color.hita_primary_fill'), false,
              !this.presentedAsSheet || CompatibleSheetMaterial.isEnabled()))
            .enabled(!this.loading).accessibilityText('刷新学分').onClick(() => this.load())
        }.width('100%').height(HEADER_HEIGHT).padding({ left: 16, right: 16 })
          .hitTestBehavior(HitTestMode.Transparent)
      }
    }.width('100%').height('100%')
      .padding({ top: this.presentedAsSheet ? 0 : this.statusBarInset })
      .backgroundColor(this.presentedAsSheet ? CompatibleSheetMaterial.bodyColor($r('app.color.hita_page')) :
        $r('app.color.hita_page'))
      .attributeModifier(new CompatibleLightModifier(24, this.presentedAsSheet &&
        CompatibleSheetMaterial.isEnabled(), true))
  }
}
