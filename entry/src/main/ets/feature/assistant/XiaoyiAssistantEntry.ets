import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ButtonType, FunctionComponent, FunctionController } from '@kit.AgentFrameworkKit';
import { HitaDesign } from '../../common/theme/HitaDesign';

// Verified from the HITA Agent configuration URL on Xiaoyi Open Platform.
const HITA_AGENT_ID: string = 'agent26e52f2a50ad42059267f9077d548b6c';

/** The system component owns the click and the half-screen dialog over HITA. */
@Component
export struct XiaoyiAssistantEntry {
  @Prop glyphTint: ResourceColor = $r('sys.color.ohos_id_color_text_secondary');
  private controller: FunctionController = new FunctionController();

  private onAgentOpened = (): void => {
    hilog.info(0x0000, 'HitaAgent', 'dialog opened');
  };

  private onAgentClosed = (): void => {
    hilog.info(0x0000, 'HitaAgent', 'dialog closed');
  };

  aboutToAppear(): void {
    hilog.debug(0x0000, 'HitaAgent', 'entry mounted');
    this.controller.on('agentDialogOpened', this.onAgentOpened);
    this.controller.on('agentDialogClosed', this.onAgentClosed);
  }

  aboutToDisappear(): void {
    hilog.debug(0x0000, 'HitaAgent', 'entry unmounted');
    this.controller.off('agentDialogOpened', this.onAgentOpened);
    this.controller.off('agentDialogClosed', this.onAgentClosed);
  }

  private onAgentError(error: BusinessError): void {
    hilog.warn(0x0000, 'HitaAgent', 'dialog failed code=%{public}d', error.code);
    this.getUIContext().getPromptAction().showToast({ message: '暂时无法呼出助手，请检查网络和小艺服务后重试' });
  }

  build() {
    Column({ space: HitaDesign.dockIconLabelGap }) {
      // The native button gets its full hit box while its visible icon occupies
      // the same 20 vp row as the other Dock icons.
      Stack() {
      // Keep the documented native control visible and clickable. Its controller
      // has no public open() API; do not simulate a click or launch VoiceAbility.
      FunctionComponent({
        agentId: HITA_AGENT_ID,
        controller: this.controller,
        onError: (error: BusinessError): void => this.onAgentError(error),
        options: {
          title: '',
          buttonType: ButtonType.CAPSULE,
          controlSize: ControlSize.SMALL,
          iconSize: HitaDesign.iconMd,
          iconColors: [this.glyphTint],
          backgroundColor: Color.Transparent,
          isShowShadow: false,
          queryText: ''
        }
      })
        // The native icon row reserves 8 vp on both sides of its image.
        .width(HitaDesign.iconMd + HitaDesign.spaceXs * 2)
        .height(HitaDesign.compactControlHeight)
        .onTouch((event: TouchEvent): void => {
          if (event.type === TouchType.Down || event.type === TouchType.Up || event.type === TouchType.Cancel) {
            hilog.debug(0x0000, 'HitaAgent', 'native touch type=%{public}d', event.type);
          }
        })
        .accessibilityText('助手，呼出小艺 HITA 助手');
      }
      .width(HitaDesign.iconMd + HitaDesign.spaceXs * 2)
      .height(HitaDesign.iconMd)
      .responseRegion({ x: 0, y: (HitaDesign.iconMd - HitaDesign.compactControlHeight) / 2,
        width: HitaDesign.iconMd + HitaDesign.spaceXs * 2, height: HitaDesign.compactControlHeight })
      .clip(false);
      Text('助手')
        .fontSize(HitaDesign.dockLabel)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.glyphTint)
        .maxLines(1)
        .hitTestBehavior(HitTestMode.None)
        .accessibilityLevel('no');
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center);
  }
}
