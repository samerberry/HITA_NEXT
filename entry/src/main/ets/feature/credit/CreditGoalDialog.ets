import { HitaDesign } from '../../common/theme/HitaDesign';
import { ImmersiveHeader } from '../../common/components/ImmersiveHeader';
import { CompatibleMaterialModifier } from '../../common/theme/CompatibleMaterialModifier';

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
      Text(this.categoryName + '学分目标').fontSize(20).fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.hita_text')).width('100%')
      TextInput({ text: this.value, placeholder: '目标学分' }).type(InputType.NUMBER_DECIMAL)
        .fontSize(18).height(48).onChange((value: string) => { this.value = value; this.errorText = ''; })
        .enabled(!this.saving)
      Text(this.errorText || '设为 0 可取消目标').fontSize(HitaDesign.caption)
        .fontColor(this.errorText ? $r('app.color.hita_error') : $r('app.color.hita_text_secondary')).width('100%')
      ImmersiveHeader({ barHeight: 44 }) {
        Row({ space: 12 }) {
          Button('取消', { type: ButtonType.Capsule }).layoutWeight(1).height(44).enabled(!this.saving)
            .fontColor($r('app.color.hita_text')).backgroundColor($r('app.color.hita_surface_soft'))
            .attributeModifier(new CompatibleMaterialModifier($r('app.color.hita_surface_soft')))
            .onClick(() => this.controller.close())
          Button(this.saving ? '保存中' : '保存', { type: ButtonType.Capsule }).layoutWeight(1).height(44).enabled(!this.saving)
            .fontColor(CompatibleMaterialModifier.foreground('#FFFFFF')).backgroundColor($r('app.color.hita_primary_fill'))
            .attributeModifier(new CompatibleMaterialModifier($r('app.color.hita_primary_fill')))
            .onClick(() => this.save())
        }.width('100%')
      }
    }.width('100%').padding(24).backgroundColor($r('app.color.hita_surface')).borderRadius(24)
  }
}
