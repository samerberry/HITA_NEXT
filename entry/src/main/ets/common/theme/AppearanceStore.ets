import { common, Configuration, ConfigurationConstant } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

export enum AppearanceMode {
  SYSTEM = 'system',
  DARK = 'dark',
  LIGHT = 'light'
}

export const APPEARANCE_MODE_KEY: string = 'hita_appearance_mode';
export const APPEARANCE_DARK_KEY: string = 'hita_appearance_dark';

export function validAppearanceMode(value: preferences.ValueType): AppearanceMode {
  if (value === AppearanceMode.DARK) {
    return AppearanceMode.DARK;
  }
  if (value === AppearanceMode.LIGHT) {
    return AppearanceMode.LIGHT;
  }
  return AppearanceMode.SYSTEM;
}

export function appearanceColorMode(mode: AppearanceMode): ConfigurationConstant.ColorMode {
  if (mode === AppearanceMode.DARK) {
    return ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }
  if (mode === AppearanceMode.LIGHT) {
    return ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  }
  return ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
}

/** Application overrides belong to ApplicationContext, never the system setting. */
export class AppearanceStore {
  private static instance: AppearanceStore | undefined = undefined;
  private context: common.ApplicationContext | undefined = undefined;
  private store: preferences.Preferences | undefined = undefined;
  private mainWindow: window.Window | undefined = undefined;
  private mode: AppearanceMode = AppearanceMode.SYSTEM;
  private dark: boolean = false;
  private contentReady: boolean = false;
  private saving: boolean = false;
  private barUpdate: Promise<void> = Promise.resolve();
  private pageStatusColor: string = '';
  private pageNavigationColor: string = '';

  static getInstance(): AppearanceStore {
    if (AppearanceStore.instance === undefined) {
      AppearanceStore.instance = new AppearanceStore();
    }
    return AppearanceStore.instance;
  }

  initialize(context: common.UIAbilityContext): void {
    this.context = context.getApplicationContext();
    try {
      this.store = preferences.getPreferencesSync(context, { name: 'hita_appearance' });
      this.mode = validAppearanceMode(this.store.getSync('mode', AppearanceMode.SYSTEM));
    } catch (_) {
      this.store = undefined;
      this.mode = AppearanceMode.SYSTEM;
    }
    this.dark = this.mode === AppearanceMode.DARK ||
      (this.mode === AppearanceMode.SYSTEM &&
        context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    this.publish();
  }

  attachWindow(mainWindow: window.Window): void {
    this.mainWindow = mainWindow;
    this.updateBars();
  }

  detachWindow(): void {
    this.mainWindow = undefined;
    this.contentReady = false;
    this.pageStatusColor = '';
    this.pageNavigationColor = '';
  }

  setPageBarColors(status: string = '', navigation: string = ''): void {
    const nextStatus = /^#[0-9a-fA-F]{6}$/.test(status) ? status : '';
    const nextNavigation = /^#[0-9a-fA-F]{6}$/.test(navigation) ? navigation : '';
    if (this.pageStatusColor === nextStatus && this.pageNavigationColor === nextNavigation) return;
    this.pageStatusColor = nextStatus;
    this.pageNavigationColor = nextNavigation;
    this.updateBars();
  }

  onContentReady(): void {
    this.contentReady = true;
    // Huawei requires loadContent to complete before setColorMode is called.
    try {
      this.context?.setColorMode(appearanceColorMode(this.mode));
    } catch (_) {
      hilog.warn(0x0000, 'HitaAppearance', 'Unable to apply saved appearance');
    }
    this.publish();
  }

  onConfigurationUpdate(config: Configuration): void {
    if (this.mode === AppearanceMode.SYSTEM) {
      if (config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK) {
        this.dark = true;
      } else if (config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT) {
        this.dark = false;
      }
    } else {
      this.dark = this.mode === AppearanceMode.DARK;
    }
    this.publish();
  }

  async select(mode: AppearanceMode): Promise<void> {
    if (this.saving || !this.contentReady || this.context === undefined || this.store === undefined) {
      throw new Error('APPEARANCE_NOT_READY');
    }
    if (mode === this.mode) {
      return;
    }
    const previous: AppearanceMode = this.mode;
    const previousDark: boolean = this.dark;
    this.saving = true;
    try {
      await this.store.put('mode', mode);
      await this.store.flush();
      this.mode = mode;
      this.context.setColorMode(appearanceColorMode(mode));
      if (mode !== AppearanceMode.SYSTEM) {
        this.dark = mode === AppearanceMode.DARK;
      }
      // Follow-system resolves through the framework configuration callback.
      // Do not mistake the old forced application color for the system color.
      this.publish();
    } catch (_) {
      this.mode = previous;
      this.dark = previousDark;
      try {
        await this.store.put('mode', previous);
        await this.store.flush();
        this.context.setColorMode(appearanceColorMode(previous));
      } catch (_) {
      }
      this.publish();
      throw new Error('APPEARANCE_SAVE_FAILED');
    } finally {
      this.saving = false;
    }
  }

  private publish(): void {
    AppStorage.setOrCreate(APPEARANCE_MODE_KEY, this.mode);
    AppStorage.setOrCreate(APPEARANCE_DARK_KEY, this.dark);
    this.updateBars();
  }

  private updateBars(): void {
    const target: window.Window | undefined = this.mainWindow;
    const dark: boolean = this.dark;
    const status = this.pageStatusColor || (dark ? '#ECEFF4' : '#14213D');
    const navigation = this.pageNavigationColor || (dark ? '#BCC3CF' : '#4E5C72');
    if (target === undefined) {
      return;
    }
    this.barUpdate = this.barUpdate.then(async (): Promise<void> => {
      if (this.mainWindow !== target) {
        return;
      }
      await target.setWindowBackgroundColor(dark ? '#101214' : '#F5F6F8');
      await target.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        statusBarContentColor: status,
        navigationBarColor: '#00000000',
        navigationBarContentColor: navigation
      });
    }).catch(() => {
      hilog.warn(0x0000, 'HitaAppearance', 'Unable to update system bars');
    });
  }
}
