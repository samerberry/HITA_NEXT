import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

/**
 * Shared dependency of the UIAbility and the system-loaded intent entry.
 * Do not keep this state on the executor class: loading that entry can evaluate it again.
 */
export class TimetableExecutionContext {
  private static active: TimetableExecutionContext | undefined = undefined;
  readonly context: common.Context;
  readonly startup: Promise<void>;
  private studyOpener: ((id: string) => Promise<void>) | undefined = undefined;

  private constructor(context: common.Context, startup: Promise<void>) {
    this.context = context;
    this.startup = startup;
  }

  static attach(context: common.Context, startup: Promise<void>): void {
    TimetableExecutionContext.active = new TimetableExecutionContext(context, startup);
    hilog.info(0x0000, 'HitaIntent', 'attach shared application context');
  }

  static current(): TimetableExecutionContext | undefined {
    return TimetableExecutionContext.active;
  }

  setStudyOpener(opener: (id: string) => Promise<void>): void { this.studyOpener = opener; }

  async openStudyConfirmation(id: string): Promise<void> {
    // The foreground intent can arrive before loadContent's callback on a cold launch.
    for (let attempt: number = 0; attempt < 100; attempt++) {
      if (TimetableExecutionContext.current() !== this) throw new Error('应用已重新启动，请重试');
      if (this.studyOpener !== undefined) { await this.studyOpener(id); return; }
      await new Promise<void>((resolve) => { setTimeout(resolve, 50); });
    }
    throw new Error('确认页面尚未准备好，请打开 HITA 后重试');
  }

  static detach(context: common.Context): void {
    if (TimetableExecutionContext.active?.context === context) {
      TimetableExecutionContext.active = undefined;
      hilog.info(0x0000, 'HitaIntent', 'detach shared application context');
    }
  }
}
