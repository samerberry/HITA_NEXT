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

  static detach(context: common.Context): void {
    if (TimetableExecutionContext.active?.context === context) {
      TimetableExecutionContext.active = undefined;
      hilog.info(0x0000, 'HitaIntent', 'detach shared application context');
    }
  }
}
