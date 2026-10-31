import { AssistantDockItem } from './AssistantDockItem';
import { ImmersiveHeader } from '../../common/components/ImmersiveHeader';
import { CompatibleRailModifier } from '../../common/theme/CompatibleRailModifier';
import { HitaDesign } from '../../common/theme/HitaDesign';
import { DOCK_ACTION_SIZE } from '../../common/util/DockHandedness';

/** Independent glass surface; the visible FunctionComponent still owns opening. */
@Component
export struct AssistantDockButton {
  @Prop darkMode: boolean = false;
  onButtonTouch: (event: TouchEvent) => void = () => {};

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        ImmersiveHeader({ barHeight: DOCK_ACTION_SIZE + HitaDesign.spaceMd * 2 }) {
          Column() {
            Stack() {
              AssistantDockItem()
                .width(DOCK_ACTION_SIZE)
                .height(HitaDesign.buttonHeight);
            }
            .width(DOCK_ACTION_SIZE)
            .height(DOCK_ACTION_SIZE)
            .borderRadius(DOCK_ACTION_SIZE / 2)
            .attributeModifier(new CompatibleRailModifier(this.darkMode))
            .onTouch((event: TouchEvent) => this.onButtonTouch(event));
          }
          .width('100%')
          .height(DOCK_ACTION_SIZE + HitaDesign.spaceMd * 2)
          .padding(HitaDesign.spaceMd)
          .clip(false)
          .hitTestBehavior(HitTestMode.Transparent);
        }
      }
      .width(DOCK_ACTION_SIZE + HitaDesign.spaceMd * 2)
      .height(DOCK_ACTION_SIZE + HitaDesign.spaceMd * 2)
      .position({ x: -HitaDesign.spaceMd, y: -HitaDesign.spaceMd })
      .clip(false)
      .hitTestBehavior(HitTestMode.Transparent);
    }
    .width(DOCK_ACTION_SIZE)
    .height(DOCK_ACTION_SIZE)
    .clip(false)
    // This bounded button must not pass a tap to the Tabs content underneath.
    .hitTestBehavior(HitTestMode.Default);
  }
}
