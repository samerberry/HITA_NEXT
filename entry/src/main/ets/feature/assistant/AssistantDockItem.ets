import { deviceInfo } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AssistantEntryParams } from './AssistantEntryParams';
import { HitaDesign } from '../../common/theme/HitaDesign';

/** Shared fourth action for the native bottom bar, fallback dock and side rail. */
@Component
export struct AssistantDockItem {
  @Prop glyphTint: ResourceColor = $r('sys.color.ohos_id_color_text_secondary');
  @State private nativeEntry: WrappedBuilder<[AssistantEntryParams]> | undefined = undefined;
  private mounted: boolean = false;
  private loadGeneration: number = 0;

  private supportsAssistant(): boolean {
    // API 23 emulator images advertise AgentKit even though agentKitHsp is absent.
    // Avoid resolving that system HSP: its loader can abort before a catch runs.
    return !deviceInfo.productModel.toLowerCase().includes('emulator') &&
      (deviceInfo.deviceType === 'phone' || deviceInfo.deviceType === 'tablet') &&
      canIUse('SystemCapability.AI.Agent.AgentKit');
  }

  async aboutToAppear(): Promise<void> {
    this.mounted = true;
    const generation: number = ++this.loadGeneration;
    this.nativeEntry = undefined;
    if (!this.supportsAssistant()) return;
    try {
      // A lazy static import still enters the startup module dependency graph.
      // Only resolve the native component after checking the actual environment.
      const entry = await import('./XiaoyiAssistantEntry');
      if (!this.mounted || generation !== this.loadGeneration) return;
      this.nativeEntry = entry.createXiaoyiAssistantBuilder();
    } catch (_) {
      if (!this.mounted || generation !== this.loadGeneration) return;
      hilog.warn(0x0000, 'HitaAgent', 'native entry unavailable; using fallback');
    }
  }

  aboutToDisappear(): void {
    this.mounted = false;
    ++this.loadGeneration;
  }

  build() {
    Column() {
      if (this.nativeEntry !== undefined) {
        this.nativeEntry.builder({ glyphTint: this.glyphTint });
      } else {
        Column({ space: HitaDesign.dockIconLabelGap }) {
          SymbolGlyph($r('sys.symbol.AI_message'))
            .fontSize(HitaDesign.iconMd)
            .fontColor([this.glyphTint]);
          Text('助手')
            .fontSize(HitaDesign.dockLabel)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.glyphTint);
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .accessibilityText('助手，当前设备暂不支持')
        .onClick(() => {
          this.getUIContext().getPromptAction().showToast({ message: '请在支持小艺的手机或平板上使用助手' });
        });
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center);
  }
}
