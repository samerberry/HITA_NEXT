/**
 * HITA NEXT main shell.
 *
 * The Android client uses a compact toolbar and a floating pill navigation bar.
 * This page keeps the same information hierarchy while reusing the HarmonyOS
 * timetable/session data layer already used by the app.
 */
import { common } from '@kit.AbilityKit';
import { formProvider } from '@kit.FormKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { CommonModifier, FrameCallback, KeyboardAvoidMode, SymbolGlyphModifier } from '@kit.ArkUI';
import { HeaderBackButton } from '../common/components/HeaderBackButton';
import { ImmersiveHeader } from '../common/components/ImmersiveHeader';
import { ImmersiveEventCard } from '../common/components/ImmersiveEventCard';
import { HeaderFadeMask } from '../common/components/HeaderFadeMask';
import { HeaderFade } from '../common/theme/HeaderFade';
import { TimetableTheme } from '../common/theme/TimetableTheme';
import { TimetableBackdropColors, TimetableBackdropPixels } from '../common/theme/TimetableBackdrop';
import { AppearanceMode, AppearanceStore } from '../common/theme/AppearanceStore';
import { NAV_BAR_INSET_FALLBACK, STATUS_BAR_INSET_FALLBACK } from '../common/theme/StatusBarInset';
import { CompatibleDockModifier } from '../common/theme/CompatibleDockModifier';
import { CompatibleMaterialModifier } from '../common/theme/CompatibleMaterialModifier';
import { CompatibleSheetMaterial } from '../common/theme/CompatibleSheetMaterial';
import { CompatibleLightModifier } from '../common/theme/CompatibleLightModifier';
import { CirclePaintModifier } from '../common/theme/CirclePaintModifier';
import { FrostedDock } from '../common/components/FrostedDock';
import { DockLightOverlay } from '../common/components/DockLightOverlay';
import { DockLightController } from '../common/util/DockLightEffect';
import { DOCK_HOLD_DELAY_MS, DockNavigationGuard } from '../common/util/DockNavigationGuard';
import { DeleteEffectController } from '../common/util/DeleteEffectController';
import { CourseColorEditor } from '../feature/timetable/views/CourseColorEditor';
import { CourseControlHost } from '../feature/timetable/views/CourseControlHost';
import { TimetableFloatingActions } from '../feature/timetable/views/TimetableFloatingActions';
import { TimetableCardMaterials } from '../feature/timetable/views/TimetableCardMaterials';
import { TimetableCardPainter } from '../feature/timetable/views/TimetableCardPainter';
import { RdbHelper } from '../common/db/RdbHelper';
import { EasEventItem, EasEventType, EasTermSubject, EasTimetable } from '../common/model/timetable/TimetableModels';
import { CurrentClassSelection } from '../common/model/timetable/CurrentClassSelection';
import { DOW_FULL, EasTimeTools } from '../common/util/EasTimeTools';
import { EasCampus, EasSession } from '../feature/eas/EasSession';
import { EasSessionStore, EAS_SESSION_REVISION_KEY } from '../feature/eas/EasSessionStore';
import { attachEasSilentRenewal } from '../feature/eas/webLogin/EasSilentLoginWeb';
import { SheetContent } from '../common/components/SheetContent';
import { EasApiClient } from '../feature/eas/EasApiClient';
import { EasDataProvider } from '../feature/eas/EasDataProvider';
import { EasSessionStatus } from '../feature/eas/EasSessionStatus';
import { EasImportResult, EasTimetableImporter, EasTimetableUpdate } from '../feature/eas/EasTimetableImporter';
import { TimetableUpdateDialog } from '../feature/timetable/views/TimetableUpdateDialog';
import { EasUserMessages } from '../feature/eas/EasUserMessages';
import { EasLoginPage } from '../feature/eas/webLogin/EasLoginPage';
import { TimetableResolver } from '../feature/timetable/data/TimetableResolver';
import { TimetableSelectionStore } from '../feature/timetable/data/TimetableSelectionStore';
import { hasEveningCourse, eveningHintVisible } from '../feature/timetable/data/EveningCourseHint';
import { TimetableVideoBackground } from '../feature/timetable/views/TimetableVideoBackground';
import { TimetableBackgroundStore } from '../feature/timetable/data/TimetableBackgroundStore';
import { WidgetBackgroundStore } from '../feature/widget/WidgetBackgroundStore';
import { NextClassWidgetService } from '../feature/widget/NextClassWidgetService';
import { WidgetBackgroundPage } from '../feature/widget/WidgetBackgroundPage';
import { ImportTimetablePanel } from './ImportTimetablePanel';
import { ExamPage } from './ExamPage';
import { ScorePage } from './ScorePage';
import { CreditPage } from './CreditPage';
import { EmptyClassroomPage } from './EmptyClassroomPage';
import { TimetableWallpaperSampler } from '../feature/timetable/data/TimetableWallpaperSampler';
import { TimetableDisplayOptions } from '../feature/timetable/data/TimetableDisplayOptions';
import { TimetableDisplayStore } from '../feature/timetable/data/TimetableDisplayStore';
import { TimetableDisplaySettings } from '../feature/timetable/views/TimetableDisplaySettings';
import { ClassReminderStore } from '../feature/timetable/data/ClassReminderStore';
import { ClassReminderScheduler, ClassReminderSyncResult } from '../feature/timetable/data/ClassReminderScheduler';
import { IcsImportResult, TimetableIcsImporter } from '../feature/timetable/data/TimetableIcsImporter';
import { CalendarExportResult, TimetableCalendarExporter } from '../feature/timetable/data/TimetableCalendarExporter';
import {
  AXIS_END_HOUR,
  AXIS_START_HOUR,
  TIMETABLE_GRID_TOP_PADDING,
  TIMETABLE_GUTTER_WIDTH,
  TIMETABLE_HEADER_HEIGHT,
  TIMETABLE_HOUR_HEIGHT,
  TimetableCardLayer,
  TimetableCardSurface,
  TimetablePlaceLabel,
  DOW_NAMES,
  drawTimetableWeek,
  eventsOfWeek,
  timetableBlockColor,
  timetableEventSpan
} from '../feature/timetable/views/TimetableWeekDraw';

const DAY_MS: number = 24 * 60 * 60 * 1000;
/** 打开应用或回到前台时，距上次检查同一张课表至少间隔这么久；重启应用后仍然有效。 */
const TIMETABLE_UPDATE_INTERVAL_MS: number = 60 * 60 * 1000;
const COLOR_PRIMARY: Resource = $r('app.color.hita_primary');
const COLOR_SURFACE: ResourceColor = $r('app.color.hita_page');
const COLOR_CARD: ResourceColor = $r('app.color.hita_surface');
const COLOR_TEXT_PRIMARY: ResourceColor = $r('app.color.hita_text');
const COLOR_TEXT_SECONDARY: ResourceColor = $r('app.color.hita_text_secondary');
const COLOR_TEXT_HINT: ResourceColor = $r('app.color.hita_text_secondary_5a6880');
const COLOR_NAV_ACTIVE: ResourceColor = $r('app.color.hita_selected');
const COLOR_CLASS: ResourceColor = $r('app.color.hita_primary');
const COLOR_EXAM: ResourceColor = $r('app.color.hita_error_8a2e42');
const COLOR_OTHER: ResourceColor = $r('app.color.hita_link');
const COLOR_TAG: ResourceColor = $r('app.color.hita_success_0f6e56');
const TIMETABLE_BOTTOM_SAFE_EXTENSION: number = 56;
const TAB_TODAY: number = 0;
const TAB_TIMETABLE: number = 1;
const NAV_TAB_COUNT: number = 3;
const MORE_HEADER_HEIGHT: number = 56;
const TIMETABLE_CHROME_FALLBACK: number = 200;
const COLOR_SURFACE_RGB: string = '244,247,252';
// 周切换：位移超过页宽的该比例即翻周；位移较短时抬手速度够快（vp/s）同样翻周。
const TIMETABLE_SWIPE_RATIO: number = 0.08;
const TIMETABLE_FLING_VELOCITY: number = 400;
const TIMETABLE_FLING_MIN_OFFSET: number = 12;
const TAB_SWIPE_MS: number = 300;
const TIMETABLE_SLIDE_MS: number = 220;
const COURSE_DETAIL_ICON_SIZE: number = 38;
const COURSE_DETAIL_TEXT_GAP: number = 12;

interface MoreShortcutOptions {
  symbol: Resource;
  title: string;
  subtitle: string;
  action: () => void;
}

@Extend(Column)
function tabPage(bottomInset: number, background: ResourceColor) {
  .width('100%')
  .height('100%')
  .padding({ bottom: bottomInset })
  .backgroundColor(background)
  .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.KEYBOARD], [SafeAreaEdge.BOTTOM])
}

class TimetableMarqueeCallback extends FrameCallback {
  private callback: (timeMs: number) => void;

  constructor(callback: (timeMs: number) => void) {
    super();
    this.callback = callback;
  }

  onFrame(frameTimeInNano: number): void {
    this.callback(frameTimeInNano / 1000000);
  }
}

@Entry
@Component
struct Home {
  @StorageProp('hita_appearance_mode') appearanceMode: AppearanceMode = AppearanceMode.SYSTEM;
  @StorageProp('hita_appearance_dark') @Watch('onAppearanceChanged') darkMode: boolean = false;
  @State appearanceBusy: boolean = false;
  @State appearanceExpanded: boolean = false;
  @State widgetMenuExpanded: boolean = false;
  @State widgetBackgroundSet: boolean = false;
  @State widgetBackgroundSheetOpen: boolean = false;
  @State importTimetableSheetOpen: boolean = false;
  @State academicPanelOpen: boolean = false;
  @State academicPanelKind: number = 0;
  @State widgetBackgroundDirty: boolean = false;
  @State widgetBackgroundBusy: boolean = false;
  private widgetBackgroundConfirmDismiss: ((dismiss: () => void, springBack: () => void) => void) | undefined =
    undefined;
  private widgetBackgroundSpringBack: (() => void) | undefined = undefined;
  @State todayItems: EasEventItem[] = [];
  @State timelineText: string = '暂无今日日程';
  @State @Watch('updateTimetableSystemBars') currentTab: number = 0;
  @State hasTimetable: boolean = false;
  @State timetableCount: number = 0;
  @State calendarExporting: boolean = false;
  @State calendarExportSheetOpen: boolean = false;
  @State calendarExportTimetable: EasTimetable | undefined = undefined;
  @State currentTimetable: EasTimetable | undefined = undefined;
  @State recentTimetable: EasTimetable | undefined = undefined;
  @State importing: boolean = false;
  @State importMessage: string = '';
  @State importError: string = '';
  @State activeClass: EasEventItem | undefined = undefined;
  @State nextClass: EasEventItem | undefined = undefined;
  @State nowTick: number = Date.now();
  @State sessionInfo: EasSession | undefined = undefined;
  @StorageProp(EAS_SESSION_REVISION_KEY) @Watch('onSessionRevisionChanged') sessionRevision: number = 0;
  @State @Watch('updateTimetableSystemBars') activeSheetVisible: boolean = false;
  @State sessionSheetOpen: boolean = false;
  @State sessionSheetCampus: string = 'WEIHAI';
  @State sessionSheetInfo: EasSession | undefined = undefined;
  @State sessionSheetStatus: EasSessionStatus = EasSessionStatus.UNKNOWN;
  private sheetRequestGeneration: number = 0;
  private sessionSheetLoading: boolean = false;
  @State loginSheetOpen: boolean = false;
  @State loginCampusCode: string = 'WEIHAI';
  @State courseSheetOpen: boolean = false;
  @State courseColorEditing: boolean = false;
  @State courseColorPreview: number = 0;
  @State selectedCourse: EasEventItem | undefined = undefined;
  @State skippingCourse: boolean = false;
  private courseSkipAnimating: boolean = false;
  private courseDeleteEffects: DeleteEffectController = new DeleteEffectController();
  private courseSheetDismissed: (() => void) | undefined = undefined;
  private courseSheetDismissTimer: number = -1;
  private summaryRequestGeneration: number = 0;
  @State classReminderEnabled: boolean = false;
  @State reminderBusy: boolean = false;
  @State reminderExpanded: boolean = false;
  @State reminderMaterialHeight: number = 152;
  @State reminderLeadMinutes: number = 15;
  @State timetableEvents: EasEventItem[] = [];
  @State timetableWeek: number = 1;
  // Week paging follows the Android timetable: drag the page with the finger,
  // then slide it out/in around the week data swap.
  @State timetableDragOffset: number = 0;
  @State timetableAnimationDuration: number = 0;
  @State timetableAnimating: boolean = false;
  private importRequested: boolean = false;
  private timetableUpdateChecking: boolean = false;
  private timetableUpdatePrompting: boolean = false;
  private pendingTimetableUpdate: EasTimetableUpdate | undefined = undefined;
  private timetableUpdateDialog: CustomDialogController | undefined = undefined;
  private clockTimer: number = -1;
  private lastReminderDispatchAt: number = 0;
  @State @Watch('updateTimetableSystemBars') private pageVisible: boolean = false;
  @State private tabTransitionRunning: boolean = false;
  private timetablePlaceLabels: TimetablePlaceLabel[] = [];
  private timetableMarqueeCallback: TimetableMarqueeCallback | undefined = undefined;
  private timetableMarqueeGeneration: number = 0;
  private timetableMarqueeElapsedMs: number = 0;
  private timetableMarqueeLastFrameMs: number = -1;
  private timetableAnimationTimer: number = -1;
  private dayKey: string = EasTimeTools.printDate(Date.now());
  private timetableCanvas: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private timetableCardPainter: TimetableCardPainter = new TimetableCardPainter();
  @State private timetableCardSurfaces: TimetableCardSurface[] = [];
  // @State: the fixed today column and header fade are laid out from these.
  @State private timetableAreaW: number = 0;
  @State private timetableAreaH: number = 0;
  @State private timetableCanvasHeight: number = 0;
  @State private showEveningCourseHint: boolean = false;
  @State timetableFadeOpacity: number = 0;
  @State private timetableScrollY: number = 0;
  @State moreHeaderMaskOpacity: number = 0;
  @State selectedNav: number = TAB_TODAY;
  @State timetableBgUri: string = '';
  @State timetableVideoUri: string = '';
  @State timetableVideoFailed: boolean = false;
  @StorageProp('hita_app_foreground') appForeground: boolean = false;
  private timetableBackgroundBusy: boolean = false;
  @State timetableTextColor: string = TimetableTheme.AUTO_TEXT;
  @State @Watch('updateTimetableSystemBars') private timetableBackdrop: TimetableBackdropColors = new TimetableBackdropColors(false);
  private timetableWallpaperPixels: TimetableBackdropPixels | undefined = undefined;
  private timetableWallpaperGeneration: number = 0;
  private timetableBackdropKey: string = '';
  private timetableViewportW: number = 360;
  private timetableViewportH: number = 800;
  @State timetableDisplayOpen: boolean = false;
  @State timetableDisplay: TimetableDisplayOptions = new TimetableDisplayOptions();
  @State timetableMaskDepth: number = 0;
  @State timetableChromeH: number = TIMETABLE_CHROME_FALLBACK;
  @StorageProp('hita_status_bar_vp') statusBarInset: number = STATUS_BAR_INSET_FALLBACK;
  @StorageProp('hita_nav_bar_vp') navBarInset: number = NAV_BAR_INSET_FALLBACK;
  private tabsController: TabsController = new TabsController();
  private timetableDateBottom: number = TIMETABLE_CHROME_FALLBACK;
  private weekGestureActive: boolean = false;
  private dockNavigation: DockNavigationGuard = new DockNavigationGuard();
  @State private dockHolding: boolean = false;
  private dockHoldTimer: number = -1;
  private dockPressSource: number = TAB_TODAY;
  private dockLightPosition: number = 106;
  private dockLight: DockLightController = new DockLightController();
  private dockBarModifier: CommonModifier = new CommonModifier()
    .onTouchIntercept((event: TouchEvent) => {
      this.dockNavigation.begin(event, true);
      return HitTestMode.Default;
    })
    .onTouch((event: TouchEvent) => {
      this.observeDockTouch(event, true);
    })
    .onGestureRecognizerJudgeBegin((event: BaseGestureEvent, current: GestureRecognizer) => {
      return this.judgePagePan(current, true);
    }, true);
  private moreScroller: Scroller = new Scroller();
  private timetableScroller: Scroller = new Scroller();

  async aboutToAppear(): Promise<void> {
    this.pageVisible = true;
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.NONE);
    const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
    await EasSessionStore.getInstance().init(ctx);
    attachEasSilentRenewal(this.getUIContext());
    await TimetableSelectionStore.getInstance().init(ctx);
    await ClassReminderStore.getInstance().init(ctx);
    this.classReminderEnabled = await ClassReminderStore.getInstance().loadEnabled();
    this.reminderLeadMinutes = await ClassReminderStore.getInstance().loadLeadMinutes();
    const background = TimetableBackgroundStore.load(ctx);
    const bgPath: string = background.imagePath;
    this.timetableVideoUri = background.videoPath ? 'file://' + background.videoPath : '';
    this.timetableBgUri = bgPath.length > 0 ? TimetableBackgroundStore.toDisplayUri(bgPath) : '';
    this.timetableTextColor = await TimetableSelectionStore.getInstance()
      .loadTextColor(TimetableTheme.AUTO_TEXT);
    try {
      await TimetableDisplayStore.getInstance().init(ctx);
      this.timetableDisplay = await TimetableDisplayStore.getInstance().load();
      this.timetableMaskDepth = this.timetableDisplay.wallpaperMask;
    } catch (_) {
      // Keep the existing appearance if preferences are temporarily unavailable.
    }
    this.drawTimetableNow();
    this.loadTimetableWallpaperColors(bgPath);
    const params: Object | undefined = this.getUIContext().getRouter().getParams();
    if (params !== undefined && params !== null) {
      const record: Record<string, string> = params as Record<string, string>;
      // ScorePage 等页面的“去登录”直达会话弹层（原开发入口页已移除）。
      if (record['openSession'] === '1') {
        this.openSessionSheet();
      }
    }
    await this.refreshSummaries();
    this.startClock();
    this.checkTimetableUpdate();
  }

  async onPageShow(): Promise<void> {
    this.pageVisible = true;
    this.courseDeleteEffects.resume();
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.NONE);
    this.startClock();
    this.widgetBackgroundSet = WidgetBackgroundStore.hasBackground(
      this.getUIContext().getHostContext() as common.Context);
    const preserveWeek: boolean = this.returningFromCourseEditor;
    this.returningFromCourseEditor = false;
    await this.refreshSummaries(preserveWeek);
    this.checkTimetableUpdate();
  }

  onPageHide(): void {
    this.pageVisible = false;
    this.stopClock();
    this.resetDockInteraction();
    this.closeActiveSheet();
    this.courseDeleteEffects.pause();
    this.finishCourseSheetDismissal();
    this.tabTransitionRunning = false;
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.OFFSET);
    this.stopTimetableMarquee();
  }

  private async onSessionRevisionChanged(): Promise<void> {
    const revision = this.sessionRevision;
    const store = EasSessionStore.getInstance();
    const session = await store.loadPreferred();
    if (revision !== this.sessionRevision) return;
    this.sessionInfo = session;
    if (this.sessionSheetOpen) {
      const campus = this.sessionSheetCampus;
      const selected = await store.load(Home.campusFromCode(campus));
      if (revision !== this.sessionRevision || !this.sessionSheetOpen || campus !== this.sessionSheetCampus) return;
      this.sessionSheetInfo = selected;
      this.sessionSheetStatus = selected?.loginExpired ? EasSessionStatus.EXPIRED : EasSessionStatus.SAVED;
    }
  }

  private onAppearanceChanged(): void {
    this.drawTimetableNow();
  }

  private timetableInk(region: string = 'title'): string {
    const adaptive = region === 'time' ? this.timetableBackdrop.timeText :
      (region === 'date' ? this.timetableBackdrop.dateText : this.timetableBackdrop.titleText);
    return TimetableTheme.resolveText(this.timetableTextColor, this.darkMode,
      this.hasTimetableBackground(), adaptive);
  }

  private refreshTimetableBackdrop(): void {
    const today = EasTimetable.dowOfMs(this.nowTick);
    const key = [this.timetableBgUri, this.darkMode, this.timetableMaskDepth, this.timetableViewportW,
      this.timetableViewportH, this.timetableChromeH, today, this.statusBarInset, this.navBarInset].join('|');
    if (key === this.timetableBackdropKey) return;
    this.timetableBackdropKey = key;
    this.timetableBackdrop = this.hasTimetableBackground() && this.timetableWallpaperPixels !== undefined ?
      this.timetableWallpaperPixels.colors(this.darkMode, this.timetableMaskDepth, this.timetableViewportW,
        this.timetableViewportH, this.timetableChromeH, TIMETABLE_HEADER_HEIGHT, today,
        this.statusBarInset, this.navBarInset) :
      new TimetableBackdropColors(this.darkMode);
  }

  private updateTimetableSystemBars(): void {
    const visible = this.pageVisible && this.currentTab === TAB_TIMETABLE && this.hasTimetableBackground();
    AppearanceStore.getInstance().setPageBarColors(visible ? this.timetableBackdrop.statusText : '',
      visible && !this.activeSheetVisible ? this.timetableBackdrop.navigationText : '');
  }

  private async loadTimetableWallpaperColors(path: string): Promise<void> {
    const generation = ++this.timetableWallpaperGeneration;
    this.timetableWallpaperPixels = undefined;
    this.timetableBackdropKey = '';
    this.drawTimetableNow();
    const pixels = await TimetableWallpaperSampler.read(path);
    if (generation !== this.timetableWallpaperGeneration) return;
    this.timetableWallpaperPixels = pixels;
    this.timetableBackdropKey = '';
    this.drawTimetableNow();
  }

  private async selectAppearance(mode: AppearanceMode): Promise<void> {
    if (this.appearanceBusy || this.appearanceMode === mode) {
      return;
    }
    this.appearanceBusy = true;
    try {
      await AppearanceStore.getInstance().select(mode);
    } catch (_) {
      this.getUIContext().getPromptAction().showToast({ message: '外观设置未保存，请重试' });
    } finally {
      this.appearanceBusy = false;
    }
  }

  aboutToDisappear(): void {
    this.pageVisible = false;
    this.timetableWallpaperGeneration++;
    this.resetDockInteraction();
    this.closeActiveSheet();
    this.courseDeleteEffects.pause();
    this.finishCourseSheetDismissal();
    this.stopTimetableMarquee();
    this.stopClock();
    if (this.timetableAnimationTimer >= 0) {
      clearTimeout(this.timetableAnimationTimer);
      this.timetableAnimationTimer = -1;
    }
  }

  private startClock(): void {
    if (this.clockTimer < 0) {
      this.clockTimer = setInterval(() => {
        const now: number = Date.now();
        this.nowTick = now;
        this.updateTodayHighlights();
        const nextDayKey: string = EasTimeTools.printDate(this.nowTick);
        if (nextDayKey !== this.dayKey) {
          this.dayKey = nextDayKey;
          this.refreshSummaries();
        }
        if (this.classReminderEnabled && now - this.lastReminderDispatchAt >= 15000) {
          this.lastReminderDispatchAt = now;
          const host: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
          void ClassReminderScheduler.dispatchDue(host, this.timetableEvents);
        }
      }, 1000);
    }
  }

  private stopClock(): void {
    if (this.clockTimer >= 0) {
      clearInterval(this.clockTimer);
      this.clockTimer = -1;
    }
  }

  private stopTimetableMarquee(): void {
    // Queued frame callbacks cannot be cancelled; invalidate their generation.
    this.timetableMarqueeGeneration++;
    this.timetableMarqueeCallback = undefined;
    this.timetableMarqueeLastFrameMs = -1;
  }

  private startTimetableMarquee(): void {
    if (this.timetableMarqueeCallback !== undefined || !this.pageVisible || this.tabTransitionRunning ||
      this.currentTab !== 1 || this.timetablePlaceLabels.length === 0) {
      return;
    }
    const generation: number = this.timetableMarqueeGeneration;
    const callback: TimetableMarqueeCallback = new TimetableMarqueeCallback((timeMs: number) => {
      if (generation !== this.timetableMarqueeGeneration || !this.pageVisible ||
        this.tabTransitionRunning || this.currentTab !== 1) {
        return;
      }
      if (this.timetableMarqueeLastFrameMs >= 0) {
        this.timetableMarqueeElapsedMs += Math.max(0, timeMs - this.timetableMarqueeLastFrameMs);
      }
      this.timetableMarqueeLastFrameMs = timeMs;
      const nextDelay: number = this.drawTimetablePlaceFrame();
      if (nextDelay < 0) {
        this.stopTimetableMarquee();
      } else if (nextDelay > 0) {
        this.getUIContext().postDelayedFrameCallback(callback, Math.ceil(nextDelay));
      } else {
        this.getUIContext().postFrameCallback(callback);
      }
    });
    this.timetableMarqueeCallback = callback;
    this.getUIContext().postFrameCallback(callback);
  }

  private drawTimetablePlaceFrame(): number {
    return this.timetableCardPainter.drawPlaces(this.timetablePlaceLabels, this.timetableMarqueeElapsedMs);
  }

  async refreshSummaries(preserveWeek: boolean = false): Promise<void> {
    if (this.skippingCourse) {
      return;
    }
    const generation: number = ++this.summaryRequestGeneration;
    const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
    const rdb: RdbHelper = RdbHelper.getInstance();
    await rdb.init(ctx);

    const found: EasSession | undefined = await EasSessionStore.getInstance().loadPreferred();

    const allTimetables: EasTimetable[] = await rdb.getTimetables();
    const recent: EasTimetable | undefined = await TimetableResolver.getRecent(rdb, this.nowTick);
    const selectedId: string = await TimetableSelectionStore.getInstance().load();
    let selected: EasTimetable | undefined = undefined;
    if (selectedId.length > 0) {
      selected = await rdb.getTimetableById(selectedId);
      if (selected === undefined) {
        await TimetableSelectionStore.getInstance().clearIf(selectedId);
      }
    }
    const real: EasTimetable | undefined = await TimetableResolver.getReal(rdb);
    if (generation !== this.summaryRequestGeneration || this.skippingCourse) {
      return;
    }
    if (found !== undefined && !found.loginExpired && real === undefined && selected === undefined &&
      !this.importing && !this.importRequested) {
      await this.importTimetable(false);
      return;
    }

    const display: EasTimetable | undefined = selected !== undefined ? selected :
      (real !== undefined ? real : await TimetableResolver.getForDisplay(rdb));
    const now0: number = new Date(new Date().setHours(0, 0, 0, 0)).getTime();
    let allEvents: EasEventItem[] = [];
    if (display !== undefined) {
      allEvents = await rdb.getEventsOfTimetable(display.id);
      const subjects: EasTermSubject[] = await rdb.getSubjectsOfTimetable(display.id);
      const colorById: Map<string, number> = new Map<string, number>();
      for (let i: number = 0; i < subjects.length; i++) {
        colorById.set(subjects[i].id, subjects[i].color);
      }
      for (let i: number = 0; i < allEvents.length; i++) {
        const color: number | undefined = colorById.get(allEvents[i].subjectId);
        if (allEvents[i].type === EasEventType.EXAM) {
          allEvents[i].color = allEvents[i].color === 0 ?
            Home.defaultCanvasColor(allEvents[i].type) : allEvents[i].color;
        } else {
          allEvents[i].color = color === undefined ? Home.defaultCanvasColor(allEvents[i].type) : color;
        }
      }
    }
    if (generation !== this.summaryRequestGeneration || this.skippingCourse) {
      return;
    }
    const keepWeek: boolean = preserveWeek && this.currentTimetable?.id === display?.id;
    const latestSession = await EasSessionStore.getInstance().loadPreferred();
    if (generation !== this.summaryRequestGeneration || this.skippingCourse) return;
    this.sessionInfo = latestSession;
    this.timetableCount = allTimetables.length;
    this.recentTimetable = recent;
    this.hasTimetable = display !== undefined;
    this.currentTimetable = display;
    this.timetableEvents = allEvents;
    if (!keepWeek) {
      const currentWeek: number = display?.getWeekNumber(this.nowTick) ?? 1;
      this.timetableWeek = currentWeek > 0 ? currentWeek : 1;
    }
    const today: EasEventItem[] = allEvents.filter((event: EasEventItem): boolean =>
      event.from >= now0 && event.from < now0 + DAY_MS);
    today.sort((a: EasEventItem, b: EasEventItem): number => a.from - b.from);
    this.todayItems = today;
    this.nowTick = Date.now();
    this.updateTodayHighlights();
    this.timelineText = today.length === 0 ? (display === undefined ? '暂无课表' : '今日暂无安排') :
      '今日 ' + today.length.toString() + ' 项安排';
    this.drawTimetableNow();
    NextClassWidgetService.scheduleRefresh();
    if (this.classReminderEnabled) {
      const host: common.UIAbilityContext = ctx as common.UIAbilityContext;
      await ClassReminderScheduler.sync(host, allEvents);
    }
  }

  private classReminderSubtitle(): string {
    if (!this.classReminderEnabled) {
      return '已关闭';
    }
    return '上课前 ' + this.reminderLeadMinutes.toString() + ' 分钟提醒';
  }

  private showReminderTimePicker(): void {
    if (this.reminderBusy) return;
    const options: string[] = [];
    for (let minutes: number = 1; minutes <= 120; minutes++) {
      options.push('上课前 ' + minutes.toString() + ' 分钟');
    }
    this.getUIContext().showTextPickerDialog({
      range: options,
      selected: this.reminderLeadMinutes - 1,
      canLoop: false,
      onAccept: (result: TextPickerResult) => {
        const index: number = Number(result.index);
        void this.saveReminderTime(index + 1);
      }
    });
  }

  private async saveReminderTime(minutes: number): Promise<void> {
    if (this.reminderBusy || !ClassReminderStore.validLeadMinutes(minutes)) return;
    this.reminderBusy = true;
    try {
      await ClassReminderStore.getInstance().saveLeadMinutes(minutes);
      this.reminderLeadMinutes = minutes;
      if (this.classReminderEnabled) {
        const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
        // Preserve notification history when changing the lead time: don't alert twice for one class.
        await ClassReminderScheduler.sync(ctx, this.timetableEvents);
      }
      this.getUIContext().getPromptAction().showToast({ message: '已设置为上课前 ' + minutes.toString() + ' 分钟提醒' });
    } catch (_) {
      this.getUIContext().getPromptAction().showToast({ message: '提醒时间保存失败，请重试' });
    } finally {
      this.reminderBusy = false;
    }
  }

  private async setClassReminderEnabled(on: boolean): Promise<void> {
    if (this.reminderBusy) {
      return;
    }
    this.reminderBusy = true;
    const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      if (!on) {
        this.classReminderEnabled = false;
        await ClassReminderStore.getInstance().saveEnabled(false);
        await ClassReminderScheduler.cancelAll(ctx);
        this.getUIContext().getPromptAction().showToast({ message: '已关闭课程提醒' });
        return;
      }
      const allowed: boolean = await ClassReminderScheduler.requestNotification(ctx);
      if (!allowed) {
        this.classReminderEnabled = false;
        await ClassReminderStore.getInstance().saveEnabled(false);
        this.getUIContext().getPromptAction().showToast({ message: '未授予通知权限，无法开启课程提醒' });
        return;
      }
      this.classReminderEnabled = true;
      await ClassReminderStore.getInstance().saveEnabled(true);
      const result: ClassReminderSyncResult = await ClassReminderScheduler.sync(ctx, this.timetableEvents, true);
      if (result.pendingClasses === 0) {
        this.getUIContext().getPromptAction().showToast({
          message: '已开启课程提醒（当前没有未开始的课程，有课之后会自动提醒）'
        });
      } else {
        const whenText: string = result.nextFire.length > 0 ? '，下一次约 ' + result.nextFire : '';
        this.getUIContext().getPromptAction().showToast({
          message: '已开启课程提醒' + whenText +
            '。应用在前台或后台时会通知，划掉应用后不会提醒'
        });
      }
    } finally {
      this.reminderBusy = false;
    }
  }

  private updateTodayHighlights(): void {
    const now: number = this.nowTick;
    const courses: EasEventItem[] = this.timetableEvents.filter((event: EasEventItem): boolean =>
      event.type === EasEventType.CLASS);
    const selection = CurrentClassSelection.find(courses, now);
    this.activeClass = selection.current;
    this.nextClass = selection.next;
  }

  private drawTimetableNow(): void {
    this.refreshTimetableBackdrop();
    if (this.courseSkipAnimating) {
      return;
    }
    if (this.timetableAreaW <= 0 || this.timetableAreaH <= 0 || this.currentTimetable === undefined) {
      this.stopTimetableMarquee();
      return;
    }
    const weekEvents: EasEventItem[] = eventsOfWeek(this.currentTimetable,
      this.timetableEvents, this.timetableWeek);
    const current: number = this.currentTimetable.getWeekNumber(this.nowTick);
    const hourHeight: number = this.timetableHourHeight();
    const bodyViewportHeight: number = Math.max(1,
      this.timetableAreaH - this.timetableChromeH + TIMETABLE_BOTTOM_SAFE_EXTENSION);
    const contentHeight: number = TIMETABLE_GRID_TOP_PADDING +
      (AXIS_END_HOUR - AXIS_START_HOUR) * hourHeight + 8;
    const canvasHeight: number = Math.max(bodyViewportHeight, contentHeight);
    if (this.timetableCanvasHeight !== canvasHeight) {
      this.timetableCanvasHeight = canvasHeight;
    }
    this.updateEveningCourseHint();
    const cardLayer: TimetableCardLayer = new TimetableCardLayer();
    // The grid shares the page's resource-backed background with the heading.
    const labels: TimetablePlaceLabel[] = drawTimetableWeek(this.timetableCanvas,
      this.timetableAreaW, canvasHeight,
      this.currentTimetable, weekEvents, this.timetableWeek, current === this.timetableWeek,
      hourHeight, 0, false, false, this.timetableInk('time'), this.darkMode, cardLayer, this.timetableDisplay,
      this.timetableBackdrop, this.hasTimetableBackground(), false);
    const cards: TimetableCardSurface[] = cardLayer.surfaces;
    if (cards.length !== this.timetableCardSurfaces.length ||
      cards.some((card: TimetableCardSurface, index: number): boolean =>
        card.renderKey() !== this.timetableCardSurfaces[index].renderKey())) {
      this.timetableCardSurfaces = cards;
    }
    if (labels.length !== this.timetablePlaceLabels.length ||
      labels.some((label: TimetablePlaceLabel, index: number): boolean =>
        !label.matches(this.timetablePlaceLabels[index]))) {
      this.stopTimetableMarquee();
      this.timetableMarqueeElapsedMs = 0;
    }
    this.timetablePlaceLabels = labels;
    this.drawTimetablePlaceFrame();
    this.startTimetableMarquee();
  }

  private maxTimetableWeek(): number {
    if (this.currentTimetable === undefined) {
      return 1;
    }
    const max: number = this.currentTimetable.getWeekNumber(this.currentTimetable.endTime - 1);
    return max > 0 ? max : 1;
  }

  private showReturnToCurrentWeek(): boolean {
    const week: number = this.currentTimetable?.getWeekNumber(this.nowTick) ?? -1;
    return week > 0 && week <= this.maxTimetableWeek() && week !== this.timetableWeek;
  }

  private returnToCurrentWeek(): void {
    if (!this.canOpenSheet() || this.timetableAnimating) return;
    const now: number = Date.now();
    const week: number = this.currentTimetable?.getWeekNumber(now) ?? -1;
    if (week < 1 || week > this.maxTimetableWeek() || week === this.timetableWeek) return;
    this.nowTick = now;
    this.animateTimetableWeek(week - this.timetableWeek);
  }

  private shiftTimetableWeek(delta: number): void {
    const next: number = this.timetableWeek + delta;
    if (next < 1 || next > this.maxTimetableWeek()) {
      return;
    }
    this.timetableWeek = next;
    this.stopTimetableMarquee();
    this.timetableMarqueeElapsedMs = 0;
    this.drawTimetableNow();
  }

  private timetableDragLimit(): number {
    return Math.max(1, this.timetableAreaW);
  }

  private timetableHourHeight(): number {
    if (this.timetableAreaH <= this.timetableChromeH) {
      return TIMETABLE_HOUR_HEIGHT;
    }
    // Keep 08:00–19:00 visible in the initial viewport, while preserving
    // the iOS compact layout's 56vp/hour as the upper bound.
    const visibleHours: number = 19 - AXIS_START_HOUR;
    const availableGridHeight: number = this.timetableAreaH - this.timetableChromeH -
      TIMETABLE_GRID_TOP_PADDING - 8 + TIMETABLE_BOTTOM_SAFE_EXTENSION;
    return Math.max(42, Math.min(TIMETABLE_HOUR_HEIGHT, availableGridHeight / visibleHours));
  }

  private openCourseAt(x: number, y: number): void {
    if (!this.canOpenSheet() || this.currentTimetable === undefined ||
      x <= 0 || y < TIMETABLE_GRID_TOP_PADDING) {
      return;
    }
    for (let i: number = this.timetableCardSurfaces.length - 1; i >= 0; i--) {
      const card: TimetableCardSurface = this.timetableCardSurfaces[i];
      if (x < card.left || x > card.left + card.width || y < card.top || y > card.top + card.height) {
        continue;
      }
      this.openCourseCard(card.key);
      return;
    }
  }

  private openCourseCard(key: string): void {
    if (!this.canOpenSheet() || this.currentTimetable === undefined || this.timetableAnimating) {
      return;
    }
    const card: TimetableCardSurface | undefined = this.timetableCardSurfaces.find(
      (item: TimetableCardSurface): boolean => item.key === key);
    if (card === undefined) {
      return;
    }
    const event: EasEventItem | undefined = this.timetableEvents.find((item: EasEventItem): boolean =>
      item.id === card.eventIds[0] && item.timetableId === this.currentTimetable?.id);
    if (event !== undefined && (event.type === EasEventType.CLASS || event.type === EasEventType.EXAM)) {
      this.courseColorEditing = false;
      this.selectedCourse = event;
      this.courseSheetOpen = true;
      this.activeSheetVisible = true;
    }
  }

  private async confirmSkipCourse(event: EasEventItem): Promise<void> {
    if (this.skippingCourse || !this.pageVisible || this.currentTab !== TAB_TIMETABLE ||
      !this.activeSheetVisible || !this.courseSheetOpen || this.selectedCourse?.id !== event.id ||
      event.type !== EasEventType.CLASS) {
      return;
    }
    const card: TimetableCardSurface | undefined = this.timetableCardSurfaces.find(
      (item: TimetableCardSurface): boolean => item.eventIds.indexOf(event.id) >= 0);
    if (card === undefined) {
      return;
    }
    this.skippingCourse = true;
    this.summaryRequestGeneration++;
    const sheetGeneration: number = this.sheetRequestGeneration;
    const week: number = this.timetableWeek;
    const ids: string[] = card.eventIds.slice();
    let confirmed: boolean = false;
    let deleted: boolean = false;
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: '确定要翘掉这节课吗？',
        buttons: [
          { text: '我去上课', color: $r('app.color.hita_text_secondary') },
          { text: '我意已决', color: '#E84040' }
        ]
      });
      if (result.index !== 1 || sheetGeneration !== this.sheetRequestGeneration ||
        !this.pageVisible || this.currentTab !== TAB_TIMETABLE || !this.activeSheetVisible ||
        this.currentTimetable?.id !== event.timetableId || this.timetableWeek !== week) {
        return;
      }
      confirmed = true;
      await RdbHelper.getInstance().deleteClassOccurrences(ids, event.timetableId);
      deleted = true;
      this.courseSkipAnimating = true;
      // Keep the rendered card alive until its snapshot has finished dissolving.
      this.timetableEvents = this.timetableEvents.filter((item: EasEventItem): boolean => ids.indexOf(item.id) < 0);
      this.todayItems = this.todayItems.filter((item: EasEventItem): boolean => ids.indexOf(item.id) < 0);
      this.updateTodayHighlights();
      this.timelineText = this.todayItems.length === 0 ? '今日暂无安排' :
        '今日 ' + this.todayItems.length.toString() + ' 项安排';
      await this.closeCourseSheetBeforeSkip();
      if (this.pageVisible && this.currentTab === TAB_TIMETABLE && this.timetableWeek === week &&
        this.currentTimetable?.id === event.timetableId) {
        await this.courseDeleteEffects.play([card.key]);
      }
      this.courseSkipAnimating = false;
      this.drawTimetableNow();
      if (this.pageVisible) {
        const name: string = event.name.trim().length === 0 || event.name === 'NULL' ? '未命名课程' : event.name;
        this.getUIContext().getPromptAction().showToast({
          message: '这节' + name + '如奶油般化开了。', duration: 3500
        });
      }
    } catch (_) {
      // Dismissing the dialog is cancellation; only a confirmed write can fail.
      if (confirmed && this.pageVisible && !deleted && this.activeSheetVisible &&
        sheetGeneration === this.sheetRequestGeneration) {
        this.getUIContext().getPromptAction().showToast({ message: '未能翘掉这节课，请重试' });
      }
    } finally {
      this.courseSkipAnimating = false;
      this.skippingCourse = false;
      if (deleted) {
        this.drawTimetableNow();
        NextClassWidgetService.scheduleRefresh();
        if (this.classReminderEnabled) {
          try {
            const host: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
            await ClassReminderScheduler.sync(host, this.timetableEvents);
          } catch (_) {
            console.warn('Failed to update class reminders after skipping a lesson');
          }
        }
      }
      if (this.pageVisible) {
        await this.refreshSummaries(true).catch(() => {});
      }
    }
  }

  private closeCourseSheetBeforeSkip(): Promise<void> {
    if (!this.courseSheetOpen || !this.pageVisible) {
      return Promise.resolve();
    }
    return new Promise<void>((resolve: () => void) => {
      this.courseSheetDismissed = resolve;
      this.courseSheetDismissTimer = setTimeout(() => this.finishCourseSheetDismissal(), 650);
      this.closeActiveSheet();
    });
  }

  private finishCourseSheetDismissal(): void {
    clearTimeout(this.courseSheetDismissTimer);
    this.courseSheetDismissTimer = -1;
    const finish: (() => void) | undefined = this.courseSheetDismissed;
    this.courseSheetDismissed = undefined;
    if (finish !== undefined) {
      finish();
    }
  }

  private async saveCourseColor(event: EasEventItem, color: number): Promise<void> {
    const isExam: boolean = event.type === EasEventType.EXAM;
    if (isExam) {
      await RdbHelper.getInstance().saveExamColor(event.id, event.timetableId, color);
    } else {
      await RdbHelper.getInstance().saveCourseColor(event.subjectId, event.timetableId, color);
    }
    // Update every week without resetting the currently viewed week.
    for (const item of this.timetableEvents) {
      if (item.timetableId === event.timetableId && (isExam ? item.id === event.id :
        item.type !== EasEventType.EXAM && item.subjectId === event.subjectId)) {
        item.color = color;
      }
    }
    this.timetableEvents = this.timetableEvents.slice();
    this.drawTimetableNow();
    if (this.selectedCourse?.id === event.id && this.activeSheetVisible) {
      this.selectedCourse = this.timetableEvents.find((item: EasEventItem) => item.id === event.id);
      this.courseColorEditing = false;
    }
  }

  private eventDetailEndTime(event: EasEventItem): number {
    if (event.to > event.from) {
      return event.to;
    }
    if (this.currentTimetable !== undefined) {
      const span = timetableEventSpan(this.currentTimetable, event, this.timetableWeek);
      if (span !== undefined && span.to > span.from) {
        return span.to;
      }
    }
    return event.from + 60 * 60 * 1000;
  }

  private courseProgressText(event: EasEventItem): string {
    const instances: EasEventItem[] = this.timetableEvents.filter((item: EasEventItem): boolean =>
      item.type === EasEventType.CLASS && item.subjectId === event.subjectId);
    instances.sort((a: EasEventItem, b: EasEventItem): number => a.from - b.from);
    let index: number = 0;
    for (let i: number = 0; i < instances.length; i++) {
      if (instances[i].id === event.id) {
        index = i + 1;
        break;
      }
    }
    return index > 0 ? '第 ' + index.toString() + ' / ' + instances.length.toString() + ' 次课' :
      '共 ' + instances.length.toString() + ' 次课';
  }

  private static courseDateText(timestamp: number): string {
    const date: Date = new Date(timestamp);
    return date.getFullYear().toString() + '年' + (date.getMonth() + 1).toString() + '月' +
      date.getDate().toString() + '日 · ' + DOW_FULL[EasTimeTools.getDow(timestamp)];
  }

  private static coursePeriodText(event: EasEventItem): string {
    if (event.fromNumber <= 0 || event.lastNumber <= 0) {
      return '未记录节次';
    }
    return event.fromNumber === event.lastNumber ? '第 ' + event.fromNumber.toString() + ' 节' :
      '第 ' + event.fromNumber.toString() + ' - ' + event.lastNumber.toString() + ' 节';
  }

  private timetableOpacity(): number {
    const ratio: number = Math.abs(this.timetableDragOffset) / this.timetableDragLimit();
    // Android uses alpha = 1 - abs(offset) / pageWidth while paging.
    return 1 - Math.min(1, ratio);
  }

  private resetTimetableAnimationState(): void {
    this.timetableAnimationDuration = 0;
    this.timetableDragOffset = 0;
    this.timetableAnimating = false;
    this.timetableAnimationTimer = -1;
  }

  private animateTimetableSnapBack(): void {
    // A tap can cancel the pan recognizer without ever moving the week.
    if (this.timetableAnimating || this.timetableDragOffset === 0) {
      return;
    }
    this.timetableAnimating = true;
    this.timetableAnimationDuration = TIMETABLE_SLIDE_MS;
    this.timetableDragOffset = 0;
    this.timetableAnimationTimer = setTimeout(() => {
      this.resetTimetableAnimationState();
    }, TIMETABLE_SLIDE_MS + 20);
  }

  private animateTimetableWeek(delta: number): void {
    if (this.timetableAnimating) {
      return;
    }
    const width: number = this.timetableDragLimit();
    const exitOffset: number = delta > 0 ? -width : width;
    const entryOffset: number = -exitOffset;
    this.timetableAnimating = true;
    this.timetableAnimationDuration = TIMETABLE_SLIDE_MS;
    this.timetableDragOffset = exitOffset;

    // Swap the week after the outgoing page has left, then bring the new page
    // in from the opposite edge. A zero-duration reposition prevents a reverse
    // animation through the center between the outgoing and incoming legs.
    this.timetableAnimationTimer = setTimeout(() => {
      this.timetableAnimationDuration = 0;
      this.shiftTimetableWeek(delta);
      this.timetableDragOffset = entryOffset;
      this.timetableAnimationTimer = setTimeout(() => {
        this.timetableAnimationDuration = TIMETABLE_SLIDE_MS;
        this.timetableDragOffset = 0;
        this.timetableAnimationTimer = setTimeout(() => {
          this.resetTimetableAnimationState();
        }, TIMETABLE_SLIDE_MS + 20);
      }, 20);
    }, TIMETABLE_SLIDE_MS + 10);
  }

  private handleTimetablePanUpdate(event: GestureEvent): void {
    if (this.timetableAnimating || this.skippingCourse) {
      return;
    }
    const width: number = this.timetableDragLimit();
    this.timetableAnimationDuration = 0;
    this.timetableDragOffset = Math.max(-width, Math.min(width, event.offsetX));
  }

  private handleTimetablePanEnd(event: GestureEvent): void {
    if (this.timetableAnimating || this.skippingCourse) {
      return;
    }
    const width: number = this.timetableDragLimit();
    const offset: number = event.offsetX;
    const fling: boolean = Math.abs(offset) >= TIMETABLE_FLING_MIN_OFFSET &&
      Math.abs(event.velocityX) >= TIMETABLE_FLING_VELOCITY && event.velocityX * offset > 0;
    const committed: boolean = fling || Math.abs(offset) >= width * TIMETABLE_SWIPE_RATIO;
    if (committed && offset < 0 && this.timetableWeek < this.maxTimetableWeek()) {
      this.animateTimetableWeek(1);
    } else if (committed && offset > 0 && this.timetableWeek > 1) {
      this.animateTimetableWeek(-1);
    } else if (Math.abs(offset) > 0) {
      this.animateTimetableSnapBack();
    } else {
      this.resetTimetableAnimationState();
    }
  }

  private selectTab(index: number): void {
    if (index === this.currentTab) {
      return;
    }
    this.closeActiveSheet();
    this.stopTimetableMarquee();
    this.currentTab = index;
    if (index === TAB_TIMETABLE) {
      this.courseDeleteEffects.resume();
      // Tabs keeps the canvas alive. Reuse it until data, date or layout changes.
      this.startTimetableMarquee();
    } else {
      this.courseDeleteEffects.pause();
      this.finishCourseSheetDismissal();
    }
  }

  private finishTabAnimation(index: number): void {
    this.tabTransitionRunning = false;
    this.selectTab(index);
    this.selectedNav = index;
    // Also resume after a cancelled swipe, where onChange may not fire.
    this.startTimetableMarquee();
  }

  private dockPageInset(): number {
    return 64 + this.navBarInset;
  }

  private dockTab(icon: Resource, label: string): BottomTabBarStyle {
    const normal: SymbolGlyphModifier = new SymbolGlyphModifier(icon);
    normal.fontSize(20);
    normal.fontColor([$r('sys.color.ohos_id_color_text_secondary')]);
    const selected: SymbolGlyphModifier = new SymbolGlyphModifier(icon);
    selected.fontSize(20);
    selected.fontColor([$r('sys.color.ohos_id_color_text_primary')]);
    const symbol: TabBarSymbol = {
      normal: normal,
      selected: selected
    };
    return BottomTabBarStyle.of(symbol, label)
      .layoutMode(LayoutMode.VERTICAL)
      .labelStyle({
        font: { size: 11, weight: FontWeight.Medium },
        selectedColor: $r('sys.color.ohos_id_color_text_primary'),
        unselectedColor: $r('sys.color.ohos_id_color_text_secondary')
      });
  }

  private timetableHeaderMonth(): string {
    if (this.currentTimetable === undefined) {
      return '';
    }
    const monday: Date = new Date(this.currentTimetable.startTime + (this.timetableWeek - 1) * 7 * DAY_MS);
    return (monday.getMonth() + 1).toString() + '月';
  }

  private timetableHeaderDate(dayIndex: number): string {
    if (this.currentTimetable === undefined) {
      return '';
    }
    const monday: number = this.currentTimetable.startTime + (this.timetableWeek - 1) * 7 * DAY_MS;
    return new Date(monday + dayIndex * DAY_MS).getDate().toString();
  }

  private timetableHeaderIsToday(dayIndex: number): boolean {
    if (this.currentTimetable === undefined) {
      return false;
    }
    return this.currentTimetable.getWeekNumber(this.nowTick) === this.timetableWeek &&
      EasTimetable.dowOfMs(Date.now()) === dayIndex + 1;
  }

  /** Zero-based today column for the shown week, or -1 when the week is not current. */
  private timetableTodayColumn(): number {
    if (this.currentTimetable === undefined || this.timetableAreaW <= TIMETABLE_GUTTER_WIDTH) {
      return -1;
    }
    for (let dayIndex = 0; dayIndex < 7; dayIndex++) {
      if (this.timetableHeaderIsToday(dayIndex)) {
        return dayIndex;
      }
    }
    return -1;
  }

  private timetableTodayColumnWidth(): number {
    return Math.max(0, (this.timetableAreaW - TIMETABLE_GUTTER_WIDTH) / 7);
  }

  /**
   * The column stays pinned to the date header's bottom edge and ends at the
   * last hour line; overscroll stretches it instead of opening a gap.
   */
  private timetableTodayMaskVisibleHeight(): number {
    const gridBottom: number = Math.min(this.timetableCanvasHeight - 4,
      TIMETABLE_GRID_TOP_PADDING + (AXIS_END_HOUR - AXIS_START_HOUR) * this.timetableHourHeight());
    return Math.max(0, gridBottom - this.timetableScrollY);
  }

  private timetableCampusTerm(): string {
    const campus: string = this.sessionInfo === undefined ? '' : Home.campusName(this.sessionInfo.campus);
    if (this.currentTimetable === undefined) {
      return campus.length > 0 ? campus : '当前学期';
    }
    return (campus.length > 0 ? campus + ' · ' : '') + this.currentTimetable.name;
  }

  private onTimetableArea(w: number, h: number): void {
    this.timetableAreaW = w;
    this.timetableAreaH = h;
    const hourHeight: number = this.timetableHourHeight();
    const bodyViewportHeight: number = Math.max(1,
      h - this.timetableChromeH + TIMETABLE_BOTTOM_SAFE_EXTENSION);
    const contentHeight: number = TIMETABLE_GRID_TOP_PADDING +
      (AXIS_END_HOUR - AXIS_START_HOUR) * hourHeight + 8;
    this.timetableCanvasHeight = Math.max(bodyViewportHeight, contentHeight);
    this.drawTimetableNow();
  }

  private updateEveningCourseHint(): void {
    if (!this.timetableDisplay.eveningHint || this.currentTimetable === undefined || this.timetableAreaH <= 0) {
      this.showEveningCourseHint = false;
      return;
    }
    const weekEvents = eventsOfWeek(this.currentTimetable, this.timetableEvents, this.timetableWeek);
    const maxOffset = Math.max(0, this.timetableChromeH + this.timetableCanvasHeight - this.timetableAreaH);
    this.showEveningCourseHint = eveningHintVisible(hasEveningCourse(weekEvents),
      this.timetableScroller.currentOffset().yOffset, maxOffset);
  }

  private hasTimetableBackground(): boolean {
    return this.timetableBgUri.length > 0;
  }

  private onTimetableBackgroundTap(): void {
    if (this.timetableBackgroundBusy) return;
    this.getUIContext().getPromptAction().showActionMenu({
      title: '时间表壁纸',
      buttons: [
        { text: '选择图片作为壁纸', color: COLOR_PRIMARY },
        { text: '选择视频作为动态壁纸', color: COLOR_PRIMARY },
        { text: '移除壁纸', color: $r('app.color.hita_error_e53935') }
      ]
    }).then((ret) => {
      if (ret.index === 0 || ret.index === 1) {
        void this.pickTimetableBackground(ret.index === 1);
      } else if (ret.index === 2) {
        this.removeTimetableBackground();
      }
    }).catch(() => {});
  }

  private async pickTimetableBackground(video: boolean = false): Promise<void> {
    if (this.timetableBackgroundBusy) return;
    this.timetableBackgroundBusy = true;
    const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      const background = await TimetableBackgroundStore.pickAndSave(ctx, video);
      if (background === undefined) return;
      this.timetableVideoUri = '';
      this.timetableVideoFailed = false;
      this.timetableBgUri = TimetableBackgroundStore.toDisplayUri(background.imagePath);
      this.timetableFadeOpacity = 0;
      await this.loadTimetableWallpaperColors(background.imagePath);
      this.timetableVideoUri = background.videoPath ? 'file://' + background.videoPath : '';
    } catch (_) {
      this.getUIContext().getPromptAction().showToast({
        message: video ? '视频导入失败，请检查可用空间或尝试设备支持的视频格式' : '选择图片失败'
      });
    } finally {
      this.timetableBackgroundBusy = false;
    }
  }

  private removeTimetableBackground(): void {
    const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
    TimetableBackgroundStore.remove(ctx);
    this.timetableVideoUri = '';
    this.timetableVideoFailed = false;
    this.timetableBgUri = '';
    this.timetableWallpaperGeneration++;
    this.timetableWallpaperPixels = undefined;
    this.timetableBackdropKey = '';
    this.drawTimetableNow();
  }

  private async setTimetableTextColor(color: string): Promise<void> {
    await TimetableSelectionStore.getInstance().saveTextColor(color);
    this.timetableTextColor = color;
    this.drawTimetableNow();
  }

  private async saveTimetableDisplay(options: TimetableDisplayOptions): Promise<void> {
    const store = TimetableDisplayStore.getInstance();
    await store.init(this.getUIContext().getHostContext() as common.Context);
    await store.save(options);
    this.timetableDisplay = options.copy();
    this.timetableMaskDepth = options.wallpaperMask;
    this.drawTimetableNow();
  }

  private returningFromCourseEditor: boolean = false;

  private openAddCourse(): void {
    if (!this.canOpenSheet()) return;
    if (this.currentTimetable === undefined) {
      this.getUIContext().getPromptAction().showToast({ message: '请先新建或导入课表，再添加课程' });
      return;
    }
    this.returningFromCourseEditor = true;
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/AddEventPage',
      params: { type: 'CLASS', timetableId: this.currentTimetable.id, week: this.timetableWeek.toString() }
    }).catch(() => {
      this.returningFromCourseEditor = false;
      this.getUIContext().getPromptAction().showToast({ message: '无法打开添加课程，请重试' });
    });
  }

  private canOpenSheet(): boolean {
    return !this.skippingCourse && this.pageVisible && !this.tabTransitionRunning && !this.activeSheetVisible &&
      !this.sessionSheetOpen && !this.loginSheetOpen && !this.courseSheetOpen &&
      !this.calendarExportSheetOpen && !this.timetableDisplayOpen && !this.widgetBackgroundSheetOpen &&
      !this.importTimetableSheetOpen && !this.academicPanelOpen;
  }

  private closeActiveSheet(): void {
    // Invalidate pending reads immediately, but retain content until the exit animation ends.
    this.sheetRequestGeneration++;
    this.sessionSheetLoading = false;
    this.activeSheetVisible = false;
  }

  private openWidgetBackgroundSheet(): void {
    if (!this.canOpenSheet()) {
      return;
    }
    this.widgetBackgroundDirty = false;
    this.widgetBackgroundBusy = false;
    this.widgetBackgroundSheetOpen = true;
    this.activeSheetVisible = true;
  }

  private openImportTimetableSheet(): void {
    if (!this.canOpenSheet()) {
      return;
    }
    this.importTimetableSheetOpen = true;
    this.activeSheetVisible = true;
  }

  private openAcademicPanel(kind: number): void {
    if (!this.canOpenSheet() || kind < 1 || kind > 4) {
      return;
    }
    this.academicPanelKind = kind;
    this.academicPanelOpen = true;
    this.activeSheetVisible = true;
  }

  private springBackWidgetBackgroundSheet(): void {
    const springBack: (() => void) | undefined = this.widgetBackgroundSpringBack;
    this.widgetBackgroundSpringBack = undefined;
    springBack?.();
  }

  private confirmWidgetBackgroundDismiss(dismiss: () => void): void {
    if (this.widgetBackgroundBusy) {
      this.springBackWidgetBackgroundSheet();
      return;
    }
    if (!this.widgetBackgroundDirty) {
      this.widgetBackgroundSpringBack = undefined;
      dismiss();
      return;
    }
    if (this.widgetBackgroundConfirmDismiss === undefined) {
      this.springBackWidgetBackgroundSheet();
      return;
    }
    this.widgetBackgroundConfirmDismiss(dismiss, () => this.springBackWidgetBackgroundSheet());
  }

  private requestCalendarExport(): void {
    if (this.calendarExporting || !this.canOpenSheet()) {
      return;
    }
    if (this.currentTimetable === undefined) {
      this.getUIContext().getPromptAction().showToast({ message: '请先新建或导入课表' });
      return;
    }
    // Keep the confirmed target stable if the current selection refreshes.
    this.calendarExportTimetable = this.currentTimetable;
    this.calendarExportSheetOpen = true;
    this.activeSheetVisible = true;
  }

  private cancelCalendarExport(): void {
    if (this.calendarExportSheetOpen) {
      this.closeActiveSheet();
    }
  }

  private async exportToCalendar(): Promise<void> {
    const timetable: EasTimetable | undefined = this.calendarExportTimetable;
    if (this.calendarExporting || !this.calendarExportSheetOpen || !this.activeSheetVisible ||
      timetable === undefined) {
      return;
    }
    this.calendarExporting = true;
    this.closeActiveSheet();
    try {
      const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const result: CalendarExportResult = await TimetableCalendarExporter.exportTimetable(ctx, timetable);
      this.getUIContext().getPromptAction().showToast({ message: result.message, duration: 3500 });
    } catch (_) {
      this.getUIContext().getPromptAction().showToast({ message: '导出至手机日历失败，请稍后重试' });
    } finally {
      this.calendarExporting = false;
    }
  }

  private async importIcsTimetable(): Promise<void> {
    const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      const result: IcsImportResult | undefined = await TimetableIcsImporter.pickAndImport(ctx);
      if (result === undefined) {
        return;
      }
      this.getUIContext().getPromptAction().showToast({ message: result.message });
      if (result.success) {
        await this.refreshSummaries();
        this.getUIContext().getRouter().pushUrl({
          url: 'pages/TimetableDetailPage',
          params: { 'timetableId': result.timetableId }
        });
      }
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '导入 ICS 失败' });
    }
  }

  async importTimetable(showToast: boolean = true): Promise<void> {
    if (this.importing) {
      return;
    }
    const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
    this.importing = true;
    this.importRequested = true;
    this.importMessage = '正在从教务系统读取课表…';
    this.importError = '';
    try {
      const result: EasImportResult = await EasTimetableImporter.importCurrent(ctx);
      if (result.success) {
        if (result.timetable !== undefined) {
          await TimetableSelectionStore.getInstance().save(result.timetable.id);
        }
        this.importMessage = result.message;
        if (showToast) {
          this.getUIContext().getPromptAction().showToast({ message: result.message });
        }
      } else {
        this.importMessage = '';
        this.importError = result.message.length > 0 ? result.message : '导入课表失败';
        if (showToast) {
          this.getUIContext().getPromptAction().showToast({ message: this.importError });
        }
      }
    } catch (error) {
      const message: string = error instanceof Error ? error.message : String(error);
      this.importMessage = '';
      this.importError = EasUserMessages.fromError(message, '导入课表失败，请稍后重试');
      if (showToast) {
        this.getUIContext().getPromptAction().showToast({ message: this.importError });
      }
    } finally {
      this.importing = false;
      await this.refreshSummaries();
    }
  }

  /**
   * 打开应用或回到前台时检查当前教务课表在教务端是否有变化。只读取不写库，
   * 有变化时列出并由用户决定是否更新；网络或登录问题静默跳过。
   */
  private async checkTimetableUpdate(): Promise<void> {
    if (this.pendingTimetableUpdate !== undefined) {
      this.promptTimetableUpdate();
      return;
    }
    const timetable: EasTimetable | undefined = this.currentTimetable;
    const now: number = Date.now();
    if (this.timetableUpdateChecking || this.importing || timetable === undefined ||
      !EasTimetableImporter.isEasTimetable(timetable) || timetable.endTime < now) {
      return;
    }
    this.timetableUpdateChecking = true;
    try {
      const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
      const update: EasTimetableUpdate | undefined = await EasTimetableImporter.checkForUpdate(ctx, timetable,
        TIMETABLE_UPDATE_INTERVAL_MS);
      if (update !== undefined) {
        this.pendingTimetableUpdate = update;
        this.promptTimetableUpdate();
      }
    } catch (_) {
      // 过期、离线等情况由教务功能页面各自提示；启动检查不打扰用户。
    } finally {
      this.timetableUpdateChecking = false;
    }
  }

  /** 页面空闲时弹出变化清单；正在操作弹层或切页时留到下次显示页面。 */
  private promptTimetableUpdate(): void {
    const update: EasTimetableUpdate | undefined = this.pendingTimetableUpdate;
    if (update === undefined || this.timetableUpdatePrompting || this.importing || !this.canOpenSheet()) {
      return;
    }
    this.pendingTimetableUpdate = undefined;
    if (this.currentTimetable?.id !== update.timetable.id) {
      return;
    }
    this.timetableUpdatePrompting = true;
    const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
    this.timetableUpdateDialog = new CustomDialogController({
      builder: TimetableUpdateDialog({
        changes: update.changes,
        onApply: async () => {
          await EasTimetableImporter.applyUpdate(ctx, update);
          this.timetableUpdatePrompting = false;
          this.getUIContext().getPromptAction().showToast({ message: '课表已更新' });
          await this.refreshSummaries();
        },
        onDismiss: async () => {
          this.timetableUpdatePrompting = false;
          await EasTimetableImporter.dismissUpdate(ctx, update);
        }
      }),
      // 返回键关闭不算选择，下次检查仍会提醒。
      cancel: () => {
        this.timetableUpdatePrompting = false;
      },
      customStyle: true,
      autoCancel: false,
      alignment: DialogAlignment.Center
    });
    this.timetableUpdateDialog.open();
  }

  /** Edited courses keep their id; the key must change with every displayed field or the row is reused stale. */
  private static todayItemKey(event: EasEventItem): string {
    return [event.id, event.type, event.name, event.place, event.teacher, event.from.toString(),
      event.to.toString(), event.fromNumber.toString(), event.lastNumber.toString(), event.color.toString()]
      .join('\u0001');
  }

  private static eventColor(type: EasEventType): ResourceColor {
    if (type === EasEventType.CLASS) {
      return COLOR_CLASS;
    }
    if (type === EasEventType.EXAM) {
      return COLOR_EXAM;
    }
    if (type === EasEventType.TAG) {
      return COLOR_TAG;
    }
    return COLOR_OTHER;
  }

  private static defaultCanvasColor(type: EasEventType): number {
    if (type === EasEventType.EXAM) {
      return 0xFFB24B63;
    }
    if (type === EasEventType.OTHER) {
      return 0xFF4D7CC7;
    }
    if (type === EasEventType.TAG) {
      return 0xFF2F8F72;
    }
    return 0xFF2E86E8;
  }

  private todayClassCount(): number {
    let count: number = 0;
    for (let i: number = 0; i < this.todayItems.length; i++) {
      if (this.todayItems[i].type === EasEventType.CLASS) {
        count++;
      }
    }
    return count;
  }

  private completedClassCount(): number {
    let count: number = 0;
    for (let i: number = 0; i < this.todayItems.length; i++) {
      if (this.todayItems[i].type === EasEventType.CLASS && this.todayItems[i].to <= this.nowTick) {
        count++;
      }
    }
    return count;
  }

  private static durationText(milliseconds: number): string {
    const totalMinutes: number = Math.max(0, Math.ceil(milliseconds / 60000));
    const hours: number = Math.floor(totalMinutes / 60);
    const minutes: number = totalMinutes % 60;
    return hours > 0 ? hours.toString() + '小时' + minutes.toString() + '分钟' :
      totalMinutes.toString() + '分钟';
  }

  private static greeting(now: number): string {
    const hour: number = new Date(now).getHours();
    if (hour < 5) return '夜深了';
    if (hour < 11) return '早上好';
    if (hour < 13) return '中午好';
    if (hour < 18) return '下午好';
    return '晚上好';
  }

  private currentWeekNumber(): number {
    return this.currentTimetable !== undefined ? this.currentTimetable.getWeekNumber(this.nowTick) : -1;
  }

  /** The class the hero card follows: the ongoing one first, then the next one today. */
  private heroEvent(): EasEventItem | undefined {
    return this.activeClass !== undefined ? this.activeClass : this.nextClass;
  }

  private todayHeroHeight(): number {
    if (this.activeClass !== undefined) return 176;
    return this.nextClass !== undefined ? 160 : 136;
  }

  private heroTag(): string {
    if (this.activeClass !== undefined) return '上课中';
    if (this.nextClass !== undefined) return '下一节';
    if (!this.hasTimetable) return '今天';
    return this.todayClassCount() > 0 ? '已下课' : '今天';
  }

  private heroIdleTitle(): string {
    if (!this.hasTimetable) return '先导入一份课表吧';
    if (this.todayClassCount() > 0) return '今天的课都上完了';
    return '今天没有课';
  }

  /** Whole minutes until the hero class ends (ongoing) or starts (next). */
  private heroMinutesLeft(): number {
    const event: EasEventItem | undefined = this.heroEvent();
    if (event === undefined) return 0;
    const target: number = this.activeClass !== undefined ? event.to : event.from;
    return Math.max(0, Math.ceil((target - this.nowTick) / 60000));
  }

  private heroCountdownSuffix(): string {
    return this.activeClass !== undefined ? ' 后下课' : ' 后上课';
  }

  /** Summary of tomorrow's first class, shown once today is done. */
  private tomorrowText(): string {
    if (!this.hasTimetable) return '登录教务或手动创建课表';
    const start: number = new Date(new Date(this.nowTick).setHours(0, 0, 0, 0)).getTime() + DAY_MS;
    const classes: EasEventItem[] = this.timetableEvents.filter((event: EasEventItem): boolean =>
      event.type === EasEventType.CLASS && event.from >= start && event.from < start + DAY_MS);
    if (classes.length === 0) return '明天也没有课';
    classes.sort((a: EasEventItem, b: EasEventItem): number => a.from - b.from);
    return '明天 ' + classes.length.toString() + ' 节课，' + EasTimeTools.printTime(classes[0].from) +
      ' 开始 · ' + classes[0].name;
  }

  /** The nearest exam within the next 14 days in the displayed timetable. */
  private upcomingExam(): EasEventItem | undefined {
    let found: EasEventItem | undefined = undefined;
    const limit: number = this.nowTick + 14 * DAY_MS;
    for (let i: number = 0; i < this.timetableEvents.length; i++) {
      const event: EasEventItem = this.timetableEvents[i];
      if (event.type === EasEventType.EXAM && event.to > this.nowTick && event.from < limit &&
        (found === undefined || event.from < found.from)) {
        found = event;
      }
    }
    return found;
  }

  private static examWhenText(exam: EasEventItem): string {
    const date: Date = new Date(exam.from);
    const text: string = (date.getMonth() + 1).toString() + '月' + date.getDate().toString() + '日 ' +
      DOW_FULL[EasTimeTools.getDow(exam.from)] + ' ' + EasTimeTools.printTime(exam.from);
    return exam.place.length > 0 ? text + ' · ' + exam.place : text;
  }

  private static examDistanceText(exam: EasEventItem, now: number): string {
    if (exam.from <= now) return '进行中';
    const today0: number = new Date(new Date(now).setHours(0, 0, 0, 0)).getTime();
    const days: number = Math.floor((exam.from - today0) / DAY_MS);
    if (days <= 0) return '今天';
    if (days === 1) return '明天';
    return days.toString() + ' 天后';
  }

  private static placeTeacher(event: EasEventItem): string {
    const parts: string[] = [];
    if (event.place.length > 0) parts.push(event.place);
    if (event.teacher.length > 0) parts.push(event.teacher);
    return parts.join(' · ');
  }

  private static todayChipText(event: EasEventItem, now: number): string {
    if (event.containsTimestamp(now)) return '进行中';
    if (event.to <= now) return '已结束';
    if (event.from - now <= 30 * 60000) return Home.durationText(event.from - now) + '后';
    if (event.type === EasEventType.EXAM) return '考试';
    return '';
  }

  private static todayChipColor(event: EasEventItem, now: number): ResourceColor {
    if (event.to <= now && !event.containsTimestamp(now)) return COLOR_TEXT_HINT;
    if (event.type === EasEventType.EXAM) return COLOR_EXAM;
    return COLOR_PRIMARY;
  }

  private static todayChipBg(event: EasEventItem, now: number): ResourceColor {
    if (event.to <= now && !event.containsTimestamp(now)) return $r('app.color.hita_control_f1f4f8');
    if (event.type === EasEventType.EXAM) return $r('app.color.hita_error_surface');
    return $r('app.color.hita_selected');
  }

  private static campusName(campus: EasCampus): string {
    if (campus === EasCampus.SHENZHEN) {
      return '深圳校区';
    }
    if (campus === EasCampus.BENBU) {
      return '本部';
    }
    return '威海校区';
  }

  private static campusFromCode(code: string): EasCampus {
    if (code === 'SHENZHEN') {
      return EasCampus.SHENZHEN;
    }
    if (code === 'BENBU') {
      return EasCampus.BENBU;
    }
    return EasCampus.WEIHAI;
  }

  private async openSessionSheet(): Promise<void> {
    if (this.sessionSheetLoading || !this.canOpenSheet()) {
      return;
    }
    const generation: number = ++this.sheetRequestGeneration;
    this.sessionSheetLoading = true;
    try {
      const storedCampus: EasCampus | undefined = await EasSessionStore.getInstance().loadLastCampus();
      if (generation !== this.sheetRequestGeneration || !this.canOpenSheet()) {
        return;
      }
      const campus: EasCampus = this.sessionInfo === undefined ?
        (storedCampus === undefined ? EasCampus.WEIHAI : storedCampus) : this.sessionInfo.campus;
      const session: EasSession | undefined = await EasSessionStore.getInstance().load(campus);
      if (generation !== this.sheetRequestGeneration || !this.canOpenSheet()) {
        return;
      }
      this.sessionSheetCampus = campus.toString();
      this.sessionSheetInfo = session;
      this.sessionSheetStatus = EasSessionStatus.UNKNOWN;
      this.sessionSheetOpen = true;
      this.activeSheetVisible = true;
      this.sessionSheetStatus = session?.loginExpired ? EasSessionStatus.EXPIRED : EasSessionStatus.SAVED;
    } catch (_) {
      if (generation === this.sheetRequestGeneration && this.canOpenSheet()) {
        this.getUIContext().getPromptAction().showToast({ message: '教务会话读取失败，请重试' });
      }
    } finally {
      if (generation === this.sheetRequestGeneration) {
        this.sessionSheetLoading = false;
      }
    }
  }

  private async selectSessionCampus(code: string): Promise<void> {
    if (!this.activeSheetVisible || !this.sessionSheetOpen) {
      return;
    }
    const generation: number = ++this.sheetRequestGeneration;
    this.sessionSheetCampus = code;
    this.sessionSheetInfo = undefined;
    this.sessionSheetStatus = EasSessionStatus.UNKNOWN;
    try {
      const session: EasSession | undefined = await EasSessionStore.getInstance().load(Home.campusFromCode(code));
      if (generation === this.sheetRequestGeneration && this.activeSheetVisible && this.sessionSheetOpen) {
        this.sessionSheetInfo = session;
        this.sessionSheetStatus = session?.loginExpired ? EasSessionStatus.EXPIRED : EasSessionStatus.SAVED;
      }
    } catch (_) {
      if (generation === this.sheetRequestGeneration && this.activeSheetVisible && this.sessionSheetOpen) {
        this.getUIContext().getPromptAction().showToast({ message: '教务会话读取失败，请重试' });
      }
    }
  }

  private beginSessionLogin(): void {
    if (!this.activeSheetVisible || !this.sessionSheetOpen) {
      return;
    }
    this.sheetRequestGeneration++;
    this.loginCampusCode = this.sessionSheetCampus;
    this.sessionSheetOpen = false;
    this.loginSheetOpen = true;
    this.activeSheetVisible = true;
  }

  private async logoutSession(): Promise<void> {
    const generation: number = this.sheetRequestGeneration;
    const campus: EasCampus = Home.campusFromCode(this.sessionSheetCampus);
    await EasSessionStore.getInstance().clear(campus);
    if (generation === this.sheetRequestGeneration && this.sessionSheetOpen) {
      this.sessionSheetInfo = undefined;
      this.closeActiveSheet();
    }
    await this.refreshSummaries();
    this.getUIContext().getPromptAction().showToast({ message: '已退出' + Home.campusName(campus) + '教务会话' });
  }

  build() {
    if (deviceInfo.apiAvailable('26.0.0')) {
      Stack({ alignContent: Alignment.Bottom }) {
        this.homeTabs();
        if (!deviceInfo.apiAvailable('27.0.0')) {
          DockLightOverlay({ controller: this.dockLight })
            .hitTestBehavior(HitTestMode.None)
            .onAreaChange((_old: Area, area: Area) => this.updateDockBounds(area))
            .margin({ bottom: 12 + this.navBarInset })
        }
      }
      .width('100%')
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.KEYBOARD], [SafeAreaEdge.BOTTOM])
    } else {
      // A Tabs overlay captures the page's input on API 23. Keep the dock a
      // bounded sibling so content gestures and clicks reach the original tabs.
      Stack({ alignContent: Alignment.Bottom }) {
        this.homeTabs();
        this.compatibleDock();
      }
      .width('100%')
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.KEYBOARD], [SafeAreaEdge.BOTTOM])
    }
  }

  private judgeTimetableWeekPan(info: GestureInfo, event: BaseGestureEvent): GestureJudgeResult {
    if (info.tag !== 'timetable-week') {
      return GestureJudgeResult.CONTINUE;
    }
    return this.weekGestureActive && !this.skippingCourse ? GestureJudgeResult.CONTINUE : GestureJudgeResult.REJECT;
  }

  private judgePagePan(current: GestureRecognizer, fromDock: boolean = false): GestureJudgeResult {
    const dock: boolean = fromDock || this.dockNavigation.isDock();
    if (!current.isBuiltIn()) {
      return GestureJudgeResult.CONTINUE;
    }
    if (dock && current.getType() === GestureControl.GestureType.SWIPE_GESTURE) {
      return GestureJudgeResult.REJECT;
    }
    if ((this.weekGestureActive || dock) && current.getType() === GestureControl.GestureType.PAN_GESTURE) {
      const direction: PanDirection = (current as PanRecognizer).getPanGestureOptions().getDirection();
      if (direction === PanDirection.Horizontal || direction === PanDirection.Left ||
        direction === PanDirection.Right || direction === PanDirection.All) {
        return GestureJudgeResult.REJECT;
      }
    }
    return GestureJudgeResult.CONTINUE;
  }

  private requestDockClick(index: number): void {
    const source: number = this.dockNavigation.hasDockPointer() ? this.dockPressSource : this.selectedNav;
    const sequence: number = this.dockNavigation.requestClick();
    // Native click and raw Up callback ordering varies by renderer. Wait until
    // this dispatch completes; a held gesture always uses its release target.
    setTimeout(() => {
      this.dockNavigation.commitClick(sequence, index, (target: number) => {
        if (this.dockLightEnabled() && !this.dockNavigation.isHolding()) {
          this.dockLight.transfer(source, target);
        }
        this.tabsController.changeIndex(target);
      });
    }, 0);
  }

  private clearDockHoldTimer(): void {
    if (this.dockHoldTimer >= 0) {
      clearTimeout(this.dockHoldTimer);
      this.dockHoldTimer = -1;
    }
  }

  private dockLightEnabled(): boolean {
    return deviceInfo.apiAvailable('26.0.0') && !deviceInfo.apiAvailable('27.0.0');
  }

  private updateDockHoldLight(holding: boolean): void {
    const began: boolean = holding && !this.dockHolding;
    this.dockHolding = this.dockLightEnabled() && holding;
    if (began && this.dockHolding) this.dockLight.move(this.dockLightPosition);
  }

  private resetDockInteraction(): void {
    this.clearDockHoldTimer();
    this.updateDockHoldLight(false);
    this.dockNavigation.reset();
    if (this.dockLightEnabled()) {
      this.dockLight.stop();
    }
  }

  private updateDockBounds(area: Area, padding: number = 0): void {
    this.dockNavigation.setBounds(Number(area.globalPosition.x), Number(area.globalPosition.y),
      Number(area.width), Number(area.height), padding);
  }

  private observeDockTouch(event: TouchEvent, fromDock: boolean = false): void {
    if (fromDock && event.type === TouchType.Down && event.touches.length === 1) {
      this.dockNavigation.begin(event, true);
    }
    if (!this.dockNavigation.observe(event) || !this.dockNavigation.isDock()) {
      return;
    }
    if (this.dockNavigation.isRejected()) {
      this.clearDockHoldTimer();
      this.updateDockHoldLight(false);
      if (this.dockLightEnabled()) this.dockLight.release(true);
      return;
    }
    if (event.type === TouchType.Down && event.touches.length === 1) {
      this.clearDockHoldTimer();
      this.dockPressSource = this.selectedNav;
      this.dockLightPosition = this.dockNavigation.lightPosition(event) ??
        (this.dockPressSource + 0.5) * 212 / 3;
      if (this.dockLightEnabled()) {
        this.dockLight.press(this.dockPressSource);
      }
      this.updateDockHoldLight(false);
      this.dockHoldTimer = setTimeout(() => {
        this.dockHoldTimer = -1;
        const holding: boolean = this.dockNavigation.activateHold();
        this.updateDockHoldLight(holding);
      }, DOCK_HOLD_DELAY_MS);
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.clearDockHoldTimer();
      this.updateDockHoldLight(false);
      if (this.dockLightEnabled()) {
        if (this.dockNavigation.isHolding()) {
          const x: number | undefined = this.dockNavigation.lightPosition(event);
          if (x !== undefined) this.dockLight.move(x);
        }
        this.dockLight.release(event.type === TouchType.Cancel);
      }
      const target: number = this.dockNavigation.releaseTarget();
      if (target >= 0) {
        this.requestDockClick(target);
      }
    } else {
      const x: number | undefined = this.dockNavigation.lightPosition(event);
      if (x !== undefined) this.dockLightPosition = x;
      this.updateDockHoldLight(this.dockNavigation.isHolding());
      if (this.dockHolding) {
        this.dockLight.move(this.dockLightPosition);
      }
    }
  }

  @Builder
  homeTabs() {
    Tabs({ barPosition: BarPosition.End, controller: this.tabsController, barModifier: this.dockBarModifier }) {
      TabContent() {
        Column() {
          this.tabToday();
        }
        // The list reserves the dock inset itself so cards scroll under the dock.
        .tabPage(0, COLOR_SURFACE)
      }
      .clip(false)
      .tabBar(this.dockTab($r('sys.symbol.calendar'), '今日'))

      TabContent() {
        Column() {
          this.tabTimetable();
        }
        .tabPage(0, Color.Transparent)
      }
      .clip(false)
      .tabBar(this.dockTab($r('sys.symbol.doc_plaintext'), '时间表'))

      TabContent() {
        Column() {
          this.tabMine();
        }
        .tabPage(0, COLOR_SURFACE)
      }
      .clip(false)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .tabBar(this.dockTab($r('sys.symbol.more'), '更多'))
    }
    .width('100%')
    .height('100%')
    .vertical(false)
    .barOverlap(true)
    .barMode(BarMode.Fixed)
    .barHeight(deviceInfo.apiAvailable('26.0.0') ? 56 : 0)
    .barBackgroundColor(Color.Transparent)
    .divider(null)
    // Native paging tracks the finger on every system, including over the
    // timetable header. Only the grid owns a separate week-paging gesture.
    .scrollable(true)
    .onTouchIntercept((event: TouchEvent) => {
      if (event.type === TouchType.Down && event.touches.length > 0) {
        this.dockNavigation.begin(event, false);
        // Latch the region at touch-down, before either recognizer starts.
        // Crossing the date row later cannot turn week paging into page paging.
        this.weekGestureActive = this.currentTab === TAB_TIMETABLE && this.currentTimetable !== undefined &&
          event.touches[0].windowY >= this.timetableDateBottom;
      }
      return HitTestMode.Default;
    })
    .onTouch((event: TouchEvent) => {
      this.observeDockTouch(event);
    })
    .onGestureRecognizerJudgeBegin((event: BaseGestureEvent, current: GestureRecognizer) => {
      return this.judgePagePan(current);
    }, true)
    .onTabBarClick((index: number) => {
      this.requestDockClick(index);
    })
    .onContentWillChange((currentIndex: number, comingIndex: number) => {
      return this.dockNavigation.allowsChange(comingIndex);
    })
    .animationDuration(TAB_SWIPE_MS)
    .attributeModifier(new CompatibleDockModifier(12 + this.navBarInset,
      this.selectedNav === TAB_TIMETABLE && this.hasTimetableBackground(), this.darkMode))
    .backgroundColor(this.currentTab === 1 ? Color.Transparent : COLOR_SURFACE)
    .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.KEYBOARD], [SafeAreaEdge.BOTTOM])
    .onAnimationStart((index: number, targetIndex: number, extraInfo: TabsAnimationEvent) => {
      if (index !== targetIndex) {
        this.closeActiveSheet();
      }
      this.tabTransitionRunning = true;
      this.stopTimetableMarquee();
      this.selectedNav = targetIndex;
    })
    .onAnimationEnd((index: number, extraInfo: TabsAnimationEvent) => {
      this.finishTabAnimation(index);
    })
    .onChange((index: number) => {
      this.selectTab(index);
      this.selectedNav = index;
    })
    .bindSheet($$this.activeSheetVisible, this.activeSheet(), CompatibleSheetMaterial.options({
      height: this.widgetBackgroundSheetOpen || this.importTimetableSheetOpen || this.academicPanelOpen ? SheetSize.LARGE :
        (this.loginSheetOpen ? SheetSize.LARGE : SheetSize.FIT_CONTENT),
      // The first detent is the initial selection, so start expanded and allow collapsing to medium.
      detents: this.widgetBackgroundSheetOpen || this.importTimetableSheetOpen || this.academicPanelOpen ?
        [SheetSize.LARGE, SheetSize.MEDIUM] : undefined,
      scrollSizeMode: this.widgetBackgroundSheetOpen || this.importTimetableSheetOpen || this.academicPanelOpen ?
        ScrollSizeMode.CONTINUOUS : undefined,
      dragBar: true,
      // Every sheet owns its header control; the system close bubble overlaps
      // the web login toolbar's trailing actions.
      showClose: false,
      preferType: SheetType.BOTTOM,
      backgroundColor: COLOR_SURFACE,
      maskColor: $r('app.color.hita_sheet_mask'),
      shouldDismiss: this.widgetBackgroundSheetOpen ? (sheetDismiss: SheetDismiss) => {
        this.confirmWidgetBackgroundDismiss(() => sheetDismiss.dismiss());
      } : undefined,
      onWillSpringBackWhenDismiss: this.widgetBackgroundSheetOpen ? (springBack: SpringBackAction) => {
        // Defer the rebound until confirmation is declined; successful dismissals close directly.
        this.widgetBackgroundSpringBack = () => springBack.springBack();
      } : undefined,
      onWillDisappear: () => {
        this.closeActiveSheet();
      },
      onDisappear: () => {
        // Keep content and height stable until the dismissal animation finishes.
        this.activeSheetVisible = false;
        this.sessionSheetOpen = false;
        this.loginSheetOpen = false;
        this.widgetBackgroundSheetOpen = false;
        this.importTimetableSheetOpen = false;
        this.academicPanelOpen = false;
        this.academicPanelKind = 0;
        this.widgetBackgroundDirty = false;
        this.widgetBackgroundBusy = false;
        this.widgetBackgroundConfirmDismiss = undefined;
        this.widgetBackgroundSpringBack = undefined;
        this.courseSheetOpen = false;
        this.timetableDisplayOpen = false;
        this.selectedCourse = undefined;
        this.calendarExportSheetOpen = false;
        this.calendarExportTimetable = undefined;
        this.finishCourseSheetDismissal();
      }
    }, this.loginSheetOpen || this.sessionSheetOpen || this.courseSheetOpen || this.timetableDisplayOpen ||
      this.calendarExportSheetOpen || this.widgetBackgroundSheetOpen || this.importTimetableSheetOpen ||
      this.academicPanelOpen,
    !this.timetableDisplayOpen));
  }

  @Builder
  compatibleDock() {
    if (!deviceInfo.apiAvailable('26.0.0')) {
      FrostedDock({
        selectedIndex: this.selectedNav,
        bottomInset: this.navBarInset,
        darkMode: this.darkMode,
        hideMask: this.selectedNav === TAB_TIMETABLE && this.hasTimetableBackground(),
        onDockAreaChanged: (area: Area) => this.updateDockBounds(area, 4),
        onDockTouch: (event: TouchEvent) => {
          this.dockNavigation.begin(event, true);
          this.observeDockTouch(event, true);
        },
        onSelect: (index: number) => {
          this.requestDockClick(index);
        }
      })
    }
  }

  @Builder
  activeSheet() {
    SheetContent({ fillHeight: this.loginSheetOpen || this.widgetBackgroundSheetOpen || this.importTimetableSheetOpen ||
      this.academicPanelOpen }) {
      if (this.loginSheetOpen) {
        EasLoginPage({
          campusCode: this.loginCampusCode,
          studentType: '1',
          onCancel: () => {
            this.closeActiveSheet();
          },
          onLoggedIn: (session: EasSession) => {
            if (!this.activeSheetVisible || !this.loginSheetOpen) {
              return;
            }
            this.closeActiveSheet();
            this.sessionSheetInfo = session;
            this.refreshSummaries();
          }
        })
          .width('100%')
          .height('100%')
          .attributeModifier(new CompatibleLightModifier(24, CompatibleSheetMaterial.isEnabled(), true));
      } else if (this.widgetBackgroundSheetOpen) {
        WidgetBackgroundPage({
          onBackgroundChanged: (enabled: boolean) => {
            this.widgetBackgroundSet = enabled;
          },
          onDirtyChanged: (dirty: boolean) => {
            this.widgetBackgroundDirty = dirty;
          },
          onBusyChanged: (busy: boolean) => {
            this.widgetBackgroundBusy = busy;
          },
          onConfirmDismissReady: (confirm: (dismiss: () => void, springBack: () => void) => void) => {
            this.widgetBackgroundConfirmDismiss = confirm;
          },
          onClose: () => {
            this.closeActiveSheet();
          }
        })
          .width('100%')
          .height('100%');
      } else if (this.importTimetableSheetOpen) {
        ImportTimetablePanel({
          presentedAsSheet: true,
          onClose: () => this.closeActiveSheet(),
          onImported: () => { void this.refreshSummaries(); }
        })
          .width('100%')
          .height('100%');
      } else if (this.academicPanelOpen && this.academicPanelKind === 1) {
        ExamPage({ presentedAsSheet: true, onClose: () => this.closeActiveSheet() })
          .width('100%').height('100%');
      } else if (this.academicPanelOpen && this.academicPanelKind === 2) {
        ScorePage({ presentedAsSheet: true, onClose: () => this.closeActiveSheet() })
          .width('100%').height('100%');
      } else if (this.academicPanelOpen && this.academicPanelKind === 3) {
        CreditPage({ presentedAsSheet: true, onClose: () => this.closeActiveSheet() })
          .width('100%').height('100%');
      } else if (this.academicPanelOpen && this.academicPanelKind === 4) {
        EmptyClassroomPage({ presentedAsSheet: true, onClose: () => this.closeActiveSheet() })
          .width('100%').height('100%');
      } else if (this.timetableDisplayOpen) {
        TimetableDisplaySettings({
          options: this.timetableDisplay,
          textColor: this.timetableTextColor,
          darkMode: this.darkMode,
          hasWallpaper: this.hasTimetableBackground(),
          adaptiveTextColor: this.timetableBackdrop.titleText,
          adaptiveLineColor: this.timetableBackdrop.linePicker,
          onSave: async (options: TimetableDisplayOptions) => { await this.saveTimetableDisplay(options); },
          onTextColorSave: async (color: string) => { await this.setTimetableTextColor(color); },
          onMaskPreview: (value: number) => {
            this.timetableMaskDepth = value;
            this.drawTimetableNow();
          },
          onClose: () => { this.closeActiveSheet(); }
        })
      } else if (this.courseSheetOpen && this.selectedCourse !== undefined) {
        this.courseDetailSheet(this.selectedCourse as EasEventItem);
      } else if (this.calendarExportSheetOpen && this.calendarExportTimetable !== undefined) {
        this.calendarExportConfirmationSheet(this.calendarExportTimetable as EasTimetable);
      } else if (this.sessionSheetOpen) {
        this.sessionSheet();
      }
    }
  }

  @Builder
  calendarExportConfirmationSheet(timetable: EasTimetable) {
    Column() {
      Text('导出至手机日历')
        .fontSize(21)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLOR_TEXT_PRIMARY)
        .width('100%')
        .margin({ bottom: 20 });

      Text(timetable.name)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor(COLOR_TEXT_PRIMARY)
        .width('100%')
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis });
      Text('将此课表的日程写入系统日历。再次导出会更新此课表已导出的日程。')
        .fontSize(14)
        .fontColor(COLOR_TEXT_SECONDARY)
        .lineHeight(22)
        .width('100%')
        .margin({ top: 8, bottom: 24 });

      ImmersiveHeader({ barHeight: 46 }) {
        Row({ space: 12 }) {
          Button('取消', { type: ButtonType.Capsule })
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(CompatibleMaterialModifier.foreground(COLOR_TEXT_SECONDARY))
            .backgroundColor($r('app.color.hita_control'))
            .height(46)
            .width(0)
            .layoutWeight(1)
            .borderRadius(23)
            .attributeModifier(new CompatibleMaterialModifier($r('app.color.hita_control')))
            .enabled(!this.calendarExporting)
            .onClick(() => this.cancelCalendarExport());
          Button('确认导出', { type: ButtonType.Capsule })
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(CompatibleMaterialModifier.foreground('#FFFFFF'))
            .backgroundColor($r('app.color.hita_primary_fill'))
            .height(46)
            .width(0)
            .layoutWeight(1)
            .borderRadius(23)
            .attributeModifier(new CompatibleMaterialModifier($r('app.color.hita_primary_fill')))
            .enabled(!this.calendarExporting)
            .onClick(() => this.exportToCalendar());
        }
        .width('100%');
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 20, right: 20, top: 0, bottom: 20 })
    .attributeModifier(new CompatibleLightModifier(24, CompatibleSheetMaterial.isEnabled(), true));
  }

  @Builder
  tabToday() {
    Column() {
      this.todayHeader();

      List({ space: 12 }) {
        ListItem() {
          Column() {
            ImmersiveHeader({ barHeight: this.todayHeroHeight() }) {
              this.todayHeroCard();
            }
          }
          .width('100%')
          .borderRadius(24)
          .clip(true)
        }

        if (this.upcomingExam() !== undefined) {
          ListItem() {
            this.todayExamCard(this.upcomingExam() as EasEventItem);
          }
        }

        if (!this.hasTimetable) {
          ListItem() {
            this.todayNoTimetable();
          }
        } else if (this.todayItems.length > 0) {
          ListItem() {
            this.todaySectionHeader();
          }
          ForEach(this.todayItems, (event: EasEventItem) => {
            ListItem() {
              if (CompatibleSheetMaterial.isEnabled()) {
                ImmersiveEventCard({ content: () => { this.todayEventRow(event, true); } })
                  .opacity(event.to <= this.nowTick ? 0.55 : 1)
              } else {
                this.todayEventRow(event);
              }
            }
          }, (event: EasEventItem) => Home.todayItemKey(event));
        }
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 16, right: 16 })
      // Reach the screen bottom; the last card still clears the dock when scrolled to the end.
      .contentStartOffset(8)
      .contentEndOffset(this.dockPageInset() + 16)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  todayHeader() {
    Column() {
      Text(Home.greeting(this.nowTick))
        .fontSize(13)
        .fontColor(COLOR_TEXT_SECONDARY);
      Row() {
        Text((new Date(this.nowTick).getMonth() + 1).toString() + '月' +
          new Date(this.nowTick).getDate().toString() + '日')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLOR_TEXT_PRIMARY);
        Text(DOW_FULL[EasTimeTools.getDow(this.nowTick)])
          .fontSize(15)
          .fontColor(COLOR_TEXT_SECONDARY)
          .margin({ left: 10, bottom: 3 });
        Blank();
        if (this.currentWeekNumber() > 0) {
          Text('第 ' + this.currentWeekNumber().toString() + ' 周')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLOR_PRIMARY)
            .backgroundColor(COLOR_NAV_ACTIVE)
            .borderRadius(13)
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .margin({ bottom: 2 });
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
      .margin({ top: 2 });
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 20, right: 20, top: 12 + this.statusBarInset, bottom: 4 });
  }

  @Builder
  todayHeroCard() {
    Column() {
      Row() {
        Text(this.heroTag())
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .backgroundColor($r('app.color.hita_hero_chip'))
          .borderRadius(11)
          .padding({ left: 9, right: 9, top: 3, bottom: 3 });
        Blank();
        if (this.todayClassCount() > 0) {
          Text('已上 ' + this.completedClassCount().toString() + ' / ' + this.todayClassCount().toString() + ' 节')
            .fontSize(12)
            .fontColor('#DCEEFF');
        }
      }
      .width('100%');

      if (this.heroEvent() !== undefined) {
        Text((this.heroEvent() as EasEventItem).name)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 12 });
        Text(Home.placeTeacher(this.heroEvent() as EasEventItem).length > 0 ?
          Home.placeTeacher(this.heroEvent() as EasEventItem) : '地点未填写')
          .fontSize(13)
          .fontColor('#DCEEFF')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 4 });
        Blank();
        Row() {
          Text() {
            Span(this.heroMinutesLeft() >= 60 ? Math.floor(this.heroMinutesLeft() / 60).toString() : '')
              .fontSize(30)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF');
            Span(this.heroMinutesLeft() >= 60 ? ' 小时 ' : '')
              .fontSize(13)
              .fontColor('#DCEEFF');
            Span((this.heroMinutesLeft() % 60).toString())
              .fontSize(30)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF');
            Span(' 分钟' + this.heroCountdownSuffix())
              .fontSize(13)
              .fontColor('#DCEEFF');
          }
          Blank();
          Text(EasTimeTools.printTime((this.heroEvent() as EasEventItem).from) + ' - ' +
            EasTimeTools.printTime((this.heroEvent() as EasEventItem).to))
            .fontSize(13)
            .fontColor('#FFFFFF')
            .margin({ bottom: 5 });
        }
        .width('100%')
        .alignItems(VerticalAlign.Bottom);
        if (this.activeClass !== undefined) {
          Progress({ value: this.activeClass.getProgress(this.nowTick) * 100, total: 100, type: ProgressType.Linear })
            .width('100%')
            .height(5)
            .color('#FFFFFF')
            .backgroundColor($r('app.color.hita_hero_chip'))
            .margin({ top: 10 });
        }
      } else {
        Text(this.heroIdleTitle())
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .margin({ top: 12 });
        Blank();
        Row() {
          SymbolGlyph($r('sys.symbol.calendar'))
            .fontSize(15)
            .fontColor(['#DCEEFF']);
          Text(this.tomorrowText())
            .fontSize(13)
            .fontColor('#FFFFFF')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .margin({ left: 6 });
        }
        .width('100%');
      }
    }
    .width('100%')
    .height(this.todayHeroHeight())
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 18, right: 18, top: 16, bottom: 16 })
    .backgroundColor($r('app.color.hita_primary_fill'))
    .borderRadius(24)
    .attributeModifier(new CompatibleMaterialModifier($r('app.color.hita_primary_fill'), true));
  }

  @Builder
  todayExamCard(exam: EasEventItem) {
    Row() {
      Row()
        .width(4)
        .height(38)
        .borderRadius(2)
        .backgroundColor(COLOR_EXAM);
      Column() {
        Text(exam.name)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(Home.examWhenText(exam))
          .fontSize(12)
          .fontColor(COLOR_TEXT_SECONDARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 4 });
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12, right: 12 });
      Text(Home.examDistanceText(exam, this.nowTick))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(COLOR_EXAM)
        .backgroundColor($r('app.color.hita_error_surface'))
        .borderRadius(13)
        .padding({ left: 10, right: 10, top: 5, bottom: 5 });
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 14, bottom: 14 })
    .backgroundColor(COLOR_CARD)
    .borderRadius(16)
    .border({ width: 1, color: $r('app.color.hita_divider_edf1f7') })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.getUIContext().getRouter().pushUrl({ url: 'pages/ExamPage' });
    });
  }

  @Builder
  todaySectionHeader() {
    Row() {
      Text('今日安排')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(COLOR_TEXT_PRIMARY);
      Blank();
      Text(this.todayItems.length.toString() + ' 项')
        .fontSize(12)
        .fontColor(COLOR_TEXT_HINT);
    }
    .width('100%')
    .padding({ left: 4, right: 4, top: 4 });
  }

  @Builder
  todayNoTimetable() {
    Column() {
      Text('还没有课表')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(COLOR_TEXT_PRIMARY);
      Text('登录教务导入，或在课表管理里手动创建')
        .fontSize(13)
        .fontColor(COLOR_TEXT_SECONDARY)
        .margin({ top: 6, bottom: 16 });
      this.emptyTimetableActions();
    }
    .width('100%')
    .padding({ top: 28, bottom: 28 })
    .alignItems(HorizontalAlign.Center);
  }

  @Builder
  todayEventRow(event: EasEventItem, immersive: boolean = false) {
    Row() {
      Row()
        .width(4)
        .height(38)
        .borderRadius(2)
        .backgroundColor(event.type === EasEventType.CLASS ?
          Home.canvasColorCss(timetableBlockColor(event.color)) : Home.eventColor(event.type));

      Column() {
        Text(EasTimeTools.printTime(event.from))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT_PRIMARY);
        Text(EasTimeTools.printTime(event.to))
          .fontSize(12)
          .fontColor(COLOR_TEXT_HINT)
          .margin({ top: 2 });
      }
      .width(52)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 });

      Column() {
        Row() {
          Text(event.name)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(event.type === EasEventType.EXAM ? COLOR_EXAM : COLOR_TEXT_PRIMARY)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
          if (Home.todayChipText(event, this.nowTick).length > 0) {
            Text(Home.todayChipText(event, this.nowTick))
              .fontSize(11)
              .fontColor(Home.todayChipColor(event, this.nowTick))
              .backgroundColor(Home.todayChipBg(event, this.nowTick))
              .borderRadius(9)
              .padding({ left: 7, right: 7, top: 3, bottom: 3 })
              .margin({ left: 8 });
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center);
        if (Home.placeTeacher(event).length > 0) {
          Text(Home.placeTeacher(event))
            .fontSize(12)
            .fontColor(COLOR_TEXT_SECONDARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 5 });
        }
        if (event.containsTimestamp(this.nowTick)) {
          Progress({ value: event.getProgress(this.nowTick) * 100, total: 100, type: ProgressType.Linear })
            .width('100%')
            .height(3)
            .color(COLOR_PRIMARY)
            .backgroundColor($r('app.color.hita_selected_e8f1fb'))
            .margin({ top: 8 });
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 });
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 14, bottom: 14 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(immersive ? Color.Transparent : COLOR_CARD)
    .borderRadius(16)
    .border({ width: event.containsTimestamp(this.nowTick) ? 1.5 : 1,
      color: event.containsTimestamp(this.nowTick) ? $r('app.color.hita_focus') : $r('app.color.hita_divider_edf1f7') })
    .clip(true)
    .opacity(!immersive && event.to <= this.nowTick ? 0.55 : 1)
    .hitTestBehavior(immersive ? HitTestMode.Transparent : HitTestMode.Default)
    .margin({ bottom: immersive ? 0 : 2 });
  }

  @Builder
  emptyTimetableActions() {
    Row({ space: 10 }) {
      Button(this.sessionInfo === undefined ? '登录教务' : '导入课表')
        .fontSize(14)
        .height(40)
        .fontColor('#FFFFFF')
        .backgroundColor($r('app.color.hita_primary_fill'))
        .borderRadius(20)
        .onClick(() => {
          if (this.sessionInfo === undefined) {
            this.openSessionSheet();
          } else {
            this.getUIContext().getRouter().pushUrl({ url: 'pages/ImportTimetablePage' });
          }
        });
      Button('课表管理')
        .fontSize(14)
        .height(40)
        .fontColor(COLOR_PRIMARY)
        .backgroundColor(COLOR_NAV_ACTIVE)
        .borderRadius(20)
        .onClick(() => {
          this.getUIContext().getRouter().pushUrl({ url: 'pages/TimetableManagerPage' });
        });
    }
  }

  @Builder
  timetableDateHeader() {
    Row() {
      Text(this.timetableHeaderMonth())
        .width(TIMETABLE_GUTTER_WIDTH)
        .fontSize(11)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.timetableInk('date'))
        .textAlign(TextAlign.Center)
      ForEach(DOW_NAMES, (name: string, dayIndex: number) => {
        Column() {
          Text(name)
            .fontSize(this.timetableHeaderIsToday(dayIndex) ? 11 : 10)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.timetableInk('date'))
          Text(this.timetableHeaderDate(dayIndex))
            .fontSize(10)
            .fontColor(this.timetableInk('date'))
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.timetableHeaderIsToday(dayIndex) ? this.timetableBackdrop.todayHeader : Color.Transparent)
      }, (name: string, dayIndex: number) => dayIndex.toString() + name)
    }
    .width('100%')
    .height(TIMETABLE_HEADER_HEIGHT)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(Color.Transparent)
    .onAreaChange((oldValue: Area, newValue: Area) => {
      this.timetableDateBottom = (newValue.globalPosition.y as number) + (newValue.height as number);
    })
  }

  @Builder
  tabTimetable() {
    Stack({ alignContent: Alignment.Top }) {
      if (this.hasTimetableBackground()) {
        Image(this.timetableBgUri)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .hitTestBehavior(HitTestMode.None)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        if (this.timetableVideoUri.length > 0 && !this.timetableVideoFailed &&
          this.pageVisible && this.appForeground && this.currentTab === TAB_TIMETABLE) {
          TimetableVideoBackground({
            source: this.timetableVideoUri,
            onPlaybackError: () => {
              this.timetableVideoFailed = true;
              this.getUIContext().getPromptAction().showToast({ message: '当前视频无法播放，已显示静态封面' });
            }
          })
        }
        Row()
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Black)
          .opacity(this.timetableMaskDepth / 100)
          .hitTestBehavior(HitTestMode.None)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      }

      if (this.currentTimetable === undefined) {
        Column() {
          Blank().height(this.timetableChromeH);
          Column() {
            Text('还没有课表数据')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.timetableInk())
            Text('暂无已导入或手动创建的课表')
              .fontSize(13)
              .fontColor(this.timetableInk())
              .margin({ top: 8, bottom: 16 })
            this.emptyTimetableActions();
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .padding(24);
        }
        .width('100%')
        .height('100%');
      } else {
        Stack({ alignContent: Alignment.Top }) {
          // Today column lives outside the scroll and starts below the date header,
          // so scrolled content never adds a second tint under the header's today cell.
          if (this.timetableTodayColumn() >= 0) {
            Column()
              .width(this.timetableTodayColumnWidth())
              .height(this.timetableTodayMaskVisibleHeight())
              .position({
                x: TIMETABLE_GUTTER_WIDTH + this.timetableTodayColumn() * this.timetableTodayColumnWidth(),
                y: this.timetableChromeH
              })
              .backgroundColor(this.timetableBackdrop.todayHeader)
              .hitTestBehavior(HitTestMode.None)
          }
          Scroll(this.timetableScroller) {
            Column() {
              Blank().height(this.timetableChromeH);
              Stack({ alignContent: Alignment.TopStart }) {
                Canvas(this.timetableCanvas)
                  .width('100%')
                  .height('100%')
                  .backgroundColor(Color.Transparent)
                  .hitTestBehavior(HitTestMode.None)
                  .onReady(() => {
                    this.drawTimetableNow();
                  })
                TimetableCardMaterials({
                  cards: this.timetableCardSurfaces,
                  contentHeight: this.timetableCanvasHeight,
                  painter: this.timetableCardPainter,
                  deleteEffects: this.courseDeleteEffects,
                  onCardClick: (key: string) => this.openCourseCard(key)
                })
              }
              .width('100%')
              .height(this.timetableCanvasHeight)
              .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
              // Keep the grid hit target when a native material host does not dispatch its card's click.
              .onClick((event: ClickEvent) => {
                this.openCourseAt(event.x, event.y);
              })
              .onDisAppear(() => {
                this.stopTimetableMarquee();
              })
            }
            .width('100%')
          }
          .width('100%')
          .height('100%')
          .scrollable(ScrollDirection.Vertical)
          .scrollBar(BarState.Off)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
          .onDidScroll(() => {
            this.timetableScrollY = this.timetableScroller.currentOffset().yOffset;
            this.updateEveningCourseHint();
            if (this.hasTimetableBackground()) {
              this.timetableFadeOpacity = 0;
              return;
            }
            this.timetableFadeOpacity = HeaderFade.opacity(this.timetableScroller.currentOffset().yOffset);
          })

          if (!this.hasTimetableBackground()) {
            HeaderFadeMask({
              maskOpacity: this.timetableFadeOpacity,
              rgb: COLOR_SURFACE_RGB,
              headerHeight: this.timetableChromeH,
              // Under the header the fade uses page + today tint, so the fixed today
              // column below stays one even tint instead of a washed-out second band.
              highlight: this.timetableTodayColumn() >= 0 ? this.timetableBackdrop.todayHeader : 0,
              highlightLeft: TIMETABLE_GUTTER_WIDTH + this.timetableTodayColumn() * this.timetableTodayColumnWidth(),
              highlightWidth: this.timetableTodayColumnWidth(),
              highlightTop: this.timetableChromeH,
              maskWidth: this.timetableAreaW
            });
          }
        }
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
        .clip(false)
        .onAreaChange((oldValue: Area, newValue: Area) => {
          const width: number = newValue.width as number;
          const height: number = newValue.height as number;
          if (width !== this.timetableAreaW || height !== this.timetableAreaH) {
            this.onTimetableArea(width, height);
          }
        })
        .translate({ x: this.timetableDragOffset, y: 0 })
        .opacity(this.timetableOpacity())
        .animation({ duration: this.timetableAnimationDuration, curve: Curve.EaseOut })
        .priorityGesture(
          PanGesture({ direction: PanDirection.Horizontal, distance: 10 })
            .tag('timetable-week')
            .onActionUpdate((event: GestureEvent) => {
              this.handleTimetablePanUpdate(event);
            })
            .onActionEnd((event: GestureEvent) => {
              this.handleTimetablePanEnd(event);
            })
            .onActionCancel(() => {
              if (!this.timetableAnimating) {
                this.animateTimetableSnapBack();
              }
            })
        )
        .onGestureJudgeBegin((info: GestureInfo, event: BaseGestureEvent) => {
          return this.judgeTimetableWeekPan(info, event);
        });
      }

      Column() {
        ImmersiveHeader({ barHeight: 110 }) {
          Row() {
            Column() {
              Text(this.currentTimetable === undefined ? '时间表' :
                '第' + this.timetableWeek.toString() + '周')
                .fontSize(34)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.timetableInk())
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.timetableCampusTerm())
                .fontSize(15)
                .fontColor(this.timetableInk())
                .backgroundColor(Color.Transparent)
                .borderRadius(12)
                .padding({ left: 11, right: 11, top: 5, bottom: 5 })
                .margin({ top: 7 })
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            .backgroundColor(Color.Transparent)

            Button({ type: ButtonType.Circle }) {
              SymbolGlyph($r('sys.symbol.plus'))
                .fontSize(20)
                .fontColor([CompatibleMaterialModifier.foreground(COLOR_PRIMARY)]);
            }
            .width(44)
            .height(44)
            .backgroundColor(COLOR_NAV_ACTIVE)
            .attributeModifier(new CompatibleMaterialModifier(COLOR_NAV_ACTIVE))
            .flexShrink(0)
            .margin({ left: 8 })
            .accessibilityText('添加课程')
            .onClick(() => this.openAddCourse())

            Button({ type: ButtonType.Circle }) {
              SymbolGlyph($r('sys.symbol.slider_horizontal_2'))
                .fontSize(20)
                .fontColor([CompatibleMaterialModifier.foreground(COLOR_PRIMARY)]);
            }
            .width(44)
            .height(44)
            .backgroundColor(COLOR_NAV_ACTIVE)
            .attributeModifier(new CompatibleMaterialModifier(COLOR_NAV_ACTIVE))
            .flexShrink(0)
            .margin({ left: 8 })
            .accessibilityText('时间表显示设置')
            .onClick(() => {
              if (this.canOpenSheet()) {
                this.timetableDisplayOpen = true;
                this.activeSheetVisible = true;
              }
            })

            Button({ type: ButtonType.Circle }) {
              SymbolGlyph($r('sys.symbol.picture'))
                .fontSize(20)
                .fontColor([CompatibleMaterialModifier.foreground(COLOR_PRIMARY)]);
            }
            .width(44)
            .height(44)
            .backgroundColor(COLOR_NAV_ACTIVE)
            .attributeModifier(new CompatibleMaterialModifier(COLOR_NAV_ACTIVE))
            .flexShrink(0)
            .margin({ left: 8 })
            .accessibilityText('选择时间表背景')
            .onClick(() => {
              this.onTimetableBackgroundTap();
            })
          }
          .width('100%')
          .padding({ left: 20, right: 18, top: 16, bottom: 10 })
          .alignItems(VerticalAlign.Center)
          .backgroundColor(Color.Transparent)
        }

        if (this.currentTimetable !== undefined) {
          this.timetableDateHeader()
        }
      }
      .width('100%')
      .padding({ top: this.statusBarInset })
      .backgroundColor(Color.Transparent)
      .onAreaChange((oldValue: Area, newValue: Area) => {
        const height: number = newValue.height as number;
        if (height > 0 && height !== this.timetableChromeH) {
          this.timetableChromeH = height;
          if (this.timetableAreaW > 0 && this.timetableAreaH > 0) {
            this.onTimetableArea(this.timetableAreaW, this.timetableAreaH);
          }
        }
      })

      TimetableFloatingActions({
        active: this.pageVisible && this.currentTab === TAB_TIMETABLE,
        eveningVisible: this.currentTimetable !== undefined && this.showEveningCourseHint,
        returnVisible: this.showReturnToCurrentWeek(),
        returnEnabled: !this.timetableAnimating,
        interactionBlocked: this.tabTransitionRunning || this.timetableAnimating || this.activeSheetVisible,
        bottomInset: this.dockPageInset(),
        onEvening: (): void => { this.timetableScroller.scrollEdge(Edge.Bottom, { velocity: 1200 }); },
        onReturn: (): void => { this.returnToCurrentWeek(); }
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLOR_SURFACE)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onAreaChange((oldValue: Area, newValue: Area) => {
      const width = newValue.width as number;
      const height = newValue.height as number;
      if (width > 0 && height > 0 && (width !== this.timetableViewportW || height !== this.timetableViewportH)) {
        this.timetableViewportW = width;
        this.timetableViewportH = height;
        this.drawTimetableNow();
      }
    })
  }

  @Builder
  statusBanner(message: string, background: ResourceColor, foreground: ResourceColor) {
    Row() {
      Text('•')
        .fontSize(18)
        .fontColor(foreground)
      Text(message)
        .fontSize(12)
        .fontColor(foreground)
        .layoutWeight(1)
        .margin({ left: 8 })
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .backgroundColor(background)
    .borderRadius(8)
    .margin({ left: 16, right: 16, top: 10 })
  }

  @Builder
  tabMine() {
    Stack({ alignContent: Alignment.Top }) {
      Scroll(this.moreScroller) {
        Column() {
          Blank().height(MORE_HEADER_HEIGHT + this.statusBarInset);
          this.userCard();

          Row() {
            this.moreShortcut({
              symbol: $r('sys.symbol.calendar'),
              title: '最近课表',
              subtitle: this.recentTimetable === undefined ? '暂无课表' : this.recentTimetable.name,
              action: () => {
                if (this.recentTimetable !== undefined) {
                  this.getUIContext().getRouter().pushUrl({
                    url: 'pages/TimetableDetailPage',
                    params: { 'timetableId': this.recentTimetable.id }
                  });
                }
              }
            });
            Blank().width(8);
            this.moreShortcut({
              symbol: $r('sys.symbol.doc_plaintext'),
              title: '课表管理',
              subtitle: this.timetableCount === 0 ? '暂无课表' : '共 ' + this.timetableCount.toString() + ' 张课表',
              action: () => {
                this.getUIContext().getRouter().pushUrl({ url: 'pages/TimetableManagerPage' });
              }
            });
          }
          .width('100%')
          .padding({ top: 8 });

          this.moreSectionTitle('课表工具');
          Column() {
            this.desktopWidgetSettings();
            this.moreNavigationRow($r('sys.symbol.repeat_1'), '导入课表',
              this.importing ? '正在从教务系统同步' : '从教务系统同步当前学期', () => {
                this.openImportTimetableSheet();
              });
            this.moreNavigationRow($r('sys.symbol.doc_plaintext'), '导入 ICS 课表',
              '从日历文件导入课程', () => {
                this.importIcsTimetable();
              });
            this.moreNavigationRow($r('sys.symbol.calendar'),
              this.calendarExporting ? '正在导出至手机日历…' : '导出至手机日历',
              this.currentTimetable === undefined ? '暂无课表' : this.currentTimetable.name, () => {
                this.requestCalendarExport();
              });
          }
          .width('100%')
          .padding({ top: 4, bottom: 4 })
          .backgroundColor(COLOR_CARD)
          .borderRadius(16);

          this.moreSectionTitle('教务功能');
          Column() {
            this.moreNavigationRow($r('sys.symbol.calendar'), '考试',
              '查询教务考试或手动添加安排', () => {
                this.openAcademicPanel(1);
              });
            this.moreNavigationRow($r('sys.symbol.doc_plaintext'), '成绩管理',
              '按学期查询成绩、官方统计与本地均分', () => {
                this.openAcademicPanel(2);
              });
            this.moreNavigationRow($r('sys.symbol.graduationcap'), '学分查询',
              '培养方案完成度与分类学分统计', () => {
                this.openAcademicPanel(3);
              });
            this.moreNavigationRow($r('sys.symbol.magnifyingglass'), '空教室',
              '查询可用教室与空闲时段', () => {
                this.openAcademicPanel(4);
              });
          }
          .width('100%')
          .padding({ top: 4, bottom: 4 })
          .backgroundColor(COLOR_CARD)
          .borderRadius(16);

          this.moreSectionTitle('更多');
          Column() {
            this.moreNavigationRow($r('sys.symbol.AI_message'), '助手',
              '课表问答', () => {
                this.getUIContext().getRouter().pushUrl({ url: 'pages/AssistantPage' });
              });
            this.moreNavigationRow($r('sys.symbol.doc_text'), '资讯',
              '博客与通知', () => {
                this.getUIContext().getRouter().pushUrl({ url: 'pages/NewsPage' });
              });
            this.moreNavigationRow($r('sys.symbol.link'), '常用入口',
              '校园网站与课程攻略', () => {
                this.getUIContext().getRouter().pushUrl({ url: 'pages/PortalsPage' });
              });
          }
          .width('100%')
          .padding({ top: 4, bottom: 4 })
          .backgroundColor(COLOR_CARD)
          .borderRadius(16);

          this.moreSectionTitle('设置');
          Column() {
            this.classReminderSettings();
            this.appearanceSettings();
            this.moreNavigationRow($r('sys.symbol.doc_plaintext'), '公告',
              '版本更新 · 服务与故障通知', () => {
                this.getUIContext().getRouter().pushUrl({ url: 'pages/NoticesPage' });
              });
          }
          .width('100%')
          .padding({ top: 4, bottom: 4 })
          .backgroundColor(COLOR_CARD)
          .borderRadius(16);

          Blank().height(this.dockPageInset() + 20);
        }
        .width('100%')
        // Single source of truth for the tab's horizontal inset: every card,
        // title and shortcut row below spans this padded content area.
        .padding({ left: 16, right: 16 });
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .onDidScroll(() => {
        this.moreHeaderMaskOpacity = HeaderFade.opacity(this.moreScroller.currentOffset().yOffset);
      });

      // 内容滚入抬头下方时淡入；由下至上不透明度渐高，标题区完全遮住下层内容。
      HeaderFadeMask({
        maskOpacity: this.moreHeaderMaskOpacity,
        rgb: COLOR_SURFACE_RGB,
        headerHeight: MORE_HEADER_HEIGHT + this.statusBarInset
      });

      Row() {
        Text('功能中心')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .width('100%')
      .height(MORE_HEADER_HEIGHT + this.statusBarInset)
      .padding({ left: 16, right: 16, top: this.statusBarInset })
      .alignItems(VerticalAlign.Center)
      .hitTestBehavior(HitTestMode.Transparent);
    }
    .width('100%')
    .height('100%');
  }

  private openDesktopWidgetManager(): void {
    try {
      formProvider.openFormManager({
        bundleName: 'cn.berry.hitanext',
        abilityName: 'NextClassFormAbility',
        parameters: {
          'ohos.extra.param.key.form_dimension': 2,
          'ohos.extra.param.key.form_name': 'NextClassCard',
          'ohos.extra.param.key.module_name': 'entry'
        }
      });
    } catch (_) {
      this.getUIContext().getPromptAction().showToast({ message: '请长按桌面 HITA 图标，选择服务卡片' });
    }
  }

  /** 与课表详情中点击课程展开的二级菜单相同：分隔线下逐行列出单一选项。 */
  @Builder
  desktopWidgetSettings() {
    Column() {
      Row() {
        Stack() {
          SymbolGlyph($r('sys.symbol.clock'))
            .fontSize(22)
            .fontColor([COLOR_PRIMARY]);
        }
        .width(40)
        .height(40)
        .borderRadius(20)
        .alignContent(Alignment.Center)
        .backgroundColor(COLOR_NAV_ACTIVE);
        Column() {
          Text('桌面服务卡片')
            .fontSize(14)
            .fontColor(COLOR_TEXT_PRIMARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
          Text('下一节课倒计时')
            .fontSize(12)
            .fontColor(COLOR_TEXT_SECONDARY)
            .margin({ top: 2 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 12 });
        Text('›')
          .fontSize(23)
          .fontColor(COLOR_TEXT_SECONDARY)
          .rotate({ angle: this.widgetMenuExpanded ? 90 : 0 });
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)
      .accessibilityDescription(this.widgetMenuExpanded ? '已展开' : '已收起')
      .onClick(() => {
        this.getUIContext().animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
          this.widgetMenuExpanded = !this.widgetMenuExpanded;
        });
      });
      if (this.widgetMenuExpanded) {
        Column() {
          Divider()
            .color($r('app.color.hita_divider_eef1f6'))
            .margin({ left: 16, right: 16 });
          Row() {
            Text('设置桌面服务卡片')
              .fontSize(13)
              .fontColor(COLOR_TEXT_SECONDARY)
              .layoutWeight(1)
              .maxLines(1);
            Text('›')
              .fontSize(20)
              .fontColor($r('app.color.hita_text_hint_b2b8c4'))
              .margin({ left: 6 });
          }
          .width('100%')
          .height(44)
          .padding({ left: 16, right: 16 })
          .onClick(() => {
            this.openDesktopWidgetManager();
          });
          Row() {
            Text('自定义背景')
              .fontSize(13)
              .fontColor(COLOR_TEXT_SECONDARY)
              .layoutWeight(1)
              .maxLines(1);
            Text(this.widgetBackgroundSet ? '已设置' : '默认')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(COLOR_PRIMARY);
            Text('›')
              .fontSize(20)
              .fontColor($r('app.color.hita_text_hint_b2b8c4'))
              .margin({ left: 6 });
          }
          .width('100%')
          .height(44)
          .padding({ left: 16, right: 16 })
          .onClick(() => {
            this.openWidgetBackgroundSheet();
          });
        }
        .width('100%')
        .transition(TransitionEffect.OPACITY);
      }
    }
    .width('100%')
    .clip(true)
    .alignItems(HorizontalAlign.Start);
  }

  @Builder
  appearanceSettings() {
    Column() {
      Row() {
        Stack() {
          SymbolGlyph($r('sys.symbol.moon'))
            .fontSize(22)
            .fontColor([COLOR_PRIMARY]);
        }
        .width(40)
        .height(40)
        .borderRadius(20)
        .alignContent(Alignment.Center)
        .backgroundColor(COLOR_NAV_ACTIVE);
        Column() {
          Text('深色模式')
            .fontSize(14)
            .fontColor(COLOR_TEXT_PRIMARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
          Text(this.appearanceMode === AppearanceMode.DARK ? '已开启' :
            (this.appearanceMode === AppearanceMode.LIGHT ? '已关闭' : '跟随系统'))
            .fontSize(12)
            .fontColor(COLOR_TEXT_SECONDARY)
            .margin({ top: 2 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 12 });
        Text('›')
          .fontSize(23)
          .fontColor(COLOR_TEXT_SECONDARY)
          .rotate({ angle: this.appearanceExpanded ? 90 : 0 });
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)
      .accessibilityDescription(this.appearanceExpanded ? '已展开' : '已收起')
      .onClick(() => {
        this.getUIContext().animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
          this.appearanceExpanded = !this.appearanceExpanded;
        });
      });
      if (this.appearanceExpanded) {
        ImmersiveHeader({ barHeight: 60, materialEnabled: CompatibleSheetMaterial.isEnabled() }) {
          Row({ space: 8 }) {
            this.appearanceOption(AppearanceMode.DARK, '开启');
            this.appearanceOption(AppearanceMode.LIGHT, '关闭');
            this.appearanceOption(AppearanceMode.SYSTEM, '跟随系统');
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 4, bottom: 12 })
          .transition(TransitionEffect.OPACITY);
        }
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start);
  }

  @Builder
  appearanceOption(mode: AppearanceMode, label: string) {
    Row({ space: 4 }) {
      Radio({ value: mode, group: 'appearance_mode' })
        .checked(this.appearanceMode === mode)
        .width(18)
        .height(18)
        .margin(0)
        .radioStyle({ checkedBackgroundColor: COLOR_PRIMARY })
        .enabled(!this.appearanceBusy)
        .accessibilityText('深色模式：' + label)
        .onChange((checked: boolean) => {
          if (checked) {
            void this.selectAppearance(mode);
          }
        });
      Text(label)
        .fontSize(13)
        .fontColor(CompatibleSheetMaterial.isEnabled() ? CompatibleMaterialModifier.foreground(COLOR_TEXT_PRIMARY) :
          COLOR_TEXT_PRIMARY)
        .maxLines(1);
    }
    .width(0)
    .layoutWeight(1)
    .height(44)
    .padding({ left: 6, right: 6 })
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.appearanceMode === mode ? COLOR_NAV_ACTIVE : $r('app.color.hita_control'))
    .borderRadius(8)
    .attributeModifier(new CompatibleMaterialModifier(this.appearanceMode === mode ? COLOR_NAV_ACTIVE :
      $r('app.color.hita_control'), false, CompatibleSheetMaterial.isEnabled()))
    .enabled(!this.appearanceBusy)
    .onClick(() => {
      void this.selectAppearance(mode);
    });
  }

  @Builder
  userCard() {
    Row() {
      Column() {
        Text(this.sessionInfo === undefined ? '?' :
          (this.sessionInfo.name.length > 0 ? this.sessionInfo.name.substring(0, 1) : 'U'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF');
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .id('eas-account-avatar')
      .backgroundColor(this.sessionInfo === undefined ? $r('app.color.hita_disabled_aab4c1') :
        (this.sessionInfo.loginExpired ? $r('app.color.hita_error') : $r('app.color.hita_primary_fill')))
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center);
      Column() {
        Text(this.sessionInfo === undefined ? '未登录教务' :
          this.sessionInfo.loginExpired ? '已过期教务' :
          (this.sessionInfo.name.length > 0 ? this.sessionInfo.name :
            (this.sessionInfo.username.length > 0 ? this.sessionInfo.username :
              (this.sessionInfo.stuId.length > 0 ? this.sessionInfo.stuId : '已登录教务'))))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLOR_TEXT_PRIMARY);
        Text(this.sessionInfo === undefined ? '点击进行教务登录' :
          this.sessionInfo.loginExpired ? Home.campusName(this.sessionInfo.campus) + ' · 点击重新登录' :
          ((this.sessionInfo.stuId.length > 0 ? this.sessionInfo.stuId + '\n' : '') +
            Home.campusName(this.sessionInfo.campus) +
            (this.sessionInfo.school.length > 0 ? ' · ' + this.sessionInfo.school : '') +
            (this.sessionInfo.major.length > 0 ? ' · ' + this.sessionInfo.major : '')))
          .fontSize(12)
          .fontColor(COLOR_TEXT_SECONDARY)
          .margin({ top: 4 })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 });
      Text('›')
        .fontSize(24)
        .fontColor(COLOR_TEXT_SECONDARY);
    }
    .width('100%')
    .padding(16)
    .backgroundColor(COLOR_CARD)
    .borderRadius(16)
    .margin({ top: 8, bottom: 8 })
    .onClick(() => {
      this.openSessionSheet();
    });
  }

  @Builder
  courseDetailSheet(event: EasEventItem) {
    Column() {
      Row() {
        Circle()
          .width(COURSE_DETAIL_ICON_SIZE)
          .height(COURSE_DETAIL_ICON_SIZE)
          .flexShrink(0)
          .attributeModifier(new CirclePaintModifier(Home.canvasColorCss(timetableBlockColor(
            this.courseColorEditing ? this.courseColorPreview : event.color))));
        Column() {
          Text(event.name === 'NULL' || event.name.length === 0 ? '未命名课程' : event.name)
            .fontSize(21)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLOR_TEXT_PRIMARY)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
          Text(event.type === EasEventType.EXAM ? '考试详情' : '课程详情')
            .fontSize(13)
            .fontColor(COLOR_TEXT_SECONDARY)
            .margin({ top: 4 });
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ left: COURSE_DETAIL_TEXT_GAP });
        if (event.type === EasEventType.EXAM ||
          (event.type === EasEventType.CLASS && event.subjectId.length > 0)) {
          Column() {
            ImmersiveHeader({ barHeight: 44, materialEnabled: CompatibleSheetMaterial.isEnabled() }) {
              Button({ type: ButtonType.Circle }) {
                SymbolGlyph($r('sys.symbol.paintpalette')).fontSize(22)
                  .fontColor([CompatibleSheetMaterial.isEnabled() ? CompatibleMaterialModifier.foreground(COLOR_PRIMARY) :
                    COLOR_PRIMARY]);
              }
              .width(44).height(44).padding(0).flexShrink(0)
              .backgroundColor(COLOR_NAV_ACTIVE)
              .attributeModifier(new CompatibleMaterialModifier(COLOR_NAV_ACTIVE, false, CompatibleSheetMaterial.isEnabled()))
              .accessibilityText(event.type === EasEventType.EXAM ? '修改考试颜色' : '修改课程颜色')
              .onClick(() => {
                this.courseColorPreview = event.color;
                this.courseColorEditing = !this.courseColorEditing;
              });
            }
          }
          .width(44).height(44).flexShrink(0);
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ bottom: 14 });

      if (this.courseColorEditing) {
        CourseColorEditor({
          initialColor: event.color,
          immersiveControls: true,
          examMode: event.type === EasEventType.EXAM,
          textColor: this.timetableTextColor,
          onPreview: (color: number) => { this.courseColorPreview = color; },
          onSave: async (color: number) => { await this.saveCourseColor(event, color); },
          onCancel: () => { this.courseColorEditing = false; }
        })
      } else {
      this.courseDetailRow($r('sys.symbol.person_crop_circle_fill'), '老师',
        event.teacher.trim().length > 0 ? event.teacher : '无');
      this.courseDetailRow($r('sys.symbol.pin'), event.type === EasEventType.EXAM ? '考场' : '教室',
        event.place.trim().length > 0 ? event.place : '无');
      this.courseDetailRow($r('sys.symbol.clock'), '时间',
        EasTimeTools.printTime(event.from) + ' - ' + EasTimeTools.printTime(this.eventDetailEndTime(event)));
      if (event.type !== EasEventType.EXAM) {
        this.courseDetailRow($r('sys.symbol.doc_plaintext'), '节次', Home.coursePeriodText(event));
      }
      this.courseDetailRow($r('sys.symbol.calendar'), '日期', Home.courseDateText(event.from));
      if (event.type === EasEventType.EXAM) {
        this.courseDetailRow($r('sys.symbol.checkmark'), '类型', '考试');
      } else {
        this.courseDetailRow($r('sys.symbol.repeat_1'), '课程进度', this.courseProgressText(event));
      }
      if (event.type === EasEventType.CLASS) {
        Column() {
          ImmersiveHeader({ barHeight: 40, materialEnabled: CompatibleSheetMaterial.isEnabled() }) {
            Row() {
              Button('翘课', { type: ButtonType.Capsule })
                .height(32)
                .padding({ left: 12, right: 12 })
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor('#FFFFFF')
                .backgroundColor('#E84040')
                .attributeModifier(new CompatibleMaterialModifier('#E84040', true,
                  CompatibleSheetMaterial.isEnabled(), '#EBE84040', false))
                .enabled(!this.skippingCourse)
                .onClick(() => { this.confirmSkipCourse(event); });
            }
            .width('100%')
            .height(40)
            .justifyContent(FlexAlign.End);
          }
        }
        .width('100%')
        .margin({ top: 12 });
      }
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 0, bottom: 20 })
    .attributeModifier(new CompatibleLightModifier(24, CompatibleSheetMaterial.isEnabled(), true));
  }

  @Builder
  courseDetailRow(symbol: Resource, label: string, value: string) {
    Row() {
      Stack() {
        SymbolGlyph(symbol)
          .fontSize(20)
          .fontColor([COLOR_PRIMARY]);
      }
      .width(COURSE_DETAIL_ICON_SIZE)
      .height(COURSE_DETAIL_ICON_SIZE)
      .borderRadius(COURSE_DETAIL_ICON_SIZE / 2)
      .flexShrink(0)
      .backgroundColor(COLOR_NAV_ACTIVE)
      .alignContent(Alignment.Center);
      Column() {
        Text(label)
          .fontSize(12)
          .fontColor(COLOR_TEXT_SECONDARY);
        Text(value)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT_PRIMARY)
          .margin({ top: 2 })
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: COURSE_DETAIL_TEXT_GAP });
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center);
  }

  private static canvasColorCss(argb: number): string {
    const r: number = (argb >> 16) & 0xFF;
    const g: number = (argb >> 8) & 0xFF;
    const b: number = argb & 0xFF;
    return 'rgb(' + r.toString() + ',' + g.toString() + ',' + b.toString() + ')';
  }

  @Builder
  sessionSheet() {
    Column() {
      ImmersiveHeader({ barHeight: 60 }) {
        Row() {
          HeaderBackButton({
            onBack: () => {
              this.closeActiveSheet();
            }
          })
            .margin({ right: 12 });
          Column() {
            Text('教务认证')
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(COLOR_TEXT_PRIMARY);
            Text(this.sessionSheetInfo === undefined ? '请登录教务账号以继续' : '当前教务会话')
              .fontSize(13)
              .fontColor(COLOR_TEXT_SECONDARY)
              .margin({ top: 4 });
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start);

        }
        .width('100%')
        .alignItems(VerticalAlign.Center);
      }

      Column() {
        Text('认证校区')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT_SECONDARY)
          .width('100%');

        ImmersiveHeader({ barHeight: 57 }) {
          Row({ space: 4 }) {
            this.sessionCampusButton('SHENZHEN', '深圳');
            this.sessionCampusButton('BENBU', '本部');
            this.sessionCampusButton('WEIHAI', '威海');
          }
          .width('100%')
          .padding(4)
          .backgroundColor($r('app.color.hita_control_eaf0f7'))
          .borderRadius(16)
          .attributeModifier(new CompatibleMaterialModifier($r('app.color.hita_control_eaf0f7')))
          .margin({ top: 7 });
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ top: 18 });

      if (this.sessionSheetInfo !== undefined) {
        Row() {
          Stack() {
            Text(this.sessionSheetInfo.name.length > 0 ?
              this.sessionSheetInfo.name.substring(0, 1) : 'U')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF');
          }
          .width(48)
          .height(48)
          .borderRadius(24)
          .backgroundColor($r('app.color.hita_primary_fill'))
          .alignContent(Alignment.Center);
          Column() {
            Text(this.sessionSheetInfo.name.length > 0 ? this.sessionSheetInfo.name :
              (this.sessionSheetInfo.stuId.length > 0 ? this.sessionSheetInfo.stuId : '教务账号'))
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor(COLOR_TEXT_PRIMARY)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis });
            Text(Home.campusName(this.sessionSheetInfo.campus) +
              (this.sessionSheetInfo.stuId.length > 0 ? ' · ' + this.sessionSheetInfo.stuId : ''))
              .fontSize(13)
              .fontColor(COLOR_TEXT_SECONDARY)
              .margin({ top: 4 });
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          .margin({ left: 12 });

          Text(this.sessionSheetStatus)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.sessionSheetStatus === EasSessionStatus.SAVED ? $r('app.color.hita_success') :
              this.sessionSheetStatus === EasSessionStatus.EXPIRED ? $r('app.color.hita_error') :
                COLOR_TEXT_SECONDARY)
            .padding({ left: 9, right: 9, top: 5, bottom: 5 })
            .backgroundColor(this.sessionSheetStatus === EasSessionStatus.SAVED ?
              $r('app.color.hita_success_surface') : this.sessionSheetStatus === EasSessionStatus.EXPIRED ?
                $r('app.color.hita_error_surface') : $r('app.color.hita_control'))
            .flexShrink(0)
            .borderRadius(12);
        }
        .width('100%')
        .padding(15)
        .backgroundColor(CompatibleSheetMaterial.cardColor($r('app.color.hita_surface_soft_f8fafd')))
        .border({ width: 1, color: $r('app.color.hita_divider_e3eaf2') })
        .borderRadius(18)
        .margin({ top: 16 });

        Row({ space: 8 }) {
          Button('重新登录')
            .layoutWeight(1)
            .height(46)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLOR_PRIMARY)
            .backgroundColor(COLOR_NAV_ACTIVE)
            .borderRadius(17)
            .onClick(() => {
              this.beginSessionLogin();
            });
          Button('退出登录')
            .layoutWeight(1)
            .height(46)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.hita_error'))
            .backgroundColor($r('app.color.hita_error_surface'))
            .borderRadius(17)
            .onClick(() => {
              this.logoutSession();
            });
        }
        .width('100%')
        .margin({ top: 12 });
      } else {
        Column() {
          Row() {
            Stack() {
              SymbolGlyph($r('sys.symbol.lock_shield'))
                .fontSize(22)
                .fontColor([COLOR_PRIMARY]);
            }
            .width(42)
            .height(42)
            .borderRadius(21)
            .backgroundColor(COLOR_NAV_ACTIVE)
            .alignContent(Alignment.Center);
            Column() {
              Text('登录教务系统')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(COLOR_TEXT_PRIMARY);
              Text('将打开对应校区的官方认证页')
                .fontSize(12)
                .fontColor(COLOR_TEXT_SECONDARY)
                .margin({ top: 3 });
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            .margin({ left: 12 });
          }
          .width('100%');

          Button('网页登录')
            .width('100%')
            .height(46)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
            .backgroundColor($r('app.color.hita_primary_fill'))
            .borderRadius(17)
            .margin({ top: 14 })
            .onClick(() => {
              this.beginSessionLogin();
            });

          Row() {
            SymbolGlyph($r('sys.symbol.lock_shield'))
              .fontSize(14)
              .fontColor([COLOR_TEXT_HINT]);
            Text('HITA 不保存您的教务密码')
              .fontSize(12)
              .fontColor(COLOR_TEXT_HINT)
              .margin({ left: 6 });
          }
          .margin({ top: 12 });
        }
        .width('100%')
        .padding(16)
        .backgroundColor(CompatibleSheetMaterial.cardColor($r('app.color.hita_surface_soft_f8fafd')))
        .border({ width: 1, color: $r('app.color.hita_divider_e3eaf2') })
        .borderRadius(18)
        .margin({ top: 16 });
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 0, bottom: 22 })
    .attributeModifier(new CompatibleLightModifier(24, CompatibleSheetMaterial.isEnabled(), true));
  }

  @Builder
  sessionCampusButton(code: string, label: string) {
    Row() {
      Circle()
        .width(9)
        .height(9)
        .attributeModifier(new CirclePaintModifier(this.sessionSheetCampus === code ? COLOR_PRIMARY : 'transparent',
          this.sessionSheetCampus === code ? COLOR_PRIMARY : $r('app.color.hita_text_hint_a9b4c2')))
        .strokeWidth(1.5);
      Text(label)
        .fontSize(15)
        .fontWeight(this.sessionSheetCampus === code ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.sessionSheetCampus === code ? COLOR_TEXT_PRIMARY : COLOR_TEXT_SECONDARY)
        .margin({ left: 7 });
    }
    .layoutWeight(1)
    .height(42)
    .justifyContent(FlexAlign.Center)
    .borderRadius(13)
    .backgroundColor(this.sessionSheetCampus === code ? COLOR_CARD : 'transparent')
    .onClick(() => {
      this.selectSessionCampus(code);
    });
  }

  @Builder
  moreShortcut(options: MoreShortcutOptions) {
    Row() {
      Stack() {
        SymbolGlyph(options.symbol)
          .fontSize(22)
          .fontColor([COLOR_PRIMARY]);
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .alignContent(Alignment.Center)
      .backgroundColor(COLOR_NAV_ACTIVE);
      Column() {
        Text(options.title)
          .fontSize(12)
          .fontColor(COLOR_TEXT_SECONDARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(options.subtitle)
          .fontSize(14)
          .fontColor(COLOR_TEXT_PRIMARY)
          .margin({ top: 4 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 });
    }
    // Give each shortcut a zero base width so the two weighted cards remain
    // exactly equal on narrow devices.
    .width(0)
    .layoutWeight(1)
    .height(80)
    .padding({ left: 12, right: 12 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(COLOR_CARD)
    .borderRadius(16)
    .onClick(options.action);
  }

  @Builder
  moreSectionTitle(title: string) {
    Text(title)
      .fontSize(18)
      .fontWeight(FontWeight.Bold)
      .fontColor(COLOR_TEXT_PRIMARY)
      .margin({ top: 16, bottom: 4 })
      .alignSelf(ItemAlign.Start);
  }

  @Builder
  classReminderSettings() {
    Column() {
      Row() {
        Stack() {
          SymbolGlyph($r('sys.symbol.bell'))
            .fontSize(22)
            .fontColor([COLOR_PRIMARY]);
        }
        .width(40)
        .height(40)
        .borderRadius(20)
        .alignContent(Alignment.Center)
        .backgroundColor(COLOR_NAV_ACTIVE);
        Column() {
          Text('课程提醒')
            .fontSize(14)
            .fontColor(COLOR_TEXT_PRIMARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
          if (this.classReminderSubtitle().length > 0) {
            Text(this.classReminderSubtitle())
              .fontSize(12)
              .fontColor(COLOR_TEXT_SECONDARY)
              .margin({ top: 2 })
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis });
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 12 });
        Text('›')
          .fontSize(23)
          .fontColor(COLOR_TEXT_SECONDARY)
          .rotate({ angle: this.reminderExpanded ? 90 : 0 });
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)
      .accessibilityDescription(this.reminderExpanded ? '已展开' : '已收起')
      .onClick(() => {
        this.getUIContext().animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
          this.reminderExpanded = !this.reminderExpanded;
        });
      });
      if (this.reminderExpanded) {
        ImmersiveHeader({ barHeight: this.reminderMaterialHeight, materialEnabled: CompatibleSheetMaterial.isEnabled() }) {
        Column() {
          Column() {
            Row({ space: 12 }) {
              Text('开启课程提醒')
                .fontSize(14)
                .fontColor(CompatibleSheetMaterial.isEnabled() ? CompatibleMaterialModifier.foreground(COLOR_TEXT_PRIMARY) :
                  COLOR_TEXT_PRIMARY)
                .layoutWeight(1);
              Toggle({ type: ToggleType.Switch, isOn: this.classReminderEnabled })
                .selectedColor(COLOR_PRIMARY)
                .margin(0)
                .enabled(!this.reminderBusy)
                .accessibilityText('开启课程提醒')
                .onChange((isOn: boolean) => {
                  void this.setClassReminderEnabled(isOn);
                });
            }
            .width('100%')
            .height(40)
            .alignItems(VerticalAlign.Center);
            Text('应用在前台或后台运行时会通知。')
              .fontSize(12)
              .lineHeight(18)
              .fontColor(COLOR_TEXT_SECONDARY)
              .width('100%')
              .margin({ top: 2, bottom: 14 });
            Divider()
              .strokeWidth(0.5)
              .color(COLOR_TEXT_SECONDARY)
              .opacity(0.15);
            Row({ space: 8 }) {
              Text('提醒时间')
                .fontSize(14)
                .fontColor(CompatibleSheetMaterial.isEnabled() ? CompatibleMaterialModifier.foreground(COLOR_TEXT_PRIMARY) :
                  COLOR_TEXT_PRIMARY)
                .layoutWeight(1);
              Text('上课前 ' + this.reminderLeadMinutes.toString() + ' 分钟')
                .fontSize(13)
                .fontColor(COLOR_TEXT_SECONDARY)
                .maxLines(1);
              SymbolGlyph($r('sys.symbol.chevron_right'))
                .fontSize(12)
                .fontColor([COLOR_TEXT_SECONDARY])
                .width(16)
                .height(20);
            }
            .width('100%')
            .height(48)
            .alignItems(VerticalAlign.Center)
            .enabled(!this.reminderBusy)
            .accessibilityText('提醒时间，上课前 ' + this.reminderLeadMinutes.toString() + ' 分钟，点击修改')
            .onClick(() => { this.showReminderTimePicker(); });
          }
          .width('100%')
          .padding({ left: 14, right: 14, top: 8, bottom: 2 })
          .backgroundColor($r('app.color.hita_control'))
          .borderRadius(12)
          .attributeModifier(new CompatibleMaterialModifier($r('app.color.hita_control'), false,
            CompatibleSheetMaterial.isEnabled()))
          .alignItems(HorizontalAlign.Start);
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 6, bottom: 12 })
        .onAreaChange((_old: Area, area: Area) => {
          const height: number = Number(area.height);
          if (height > 0 && Math.abs(height - this.reminderMaterialHeight) > 1) {
            this.reminderMaterialHeight = height;
          }
        })
        .transition(TransitionEffect.OPACITY);
        }
    }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start);
  }

  @Builder
  moreNavigationRow(symbol: Resource, title: string, subtitle: string, action: () => void) {
    Row() {
      Stack() {
        SymbolGlyph(symbol)
          .fontSize(22)
          .fontColor([COLOR_PRIMARY]);
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .alignContent(Alignment.Center)
      .backgroundColor(COLOR_NAV_ACTIVE);
      Column() {
        Text(title)
          .fontSize(14)
          .fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
        if (subtitle.length > 0) {
          Text(subtitle)
            .fontSize(12)
            .fontColor(COLOR_TEXT_SECONDARY)
            .margin({ top: 2 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 });
      Text('›')
        .fontSize(23)
        .fontColor(COLOR_TEXT_SECONDARY);
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .onClick(action);
  }
}
