import { common } from '@kit.AbilityKit';
import { RdbHelper } from '../../common/db/RdbHelper';
import { LearningContext, LearningTask, LearningTaskKind, LearningTaskRules } from '../../common/model/learning/LearningTask';
import { EasEventItem, EasTermSubject, newId } from '../../common/model/timetable/TimetableModels';
import { EasTimeTools } from '../../common/util/EasTimeTools';
import { ScheduleChangeSignal } from '../../common/util/ScheduleChangeSignal';
import { HitaDesign } from '../../common/theme/HitaDesign';
import { CompatibleSheetMaterial } from '../../common/theme/CompatibleSheetMaterial';
import { ImmersiveHeader } from '../../common/components/ImmersiveHeader';
import { HeaderBackButton } from '../../common/components/HeaderBackButton';
import { HeaderActionButton } from '../../common/components/HeaderActionButton';
import { LearningTaskEditor } from './LearningTaskEditor';
import { LearningTaskReminders } from './LearningTaskReminders';

@Component
export struct LearningTasksPanel {
  @Prop subjectId: string = '';
  @Prop timetableId: string = '';
  @Prop examId: string = '';
  @Prop filterKind: string = '';
  @Prop initialTaskId: string = '';
  onClose: () => void = () => {};
  onBusyChanged: (busy: boolean) => void = () => {};
  @State tasks: LearningTask[] = [];
  @State data: LearningContext = new LearningContext();
  @State loading: boolean = true;
  @State error: string = '';
  @State selectedKind: string = LearningTaskKind.HOMEWORK;
  @State editing: boolean = false;
  @State isNew: boolean = true;
  @State draft: LearningTask = new LearningTask();
  @State busy: boolean = false;
  @State showCompleted: boolean = false;
  @State now: number = Date.now();
  @StorageProp('hita_nav_bar_vp') navBarInset: number = 16;
  private active: boolean = false;
  private generation: number = 0;
  private signalKey: string = 'learning-panel-' + newId();
  private timer: number = -1;
  private openedInitial: boolean = false;

  aboutToAppear(): void {
    this.active = true;
    if (this.filterKind.length > 0) this.selectedKind = this.filterKind;
    ScheduleChangeSignal.subscribe(this.signalKey, () => { if (!this.editing && !this.busy) void this.load(); });
    this.timer = setInterval(() => { this.now = Date.now(); }, 30000);
    void this.load();
  }

  aboutToDisappear(): void {
    this.active = false; this.generation++;
    clearInterval(this.timer);
    ScheduleChangeSignal.unsubscribe(this.signalKey);
  }

  private async load(): Promise<void> {
    const generation: number = ++this.generation;
    try {
      const rdb: RdbHelper = RdbHelper.getInstance();
      await rdb.init(this.getUIContext().getHostContext() as common.Context);
      const data: LearningContext = await rdb.getLearningContext();
      const tasks: LearningTask[] = await rdb.getLearningTasks();
      if (!this.active || generation !== this.generation) return;
      this.data = data; this.tasks = tasks; this.error = ''; this.now = Date.now();
      if (!this.openedInitial && this.initialTaskId.length > 0) {
        this.openedInitial = true;
        const task: LearningTask | undefined = tasks.find(item => item.id === this.initialTaskId);
        if (task !== undefined) {
          // Show the opened task's tab behind the editor, so it is in the list after saving.
          if (this.filterKind.length === 0) this.selectedKind = task.kind;
          this.edit(task);
        } else this.error = '这条待办已被删除';
      }
    } catch (_) { if (this.active && generation === this.generation) this.error = '待办加载失败，请重试'; }
    finally { if (this.active && generation === this.generation) this.loading = false; }
  }

  private scoped(): LearningTask[] {
    return this.tasks.filter(task => {
      if (this.subjectId.length > 0 && (task.kind !== LearningTaskKind.HOMEWORK ||
        task.timetableId !== this.timetableId || LearningTaskRules.subject(task, this.data)?.id !== this.subjectId)) return false;
      if (this.examId.length > 0 && (task.examId !== this.examId || task.timetableId !== this.timetableId)) return false;
      return task.kind === this.selectedKind;
    });
  }

  private grouped(group: number): LearningTask[] {
    return LearningTaskRules.sort(this.scoped().filter(task => LearningTaskRules.group(task, this.now) === group), this.now);
  }

  private title(): string {
    return this.subjectId.length > 0 ? '课程作业' : this.examId.length > 0 ? '复习清单' : '学习待办';
  }

  private scopeTitle(): string {
    if (this.subjectId.length > 0) return this.data.subjects.find(subject => subject.id === this.subjectId)?.name ?? '课程已移除';
    if (this.examId.length > 0) return this.data.events.find(event => event.id === this.examId)?.name ?? '考试已移除';
    const count: number = this.scoped().filter(task => task.completedAt === 0).length;
    return count === 0 ? '暂无待完成事项' : count.toString() + ' 项待完成';
  }

  private createTask(): void {
    if (this.busy || this.loading || this.error.length > 0) return;
    const task: LearningTask = new LearningTask();
    task.kind = this.examId.length > 0 || this.selectedKind === LearningTaskKind.REVIEW ? LearningTaskKind.REVIEW : LearningTaskKind.HOMEWORK;
    const subject: EasTermSubject | undefined = this.data.subjects.find(item => item.id === this.subjectId && item.timetableId === this.timetableId);
    if (subject !== undefined) {
      task.subjectId = subject.id; task.timetableId = subject.timetableId; task.courseName = subject.name; task.courseCode = subject.code;
    }
    const exam: EasEventItem | undefined = this.data.events.find(item => item.id === this.examId && item.timetableId === this.timetableId);
    if (exam !== undefined) {
      task.examId = exam.id; task.examName = exam.name; task.examAt = exam.from; task.timetableId = exam.timetableId;
    }
    this.draft = task; this.isNew = true; this.editing = true;
  }

  private edit(task: LearningTask): void {
    if (this.busy) return;
    this.draft = LearningTaskRules.copy(task); this.isNew = false; this.editing = true;
  }

  private setBusy(busy: boolean): void { this.busy = busy; this.onBusyChanged(busy); }

  private async toggle(task: LearningTask): Promise<void> {
    if (this.busy) return;
    this.setBusy(true);
    try {
      await RdbHelper.getInstance().setLearningTaskCompleted(task.id, task.completedAt === 0);
      if (task.completedAt === 0) await LearningTaskReminders.cancel(task.id);
      await this.load();
    } catch (_) { if (this.active) this.error = '状态保存失败，请重试'; }
    finally { this.setBusy(false); }
  }

  private remove(task: LearningTask): void {
    if (this.busy) return;
    this.getUIContext().showAlertDialog({ title: '删除这条待办？', message: task.title,
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: '删除', action: () => { void this.deleteTask(task); } }
    });
  }

  private async deleteTask(task: LearningTask): Promise<void> {
    if (this.busy || !this.active) return;
    this.setBusy(true);
    try {
      await RdbHelper.getInstance().deleteLearningTask(task.id);
      await LearningTaskReminders.cancel(task.id);
      this.editing = false;
      await this.load();
    } catch (_) { if (this.active) this.error = '删除失败，请重试'; }
    finally { this.setBusy(false); }
  }

  private courseLabel(task: LearningTask): string {
    if (task.kind === LearningTaskKind.REVIEW) {
      const exam: EasEventItem | undefined = LearningTaskRules.exam(task, this.data);
      return ((exam?.name ?? task.examName) || '未关联考试') + (exam === undefined ? ' · 考试已移除' :
        task.examAt > 0 && task.examAt !== exam.from ? ' · 考试已改期' : ' · 复习');
    }
    const subject: EasTermSubject | undefined = LearningTaskRules.subject(task, this.data);
    return ((subject?.name ?? task.courseName) || '未关联课程') + (subject === undefined ? ' · 课程已移除' : '');
  }

  private deadlineText(task: LearningTask): string {
    if (task.dueAt === 0) return '未设截止日期';
    return EasTimeTools.printDate(task.dueAt) + (task.allDay ? ' · 全天' : ' ' + EasTimeTools.printTime(task.dueAt)) +
      (LearningTaskRules.group(task, this.now) === 0 ? ' · 已逾期' : '');
  }

  private changedExam(): EasEventItem | undefined {
    return this.data.events.find(exam => this.examId === exam.id && this.tasks.some(task => task.examId === exam.id &&
      task.timetableId === exam.timetableId && task.completedAt === 0 && task.examAt > 0 && task.examAt !== exam.from));
  }

  private confirmShift(): void {
    const exam: EasEventItem | undefined = this.changedExam();
    if (exam === undefined || this.busy) return;
    this.getUIContext().showAlertDialog({ title: '调整复习日期？',
      message: '考试已改至 ' + EasTimeTools.printDate(exam.from) + ' ' + EasTimeTools.printTime(exam.from) +
        '，将按考试改期的时间差平移未完成任务的截止和提醒时间。',
      primaryButton: { value: '保留日期', action: () => {} },
      secondaryButton: { value: '调整日期', action: () => { void this.shift(exam); } }
    });
  }

  private async shift(exam: EasEventItem): Promise<void> {
    if (this.busy || !this.active) return;
    this.setBusy(true);
    try {
      await RdbHelper.getInstance().shiftLearningTasksForExam(exam.id, exam.from);
      await this.load();
    } catch (_) { if (this.active) this.error = '调整失败，请刷新后重试'; }
    finally { this.setBusy(false); }
  }

  @Builder
  private kindTab(label: string, kind: string) {
    Button(label, { type: ButtonType.Capsule }).height(36).fontSize(HitaDesign.caption).layoutWeight(1)
      .fontColor(this.selectedKind === kind ? $r('app.color.hita_primary') : $r('app.color.hita_text_secondary'))
      .backgroundColor(this.selectedKind === kind ? $r('app.color.hita_selected') : Color.Transparent)
      .onClick(() => { this.selectedKind = kind; })
  }

  @Builder
  private taskRow(task: LearningTask) {
    Row({ space: 12 }) {
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph(task.completedAt > 0 ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.circle'))
          .fontSize(HitaDesign.iconLg).fontColor([task.completedAt > 0 ? $r('app.color.hita_primary') : $r('app.color.hita_text_secondary')])
      }.width(44).height(44).backgroundColor(Color.Transparent).padding(0)
        .accessibilityText(task.completedAt > 0 ? '撤销完成：' + task.title : '完成：' + task.title)
        .onClick(() => { void this.toggle(task); })
      Column({ space: 4 }) {
        Text(task.title).fontSize(HitaDesign.body).fontWeight(FontWeight.Medium)
          .fontColor(task.completedAt > 0 ? $r('app.color.hita_text_secondary') : $r('app.color.hita_text'))
          .decoration({ type: task.completedAt > 0 ? TextDecorationType.LineThrough : TextDecorationType.None })
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.courseLabel(task)).fontSize(HitaDesign.caption).fontColor($r('app.color.hita_text_secondary'))
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.deadlineText(task)).fontSize(HitaDesign.caption)
          .fontColor(LearningTaskRules.group(task, this.now) === 0 ? $r('app.color.hita_error') : $r('app.color.hita_text_secondary'))
        if (task.note.length > 0) {
          Text(task.note).fontSize(HitaDesign.caption).fontColor($r('app.color.hita_text_secondary'))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start).onClick(() => this.edit(task))
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(HitaDesign.iconSm).fontColor([$r('app.color.hita_text_secondary')])
        .onClick(() => this.edit(task))
    }.width('100%').padding({ left: 8, right: 16, top: 12, bottom: 12 }).borderRadius(HitaDesign.cardRadius)
      .backgroundColor(CompatibleSheetMaterial.cardColor($r('app.color.hita_surface'))).enabled(!this.busy)
  }

  @Builder
  private groupTitle(title: string, count: () => number) {
    Row() {
      Text(title).fontSize(HitaDesign.section).fontWeight(FontWeight.Medium).fontColor($r('app.color.hita_text'))
      Blank()
      Text(count().toString()).fontSize(HitaDesign.caption).fontColor($r('app.color.hita_text_secondary'))
    }.width('100%').padding({ top: 12, bottom: 4, left: 4, right: 4 })
  }

  build() {
    Column() {
      if (this.editing) {
        LearningTaskEditor({ initialTask: this.draft, data: this.data, isNew: this.isNew,
          onCancel: () => { this.editing = false; void this.load(); },
          onSaved: () => { this.editing = false; void this.load(); },
          onBusyChanged: (busy: boolean) => this.setBusy(busy),
          onDelete: () => this.remove(this.draft)
        }).width('100%').height('100%')
      } else {
        ImmersiveHeader({ barHeight: 60, materialEnabled: CompatibleSheetMaterial.isEnabled() }) {
          Row({ space: 12 }) {
            HeaderBackButton({ onBack: () => { if (!this.busy) this.onClose(); } })
            Column({ space: 4 }) {
              Text(this.title()).fontSize(HitaDesign.title)
                .fontWeight(FontWeight.Medium).fontColor($r('app.color.hita_text'))
              Text(this.scopeTitle()).fontSize(HitaDesign.caption).fontColor($r('app.color.hita_text_secondary'))
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            HeaderActionButton({ label: '添加', disabled: this.loading || this.busy || this.error.length > 0,
              materialEnabled: CompatibleSheetMaterial.isEnabled(), onTap: () => this.createTask() })
          }.width('100%').height(60).padding({ left: 16, right: 16 })
        }
        if (this.filterKind.length === 0 && this.subjectId.length === 0 && this.examId.length === 0) {
          Row({ space: 4 }) {
            this.kindTab('作业', LearningTaskKind.HOMEWORK)
            this.kindTab('复习', LearningTaskKind.REVIEW)
          }.width('100%').padding({ left: 16, right: 16, bottom: 8 })
        }
        if (this.loading) {
          LoadingProgress().width(36).height(36).color($r('app.color.hita_primary')).margin(24)
        } else {
          List({ space: 12 }) {
            if (this.error.length > 0) {
              ListItem() {
                Row({ space: 12 }) {
                  Text(this.error).fontSize(HitaDesign.caption).fontColor($r('app.color.hita_error')).layoutWeight(1)
                  Button('重试').fontSize(HitaDesign.caption).onClick(() => { void this.load(); })
                }.width('100%')
              }
            }
            if (this.changedExam() !== undefined) {
              ListItem() {
                Button('考试已改期，调整复习日期').fontSize(HitaDesign.caption).width('100%')
                  .backgroundColor($r('app.color.hita_selected')).fontColor($r('app.color.hita_primary'))
                  .enabled(!this.busy).onClick(() => this.confirmShift())
              }
            }
            if (this.scoped().length === 0 && this.error.length === 0) {
              ListItem() {
                Column({ space: 8 }) {
                  Text('暂无' + (this.selectedKind === LearningTaskKind.REVIEW ? '复习任务' : '作业'))
                    .fontSize(HitaDesign.body).fontWeight(FontWeight.Medium).fontColor($r('app.color.hita_text'))
                  Text('点击右上角添加').fontSize(HitaDesign.caption).fontColor($r('app.color.hita_text_secondary'))
                }.width('100%').padding({ top: 48, bottom: 48 })
              }
            }
            ForEach([0, 1, 2, 3], (group: number) => {
              if (this.grouped(group).length > 0) {
                ListItem() { this.groupTitle(['已逾期', '今天', '之后', '未设日期'][group], () => this.grouped(group).length) }
                ForEach(this.grouped(group), (task: LearningTask) => {
                  ListItem() { this.taskRow(task) }
                }, (task: LearningTask) => task.id + ':' + task.updatedAt.toString())
              }
            }, (group: number) => group.toString())
            if (this.grouped(4).length > 0) {
              ListItem() {
                Row() {
                  Text('已完成 ' + this.grouped(4).length.toString() + ' 项').fontSize(HitaDesign.body)
                    .fontColor($r('app.color.hita_text_secondary')).layoutWeight(1)
                  SymbolGlyph(this.showCompleted ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
                    .fontSize(HitaDesign.iconSm).fontColor([$r('app.color.hita_text_secondary')])
                }.width('100%').height(48).onClick(() => { this.showCompleted = !this.showCompleted; })
              }
              if (this.showCompleted) {
                ForEach(this.grouped(4), (task: LearningTask) => {
                  ListItem() { this.taskRow(task) }
                }, (task: LearningTask) => task.id + ':' + task.updatedAt.toString())
              }
            }
          }.width('100%').layoutWeight(1).scrollBar(BarState.Off)
            .padding({ left: 16, right: 16, bottom: this.navBarInset + 24 })
        }
      }
    }.width('100%').height('100%')
      .backgroundColor(CompatibleSheetMaterial.bodyColor($r('app.color.hita_page_f6f7fa')))
  }
}
