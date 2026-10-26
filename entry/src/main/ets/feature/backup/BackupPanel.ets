import { HitaDesign } from '../../common/theme/HitaDesign';
import { common } from '@kit.AbilityKit';
import { HeaderBackButton } from '../../common/components/HeaderBackButton';
import { ImmersiveHeader } from '../../common/components/ImmersiveHeader';
import { CompatibleSheetMaterial } from '../../common/theme/CompatibleSheetMaterial';
import { CompatibleMaterialModifier } from '../../common/theme/CompatibleMaterialModifier';
import { STATUS_BAR_INSET_FALLBACK, NAV_BAR_INSET_FALLBACK } from '../../common/theme/StatusBarInset';
import { BackupService } from './BackupService';
import { PreparedBackup } from './BackupArchive';

@Component
export struct BackupPanel {
  @Prop presentedAsSheet: boolean = false;
  onClose: () => void = () => {};
  onBusyChanged: (busy: boolean) => void = () => {};
  onRestored: () => void = () => {};
  @StorageProp('hita_status_bar_vp') statusBarInset: number = STATUS_BAR_INSET_FALLBACK;
  @StorageProp('hita_nav_bar_vp') navBarInset: number = NAV_BAR_INSET_FALLBACK;
  @State busy: boolean = false;
  @State status: string = '';
  @State failed: boolean = false;
  @State prepared: PreparedBackup | undefined = undefined;

  aboutToDisappear(): void {
    BackupService.discard(this.prepared);
  }
  onBackPress(): boolean { return this.busy; }
  private context(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }
  private setBusy(busy: boolean): void {
    this.busy = busy;
    this.onBusyChanged(busy);
  }
  private navigateBack(): void {
    if (this.busy) return;
    if (this.presentedAsSheet) this.onClose();
    else this.getUIContext().getRouter().back();
  }
  private progress(message: string): void { this.status = message; }

  private async createBackup(): Promise<void> {
    if (this.busy) return;
    this.setBusy(true);
    this.failed = false;
    try {
      const saved = await BackupService.exportFile(this.context(), message => this.progress(message));
      this.status = saved ? '备份已保存' : '';
    } catch (error) { this.showError(error as Error); }
    finally { this.setBusy(false); }
  }
  private async chooseBackup(): Promise<void> {
    if (this.busy) return;
    this.setBusy(true);
    this.failed = false;
    this.status = '';
    try {
      const next = await BackupService.pick(this.context(), message => this.progress(message));
      if (next !== undefined) {
        BackupService.discard(this.prepared);
        this.prepared = next;
      }
      this.status = '';
    } catch (error) { this.showError(error as Error); }
    finally { this.setBusy(false); }
  }
  private confirmRestore(): void {
    if (this.busy || this.prepared === undefined) return;
    this.getUIContext().showAlertDialog({
      title: '恢复此备份？',
      message: '现有课表会保留，备份课表将恢复为新副本。提醒、显示设置和背景将替换为备份中的内容。',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: '恢复', action: () => { void this.restoreBackup(); } }
    });
  }
  private async restoreBackup(): Promise<void> {
    if (this.busy || this.prepared === undefined) return;
    this.setBusy(true);
    this.failed = false;
    try {
      await BackupService.restore(this.context(), this.prepared, message => this.progress(message));
      BackupService.discard(this.prepared);
      this.prepared = undefined;
      this.status = '备份已恢复，现有课表已保留';
      this.onRestored();
    } catch (error) { this.showError(error as Error); }
    finally { this.setBusy(false); }
  }
  private showError(error: Error): void {
    this.failed = true;
    this.status = /[\u4e00-\u9fff]/.test(error.message) ? error.message : '操作未完成，请检查文件及可用空间后重试';
  }
  private summary(): string {
    const m = this.prepared?.manifest;
    if (m === undefined) return '';
    const events = m.timetables.reduce((count, item) => count + item.events.length, 0);
    return m.timetables.length.toString() + ' 张课表 · ' + events.toString() + ' 项课程与考试';
  }
  private mediaSummary(): string {
    const m = this.prepared?.manifest;
    if (m === undefined) return '';
    const bytes = m.assets.reduce((count, item) => count + item.size, 0);
    return bytes > 0 ? '提醒、显示设置及背景 · ' + (bytes / 1024 / 1024).toFixed(1) + ' MB' : '提醒与显示设置';
  }

  build() {
    Column() {
      ImmersiveHeader({ barHeight: 60, materialEnabled: !this.presentedAsSheet || CompatibleSheetMaterial.isEnabled() }) {
        Row({ space: 12 }) {
          HeaderBackButton({ onBack: () => this.navigateBack() })
            .enabled(!this.busy)
          Text('备份与恢复').fontSize(HitaDesign.title).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.hita_text_1a1a1a')).layoutWeight(1)
        }.width('100%').height(60).padding({ left: 16, right: 16 })
      }
      Scroll() {
        Column({ space: 16 }) {
          Column({ space: 16 }) {
            Row({ space: 14 }) {
              SymbolGlyph($r('sys.symbol.doc_plaintext')).fontSize(HitaDesign.display).fontColor([$r('app.color.hita_primary')])
              Column({ space: 5 }) {
                Text('保存你的课表').fontSize(HitaDesign.section).fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.hita_text_1a1a1a'))
                Text('课表、考试、颜色、提醒与显示设置').fontSize(HitaDesign.caption)
                  .fontColor($r('app.color.hita_text_secondary_566276'))
                Text('包含背景图片、视频及服务卡片背景').fontSize(HitaDesign.caption)
                  .fontColor($r('app.color.hita_text_secondary_566276'))
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            }.width('100%')
            Button('创建备份').width('100%').height(44)
              .backgroundColor($r('app.color.hita_primary')).fontColor(Color.White)
              .attributeModifier(new CompatibleMaterialModifier($r('app.color.hita_primary'), true))
              .enabled(!this.busy).onClick(() => { void this.createBackup(); })
          }.width('100%').padding(20).backgroundColor(this.presentedAsSheet ? CompatibleSheetMaterial.cardColor($r('app.color.hita_surface')) :
            $r('app.color.hita_surface')).borderRadius(HitaDesign.cardRadius)

          Column({ space: 14 }) {
            Text('从备份恢复').fontSize(HitaDesign.section).fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.hita_text_1a1a1a')).alignSelf(ItemAlign.Start)
            Button('选择备份文件').width('100%').height(44)
              .backgroundColor($r('app.color.hita_selected')).fontColor($r('app.color.hita_primary'))
              .attributeModifier(new CompatibleMaterialModifier($r('app.color.hita_selected')))
              .enabled(!this.busy).onClick(() => { void this.chooseBackup(); })
            if (this.prepared !== undefined) {
              Column({ space: 8 }) {
                Text(new Date(this.prepared.manifest.createdAt).toLocaleString()).fontSize(HitaDesign.caption)
                  .fontColor($r('app.color.hita_text_secondary_566276'))
                Text(this.summary()).fontSize(HitaDesign.body).fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.hita_text_1a1a1a'))
                Text(this.mediaSummary()).fontSize(HitaDesign.caption).fontColor($r('app.color.hita_text_secondary_566276'))
              }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 4, bottom: 4 })
              Button('恢复此备份').width('100%').height(44)
                .backgroundColor($r('app.color.hita_primary')).fontColor(Color.White)
                .attributeModifier(new CompatibleMaterialModifier($r('app.color.hita_primary'), true))
                .enabled(!this.busy).onClick(() => this.confirmRestore())
            }
          }.width('100%').padding(20).backgroundColor(this.presentedAsSheet ? CompatibleSheetMaterial.cardColor($r('app.color.hita_surface')) :
            $r('app.color.hita_surface')).borderRadius(HitaDesign.cardRadius)
          if (this.status.length > 0) {
            Row({ space: HitaDesign.gap }) {
              if (this.busy) { LoadingProgress().width(20).height(20).color($r('app.color.hita_primary')) }
              Text(this.status).fontSize(HitaDesign.caption)
                .fontColor(this.failed ? '#D94A50' : $r('app.color.hita_text_secondary_566276')).layoutWeight(1)
            }.width('100%').padding({ left: 8, right: 8 })
          }
          Text('备份不含教务登录信息及手机日历同步登记').fontSize(HitaDesign.label)
            .fontColor($r('app.color.hita_text_secondary_566276')).padding({ top: 4 })
        }.width('100%').padding({ left: 16, right: 16, top: 16, bottom: this.navBarInset + 24 })
      }.width('100%').layoutWeight(1).align(Alignment.Top).scrollBar(BarState.Off)
    }.width('100%').height('100%').padding({ top: this.presentedAsSheet ? 0 : this.statusBarInset })
      .backgroundColor(this.presentedAsSheet ? CompatibleSheetMaterial.bodyColor($r('app.color.hita_page_f6f7fa')) :
        $r('app.color.hita_page_f6f7fa'))
  }
}
