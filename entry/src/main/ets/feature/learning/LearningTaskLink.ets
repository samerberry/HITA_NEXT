import { common } from '@kit.AbilityKit';
import { RdbHelper } from '../../common/db/RdbHelper';
import { LearningContext, LearningTask, LearningTaskRules } from '../../common/model/learning/LearningTask';
import { EasEventItem, EasEventType, EasTermSubject, newId } from '../../common/model/timetable/TimetableModels';
import { ScheduleChangeSignal } from '../../common/util/ScheduleChangeSignal';
import { HitaDesign } from '../../common/theme/HitaDesign';
import { CompatibleSheetMaterial } from '../../common/theme/CompatibleSheetMaterial';
import { CompatibleLightModifier } from '../../common/theme/CompatibleLightModifier';
import { SheetContent } from '../../common/components/SheetContent';
import { LearningTasksPanel } from './LearningTasksPanel';

/** Keeps task navigation inside the existing course/exam sheet, with one independent dismissal lifecycle. */
@Component
export struct LearningTaskLink {
  @Prop event: EasEventItem = new EasEventItem();
  @State visible: boolean = false;
  @State busy: boolean = false;
  @State count: number = 0;
  @State total: number = 0;
  @State subjectId: string = '';
  @State failed: boolean = false;
  private active: boolean = false;
  private generation: number = 0;
  private signalKey: string = 'learning-link-' + newId();

  aboutToAppear(): void {
    this.active = true;
    ScheduleChangeSignal.subscribe(this.signalKey, () => { void this.refresh(); });
    void this.refresh();
  }
  aboutToDisappear(): void {
    this.active = false; this.generation++;
    ScheduleChangeSignal.unsubscribe(this.signalKey);
  }

  private async refresh(): Promise<void> {
    const generation: number = ++this.generation;
    try {
      const rdb: RdbHelper = RdbHelper.getInstance();
      await rdb.init(this.getUIContext().getHostContext() as common.Context);
      const data: LearningContext = await rdb.getLearningContext();
      const tasks: LearningTask[] = await rdb.getLearningTasks();
      if (!this.active || generation !== this.generation) return;
      const matches: EasTermSubject[] = data.subjects.filter(subject => subject.timetableId === this.event.timetableId &&
        (this.event.subjectId.length > 0 ? subject.id === this.event.subjectId : subject.name === this.event.name));
      this.subjectId = matches.length === 1 ? matches[0].id : '';
      const related: LearningTask[] = tasks.filter(task => this.event.type === EasEventType.EXAM ?
        task.examId === this.event.id && task.timetableId === this.event.timetableId :
        task.kind === 'HOMEWORK' && task.timetableId === this.event.timetableId &&
        this.subjectId.length > 0 && LearningTaskRules.subject(task, data)?.id === this.subjectId);
      this.count = related.filter(task => task.completedAt === 0).length;
      this.total = related.length;
      this.failed = false;
    } catch (_) { if (this.active && generation === this.generation) this.failed = true; }
  }

  @Builder
  private taskSheet() {
    SheetContent({ fillHeight: true }) {
      LearningTasksPanel({
        subjectId: this.event.type === EasEventType.EXAM ? '' : this.subjectId,
        timetableId: this.event.timetableId,
        examId: this.event.type === EasEventType.EXAM ? this.event.id : '',
        filterKind: this.event.type === EasEventType.EXAM ? 'REVIEW' : 'HOMEWORK',
        onClose: () => { if (!this.busy) this.visible = false; },
        onBusyChanged: (busy: boolean) => { this.busy = busy; }
      }).width('100%').height('100%')
        .attributeModifier(new CompatibleLightModifier(24, CompatibleSheetMaterial.isEnabled(), true))
    }
  }

  build() {
    Row({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.checkmark_circle_fill')).fontSize(HitaDesign.iconMd)
        .fontColor([$r('app.color.hita_primary')]).width(38)
      Text(this.event.type === EasEventType.EXAM ? '复习清单' : '作业待办').fontSize(HitaDesign.body)
        .fontColor($r('app.color.hita_text')).layoutWeight(1)
      Text(this.failed ? '重试' : this.count > 0 ? this.count.toString() + ' 项未完成' : this.total > 0 ? '已全部完成' : '添加')
        .fontSize(HitaDesign.caption).fontColor($r('app.color.hita_text_secondary'))
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(HitaDesign.iconSm).fontColor([$r('app.color.hita_text_secondary')])
    }.width('100%').constraintSize({ minHeight: 52 }).padding({ top: 8, bottom: 8 })
      .onClick(() => {
        if (this.failed) { void this.refresh(); return; }
        if (this.busy || this.visible) return;
        if (this.event.type !== EasEventType.EXAM && this.subjectId.length === 0) {
          this.getUIContext().getPromptAction().showToast({ message: '课程已变化，请重新打开详情' }); return;
        }
        this.visible = true;
      })
      .bindSheet($$this.visible, this.taskSheet(), CompatibleSheetMaterial.options({
        height: '78%', dragBar: true, showClose: false, preferType: SheetType.BOTTOM,
        backgroundColor: $r('app.color.hita_surface_soft'), maskColor: $r('app.color.hita_sheet_mask'),
        shouldDismiss: (dismiss: SheetDismiss) => { if (!this.busy) dismiss.dismiss(); },
        onWillDisappear: () => { this.visible = false; },
        onDisappear: () => { this.visible = false; this.busy = false; void this.refresh(); }
      }))
  }
}
