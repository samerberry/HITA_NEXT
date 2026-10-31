import { common } from '@kit.AbilityKit';
import { CampusOperation, CampusSkillService } from '../feature/assistant/CampusSkillService';
import { HitaDesign } from '../common/theme/HitaDesign';
import { HitaColors } from '../common/theme/HitaColors';
import { HitaButton, HitaButtonVariant } from '../common/components/HitaButton';
import { HeaderBackButton } from '../common/components/HeaderBackButton';
import { ImmersiveHeader } from '../common/components/ImmersiveHeader';
import { CompatibleMaterialModifier } from '../common/theme/CompatibleMaterialModifier';
import { EasEventItem } from '../common/model/timetable/TimetableModels';
import { STATUS_BAR_INSET_FALLBACK, NAV_BAR_INSET_FALLBACK } from '../common/theme/StatusBarInset';

@Entry
@Component
struct CampusSkillConfirmPage {
  @StorageProp('hita_campus_operation') @Watch('reload') operationId: string = '';
  @StorageProp('hita_status_bar_vp') topInset: number = STATUS_BAR_INSET_FALLBACK;
  @StorageProp('hita_nav_bar_vp') bottomInset: number = NAV_BAR_INSET_FALLBACK;
  @State operation: CampusOperation | undefined = undefined;
  @State warning: string = '';
  @State message: string = '';
  @State busy: boolean = true;
  private generation: number = 0;

  aboutToAppear(): void { void this.reload(); }
  aboutToDisappear(): void { this.generation++; }
  onBackPress(): boolean {
    if (!this.busy) this.close();
    return true;
  }

  private context(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }

  private async reload(): Promise<void> {
    const generation = ++this.generation;
    this.busy = true;
    this.operation = undefined;
    this.message = '';
    this.warning = '';
    try {
      const operation = await CampusSkillService.operation(this.context(), this.operationId);
      const conflicts = operation.status === 'pending' ? await CampusSkillService.conflicts(this.context(), operation) : [];
      if (generation !== this.generation) return;
      this.operation = operation;
      this.warning = conflicts.length > 0 ? '与以下安排重叠：' + conflicts.map((item): string => item.name).join('、') : '';
      if (operation.status !== 'pending') this.message = operation.status === 'saved' ? '已保存' : '此操作已取消或过期';
    } catch (_) { if (generation === this.generation) this.message = '无法读取草稿，请回到小艺重新发起'; }
    finally { if (generation === this.generation) this.busy = false; }
  }

  private close(): void {
    const router = this.getUIContext().getRouter();
    router.back();
  }

  private async finish(save: boolean): Promise<void> {
    if (this.busy || this.operation === undefined) return;
    this.busy = true;
    const id = this.operation.id;
    const generation = this.generation;
    try {
      await CampusSkillService.finish(this.context(), id, save);
      if (generation !== this.generation) return;
      this.message = save ? '已保存，可返回小艺查看结果' : '已取消';
      await this.reload();
      if (!save && this.operationId === id) this.close();
    } catch (error) {
      const message = (error as Error).message || '保存失败，请稍后重试';
      try {
        // A preference failure after the DB commit must not tell the user the save failed.
        const current = await CampusSkillService.operation(this.context(), id);
        if (generation === this.generation) {
          this.operation = current;
          this.message = current.status === 'saved' ? '已保存，可返回小艺查看结果' : message;
        }
      } catch (_) { if (generation === this.generation) this.message = message; }
    }
    finally { if (this.operation?.id === id) this.busy = false; }
  }

  private time(value: number): string { return new Date(value).toLocaleString(); }

  private originalTime(): string {
    if (this.operation === undefined || this.operation.before.length === 0) return '';
    const event = JSON.parse(this.operation.before) as EasEventItem;
    return this.time(event.from) + ' 至 ' + this.time(event.to) + (event.place.length > 0 ? '，' + event.place : '');
  }

  build() {
    Column({ space: HitaDesign.sectionGap }) {
      ImmersiveHeader({ barHeight: HitaDesign.headerHeight }) {
        Row({ space: HitaDesign.gap }) {
          HeaderBackButton({ onBack: () => { if (!this.busy) this.close(); } })
          Text('确认小艺操作').fontSize(HitaDesign.title).fontWeight(FontWeight.Medium)
            .fontColor(CompatibleMaterialModifier.foreground(HitaColors.onSurface))
        }.width('100%').padding({ left: HitaDesign.inset, right: HitaDesign.inset })
      }
      Scroll() {
        Column({ space: HitaDesign.spaceLg }) {
          if (this.operation !== undefined) {
            Column({ space: HitaDesign.spaceMd }) {
              Text(this.operation.kind === 'move' ? '调整本次课程' : '添加日程')
                .fontSize(HitaDesign.caption).fontColor(HitaColors.onSurfaceVariant)
              Text(this.operation.event.name).fontSize(HitaDesign.title).fontWeight(FontWeight.Medium)
                .fontColor(HitaColors.onSurface)
              Text(this.operation.timetableName).fontSize(HitaDesign.body).fontColor(HitaColors.onSurfaceVariant)
              if (this.operation.before.length > 0) {
                Text('原安排：' + this.originalTime())
                  .fontSize(HitaDesign.body).fontColor(HitaColors.onSurfaceVariant)
              }
              Text('开始：' + this.time(this.operation.event.from)).fontSize(HitaDesign.body).fontColor(HitaColors.onSurface)
              Text('结束：' + this.time(this.operation.event.to)).fontSize(HitaDesign.body).fontColor(HitaColors.onSurface)
              if (this.operation.event.place.length > 0) {
                Text('地点：' + this.operation.event.place).fontSize(HitaDesign.body).fontColor(HitaColors.onSurface)
              }
            }.alignItems(HorizontalAlign.Start).width('100%').padding(HitaDesign.spaceLg)
              .backgroundColor($r('app.color.hita_surface')).borderRadius(HitaDesign.cardRadius)
            if (this.warning.length > 0) {
              Text(this.warning).fontSize(HitaDesign.body).fontColor(HitaColors.error).width('100%')
            }
          }
          if (this.message.length > 0) {
            Text(this.message).fontSize(HitaDesign.body).fontColor(HitaColors.onSurfaceVariant).width('100%')
          }
        }.width('100%').padding(HitaDesign.inset)
      }.layoutWeight(1)
      Row({ space: HitaDesign.gap }) {
        if (this.operation?.status === 'pending') {
          HitaButton({ label: '取消', variant: HitaButtonVariant.NEUTRAL, disabled: this.busy,
            onTap: () => { void this.finish(false); } }).layoutWeight(1)
          HitaButton({ label: this.busy ? '处理中' : '确认保存', disabled: this.busy,
            onTap: () => { void this.finish(true); } }).layoutWeight(1)
        } else {
          HitaButton({ label: '返回', disabled: this.busy, onTap: () => this.close() })
        }
      }.padding({ left: HitaDesign.inset, right: HitaDesign.inset, bottom: HitaDesign.inset })
    }.width('100%').height('100%').padding({ top: this.topInset, bottom: this.bottomInset })
      .backgroundColor($r('app.color.hita_page_f6f7fa'))
  }
}
