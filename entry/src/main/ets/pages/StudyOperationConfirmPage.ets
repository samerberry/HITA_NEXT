import { common } from '@kit.AbilityKit';
import { StudyOperation } from '../common/model/learning/StudyOperation';
import { StudyAssistantService } from '../feature/assistant/StudyAssistantService';
import { HitaDesign } from '../common/theme/HitaDesign';
import { HitaColors } from '../common/theme/HitaColors';
import { HitaButton, HitaButtonVariant } from '../common/components/HitaButton';
import { HeaderBackButton } from '../common/components/HeaderBackButton';
import { ImmersiveHeader } from '../common/components/ImmersiveHeader';
import { CompatibleMaterialModifier } from '../common/theme/CompatibleMaterialModifier';
import { STATUS_BAR_INSET_FALLBACK, NAV_BAR_INSET_FALLBACK } from '../common/theme/StatusBarInset';
import { ClassReminderScheduler } from '../feature/timetable/data/ClassReminderScheduler';

@Entry
@Component
struct StudyOperationConfirmPage {
  @StorageProp('hita_study_operation') @Watch('reload') operationId: string = '';
  @StorageProp('hita_status_bar_vp') topInset: number = STATUS_BAR_INSET_FALLBACK;
  @StorageProp('hita_nav_bar_vp') bottomInset: number = NAV_BAR_INSET_FALLBACK;
  @State operation: StudyOperation | undefined = undefined;
  @State busy: boolean = true;
  @State message: string = '';
  private generation: number = 0;
  private active: boolean = false;

  aboutToAppear(): void { this.active = true; void this.reload(); }
  aboutToDisappear(): void { this.active = false; this.generation++; }
  onBackPress(): boolean { if (!this.busy) this.close(); return true; }

  private context(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }

  private async reload(): Promise<void> {
    const generation: number = ++this.generation;
    this.operation = undefined; this.busy = true; this.message = '';
    try {
      const operation: StudyOperation = await StudyAssistantService.operation(this.context(), this.operationId);
      if (!this.active || generation !== this.generation) return;
      this.operation = operation;
      this.message = this.statusMessage(operation);
    } catch (_) { if (this.active && generation === this.generation) this.message = '无法读取操作，请回到小艺重新发起'; }
    finally { if (this.active && generation === this.generation) this.busy = false; }
  }

  private statusMessage(operation: StudyOperation): string {
    return operation.status === 'saved' ? (operation.kind === 'complete' ? '已标记完成' : '已添加到学习待办') :
      operation.status === 'cancelled' ? '已取消' : operation.status === 'expired' ? '操作已过期，请重新发起' : '';
  }

  private close(): void { this.getUIContext().getRouter().back(); }

  private async finish(confirm: boolean): Promise<void> {
    if (this.busy || this.operation?.status !== 'pending') return;
    const id: string = this.operation.id;
    const generation: number = this.generation;
    this.busy = true;
    try {
      if (confirm && this.operation.kind === 'create' && this.operation.task.remindAt > 0 &&
        !(await ClassReminderScheduler.requestNotification(this.context()))) {
        if (this.active && generation === this.generation) this.message = '请允许通知后重试，或重新发起不带提醒的作业';
        return;
      }
      // A second tool request can replace the preview during the permission dialog. Never commit the hidden preview.
      if (!this.active || generation !== this.generation || this.operationId !== id) return;
      const operation: StudyOperation = await StudyAssistantService.finish(this.context(), id, confirm);
      if (!this.active || generation !== this.generation) return;
      this.operation = operation;
      this.message = this.statusMessage(operation);
    } catch (error) {
      if (this.active && generation === this.generation) this.message = error instanceof Error && /[\u4e00-\u9fff]/.test(error.message) ?
        error.message : '保存失败，请重试';
    } finally { if (this.active && generation === this.generation) this.busy = false; }
  }

  @Builder
  private detail(label: string, value: string) {
    Row({ space: HitaDesign.gap }) {
      Text(label).fontSize(HitaDesign.body).fontColor(HitaColors.onSurfaceVariant)
      Text(value).fontSize(HitaDesign.body).fontColor(HitaColors.onSurface).layoutWeight(1).textAlign(TextAlign.End)
    }.width('100%').alignItems(VerticalAlign.Top)
  }

  build() {
    Column() {
      ImmersiveHeader({ barHeight: HitaDesign.headerHeight }) {
        Row({ space: HitaDesign.gap }) {
          HeaderBackButton({ onBack: () => { if (!this.busy) this.close(); } })
          Text(this.operation?.kind === 'complete' ? '确认完成作业' : '确认添加作业')
            .fontSize(HitaDesign.title).fontWeight(FontWeight.Medium)
            .fontColor(CompatibleMaterialModifier.foreground(HitaColors.onSurface))
        }.width('100%').padding({ left: HitaDesign.inset, right: HitaDesign.inset })
      }
      Scroll() {
        Column({ space: HitaDesign.sectionGap }) {
          if (this.operation !== undefined) {
            Column({ space: HitaDesign.spaceLg }) {
              Text(this.operation.task.title).fontSize(HitaDesign.title).fontWeight(FontWeight.Medium).fontColor(HitaColors.onSurface)
              this.detail('课程', this.operation.task.courseName)
              this.detail('课表', this.operation.timetableName)
              this.detail('截止', this.operation.task.dueAt > 0 ? StudyAssistantService.date(this.operation.task.dueAt) +
                (this.operation.task.allDay ? ' · 全天' : ' ' + StudyAssistantService.time(this.operation.task.dueAt)) : '未设置')
              if (this.operation.task.remindAt > 0) {
                this.detail('提醒', StudyAssistantService.date(this.operation.task.remindAt) + ' ' + StudyAssistantService.time(this.operation.task.remindAt))
              }
              if (this.operation.task.note.length > 0) {
                Text(this.operation.task.note).fontSize(HitaDesign.body).fontColor(HitaColors.onSurfaceVariant).width('100%')
              }
            }.width('100%').alignItems(HorizontalAlign.Start).padding(HitaDesign.spaceLg)
              .backgroundColor($r('app.color.hita_surface')).borderRadius(HitaDesign.cardRadius)
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
          HitaButton({ label: this.busy ? '处理中' : this.operation.kind === 'complete' ? '确认完成' : '确认添加', disabled: this.busy,
            onTap: () => { void this.finish(true); } }).layoutWeight(1)
        } else HitaButton({ label: '返回', disabled: this.busy, onTap: () => { this.close(); } })
      }.width('100%').padding(HitaDesign.inset)
    }.width('100%').height('100%').padding({ top: this.topInset, bottom: this.bottomInset })
      .backgroundColor($r('app.color.hita_page'))
  }
}
