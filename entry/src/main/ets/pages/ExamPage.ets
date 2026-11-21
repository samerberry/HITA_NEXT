import { HitaDesign } from '../common/theme/HitaDesign';
import { SheetContent } from '../common/components/SheetContent';
import { DetailActionBar } from '../common/components/DetailActionBar';
import { LearningTask } from '../common/model/learning/LearningTask';
import { ScheduleChangeSignal } from '../common/util/ScheduleChangeSignal';
/**
 * ExamPage.ets — 考试查询。
 *
 * 数据面：聚合本地全部课表中类型为考试（EXAM）的事件，按时间升序展示；
 * 新建考试写入当前课表，编辑和删除始终使用考试原有的事件 ID。
 * 查询到的考试自动同步到当前课表；时间待定的考试只显示查询结果。
 */
import { common } from '@kit.AbilityKit';
import { HeaderBackButton } from '../common/components/HeaderBackButton';
import { HeaderActionButton } from '../common/components/HeaderActionButton';
import { HitaButton } from '../common/components/HitaButton';
import { HitaTag, HitaTagTone } from '../common/components/HitaTag';
import { ImmersiveHeader } from '../common/components/ImmersiveHeader';
import { CompatibleMaterialModifier } from '../common/theme/CompatibleMaterialModifier';
import { CompatibleLightModifier } from '../common/theme/CompatibleLightModifier';
import { CompatibleSheetMaterial } from '../common/theme/CompatibleSheetMaterial';
import { HeaderFadeMask } from '../common/components/HeaderFadeMask';
import { HeaderFade } from '../common/theme/HeaderFade';
import { CirclePaintModifier } from '../common/theme/CirclePaintModifier';
import { DeleteParticleCard } from '../common/components/DeleteParticleCard';
import { DeleteEffectController } from '../common/util/DeleteEffectController';
import { NAV_BAR_INSET_FALLBACK, STATUS_BAR_INSET_FALLBACK } from '../common/theme/StatusBarInset';
import { RdbHelper } from '../common/db/RdbHelper';
import { EasEventItem, EasEventType, EasTimetable, newId } from '../common/model/timetable/TimetableModels';
import { DOW_FULL, EasTimeTools } from '../common/util/EasTimeTools';
import { TimetableSelectionStore } from '../feature/timetable/data/TimetableSelectionStore';
import { CourseColorEditor } from '../feature/timetable/views/CourseColorEditor';
import { timetableBlockColor } from '../feature/timetable/views/TimetableWeekDraw';
import { EasSession } from '../feature/eas/EasSession';
import { DemoAccount } from '../feature/eas/demo/DemoAccount';
import { EasSessionStore } from '../feature/eas/EasSessionStore';
import { EasDataProvider, EasExamQueryResult } from '../feature/eas/EasDataProvider';
import { EasUserMessages } from '../feature/eas/EasUserMessages';
import { EasApiClient } from '../feature/eas/EasApiClient';
import { EasExamItem, EasTermItem } from '../feature/eas/model/EasModels';
import { ExamSchedule } from '../feature/eas/ExamSchedule';
import { EventEditorForm } from './AddEventPage';

const HEADER_HEIGHT: number = 60;
const PAGE_BG: ResourceColor = $r('app.color.hita_page_f6f7fa');
const PAGE_BG_RGB: string = '245,246,248';
const DETAIL_ICON_SIZE: number = HitaDesign.listIconSize;
const DETAIL_TEXT_GAP: number = 12;
const EXAM_RAIL_WIDTH: number = 4;
const DEFAULT_EXAM_COLOR: number = 0xFFB24B63;

@Entry
@Component
export struct ExamPage {
  @Prop presentedAsSheet: boolean = false;
  onClose: () => void = () => {};
  @State exams: EasEventItem[] = [];
  @State upcoming: EasEventItem[] = [];
  @State past: EasEventItem[] = [];
  @State remoteExams: EasExamItem[] = [];
  @State loading: boolean = true;
  @State learningTasks: LearningTask[] = [];
  @State querying: boolean = false;
  @State preparingQuery: boolean = true;
  @State loadError: boolean = false;
  @State pendingDeleteId: string = '';
  @State openingEditor: boolean = false;
  @State hasSession: boolean = false;
  @State demoMode: boolean = false;
  @State queryMsg: string = '';
  @State queryContext: string = '';
  @State queryWarning: boolean = false;
  @State examColorEditing: boolean = false;
  @State examColorPreview: number = DEFAULT_EXAM_COLOR;
  @State savingExamColor: boolean = false;
  @StorageProp('hita_status_bar_vp') statusBarInset: number = STATUS_BAR_INSET_FALLBACK;
  @StorageProp('hita_nav_bar_vp') navBarInset: number = NAV_BAR_INSET_FALLBACK;
  /** Keep the editor identity until its dismissal animation finishes. */
  @State sheetVisible: boolean = false;
  /** 0=closed, 1=exam detail, 2=editor, 3=remote exam detail. */
  @State examSheetMode: number = 0;
  @State selectedExam: EasEventItem | undefined = undefined;
  @State selectedRemote: EasExamItem | undefined = undefined;
  @State sheetEventId: string = '';
  @State targetTimetableId: string = '';
  @State fadeOpacity: number = 0;
  private pageScroller: Scroller = new Scroller();
  private session: EasSession | undefined = undefined;
  private queryGeneration: number = 0;
  private pageGeneration: number = 0;
  private deleteEffects: DeleteEffectController = new DeleteEffectController();
  private deleteSheetDismissed: (() => void) | undefined = undefined;
  private deleteSheetTimer: number = -1;
  private sheetLoadStarted: boolean = false;
  private learningSignalKey: string = 'exam-review-' + newId();
  private learningGeneration: number = 0;
  private learningActive: boolean = false;

  async aboutToAppear(): Promise<void> {
    ScheduleChangeSignal.subscribe(this.learningSignalKey, () => { void this.loadLearningTasks(); });
    if (this.presentedAsSheet && !this.sheetLoadStarted) await this.onPageShow();
  }

  async onPageShow(): Promise<void> {
    this.learningActive = true;
    if (this.presentedAsSheet) {
      if (this.sheetLoadStarted) return;
      this.sheetLoadStarted = true;
    }
    const generation: number = ++this.pageGeneration;
    this.preparingQuery = true;
    this.fadeOpacity = 0;
    this.deleteEffects.resume();
    try {
      await this.refreshSession();
      if (generation !== this.pageGeneration) {
        return;
      }
      const queryGeneration: number = this.queryGeneration;
      await this.loadExams();
      // 本地数据先加载以去重；离开页面或已手动查询时，不再启动自动请求。
      if (generation === this.pageGeneration && queryGeneration === this.queryGeneration && this.hasSession) {
        await this.queryEasExams();
      }
    } finally {
      if (generation === this.pageGeneration) {
        this.preparingQuery = false;
      }
    }
  }

  onPageHide(): void {
    this.learningActive = false;
    this.learningGeneration++;
    this.sheetLoadStarted = false;
    this.pageGeneration++;
    this.deleteEffects.pause();
    this.finishDeleteSheetDismissal();
    this.queryGeneration++;
    this.querying = false;
    this.closeSheet();
  }

  aboutToDisappear(): void {
    ScheduleChangeSignal.unsubscribe(this.learningSignalKey);
    this.onPageHide();
  }

  private async refreshSession(): Promise<void> {
    const generation: number = ++this.queryGeneration;
    this.session = undefined;
    this.demoMode = false;
    this.hasSession = false;
    this.querying = false;
    this.remoteExams = [];
    this.queryMsg = '';
    this.queryContext = '';
    this.queryWarning = false;
    try {
      const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
      await EasSessionStore.getInstance().init(ctx);
      const session: EasSession | undefined = await EasSessionStore.getInstance().loadPreferred();
      if (generation !== this.queryGeneration) {
        return;
      }
      this.session = session;
      this.demoMode = DemoAccount.isSession(session);
      this.hasSession = session !== undefined;
    } catch (_) {
      if (generation === this.queryGeneration) {
        this.hasSession = false;
      }
    }
  }

  private async loadExams(): Promise<void> {
    const generation: number = this.pageGeneration;
    this.loading = true;
    this.loadError = false;
    if (this.demoMode) {
      this.exams = [];
      this.upcoming = [];
      this.past = [];
      this.remoteExams = [];
      this.learningGeneration++;
      this.learningTasks = [];
      this.loading = false;
      return;
    }
    try {
      const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
      const rdb: RdbHelper = RdbHelper.getInstance();
      await rdb.init(ctx);
      const timetables: EasTimetable[] = await rdb.getTimetables();
      const events: EasEventItem[] = [];
      for (let t = 0; t < timetables.length; t++) {
        const all: EasEventItem[] = await rdb.getEventsOfTimetable(timetables[t].id);
        for (let i = 0; i < all.length; i++) {
          if (all[i].type === EasEventType.EXAM) {
            events.push(all[i]);
          }
        }
      }
      if (generation !== this.pageGeneration || this.demoMode) return;
      events.sort((a: EasEventItem, b: EasEventItem): number => a.from - b.from);
      this.exams = events;
      const now: number = Date.now();
      this.upcoming = events.filter((event: EasEventItem): boolean => ExamSchedule.isUpcoming(event.to, now));
      this.past = events.filter((event: EasEventItem): boolean => !ExamSchedule.isUpcoming(event.to, now));
      await this.loadLearningTasks();
    } catch (_) {
      if (generation === this.pageGeneration && !this.demoMode) this.loadError = true;
    } finally {
      if (generation === this.pageGeneration) this.loading = false;
    }
  }

  private async loadLearningTasks(): Promise<void> {
    const generation: number = ++this.learningGeneration;
    if (this.demoMode) {
      this.learningTasks = [];
      return;
    }
    try {
      const tasks: LearningTask[] = await RdbHelper.getInstance().getLearningTasks();
      if (this.learningActive && generation === this.learningGeneration) this.learningTasks = tasks;
    } catch (_) {}
  }

  private reviewProgress(examId: string): string {
    const tasks: LearningTask[] = this.learningTasks.filter(task => task.examId === examId && task.kind === 'REVIEW');
    return tasks.length === 0 ? '' : '复习清单 ' + tasks.filter(task => task.completedAt > 0).length.toString() +
      ' / ' + tasks.length.toString() + ' 项已完成';
  }

  private async resolveTargetTimetable(examTermCode: string = ''): Promise<string> {
    const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
    await TimetableSelectionStore.getInstance().init(ctx);
    const rdb: RdbHelper = RdbHelper.getInstance();
    await rdb.init(ctx);
    const selectedId: string = await TimetableSelectionStore.getInstance().load();
    const selected: EasTimetable | undefined = selectedId.length > 0 ?
      await rdb.getTimetableById(selectedId) : undefined;
    if (examTermCode.length === 0 && selected !== undefined) return selected.id;
    if (selected !== undefined && ExamPage.canSyncToTimetable(selected, examTermCode)) return selected.id;
    const timetables: EasTimetable[] = await rdb.getTimetables();
    if (examTermCode.length === 0) return timetables[0]?.id ?? '';
    const matching: EasTimetable | undefined = timetables.find((table: EasTimetable): boolean =>
      table.code === examTermCode);
    if (matching !== undefined) return matching.id;
    return selected === undefined ?
      timetables.find((table: EasTimetable): boolean => ExamPage.canSyncToTimetable(table, examTermCode))?.id ?? '' : '';
  }

  private static canSyncToTimetable(table: EasTimetable, examTermCode: string): boolean {
    return table.code === examTermCode || table.code.length === 0 ||
      table.code.startsWith('LOCAL:') || table.code.startsWith('ICS:');
  }

  /** 考试事件挂到当前选中的课表；没有可用课表时引导先建课表。 */
  private async openAddExam(): Promise<void> {
    if (this.demoMode || this.examSheetMode !== 0 || this.openingEditor || this.savingExamColor ||
      this.pendingDeleteId.length > 0) {
      return;
    }
    this.openingEditor = true;
    try {
      const target: string = await this.resolveTargetTimetable();
      if (target.length === 0) {
        this.getUIContext().getPromptAction().showToast({ message: '请先在课表管理中新建课表' });
        return;
      }
      this.sheetEventId = '';
      this.targetTimetableId = target;
      this.selectedExam = undefined;
      this.selectedRemote = undefined;
      this.examSheetMode = 2;
      this.sheetVisible = true;
    } catch (_) {
      this.getUIContext().getPromptAction().showToast({ message: '暂时无法打开考试编辑，请重试' });
    } finally {
      this.openingEditor = false;
    }
  }

  private async queryEasExams(): Promise<void> {
    if (this.querying || this.openingEditor || this.savingExamColor || this.examSheetMode !== 0 ||
      this.pendingDeleteId.length > 0) {
      return;
    }
    if (this.session === undefined) {
      this.queryMsg = '请先登录教务';
      this.queryWarning = true;
      this.getUIContext().getPromptAction().showToast({ message: '请先登录教务后再查询考试' });
      return;
    }
    const session: EasSession = this.session;
    const generation: number = ++this.queryGeneration;
    this.querying = true;
    this.queryWarning = false;
    this.remoteExams = [];
    this.queryMsg = '正在查询…';
    this.queryContext = '';
    try {
      const provider: EasDataProvider = new EasDataProvider(new EasApiClient());
      const terms: EasTermItem[] = await provider.getExamTerms(session);
      if (generation !== this.queryGeneration) {
        return;
      }
      if (terms.length === 0) {
        this.queryMsg = '未获取到学期信息，请稍后重试';
        this.queryWarning = true;
        return;
      }
      const term: EasTermItem = terms.find((value: EasTermItem): boolean => value.isCurrent) ?? terms[0];
      this.queryContext = ExamSchedule.campusName(session.campus.toString()) + ' · ' + term.name;
      const result: EasExamQueryResult = await provider.getExamResult(session, term);
      if (generation !== this.queryGeneration) {
        return;
      }
      this.queryWarning = result.failedTypes.length > 0;
      this.queryMsg = this.queryWarning ? result.failedTypes.join('、') + '查询失败，请重试' :
        (result.items.length === 0 ? '本学期暂无教务考试安排' : '');
      if (!this.demoMode) await this.syncQueriedExams(session, term, result, generation);
    } catch (e) {
      if (generation !== this.queryGeneration) {
        return;
      }
      this.queryWarning = true;
      this.queryMsg = EasUserMessages.fromError(e instanceof Error ? e.message : String(e),
        '考试查询失败，请稍后重试');
    } finally {
      if (generation === this.queryGeneration) {
        this.querying = false;
      }
    }
  }

  private async syncQueriedExams(session: EasSession, term: EasTermItem, result: EasExamQueryResult,
    generation: number): Promise<void> {
    try {
      const termCode: string = session.campus.toString() + ':' + term.getCode();
      const target: string = await this.resolveTargetTimetable(termCode);
      if (generation !== this.queryGeneration) return;
      if (target.length === 0) {
        this.remoteExams = result.items;
        if (result.items.length > 0) {
          this.queryMsg = '请导入或选择对应学期的课表后重新查询';
          this.queryWarning = true;
        }
        return;
      }
      const source: string = termCode + '/';
      const events: EasEventItem[] = [];
      const pending: EasExamItem[] = [];
      for (const item of result.items) {
        const event: EasEventItem | undefined = ExamSchedule.toEvent(item, target, source);
        if (event === undefined) {
          pending.push(item);
        } else {
          event.color = DEFAULT_EXAM_COLOR;
          events.push(event);
        }
      }
      this.remoteExams = pending;
      const complete: boolean = result.failedTypes.length === 0;
      if (events.length === 0 && !complete) return;
      const pendingKeys: string[] = pending.map((item: EasExamItem): string => ExamSchedule.sourceKey(source, item));
      await RdbHelper.getInstance().syncExamEvents(target, source, events, pendingKeys, complete);
      if (generation !== this.queryGeneration) return;
      await this.loadExams();
    } catch (_) {
      if (generation === this.queryGeneration) {
        this.remoteExams = result.items;
        this.queryMsg = '考试同步失败，请重新查询';
        this.queryWarning = true;
      }
    }
  }

  private openExamDetail(event: EasEventItem): void {
    if (this.examSheetMode !== 0 || this.openingEditor || this.savingExamColor ||
      this.pendingDeleteId.length > 0) {
      return;
    }
    this.selectedExam = event;
    this.selectedRemote = undefined;
    this.examColorEditing = false;
    this.sheetEventId = event.id;
    this.targetTimetableId = event.timetableId;
    this.examSheetMode = 1;
    this.sheetVisible = true;
  }

  private openRemoteDetail(item: EasExamItem): void {
    if (this.examSheetMode !== 0 || this.openingEditor || this.savingExamColor ||
      this.pendingDeleteId.length > 0) {
      return;
    }
    this.selectedRemote = item;
    this.selectedExam = undefined;
    this.examColorEditing = false;
    this.sheetEventId = '';
    this.examSheetMode = 3;
    this.sheetVisible = true;
  }

  private openEditExam(event: EasEventItem): void {
    if (this.pendingDeleteId.length > 0 || this.savingExamColor ||
      this.examSheetMode !== 1 || !this.sheetVisible) {
      return;
    }
    this.sheetEventId = event.id;
    this.targetTimetableId = event.timetableId;
    this.examColorEditing = false;
    this.examSheetMode = 2;
  }

  private static examColor(event: EasEventItem): number {
    return event.color === 0 ? DEFAULT_EXAM_COLOR : event.color;
  }

  private static cardKey(event: EasEventItem): string {
    return JSON.stringify([event.id, event.name, event.place, event.from, event.to, event.color]);
  }

  private static colorCss(color: number): string {
    return '#' + (timetableBlockColor(color) & 0xFFFFFF).toString(16).padStart(6, '0');
  }

  private static remoteKey(item: EasExamItem): string {
    return JSON.stringify([item.campusName, item.termName, item.courseName, item.examType,
      item.examDate, item.examTime, item.examLocation]);
  }

  private toggleExamColor(color: number): void {
    if (this.savingExamColor || this.openingEditor || this.pendingDeleteId.length > 0) {
      return;
    }
    this.examColorPreview = color;
    this.examColorEditing = !this.examColorEditing;
  }

  private async saveExamColor(event: EasEventItem, color: number): Promise<void> {
    this.savingExamColor = true;
    try {
      await RdbHelper.getInstance().saveExamColor(event.id, event.timetableId, color);
      for (const item of this.exams) {
        if (item.id === event.id && item.timetableId === event.timetableId) {
          item.color = color;
        }
      }
      this.exams = this.exams.slice();
      this.upcoming = this.upcoming.slice();
      this.past = this.past.slice();
      if (this.selectedExam?.id === event.id && this.examSheetMode === 1 && this.sheetVisible) {
        event.color = color;
        this.selectedExam = this.exams.find((item: EasEventItem) => item.id === event.id) ?? event;
        this.examColorEditing = false;
      }
    } finally {
      this.savingExamColor = false;
    }
  }

  private closeSheet(): void {
    this.sheetVisible = false;
  }

  private resetSheetState(): void {
    this.examSheetMode = 0;
    this.selectedExam = undefined;
    this.selectedRemote = undefined;
    this.sheetEventId = '';
    this.targetTimetableId = '';
    this.examColorEditing = false;
  }

  private closeSheetBeforeDelete(): Promise<void> {
    if (!this.sheetVisible) {
      return Promise.resolve();
    }
    return new Promise<void>((resolve: () => void) => {
      this.deleteSheetDismissed = resolve;
      this.deleteSheetTimer = setTimeout(() => this.finishDeleteSheetDismissal(), 650);
      this.closeSheet();
    });
  }

  private finishDeleteSheetDismissal(): void {
    clearTimeout(this.deleteSheetTimer);
    this.deleteSheetTimer = -1;
    const finish: (() => void) | undefined = this.deleteSheetDismissed;
    this.deleteSheetDismissed = undefined;
    if (finish !== undefined) {
      finish();
    }
  }

  private async confirmDeleteExam(event: EasEventItem): Promise<void> {
    if (this.pendingDeleteId.length > 0 || this.examSheetMode === 2 ||
      this.openingEditor || this.savingExamColor) {
      return;
    }
    this.pendingDeleteId = event.id;
    let confirmed: boolean = false;
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: '删除考试',
        message: '确定删除「' + event.name + '」吗？',
        buttons: [
          { text: '取消', color: $r('app.color.hita_text_secondary_7b8498') },
          { text: '删除', color: $r('app.color.hita_error') }
        ]
      });
      confirmed = result.index === 1;
    } catch (_) {
      // Back or tapping outside the confirmation dialog is cancellation.
    }
    if (!confirmed) {
      this.pendingDeleteId = '';
      return;
    }
    try {
      await RdbHelper.getInstance().deleteEvent(event.id);
      await this.closeSheetBeforeDelete();
      await this.deleteEffects.play([event.id]);
      this.getUIContext().animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
        this.exams = this.exams.filter((item: EasEventItem): boolean => item.id !== event.id);
        this.upcoming = this.upcoming.filter((item: EasEventItem): boolean => item.id !== event.id);
        this.past = this.past.filter((item: EasEventItem): boolean => item.id !== event.id);
      });
      await this.loadExams();
      this.getUIContext().getPromptAction().showToast({ message: '考试已删除' });
    } catch (_) {
      this.getUIContext().getPromptAction().showToast({ message: '删除失败，请重试' });
    } finally {
      this.pendingDeleteId = '';
    }
  }

  static pad(n: number): string {
    return n < 10 ? '0' + n.toString() : n.toString();
  }

  static timeOf(ms: number): string {
    return ExamSchedule.timeOf(ms);
  }

  static dateOf(ms: number): string {
    return ExamSchedule.dateOf(ms);
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      if (this.preparingQuery || this.querying ||
        (this.loading && this.exams.length === 0 && this.remoteExams.length === 0)) {
        Column({ space: 12 }) {
          LoadingProgress()
            .width(36)
            .height(36)
            .color($r('app.color.hita_primary_3390ec'))
          Text('正在刷新考试安排…')
            .fontSize(HitaDesign.caption)
            .fontColor($r('app.color.hita_text_secondary_808080'))
        }
        .width('100%')
        .height('100%')
        .padding({ top: HEADER_HEIGHT, bottom: this.navBarInset })
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (this.loadError && this.exams.length === 0) {
        Row() {
          Text('考试安排加载失败')
            .fontSize(HitaDesign.caption)
            .fontColor($r('app.color.hita_error'))
            .layoutWeight(1)
          HitaButton({ label: '重试', buttonHeight: HitaDesign.controlHeight, fitContent: true,
            onTap: () => this.loadExams() })
        }
        .padding(16)
        .width('100%')
        .margin({ top: HEADER_HEIGHT })
      } else if (!this.loadError && this.exams.length === 0 && this.remoteExams.length === 0) {
        Column() {
          Text(this.queryWarning ? '考试查询失败' : '暂无考试安排')
            .fontSize(HitaDesign.body)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.hita_text_1a1a1a'))
            .width('100%')
            .textAlign(TextAlign.Center)
          Text(this.queryMsg.length > 0 ? this.queryMsg :
            (this.hasSession ? '可点右上角“查询”刷新，或手动添加考试' : '登录教务后可查询考试，也可手动添加'))
            .fontSize(HitaDesign.caption)
            .fontColor(this.queryWarning ? $r('app.color.hita_error') : $r('app.color.hita_text_secondary_808080'))
            .width('100%')
            .textAlign(TextAlign.Center)
            .lineHeight(20)
            .margin({ top: 8 })
        }
        .width('100%')
        .height('100%')
        .padding({ left: 32, right: 32, top: HEADER_HEIGHT, bottom: this.navBarInset })
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        List({ space: 8, scroller: this.pageScroller }) {
          ListItem() {
            Column()
              .width('100%')
              .height(HEADER_HEIGHT)
          }
          if (this.queryContext.length > 0) {
            ListItem() {
              Text(this.queryContext)
                .fontSize(HitaDesign.caption)
                .fontColor($r('app.color.hita_text_secondary_72809a'))
                .width('100%')
            }
          }
          if (this.queryWarning && this.queryMsg.length > 0) {
            ListItem() {
              Text(this.queryMsg)
                .fontSize(HitaDesign.label)
                .fontColor(this.queryWarning ? $r('app.color.hita_error') :
                  $r('app.color.hita_text_secondary_72809a'))
                .width('100%')
            }
          }
          if (this.loadError) {
            ListItem() {
              Row() {
                Text('考试安排加载失败')
                  .fontSize(HitaDesign.caption)
                  .fontColor($r('app.color.hita_error'))
                  .layoutWeight(1)
                HitaButton({ label: '重试', buttonHeight: HitaDesign.controlHeight, fitContent: true,
                  onTap: () => this.loadExams() })
              }
              .width('100%')
            }
          }
          if (this.upcoming.length > 0) {
            ListItem() {
              Text('即将到来')
                .fontSize(HitaDesign.caption)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.hita_text_secondary_72809a'))
            }
          }
          ForEach(this.upcoming, (it: EasEventItem) => {
            ListItem() {
              DeleteParticleCard({
                controller: this.deleteEffects,
                effectId: it.id
              }) {
                this.examCard(it)
              }
            }
            .enabled(this.pendingDeleteId.length === 0)
            .transition(TransitionEffect.OPACITY)
          }, (it: EasEventItem) => ExamPage.cardKey(it) + '|' + this.reviewProgress(it.id))
          ForEach(this.remoteExams, (remote: EasExamItem) => {
            ListItem() {
              this.remoteExamCard(remote)
            }
          }, (remote: EasExamItem) => ExamPage.remoteKey(remote))
          if (this.past.length > 0) {
            ListItem() {
              Text('已结束')
                .fontSize(HitaDesign.caption)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.hita_text_secondary_72809a'))
            }
          }
          ForEach(this.past, (it: EasEventItem) => {
            ListItem() {
              DeleteParticleCard({
                controller: this.deleteEffects,
                effectId: it.id
              }) {
                this.examCard(it)
              }
            }
            .enabled(this.pendingDeleteId.length === 0)
            .transition(TransitionEffect.OPACITY)
          }, (it: EasEventItem) => ExamPage.cardKey(it) + '|' + this.reviewProgress(it.id))
        }
        .width('100%')
        .height('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 24 })
        .scrollBar(BarState.Off)
        .enableScrollInteraction(this.pendingDeleteId.length === 0)
        .onDidScroll(() => {
          this.fadeOpacity = HeaderFade.opacity(this.pageScroller.currentOffset().yOffset);
        })
      }

      if (!this.preparingQuery && !this.querying && this.queryContext.length > 0 &&
        this.exams.length === 0 && this.remoteExams.length === 0) {
        Text(this.queryContext)
          .fontSize(HitaDesign.caption)
          .fontColor($r('app.color.hita_text_secondary_72809a'))
          .width('100%')
          .padding({ left: 16, right: 16 })
          .margin({ top: HEADER_HEIGHT + 12 })
      }

      HeaderFadeMask({
        maskOpacity: this.fadeOpacity,
        rgb: PAGE_BG_RGB,
        headerHeight: HEADER_HEIGHT
      })

      ImmersiveHeader({ barHeight: HEADER_HEIGHT, materialEnabled: !this.presentedAsSheet ||
        CompatibleSheetMaterial.isEnabled() }) {
        Row() {
          HeaderBackButton({
            onBack: () => this.navigateBack()
          })
            .margin({ right: 12 })
          Text('考试安排').fontSize(HitaDesign.title).fontWeight(FontWeight.Medium).fontColor($r('app.color.hita_text'))
            .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          HeaderActionButton({ label: '查询', disabled: this.preparingQuery || this.querying ||
            this.pendingDeleteId.length > 0,
            materialEnabled: !this.presentedAsSheet || CompatibleSheetMaterial.isEnabled(), onTap: () => {
              if (!this.preparingQuery) {
                this.queryEasExams();
              }
            } })
            .margin({ left: HitaDesign.spaceXs })
          if (!this.demoMode) {
            HeaderActionButton({ label: '添加', disabled: this.openingEditor || this.pendingDeleteId.length > 0,
              materialEnabled: !this.presentedAsSheet || CompatibleSheetMaterial.isEnabled(), onTap: () => {
                if (!this.preparingQuery && !this.querying) {
                  this.openAddExam();
                }
              } })
              .margin({ left: HitaDesign.spaceXs })
          }
        }
        .width('100%')
        .height(HEADER_HEIGHT)
        .padding({ left: 16, right: 16 })
        .alignItems(VerticalAlign.Center)
        .hitTestBehavior(HitTestMode.Transparent)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.presentedAsSheet ? 0 : this.statusBarInset })
    .backgroundColor(this.presentedAsSheet ? CompatibleSheetMaterial.bodyColor(PAGE_BG) : PAGE_BG)
    .bindSheet($$this.sheetVisible, this.examSheetContent(), CompatibleSheetMaterial.options({
      height: this.examSheetMode === 2 ? '78%' : SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: false,
      preferType: SheetType.BOTTOM,
      backgroundColor: $r('app.color.hita_surface_soft'),
      maskColor: $r('app.color.hita_sheet_mask'),
      onWillDisappear: () => {
        this.closeSheet();
      },
      onDisappear: () => {
        this.sheetVisible = false;
        this.resetSheetState();
        this.finishDeleteSheetDismissal();
      }
    }))
    .attributeModifier(new CompatibleLightModifier(24, this.presentedAsSheet &&
      CompatibleSheetMaterial.isEnabled(), true))
  }

  @Builder
  private examCard(it: EasEventItem) {
    Row() {
      Row()
        .width(EXAM_RAIL_WIDTH)
        .height(44)
        .borderRadius(EXAM_RAIL_WIDTH / 2)
        .backgroundColor(ExamPage.colorCss(ExamPage.examColor(it)))
      Column() {
        Row() {
          Text(it.name)
            .fontSize(HitaDesign.body)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.hita_text_242a36'))
            .layoutWeight(1)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          HitaTag({ text: ExamSchedule.remainingLabel(it.from, it.to, Date.now()), tone: HitaTagTone.DANGER })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text(ExamPage.dateOf(it.from) + ' · ' + ExamPage.timeOf(it.from) + ' - ' +
          ExamPage.timeOf(it.to))
          .fontSize(HitaDesign.caption)
          .fontColor($r('app.color.hita_text_secondary_7b8498'))
          .width('100%')
          .margin({ top: 8 })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(it.place.length > 0 ? '地点：' + it.place : '地点：待定')
          .fontSize(HitaDesign.caption)
          .fontColor($r('app.color.hita_text_hint_9aa2b1'))
          .width('100%')
          .margin({ top: 4 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.reviewProgress(it.id).length > 0) {
          Text(this.reviewProgress(it.id)).fontSize(HitaDesign.caption).fontColor($r('app.color.hita_primary')).margin({ top: 8 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
    }
    .width('100%')
    .padding(HitaDesign.inset)
    .backgroundColor($r('app.color.hita_surface'))
    .borderRadius(HitaDesign.cardRadius)
    .onClick(() => this.openExamDetail(it))
  }

  @Builder
  private remoteExamCard(remote: EasExamItem) {
    Row() {
      Row()
        .width(EXAM_RAIL_WIDTH)
        .height(44)
        .borderRadius(EXAM_RAIL_WIDTH / 2)
        .backgroundColor(ExamPage.colorCss(DEFAULT_EXAM_COLOR))
      Column() {
        Text(remote.courseName)
          .fontSize(HitaDesign.body)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.hita_text_242a36'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text((remote.examDate.length > 0 ? remote.examDate : '日期待定') +
          (remote.examTime.length > 0 ? ' · ' + remote.examTime : ''))
          .fontSize(HitaDesign.caption)
          .fontColor($r('app.color.hita_text_secondary_7b8498'))
          .width('100%')
          .margin({ top: 8 })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(remote.examLocation.length > 0 ? '地点：' + remote.examLocation : '地点：待定')
          .fontSize(HitaDesign.caption)
          .fontColor($r('app.color.hita_text_hint_9aa2b1'))
          .width('100%')
          .margin({ top: 4 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
    }
    .width('100%')
    .padding(HitaDesign.inset)
    .backgroundColor($r('app.color.hita_surface'))
    .borderRadius(HitaDesign.cardRadius)
    .onClick(() => this.openRemoteDetail(remote))
  }

  @Builder
  private examSheetContent() {
    SheetContent({ fillHeight: this.examSheetMode === 2 }) {
      Column() {
        if (this.examSheetMode === 2) {
          EventEditorForm({
            eventId: this.sheetEventId,
            targetTimetableId: this.targetTimetableId,
            initialType: 'EXAM',
            sheetMode: true,
            onCancel: () => {
              this.closeSheet();
            },
            onSaved: (_event: EasEventItem) => {
              this.closeSheet();
              this.loadExams();
            }
          })
            .width('100%')
            .height('100%');
        } else if (this.examSheetMode === 3 && this.selectedRemote !== undefined) {
          this.remoteDetailSheet(this.selectedRemote as EasExamItem);
        } else if (this.selectedExam !== undefined) {
          this.examDetailSheet(this.selectedExam as EasEventItem);
        }
      }
      .width('100%')
      .height(this.examSheetMode === 2 ? '100%' : undefined)
      .attributeModifier(new CompatibleLightModifier(24, CompatibleSheetMaterial.isEnabled(), true))
    }
  }

  @Builder
  private examDetailSheet(event: EasEventItem) {
    Column() {
      Row() {
        Circle()
          .width(DETAIL_ICON_SIZE)
          .height(DETAIL_ICON_SIZE)
          .flexShrink(0)
          .attributeModifier(new CirclePaintModifier(ExamPage.colorCss(
            this.examColorEditing ? this.examColorPreview : ExamPage.examColor(event))))
        Column() {
          Text(event.name)
            .fontSize(HitaDesign.title)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.hita_text_202b45'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('考试详情')
            .fontSize(HitaDesign.caption)
            .fontColor($r('app.color.hita_text_secondary_72809a'))
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ left: DETAIL_TEXT_GAP })
        this.examColorButton(ExamPage.examColor(event))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ bottom: HitaDesign.spaceMd })

      if (this.examColorEditing) {
        CourseColorEditor({
          initialColor: ExamPage.examColor(event),
          immersiveControls: true,
          examMode: true,
          onPreview: (color: number) => { this.examColorPreview = color; },
          onSave: async (color: number) => { await this.saveExamColor(event, color); },
          onCancel: () => { this.examColorEditing = false; }
        })
      } else {
        this.examDetailRow($r('sys.symbol.person_crop_circle_fill'), event.examSource.length > 0 ? '类型' : '老师',
          event.teacher.trim().length > 0 ? event.teacher : '未填写')
        this.examDetailRow($r('sys.symbol.pin'), '考场',
          event.place.trim().length > 0 ? event.place : '待定')
        this.examDetailRow($r('sys.symbol.clock'), '时间',
          ExamPage.timeOf(event.from) + ' - ' + ExamPage.timeOf(event.to))
        this.examDetailRow($r('sys.symbol.calendar'), '日期',
          ExamPage.dateOf(event.from) + ' · ' + DOW_FULL[EasTimeTools.getDow(event.from)])
        this.examDetailRow($r('sys.symbol.checkmark'), '状态',
          ExamSchedule.remainingLabel(event.from, event.to, Date.now()))

        DetailActionBar({
          deleteLabel: '删除', busy: this.pendingDeleteId.length > 0 || this.openingEditor, taskEvent: event,
          onEdit: () => this.openEditExam(event), onDelete: () => this.confirmDeleteExam(event)
        })
      }
    }
    .width('100%')
    .padding({ left: HitaDesign.inset, right: HitaDesign.inset, top: 0, bottom: 24 })
  }

  @Builder
  private remoteDetailSheet(item: EasExamItem) {
    Column() {
      Row() {
        Circle()
          .width(DETAIL_ICON_SIZE)
          .height(DETAIL_ICON_SIZE)
          .flexShrink(0)
          .attributeModifier(new CirclePaintModifier(ExamPage.colorCss(DEFAULT_EXAM_COLOR)))
        Column() {
          Text(item.courseName)
            .fontSize(HitaDesign.title)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.hita_text_202b45'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('考试详情')
            .fontSize(HitaDesign.caption)
            .fontColor($r('app.color.hita_text_secondary_72809a'))
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ left: DETAIL_TEXT_GAP })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ bottom: HitaDesign.spaceMd })

      this.examDetailRow($r('sys.symbol.clock'), '时间',
        item.examTime.length > 0 ? item.examTime : '待定')
      this.examDetailRow($r('sys.symbol.calendar'), '日期',
        item.examDate.length > 0 ? item.examDate : '待定')
      this.examDetailRow($r('sys.symbol.pin'), '地点',
        item.examLocation.length > 0 ? item.examLocation : '待定')
      this.examDetailRow($r('sys.symbol.checkmark'), '类型',
        item.examType.length > 0 ? item.examType : '未填写')
      this.examDetailRow($r('sys.symbol.doc_plaintext'), '学期',
        item.termName.length > 0 ? item.termName : '未填写')
      this.examDetailRow($r('sys.symbol.magnifyingglass'), '校区',
        item.campusName.length > 0 ? item.campusName : '未填写')
    }
    .width('100%')
    .padding({ left: HitaDesign.inset, right: HitaDesign.inset, top: 0, bottom: 24 })
  }

  @Builder
  private examColorButton(color: number) {
    Column() {
      ImmersiveHeader({ barHeight: 44, materialEnabled: CompatibleSheetMaterial.isEnabled() }) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.paintpalette'))
            .fontSize(HitaDesign.iconMd)
            .fontColor([CompatibleSheetMaterial.isEnabled() ?
              CompatibleMaterialModifier.foreground($r('app.color.hita_primary_3390ec')) :
              $r('app.color.hita_primary_3390ec')])
        }
        .width(44)
        .height(44)
        .padding(0)
        .backgroundColor($r('app.color.hita_selected_e4f0ff'))
        .attributeModifier(new CompatibleMaterialModifier($r('app.color.hita_selected_e4f0ff'), false,
          CompatibleSheetMaterial.isEnabled()))
        .accessibilityText('修改考试颜色')
        .enabled(!this.savingExamColor && !this.openingEditor && this.pendingDeleteId.length === 0)
        .onClick(() => this.toggleExamColor(color))
      }
    }
    .width(44)
    .height(44)
    .margin({ left: 8 })
    .flexShrink(0)
  }

  @Builder
  private examDetailRow(symbol: Resource, label: string, value: string) {
    Row() {
      Stack() {
        SymbolGlyph(symbol)
          .fontSize(HitaDesign.iconMd)
          .fontColor([$r('app.color.hita_primary_3390ec')])
      }
      .width(DETAIL_ICON_SIZE)
      .height(DETAIL_ICON_SIZE)
      .borderRadius(DETAIL_ICON_SIZE / 2)
      .flexShrink(0)
      .backgroundColor($r('app.color.hita_selected_e4f0ff'))
      .alignContent(Alignment.Center)
      Column() {
        Text(label)
          .fontSize(HitaDesign.caption)
          .fontColor($r('app.color.hita_text_secondary_72809a'))
        Text(value)
          .fontSize(HitaDesign.body)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.hita_text_202b45'))
          .margin({ top: HitaDesign.space2xs })
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: DETAIL_TEXT_GAP })
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
  }

  navigateBack(): void {
    if (this.presentedAsSheet) {
      this.onClose();
    } else {
      this.getUIContext().getRouter().back();
    }
  }
}
