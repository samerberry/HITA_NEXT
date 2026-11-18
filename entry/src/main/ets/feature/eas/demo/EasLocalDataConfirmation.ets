import { common } from '@kit.AbilityKit';
import { HitaButton } from '../../../common/components/HitaButton';
import { HitaColors } from '../../../common/theme/HitaColors';
import { HitaDesign } from '../../../common/theme/HitaDesign';
import { EasCampus, EasSession } from '../EasSession';
import { EasSessionStore } from '../EasSessionStore';
import { DemoAccount } from './DemoAccount';

@Component
export struct EasLocalDataConfirmation {
  @Prop campus: EasCampus = EasCampus.SHENZHEN;
  @Prop active: boolean = true;
  @State busy: boolean = false;
  @State errorText: string = '';
  private disposed: boolean = false;
  onConfirmed: (session: EasSession) => void = () => {};

  aboutToDisappear(): void {
    this.disposed = true;
  }

  private canConfirm(): boolean {
    return this.active && !this.disposed;
  }

  private async confirm(): Promise<void> {
    if (!this.canConfirm() || this.busy) return;
    this.busy = true;
    this.errorText = '';
    try {
      const store = EasSessionStore.getInstance();
      await store.init(this.getUIContext().getHostContext() as common.Context);
      if (!this.canConfirm()) return;
      const session: EasSession = DemoAccount.createSession(this.campus);
      const saved: boolean = await store.save(session);
      if (!this.canConfirm()) return;
      if (saved) this.onConfirmed(session);
      else this.errorText = '无法启用本地数据，请确认当前校区已退出登录后重试';
    } catch (_) {
      if (this.canConfirm()) this.errorText = '无法启用本地数据，请重试';
    } finally {
      if (this.canConfirm()) this.busy = false;
    }
  }

  build() {
    Column({ space: HitaDesign.spaceSm }) {
      if (this.errorText.length > 0) {
        Text(this.errorText)
          .fontSize(HitaDesign.caption)
          .fontColor(HitaColors.error);
      }
      HitaButton({
        label: this.busy ? '正在启用…' : '确认使用本地数据',
        disabled: this.busy,
        onTap: () => { void this.confirm(); }
      });
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .enabled(this.active);
  }
}
