/** Notify projections only after a successful local write; failures never fail the write itself. */
export class ScheduleChangeSignal {
  static listener: (() => void) | undefined = undefined;
  private static subscribers: Map<string, () => void> = new Map<string, () => void>();

  static subscribe(key: string, listener: () => void): void {
    ScheduleChangeSignal.subscribers.set(key, listener);
  }

  static notify(): void {
    try { ScheduleChangeSignal.listener?.(); } catch (_) {}
    ScheduleChangeSignal.subscribers.forEach((listener: () => void): void => {
      try { listener(); } catch (_) {}
    });
  }
}
