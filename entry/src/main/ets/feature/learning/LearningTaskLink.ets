import { common } from '@kit.AbilityKit';
import { RdbHelper } from '../../common/db/RdbHelper';
import { LearningContext, LearningTask, LearningTaskRules } from '../../common/model/learning/LearningTask';
import { EasEventItem, EasEventType, EasTermSubject, newId } from '../../common/model/timetable/TimetableModels';
import { ScheduleChangeSignal } from '../../common/util/ScheduleChangeSignal';
import { HitaDesign } from '../../common/theme/HitaDesign';
import { CompatibleSheetMaterial } from '../../common/theme/CompatibleSheetMaterial';
import { CompatibleMaterialModifier } from '../../common/theme/CompatibleMaterialModifier';
import { CompatibleLightModifier } from '../../common/theme/CompatibleLightModifier';
import { SheetContent } from '../../common/components/SheetContent';
import { LearningTasksPanel } from './LearningTasksPanel';

/** Keeps task navigation inside the existing course/exam sheet, with one independent dismissal lifecycle. */
@Component
export struct LearningTaskLink {
  @Prop event: EasEventItem = new EasEventItem();
  /** The surrounding detail sheet is deleting or opening its editor. */
  @Prop disabled: boolean = false;
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

  private label(): string {
    const name: string = this.event.type === EasEventType.EXAM ? '复习' : '作业';
    return this.count > 0 ? name + ' ' + this.count.toString() : name;
  }

  private describe(): string {
    const name: string = this.event.type === EasEventType.EXAM ? '复习清单' : '作业待办';
    return name + '，' + (this.failed ? '读取失败，点击重试' : this.count > 0 ? this.count.toString() + ' 项未完成' :
      this.total > 0 ? '已全部完成' : '暂无，点击添加');
  }

  /** Sits left of 编辑 in DetailActionBar and shares its capsule, material and touch region. */
  build() {
    Button(this.label(), { type: ButtonType.Capsule })
      .height(36).padding({ left: 16, right: 16 }).fontSize(HitaDesign.caption)
      .responseRegion({ x: 0, y: -4, width: '100%', height: 44 })
      .fontWeight(FontWeight.Medium)
      .fontColor(CompatibleSheetMaterial.isEnabled() ?
        CompatibleMaterialModifier.foreground($r('app.color.hita_primary')) : $r('app.color.hita_primary'))
      .backgroundColor($r('app.color.hita_selected'))
      .attributeModifier(new CompatibleMaterialModifier($r('app.color.hita_selected'), false,
        CompatibleSheetMaterial.isEnabled()))
      .accessibilityText(this.describe())
      .enabled(!this.disabled)
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
