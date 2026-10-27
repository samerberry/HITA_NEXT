import { HitaDesign } from '../../common/theme/HitaDesign';
import { HitaButton, HitaButtonVariant } from '../../common/components/HitaButton';

@CustomDialog
export struct CreditGoalDialog {
  controller: CustomDialogController;
  categoryName: string = '';
  initialValue: number = 0;
  onSave: (value: number) => Promise<void> = async () => {};
  @State value: string = '';
  @State saving: boolean = false;
  @State errorText: string = '';

  aboutToAppear(): void { this.value = this.initialValue > 0 ? this.initialValue.toString() : ''; }

  private async save(): Promise<void> {
    if (this.saving) return;
    const value = Number(this.value.trim());
    if (!/^\d+(?:\.\d{1,2})?$/.test(this.value.trim()) || !Number.isFinite(value) || value < 0 || value > 1000) {
      this.errorText = '请输入 0 到 1000 之间的学分，最多两位小数';
      return;
    }
    this.saving = true;
    this.errorText = '';
    try {
      await this.onSave(value);
      this.controller.close();
    } catch (_) {
      this.errorText = '保存失败，请重试';
    } finally {
      this.saving = false;
    }
  }

  build() {
    Column({ space: 16 }) {
      Text(this.categoryName + '学分目标').fontSize(HitaDesign.title).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.hita_text')).width('100%')
      TextInput({ text: this.value, placeholder: '目标学分' }).type(InputType.NUMBER_DECIMAL)
        .fontSize(HitaDesign.section).height(HitaDesign.buttonHeight).onChange((value: string) => { this.value = value; this.errorText = ''; })
        .enabled(!this.saving)
      Text(this.errorText || '设为 0 可取消目标').fontSize(HitaDesign.caption)
        .fontColor(this.errorText ? $r('app.color.hita_error') : $r('app.color.hita_text_secondary')).width('100%')
      Row({ space: HitaDesign.gap }) {
        HitaButton({ label: '取消', variant: HitaButtonVariant.NEUTRAL, buttonHeight: HitaDesign.minTouchTarget,
          disabled: this.saving, onTap: () => { this.controller.close(); } })
          .width(0)
          .layoutWeight(1)
        HitaButton({ label: this.saving ? '保存中' : '保存', variant: HitaButtonVariant.PRIMARY, buttonHeight: HitaDesign.minTouchTarget,
          disabled: this.saving, onTap: () => { void this.save(); } })
          .width(0)
          .layoutWeight(1)
      }.width('100%')
    }.width('100%').padding(HitaDesign.spaceLg).backgroundColor($r('app.color.hita_surface')).borderRadius(HitaDesign.heroRadius)
  }
}
