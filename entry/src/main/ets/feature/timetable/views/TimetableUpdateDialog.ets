import { HitaDesign } from '../../../common/theme/HitaDesign';
import { HitaButton, HitaButtonVariant } from '../../../common/components/HitaButton';
import { TimetableChangeGroup, TimetableChangeKind, TimetableUpdateDiff } from '../data/TimetableUpdateDiff';

/** Line height of a 16 fp course name; the 14 fp change label shares it so both sit on one baseline row. */
const KIND_LINE_HEIGHT: number = 22;

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
    Column({ space: HitaDesign.spaceMd }) {
      Column({ space: HitaDesign.space2xs }) {
        Text('教务课表有更新').fontSize(HitaDesign.title).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.hita_text')).width('100%')
        Text('共 ' + this.changes.length.toString() + ' 处变化').fontSize(HitaDesign.caption)
          .fontColor($r('app.color.hita_text_secondary')).width('100%')
      }
      Scroll() {
        Column({ space: 12 }) {
          ForEach(this.changes, (change: TimetableChangeGroup) => {
            Row({ space: HitaDesign.spaceSm }) {
              Text(TimetableUpdateDiff.kindLabel(change.kind)).fontSize(HitaDesign.caption).fontWeight(FontWeight.Medium)
                .fontColor(this.kindColor(change.kind)).lineHeight(KIND_LINE_HEIGHT)
              Column({ space: HitaDesign.space2xs }) {
                Text(TimetableUpdateDiff.displayName(change.name)).fontSize(HitaDesign.body).fontWeight(FontWeight.Medium)
                  .lineHeight(KIND_LINE_HEIGHT)
                  .fontColor($r('app.color.hita_text')).width('100%')
                Text(TimetableUpdateDiff.detailText(change)).fontSize(HitaDesign.caption)
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
      if (this.errorText.length > 0) {
        Text(this.errorText)
          .fontSize(HitaDesign.caption)
          .fontColor($r('app.color.hita_error'))
          .width('100%')
      }
      Row({ space: HitaDesign.gap }) {
        HitaButton({ label: '暂不更新', variant: HitaButtonVariant.NEUTRAL, buttonHeight: HitaDesign.minTouchTarget,
          disabled: this.busy, onTap: () => { void this.dismiss(); } })
          .width(0)
          .layoutWeight(1)
        HitaButton({ label: this.busy ? '更新中' : '更新', variant: HitaButtonVariant.PRIMARY, buttonHeight: HitaDesign.minTouchTarget,
          disabled: this.busy, onTap: () => { void this.apply(); } })
          .width(0)
          .layoutWeight(1)
      }.width('100%')
    }.width('100%').padding(HitaDesign.spaceLg).backgroundColor($r('app.color.hita_surface')).borderRadius(HitaDesign.heroRadius)
  }
}
