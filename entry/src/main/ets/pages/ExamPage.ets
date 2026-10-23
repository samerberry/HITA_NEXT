import { SheetContent } from '../common/components/SheetContent';
/**
 * ExamPage.ets — 考试查询。
 *
 * 数据面：聚合本地全部课表中类型为考试（EXAM）的事件，按时间升序展示；
 * 新建考试写入当前课表，编辑和删除始终使用考试原有的事件 ID。
 * 已登录教务时，可查询深圳、本部和威海本科考试安排并导入当前课表。
 */
import { common } from '@kit.AbilityKit';
import { HeaderBackButton } from '../common/components/HeaderBackButton';
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
import { EasEventItem, EasEventType, EasTimetable } from '../common/model/timetable/TimetableModels';
import { DOW_FULL, EasTimeTools } from '../common/util/EasTimeTools';
import { TimetableSelectionStore } from '../feature/timetable/data/TimetableSelectionStore';
import { CourseColorEditor } from '../feature/timetable/views/CourseColorEditor';
import { timetableBlockColor } from '../feature/timetable/views/TimetableWeekDraw';
import { EasSession } from '../feature/eas/EasSession';
import { EasSessionStore } from '../feature/eas/EasSessionStore';
import { EasDataProvider, EasExamQueryResult } from '../feature/eas/EasDataProvider';
import { EasUserMessages } from '../feature/eas/EasUserMessages';
import { EasApiClient } from '../feature/eas/EasApiClient';
import { EasExamItem, EasTermItem } from '../feature/eas/model/EasModels';
import { ExamSchedule } from '../feature/eas/ExamSchedule';
import { EventEditorForm } from './AddEventPage';

const HEADER_HEIGHT: number = 60;
const PAGE_BG: ResourceColor = $r('app.color.hita_page_f6f7fa');
const PAGE_BG_RGB: string = '246,247,250';
const DETAIL_ICON_SIZE: number = 38;
const DETAIL_TEXT_GAP: number = 12;
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
  @State querying: boolean = false;
  @State preparingQuery: boolean = true;
  @State loadError: boolean = false;
  @State pendingDeleteId: string = '';
  @State openingEditor: boolean = false;
  @State hasSession: boolean = false;
  @State queryMsg: string = '';
  @State queryContext: string = '';
  @State queryWarning: boolean = false;
  @State examColorEditing: boolean = false;
  @State examColorPreview: number = DEFAULT_EXAM_COLOR;
  @State savingExamColor: boolean = false;
  @State remoteColors: Map<string, number> = new Map<string, number>();
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

  async aboutToAppear(): Promise<void> {
    if (this.presentedAsSheet && !this.sheetLoadStarted) await this.onPageShow();
  }

  async onPageShow(): Promise<void> {
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
    this.sheetLoadStarted = false;
    this.pageGeneration++;
    this.deleteEffects.pause();
    this.finishDeleteSheetDismissal();
    this.queryGeneration++;
    this.querying = false;
    this.closeSheet();
  }

  aboutToDisappear(): void {
    this.onPageHide();
  }

  private async refreshSession(): Promise<void> {
    const generation: number = ++this.queryGeneration;
    this.session = undefined;
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
      this.hasSession = session !== undefined;
    } catch (_) {
      if (generation === this.queryGeneration) {
        this.hasSession = false;
      }
    }
  }

  private async loadExams(): Promise<void> {
    this.loading = true;
    this.loadError = false;
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
      events.sort((a: EasEventItem, b: EasEventItem): number => a.from - b.from);
      this.exams = events;
      const now: number = Date.now();
      this.upcoming = events.filter((event: EasEventItem): boolean => ExamSchedule.isUpcoming(event.to, now));
      this.past = events.filter((event: EasEventItem): boolean => !ExamSchedule.isUpcoming(event.to, now));
      this.remoteExams = this.filterImported(this.remoteExams, events);
    } catch (_) {
      this.loadError = true;
    } finally {
      this.loading = false;
    }
  }

  private filterImported(items: EasExamItem[], events: EasEventItem[]): EasExamItem[] {
    const kept: EasExamItem[] = [];
    for (let i = 0; i < items.length; i++) {
      let exists: boolean = false;
      for (let j = 0; j < events.length; j++) {
        if (ExamSchedule.sameAsEvent(items[i], events[j])) {
          exists = true;
          break;
        }
      }
      if (!exists) {
        kept.push(items[i]);
      }
    }
    return kept;
  }

  private async resolveTargetTimetable(): Promise<string> {
    const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
    await TimetableSelectionStore.getInstance().init(ctx);
    const rdb: RdbHelper = RdbHelper.getInstance();
    await rdb.init(ctx);
    let target: string = await TimetableSelectionStore.getInstance().load();
    if (target.length === 0 || await rdb.getTimetableById(target) === undefined) {
      target = '';
      const timetables: EasTimetable[] = await rdb.getTimetables();
      if (timetables.length > 0) {
        target = timetables[0].id;
      }
    }
    return target;
  }

  /** 考试事件挂到当前选中的课表；没有可用课表时引导先建课表。 */
  private async openAddExam(): Promise<void> {
    if (this.examSheetMode !== 0 || this.openingEditor || this.savingExamColor ||
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
    if (this.querying || this.openingEditor || this.pendingDeleteId.length > 0) {
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
      const items: EasExamItem[] = result.items;
      this.remoteExams = this.filterImported(items, this.exams);
      this.queryWarning = result.failedTypes.length > 0;
      const message: string = this.queryWarning ?
        result.failedTypes.join('、') + '查询失败，请重试' +
          (items.length === 0 ? '；尚不能确认是否有考试安排' : '') :
        (this.remoteExams.length > 0 ? '' :
          (items.length > 0 ? '教务考试已全部在本地课表中' : '本学期暂无教务考试安排'));
      this.queryMsg = message;
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

  private async importRemoteExam(item: EasExamItem): Promise<void> {
    if (this.openingEditor || this.pendingDeleteId.length > 0) {
      return;
    }
    this.openingEditor = true;
    try {
      const target: string = await this.resolveTargetTimetable();
      if (target.length === 0) {
        this.getUIContext().getPromptAction().showToast({ message: '请先在课表管理中新建课表' });
        return;
      }
      const event: EasEventItem | undefined = ExamSchedule.toEvent(item, target);
      if (event === undefined) {
        this.getUIContext().getPromptAction().showToast({ message: '考试时间无法识别，请手动添加' });
        return;
      }
      event.color = this.remoteExamColor(item);
      await RdbHelper.getInstance().saveEvent(event);
      this.closeSheet();
      await this.loadExams();
      this.getUIContext().getPromptAction().showToast({ message: '已导入到当前课表' });
    } catch (_) {
      this.getUIContext().getPromptAction().showToast({ message: '导入失败，请重试' });
    } finally {
      this.openingEditor = false;
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

  private static colorCss(color: number): string {
    return '#' + (timetableBlockColor(color) & 0xFFFFFF).toString(16).padStart(6, '0');
  }

  private static remoteKey(item: EasExamItem): string {
    return JSON.stringify([item.campusName, item.termName, item.courseName, item.examType,
      item.examDate, item.examTime, item.examLocation]);
  }

  private remoteExamColor(item: EasExamItem): number {
    return this.remoteColors.get(ExamPage.remoteKey(item)) ?? DEFAULT_EXAM_COLOR;
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

  private async saveRemoteExamColor(item: EasExamItem, color: number): Promise<void> {
    const colors: Map<string, number> = new Map<string, number>(this.remoteColors);
    colors.set(ExamPage.remoteKey(item), color);
    this.remoteColors = colors;
    this.examColorEditing = false;
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
        message: '确定删除「' + event.name + '」吗？仅删除这条考试安排，不影响其他课程。',
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
            .fontSize(13)
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
            .fontSize(14)
            .fontColor($r('app.color.hita_error'))
            .layoutWeight(1)
          Button('重试')
            .onClick(() => this.loadExams())
        }
        .padding(16)
        .width('100%')
        .margin({ top: HEADER_HEIGHT })
      } else if (!this.loadError && this.exams.length === 0 && this.remoteExams.length === 0) {
        Column() {
          Text(this.queryWarning ? '考试查询失败' : '暂无考试安排')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.hita_text_1a1a1a'))
            .width('100%')
            .textAlign(TextAlign.Center)
          Text(this.queryMsg.length > 0 ? this.queryMsg :
            (this.hasSession ? '可点右上角“查询”刷新，或手动添加考试' : '登录教务后可查询考试，也可手动添加'))
            .fontSize(13)
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
                .fontSize(12)
                .fontColor($r('app.color.hita_text_secondary_72809a'))
                .width('100%')
            }
          }
          if (this.queryWarning && this.queryMsg.length > 0) {
            ListItem() {
              Text(this.queryMsg)
                .fontSize(12)
                .fontColor(this.queryWarning ? $r('app.color.hita_error') :
                  $r('app.color.hita_text_secondary_72809a'))
                .width('100%')
            }
          }
          if (this.loadError) {
            ListItem() {
              Row() {
                Text('考试安排加载失败')
                  .fontSize(14)
                  .fontColor($r('app.color.hita_error'))
                  .layoutWeight(1)
                Button('重试')
                  .onClick(() => this.loadExams())
              }
              .width('100%')
            }
          }
          if (this.upcoming.length > 0) {
            ListItem() {
              Text('即将到来')
                .fontSize(13)
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
          }, (it: EasEventItem) => it.id + '|' + it.color.toString())
          ForEach(this.remoteExams, (remote: EasExamItem) => {
            ListItem() {
              this.remoteExamCard(remote)
            }
          }, (remote: EasExamItem) => ExamPage.remoteKey(remote) + '|' + this.remoteExamColor(remote).toString())
          if (this.past.length > 0) {
            ListItem() {
              Text('已结束')
                .fontSize(13)
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
          }, (it: EasEventItem) => it.id + '|' + it.color.toString())
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
          .fontSize(12)
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
          Text('考试查询')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.hita_text_1a1a1a'))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          this.headerAction('查询', this.pendingDeleteId.length === 0, () => {
              if (!this.preparingQuery) {
                this.queryEasExams();
              }
            })
          this.headerAction('添加',
            !this.openingEditor && this.pendingDeleteId.length === 0, () => {
              if (!this.preparingQuery && !this.querying) {
                this.openAddExam();
              }
            })
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
    .bindSheet(this.sheetVisible, this.examSheetContent(), {
      height: this.examSheetMode === 2 ? '78%' : SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: false,
      preferType: SheetType.BOTTOM,
      backgroundColor: $r('app.color.hita_surface_soft'),
      maskColor: $r('app.color.hita_sheet_mask'),
      onDisappear: () => {
        this.sheetVisible = false;
        this.resetSheetState();
        this.finishDeleteSheetDismissal();
      }
    })
    .attributeModifier(new CompatibleLightModifier(24, this.presentedAsSheet &&
      CompatibleSheetMaterial.isEnabled(), true))
  }

  @Builder
  private examCard(it: EasEventItem) {
    Row() {
      Row()
        .width(18)
        .height(54)
        .borderRadius(9)
        .backgroundColor(ExamPage.colorCss(ExamPage.examColor(it)))
      Column() {
        Row() {
          Text(it.name)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.hita_text_242a36'))
            .layoutWeight(1)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(ExamSchedule.remainingLabel(it.from, it.to, Date.now()))
            .fontSize(11)
            .fontColor($r('app.color.hita_error'))
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .backgroundColor($r('app.color.hita_error_surface_fdecec'))
            .borderRadius(10)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text(ExamPage.dateOf(it.from) + ' · ' + ExamPage.timeOf(it.from) + ' - ' +
          ExamPage.timeOf(it.to))
          .fontSize(13)
          .fontColor($r('app.color.hita_text_secondary_7b8498'))
          .width('100%')
          .margin({ top: 7 })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(it.place.length > 0 ? '地点：' + it.place : '地点：待定')
          .fontSize(13)
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
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor($r('app.color.hita_surface'))
    .borderRadius(16)
    .onClick(() => this.openExamDetail(it))
  }

  @Builder
  private remoteExamCard(remote: EasExamItem) {
    Row() {
      Row()
        .width(18)
        .height(54)
        .borderRadius(9)
        .backgroundColor(ExamPage.colorCss(this.remoteExamColor(remote)))
      Column() {
        Row() {
          Text(remote.courseName)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.hita_text_242a36'))
            .layoutWeight(1)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('教务')
            .fontSize(11)
            .fontColor($r('app.color.hita_primary_3390ec'))
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .backgroundColor($r('app.color.hita_selected_ebf4fc'))
            .borderRadius(10)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text((remote.examDate.length > 0 ? remote.examDate : '日期待定') +
          (remote.examTime.length > 0 ? ' · ' + remote.examTime : ''))
          .fontSize(13)
          .fontColor($r('app.color.hita_text_secondary_7b8498'))
          .width('100%')
          .margin({ top: 7 })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(remote.examLocation.length > 0 ? '地点：' + remote.examLocation : '地点：待定')
          .fontSize(13)
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
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor($r('app.color.hita_surface'))
    .borderRadius(16)
    .onClick(() => this.openRemoteDetail(remote))
  }

  @Builder
  private examSheetContent() {
    SheetContent({ fillHeight: this.examSheetMode === 2 }) {
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
            .fontSize(21)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.hita_text_202b45'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('考试详情')
            .fontSize(13)
            .fontColor($r('app.color.hita_text_secondary_72809a'))
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ left: DETAIL_TEXT_GAP })
        this.examColorButton(ExamPage.examColor(event))
        if (!this.examColorEditing) {
          Text('编辑')
            .fontSize(14)
            .fontColor($r('app.color.hita_primary_3390ec'))
            .fontWeight(FontWeight.Medium)
            .padding({ left: 8, right: 8, top: 8, bottom: 8 })
            .flexShrink(0)
            .enabled(this.pendingDeleteId.length === 0)
            .onClick(() => this.openEditExam(event))
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ bottom: 14 })

      if (this.examColorEditing) {
        CourseColorEditor({
          initialColor: ExamPage.examColor(event),
          examMode: true,
          onPreview: (color: number) => { this.examColorPreview = color; },
          onSave: async (color: number) => { await this.saveExamColor(event, color); },
          onCancel: () => { this.examColorEditing = false; }
        })
      } else {
        this.examDetailRow($r('sys.symbol.person_crop_circle_fill'), '老师',
          event.teacher.trim().length > 0 ? event.teacher : '未填写')
        this.examDetailRow($r('sys.symbol.pin'), '考场',
          event.place.trim().length > 0 ? event.place : '待定')
        this.examDetailRow($r('sys.symbol.clock'), '时间',
          ExamPage.timeOf(event.from) + ' - ' + ExamPage.timeOf(event.to))
        this.examDetailRow($r('sys.symbol.calendar'), '日期',
          ExamPage.dateOf(event.from) + ' · ' + DOW_FULL[EasTimeTools.getDow(event.from)])
        this.examDetailRow($r('sys.symbol.checkmark'), '状态',
          ExamSchedule.remainingLabel(event.from, event.to, Date.now()))

        Row() {
          Blank()
          Text('删除考试')
            .fontSize(14)
            .fontColor($r('app.color.hita_error'))
            .fontWeight(FontWeight.Medium)
            .padding({ left: 14, right: 14, top: 9, bottom: 9 })
            .backgroundColor($r('app.color.hita_error_surface_fdecec'))
            .borderRadius(18)
            .enabled(this.pendingDeleteId.length === 0)
            .onClick(() => this.confirmDeleteExam(event))
        }
        .width('100%')
        .margin({ top: 6 })
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 0, bottom: 20 })
  }

  @Builder
  private remoteDetailSheet(item: EasExamItem) {
    Column() {
      Row() {
        Circle()
          .width(DETAIL_ICON_SIZE)
          .height(DETAIL_ICON_SIZE)
          .flexShrink(0)
          .attributeModifier(new CirclePaintModifier(ExamPage.colorCss(
            this.examColorEditing ? this.examColorPreview : this.remoteExamColor(item))))
        Column() {
          Text(item.courseName)
            .fontSize(21)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.hita_text_202b45'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('考试详情')
            .fontSize(13)
            .fontColor($r('app.color.hita_text_secondary_72809a'))
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ left: DETAIL_TEXT_GAP })
        this.examColorButton(this.remoteExamColor(item))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ bottom: 14 })

      if (this.examColorEditing) {
        CourseColorEditor({
          initialColor: this.remoteExamColor(item),
          examMode: true,
          onPreview: (color: number) => { this.examColorPreview = color; },
          onSave: async (color: number) => { await this.saveRemoteExamColor(item, color); },
          onCancel: () => { this.examColorEditing = false; }
        })
      } else {
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

        ImmersiveHeader({ barHeight: 46 }) {
          Row() {
            Blank()
            Button('导入到课表', { type: ButtonType.Capsule })
              .fontSize(14)
              .fontColor(CompatibleMaterialModifier.foreground('#FFFFFF'))
              .fontWeight(FontWeight.Medium)
              .height(36)
              .padding({ left: 14, right: 14 })
              .backgroundColor($r('app.color.hita_primary_fill'))
              .borderRadius(18)
              .attributeModifier(new CompatibleMaterialModifier($r('app.color.hita_primary_fill')))
              .enabled(!this.openingEditor)
              .onClick(() => this.importRemoteExam(item))
          }
          .width('100%')
          .height(46)
          .padding({ top: 6 })
        }
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 0, bottom: 20 })
  }

  @Builder
  private examColorButton(color: number) {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph($r('sys.symbol.paintpalette'))
        .fontSize(22)
        .fontColor([$r('app.color.hita_primary_3390ec')])
    }
    .width(44)
    .height(44)
    .padding(0)
    .margin({ left: 8 })
    .flexShrink(0)
    .backgroundColor($r('app.color.hita_selected_e4f0ff'))
    .accessibilityText('修改考试颜色')
    .enabled(!this.savingExamColor && !this.openingEditor && this.pendingDeleteId.length === 0)
    .onClick(() => this.toggleExamColor(color))
  }

  @Builder
  private examDetailRow(symbol: Resource, label: string, value: string) {
    Row() {
      Stack() {
        SymbolGlyph(symbol)
          .fontSize(20)
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
          .fontSize(12)
          .fontColor($r('app.color.hita_text_secondary_72809a'))
        Text(value)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.hita_text_202b45'))
          .margin({ top: 2 })
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

  @Builder
  private headerAction(label: string, enabled: boolean, onAction: () => void) {
    Text(label)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor(CompatibleMaterialModifier.foreground($r('app.color.hita_primary_3390ec')))
      .height(32)
      .padding({ left: 12, right: 12 })
      .borderRadius(16)
      .backgroundColor($r('app.color.hita_selected_ebf4fc'))
      .textAlign(TextAlign.Center)
      .attributeModifier(new CompatibleMaterialModifier($r('app.color.hita_selected_ebf4fc')))
      .margin({ left: 8 })
      .flexShrink(0)
      .enabled(enabled)
      .onClick(() => {
        onAction();
      })
  }

  navigateBack(): void {
    if (this.presentedAsSheet) {
      this.onClose();
    } else {
      this.getUIContext().getRouter().back();
    }
  }
}
