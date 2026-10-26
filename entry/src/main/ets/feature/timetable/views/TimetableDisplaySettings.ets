import { HitaDesign } from '../../../common/theme/HitaDesign';
import { ImmersiveHeader } from '../../../common/components/ImmersiveHeader';
import { CompatibleMaterialModifier } from '../../../common/theme/CompatibleMaterialModifier';
import { CompatibleSheetMaterial } from '../../../common/theme/CompatibleSheetMaterial';
import { TimetableTheme } from '../../../common/theme/TimetableTheme';
import { TimetableDisplayOptions } from '../data/TimetableDisplayOptions';
import { CourseColorEditor } from './CourseColorEditor';

@Component
export struct TimetableDisplaySettings {
  @Prop options: TimetableDisplayOptions = new TimetableDisplayOptions();
  @Prop textColor: string = TimetableTheme.AUTO_TEXT;
  @Prop darkMode: boolean = false;
  @Prop hasWallpaper: boolean = false;
  @Prop adaptiveTextColor: string = TimetableTheme.DEFAULT_TEXT;
  @Prop adaptiveLineColor: string = '#D7DEE8';
  @State editing: string = '';
  @State maskValue: number = 0;
  @State saving: boolean = false;
  @State errorText: string = '';
  onSave: (options: TimetableDisplayOptions) => Promise<void> = async () => {};
  onTextColorSave: (color: string) => Promise<void> = async () => {};
  onMaskPreview: (value: number) => void = () => {};
  onClose: () => void = () => {};

  aboutToAppear(): void { this.maskValue = this.options.wallpaperMask; }

  aboutToDisappear(): void {
    if (this.maskValue !== this.options.wallpaperMask && !this.saving) this.saveMask();
  }

  private async save(next: TimetableDisplayOptions): Promise<void> {
    if (this.saving) return;
    this.saving = true;
    this.errorText = '';
    try {
      await this.onSave(next);
    } catch (_) {
      this.errorText = '设置未保存，请重试';
      this.maskValue = this.options.wallpaperMask;
      this.onMaskPreview(this.maskValue);
      throw new Error('Display settings save failed');
    } finally {
      this.saving = false;
    }
  }

  private async switchLines(value: boolean): Promise<void> {
    if (value === this.options.drawTimeLines) return;
    const next = this.options.copy();
    next.drawTimeLines = value;
    try { await this.save(next); } catch (_) {}
  }

  private async switchEvening(value: boolean): Promise<void> {
    if (value === this.options.eveningHint) return;
    const next = this.options.copy();
    next.eveningHint = value;
    try { await this.save(next); } catch (_) {}
  }

  private async saveMask(): Promise<void> {
    if (this.saving || this.maskValue === this.options.wallpaperMask) return;
    const next = this.options.copy();
    next.wallpaperMask = this.maskValue;
    try { await this.save(next); } catch (_) {}
  }

  private async saveColor(color: number): Promise<void> {
    const hex = '#' + (color & 0xFFFFFF).toString(16).padStart(6, '0').toUpperCase();
    if (this.editing === 'line') {
      const next = this.options.copy();
      next.timeLineColor = hex;
      await this.save(next);
    } else {
      await this.onTextColorSave(hex);
    }
    this.editing = '';
  }

  private automaticColor(): boolean {
    return this.editing === 'line' ? this.options.timeLineColor.length === 0 :
      this.textColor === TimetableTheme.AUTO_TEXT;
  }

  private async switchAutomatic(value: boolean): Promise<void> {
    if (this.saving || value === this.automaticColor()) return;
    if (this.editing === 'line') {
      const next = this.options.copy();
      next.timeLineColor = value ? '' : this.adaptiveLineColor;
      try { await this.save(next); } catch (_) {}
      return;
    }
    this.saving = true;
    this.errorText = '';
    try {
      await this.onTextColorSave(value ? TimetableTheme.AUTO_TEXT : this.adaptiveTextColor);
    } catch (_) {
      this.errorText = '设置未保存，请重试';
    } finally {
      this.saving = false;
    }
  }

  @Builder
  private colorSetting(title: string, mode: string) {
    Row({ space: 12 }) {
      Text(title).fontSize(HitaDesign.body).fontColor($r('app.color.hita_text')).layoutWeight(1)
      Column() {
        ImmersiveHeader({ barHeight: 40, materialEnabled: CompatibleSheetMaterial.isEnabled() }) {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.paintpalette')).fontSize(20)
              .fontColor([CompatibleMaterialModifier.foreground($r('app.color.hita_primary'))])
          }.width(40).height(40).backgroundColor($r('app.color.hita_selected'))
            .attributeModifier(new CompatibleMaterialModifier($r('app.color.hita_selected'), false,
              CompatibleSheetMaterial.isEnabled()))
            .accessibilityText(title).enabled(!this.saving)
            .onClick(() => { this.editing = mode; })
        }
      }.width(40).height(40)
    }.width('100%').constraintSize({ minHeight: 60 })
  }

  build() {
    Column({ space: 0 }) {
      Column() {
        ImmersiveHeader({ barHeight: 48, materialEnabled: CompatibleSheetMaterial.isEnabled() }) {
          Row({ space: 12 }) {
            if (this.editing.length > 0) {
              Button({ type: ButtonType.Circle }) {
                SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(20)
                  .fontColor([CompatibleMaterialModifier.foreground($r('app.color.hita_text'))])
              }.width(40).height(40).backgroundColor($r('app.color.hita_selected'))
                .attributeModifier(new CompatibleMaterialModifier($r('app.color.hita_selected'), false,
                  CompatibleSheetMaterial.isEnabled()))
                .accessibilityText('返回显示设置').enabled(!this.saving).onClick(() => { this.editing = ''; })
            }
            Text(this.editing === 'line' ? '背景时间虚线颜色' :
              (this.editing === 'text' ? '课表文字颜色' : '显示设置')).fontSize(HitaDesign.title).fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.hita_text')).layoutWeight(1)
            if (this.editing.length === 0) {
              Button({ type: ButtonType.Circle }) {
                SymbolGlyph($r('sys.symbol.xmark')).fontSize(HitaDesign.section)
                  .fontColor([CompatibleMaterialModifier.foreground($r('app.color.hita_text_secondary'))])
              }.width(40).height(40).backgroundColor($r('app.color.hita_selected'))
                .attributeModifier(new CompatibleMaterialModifier($r('app.color.hita_selected'), false,
                  CompatibleSheetMaterial.isEnabled()))
                .accessibilityText('关闭显示设置').enabled(!this.saving).onClick(() => this.onClose())
            }
          }.width('100%')
        }
      }.width('100%').margin({ bottom: 12 })
      if (this.editing.length > 0) {
        Row({ space: 12 }) {
          Text('自动适应背景').fontSize(HitaDesign.body).fontColor($r('app.color.hita_text')).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.automaticColor() })
            .selectedColor($r('app.color.hita_primary')).enabled(!this.saving)
            .accessibilityText('自动适应背景').onChange((value: boolean) => this.switchAutomatic(value))
        }.width('100%').constraintSize({ minHeight: 60 })
        if (!this.automaticColor()) {
          CourseColorEditor({
            initialColor: (0xFF000000 | parseInt((this.editing === 'line' ?
              this.options.lineColor(this.darkMode) : this.textColor).substring(1), 16)) >>> 0,
            textMode: this.editing === 'text',
            lineMode: this.editing === 'line',
            immersiveControls: true,
            previewDark: this.darkMode,
            previewWallpaper: this.hasWallpaper,
            presets: (this.editing === 'line' ? ['#D7DEE8', '#3A414B', '#FFFFFF', '#E53935',
              '#F9A825', '#43A047', '#1E88E5'] : TimetableTheme.PALETTE).map((color: string): number =>
                (0xFF000000 | parseInt(color.substring(1), 16)) >>> 0),
            onSave: async (color: number) => { await this.saveColor(color); },
            onCancel: () => { this.editing = ''; }
          })
        }
      } else {
        Row({ space: 12 }) {
          Text('绘制背景时间虚线').fontSize(HitaDesign.body).fontColor($r('app.color.hita_text')).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.options.drawTimeLines })
            .selectedColor($r('app.color.hita_primary')).enabled(!this.saving)
            .accessibilityText('绘制背景时间虚线').onChange((value: boolean) => this.switchLines(value))
        }.width('100%').constraintSize({ minHeight: 60 })
        Divider().color($r('app.color.hita_surface_soft'))
        this.colorSetting('背景时间虚线颜色', 'line')
        Divider().color($r('app.color.hita_surface_soft'))
        Row({ space: 12 }) {
          Text('显示晚间课程提示').fontSize(HitaDesign.body).fontColor($r('app.color.hita_text')).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.options.eveningHint })
            .selectedColor($r('app.color.hita_primary')).enabled(!this.saving)
            .accessibilityText('显示晚间课程提示').onChange((value: boolean) => this.switchEvening(value))
        }.width('100%').constraintSize({ minHeight: 60 })
        Divider().color($r('app.color.hita_surface_soft'))
        Column({ space: 4 }) {
          Row() {
            Text('背景蒙版深度').fontSize(HitaDesign.body).fontColor($r('app.color.hita_text')).layoutWeight(1)
            Text(this.maskValue + '%').fontSize(HitaDesign.caption).fontColor($r('app.color.hita_primary'))
          }.width('100%')
          Slider({ value: this.maskValue, min: 0, max: 80, step: 1 })
            .width('100%').selectedColor($r('app.color.hita_primary')).enabled(!this.saving)
            .accessibilityText('背景蒙版深度')
            .onChange((value: number, mode: SliderChangeMode) => {
              this.maskValue = Math.round(value);
              this.onMaskPreview(this.maskValue);
              if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) this.saveMask();
            })
            .onTouch((event: TouchEvent) => { if (event.type === TouchType.Cancel) this.saveMask(); })
        }.width('100%').padding({ top: 16, bottom: 8 })
        Divider().color($r('app.color.hita_surface_soft'))
        this.colorSetting('课表文字颜色', 'text')
      }
      if (this.errorText.length > 0) {
        Text(this.errorText).fontSize(HitaDesign.caption).fontColor($r('app.color.hita_error')).width('100%').margin({ top: 8 })
      }
    }.width('100%').padding({ left: 20, right: 20, bottom: 20 })
  }
}
