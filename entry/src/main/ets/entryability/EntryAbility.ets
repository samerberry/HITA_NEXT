import { BackupService } from '../feature/backup/BackupService';
import { ScheduleSyncService } from '../feature/timetable/data/ScheduleSyncService';
import { AbilityConstant, common, Configuration, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { display, window } from '@kit.ArkUI';
import {
  KEYBOARD_INSET_FALLBACK,
  KEYBOARD_INSET_KEY,
  NAV_BAR_INSET_FALLBACK,
  NAV_BAR_INSET_KEY,
  STATUS_BAR_INSET_FALLBACK,
  STATUS_BAR_INSET_KEY
} from '../common/theme/StatusBarInset';
import { ClassReminderStore } from '../feature/timetable/data/ClassReminderStore';
import { AppearanceStore } from '../common/theme/AppearanceStore';
import { NextClassWidgetService } from '../feature/widget/NextClassWidgetService';

const DOMAIN: number = 0x0000;
const TAG: string = 'HitaNEXT';

export default class EntryAbility extends UIAbility {
  private startup: Promise<void> = Promise.resolve();
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'Ability onCreate');
    AppStorage.setOrCreate(STATUS_BAR_INSET_KEY, STATUS_BAR_INSET_FALLBACK);
    AppStorage.setOrCreate(NAV_BAR_INSET_KEY, NAV_BAR_INSET_FALLBACK);
    AppStorage.setOrCreate(KEYBOARD_INSET_KEY, KEYBOARD_INSET_FALLBACK);
    AppearanceStore.getInstance().initialize(this.context);
    this.startup = BackupService.recover(this.context).then(() => {
      BackupService.clearAbandonedFiles(this.context);
      AppearanceStore.getInstance().initialize(this.context);
      NextClassWidgetService.attach(this.context);
      ScheduleSyncService.attach(this.context);
    });
    this.captureReminderWant(want);
    void this.startup.then(() => this.restoreClassReminders()).catch(() => {});
  }

  onNewWant(want: Want): void {
    this.captureReminderWant(want);
    if (typeof want.parameters?.['hitaReminderEventId'] === 'string') {
      void window.getLastWindow(this.context).then((mainWindow: window.Window): void => {
        const router = mainWindow.getUIContext().getRouter();
        if (Number(router.getLength()) > 1) router.back({ url: 'pages/Home' });
      }).catch(() => {});
    }
  }

  private captureReminderWant(want: Want): void {
    const id = want.parameters?.['hitaReminderEventId'];
    if (typeof id === 'string' && id.length > 0) {
      AppStorage.setOrCreate('hita_reminder_open_event', id);
    }
  }

  onDestroy(): void {
    ScheduleSyncService.detach();
    hilog.info(DOMAIN, TAG, 'Ability onDestroy');
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    await this.startup;
    this.configureSystemBars(windowStage);
    // 首屏直接进入主界面。教务登录从主界面的会话入口按需打开。
    windowStage.loadContent('pages/Home', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, 'Succeeded in loading content.');
      AppearanceStore.getInstance().onContentReady();
    });
  }

  private async configureSystemBars(windowStage: window.WindowStage): Promise<void> {
    try {
      const mainWindow: window.Window = await windowStage.getMainWindow();
      await mainWindow.setWindowLayoutFullScreen(true);
      AppearanceStore.getInstance().attachWindow(mainWindow);
      this.captureSystemInsets(mainWindow);
      this.captureKeyboardInset(mainWindow);
      mainWindow.on('avoidAreaChange', (data: window.AvoidAreaOptions) => {
        if (data.type === window.AvoidAreaType.TYPE_SYSTEM ||
          data.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
          this.captureSystemInsets(mainWindow);
        }
        if (data.type === window.AvoidAreaType.TYPE_KEYBOARD) {
          this.captureKeyboardInset(mainWindow);
        }
      });
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'Failed to configure system bars: %{public}s', String(e));
    }
  }

  private captureSystemInsets(mainWindow: window.Window): void {
    let topVp: number = STATUS_BAR_INSET_FALLBACK;
    let bottomVp: number = NAV_BAR_INSET_FALLBACK;
    try {
      const density: number = display.getDefaultDisplaySync().densityPixels;
      const systemArea: window.AvoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const indicatorArea: window.AvoidArea =
        mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      const topPx: number = systemArea.topRect.height;
      const bottomPx: number = Math.max(systemArea.bottomRect.height, indicatorArea.bottomRect.height);
      if (topPx > 0 && density > 0) {
        topVp = topPx / density;
      }
      if (bottomPx > 0 && density > 0) {
        bottomVp = bottomPx / density;
      }
    } catch (e) {
    }
    if (topVp < 24) {
      topVp = STATUS_BAR_INSET_FALLBACK;
    }
    if (bottomVp < 20) {
      bottomVp = NAV_BAR_INSET_FALLBACK;
    }
    AppStorage.setOrCreate(STATUS_BAR_INSET_KEY, topVp);
    AppStorage.setOrCreate(NAV_BAR_INSET_KEY, bottomVp);
  }

  private captureKeyboardInset(mainWindow: window.Window): void {
    let keyboardVp: number = KEYBOARD_INSET_FALLBACK;
    try {
      const density: number = display.getDefaultDisplaySync().densityPixels;
      const keyboardArea: window.AvoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_KEYBOARD);
      const keyboardPx: number = keyboardArea.bottomRect.height;
      if (keyboardPx > 0 && density > 0) {
        keyboardVp = keyboardPx / density;
      }
    } catch (_) {
      keyboardVp = KEYBOARD_INSET_FALLBACK;
    }
    AppStorage.setOrCreate(KEYBOARD_INSET_KEY, keyboardVp);
  }

  onWindowStageDestroy(): void {
    AppearanceStore.getInstance().detachWindow();
    hilog.info(DOMAIN, TAG, 'Ability onWindowStageDestroy');
  }

  async onForeground(): Promise<void> {
    await this.startup;
    AppStorage.setOrCreate('hita_app_foreground', true);
    hilog.info(DOMAIN, TAG, 'Ability onForeground');
    NextClassWidgetService.scheduleRefresh();
    ScheduleSyncService.schedule();
    void this.startup.then(() => this.restoreClassReminders()).catch(() => {});
    AppearanceStore.getInstance().onConfigurationUpdate(this.context.config);
  }

  onConfigurationUpdate(config: Configuration): void {
    AppearanceStore.getInstance().onConfigurationUpdate(config);
  }

  onBackground(): void {
    AppStorage.setOrCreate('hita_app_foreground', false);
    hilog.info(DOMAIN, TAG, 'Ability onBackground');
    void NextClassWidgetService.refreshAll();
  }

  private async restoreClassReminders(): Promise<void> {
    try {
      await ClassReminderStore.getInstance().init(this.context);
      await ScheduleSyncService.refreshReminders();
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'restoreClassReminders %{public}s', String(e));
    }
  }
}
