import { ImmersiveHeader } from '../../../common/components/ImmersiveHeader';
import { CompatibleMaterialModifier } from '../../../common/theme/CompatibleMaterialModifier';
import { TimetableChangeGroup, TimetableChangeKind, TimetableUpdateDiff } from '../data/TimetableUpdateDiff';

/** 教务课表的变化清单：逐条列出，由用户决定是否以教务课表为准更新。 */
@CustomDialog
export struct TimetableUpdateDialog {
  controller: CustomDialogController;
  changes: TimetableChangeGroup[] = [];
  onApply: () => Promise<void> = async () => {};
  onDismiss: () => Promise<void> = async () => {};
  @State busy: boolean = false;
  @State errorText: string = '';

  private async apply(): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    this.errorText = '';
    try {
      await this.onApply();
      this.controller.close();
    } catch (_) {
      this.errorText = '课表更新失败，请稍后重试';
    } finally {
      this.busy = false;
    }
  }

  private async dismiss(): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    try {
      await this.onDismiss();
    } catch (_) {
      // 记录失败只会让同一变化下次再提醒一次。
    } finally {
      this.busy = false;
    }
    this.controller.close();
  }

  private kindColor(kind: TimetableChangeKind): ResourceColor {
    if (kind === TimetableChangeKind.REMOVED) {
      return $r('app.color.hita_error');
    }
    if (kind === TimetableChangeKind.ADDED) {
      return $r('app.color.hita_primary');
    }
    return $r('app.color.hita_link');
  }

  build() {
    Column() {
      this.panel()
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
  }

  @Builder
  panel() {
    Column({ space: 14 }) {
      Column({ space: 4 }) {
        Text('教务课表有更新').fontSize(20).fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.hita_text')).width('100%')
        Text('共 ' + this.changes.length.toString() + ' 处变化').fontSize(13)
          .fontColor($r('app.color.hita_text_secondary')).width('100%')
      }
      Scroll() {
        Column({ space: 12 }) {
          ForEach(this.changes, (change: TimetableChangeGroup) => {
            Row({ space: 10 }) {
              Text(TimetableUpdateDiff.kindLabel(change.kind)).fontSize(13).fontWeight(FontWeight.Medium)
                .fontColor(this.kindColor(change.kind)).margin({ top: 1 })
              Column({ space: 2 }) {
                Text(TimetableUpdateDiff.displayName(change.name)).fontSize(15).fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.hita_text')).width('100%')
                Text(TimetableUpdateDiff.detailText(change)).fontSize(13)
                  .fontColor($r('app.color.hita_text_secondary')).width('100%')
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
            .accessibilityText(TimetableUpdateDiff.describe(change))
          }, (change: TimetableChangeGroup, index: number): string => index.toString() + TimetableUpdateDiff.describe(change))
        }
        .width('100%')
      }
      .width('100%')
      .constraintSize({ maxHeight: 340 })
      .scrollBar(BarState.Auto)
      Text(this.errorText.length > 0 ? this.errorText :
        '只同步上面这些教务端的变化；你翘过、改过或添加的课程保持不变，考试等其他日程不受影响。')
        .fontSize(12)
        .fontColor(this.errorText.length > 0 ? $r('app.color.hita_error') : $r('app.color.hita_text_secondary'))
        .width('100%')
      ImmersiveHeader({ barHeight: 44 }) {
        Row({ space: 12 }) {
          Button('暂不更新', { type: ButtonType.Capsule }).layoutWeight(1).height(44).enabled(!this.busy)
            .fontColor($r('app.color.hita_text')).backgroundColor($r('app.color.hita_surface_soft'))
            .attributeModifier(new CompatibleMaterialModifier($r('app.color.hita_surface_soft')))
            .onClick(() => this.dismiss())
          Button(this.busy ? '更新中' : '更新', { type: ButtonType.Capsule }).layoutWeight(1).height(44).enabled(!this.busy)
            .fontColor(CompatibleMaterialModifier.foreground('#FFFFFF')).backgroundColor($r('app.color.hita_primary_fill'))
            .attributeModifier(new CompatibleMaterialModifier($r('app.color.hita_primary_fill')))
            .onClick(() => this.apply())
        }.width('100%')
      }
    }.width('100%').padding(24).backgroundColor($r('app.color.hita_surface')).borderRadius(24)
  }
}
