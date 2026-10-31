import { deviceInfo } from '@kit.BasicServicesKit';
import lazy { XiaoyiAssistantEntry } from './XiaoyiAssistantEntry';
import { HitaDesign } from '../../common/theme/HitaDesign';

/** Shared fourth action for the native bottom bar, fallback dock and side rail. */
@Component
export struct AssistantDockItem {
  @Prop glyphTint: ResourceColor = $r('sys.color.ohos_id_color_text_secondary');
  build() {
    Column() {
      if (canIUse('SystemCapability.AI.Agent.AgentKit') &&
        (deviceInfo.deviceType === 'phone' || deviceInfo.deviceType === 'tablet')) {
        XiaoyiAssistantEntry({ glyphTint: this.glyphTint });
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
