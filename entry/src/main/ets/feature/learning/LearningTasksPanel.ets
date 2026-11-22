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
import { HitaButton, HitaButtonVariant } from '../../common/components/HitaButton';
import { CourseModeSegment } from '../timetable/views/CourseModeSegment';
import { LearningTaskEditor } from './LearningTaskEditor';
import { LearningTaskReminders } from './LearningTaskReminders';

const TASK_PAGE_DURATION: number = 220;
const CHECK_DURATION: number = 120;
const REGROUP_DURATION: number = 250;

@Component
export struct LearningTasksPanel {
  @Prop subjectId: string = '';
  @Prop timetableId: string = '';
  @Prop examId: string = '';
  @Prop filterKind: string = '';
  @Prop @Watch('onTaskRequestChanged') initialTaskId: string = '';
  onRequestHandled: (id: string) => void = () => {};
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
  @State private previewTaskId: string = '';
  @State private previewDone: boolean = false;
  @State showCompleted: boolean = false;
  @State now: number = Date.now();
  @StorageProp('hita_nav_bar_vp') navBarInset: number = 16;
  private active: boolean = false;
  private generation: number = 0;
  private signalKey: string = 'learning-panel-' + newId();
  private timer: number = -1;
  private requestedTaskId: string = '';
  private confirmingTaskSwitch: boolean = false;
  private draftDirty: boolean = false;

  aboutToAppear(): void {
    this.active = true;
    if (this.filterKind.length > 0) this.selectedKind = this.filterKind;
    ScheduleChangeSignal.subscribe(this.signalKey, () => { if (!this.editing && !this.busy) void this.load(); });
    this.timer = setInterval(() => { this.now = Date.now(); }, 30000);
    this.receiveTaskRequest();
    void this.load();
  }

  aboutToDisappear(): void {
    this.active = false; this.generation++;
    clearInterval(this.timer);
    ScheduleChangeSignal.unsubscribe(this.signalKey);
  }

  private async load(animateRegroup: boolean = false): Promise<void> {
    const generation: number = ++this.generation;
    try {
      const rdb: RdbHelper = RdbHelper.getInstance();
      await rdb.init(this.getUIContext().getHostContext() as common.Context);
      const data: LearningContext = await rdb.getLearningContext();
      const tasks: LearningTask[] = await rdb.getLearningTasks();
      if (!this.active || generation !== this.generation) return;
      this.data = data; this.error = ''; this.now = Date.now();
      if (animateRegroup) {
        this.getUIContext().animateTo({ duration: REGROUP_DURATION, curve: Curve.EaseOut }, () => {
          this.tasks = tasks;
          this.previewTaskId = '';
        });
      } else {
        this.tasks = tasks;
      }
      if (this.requestedTaskId) void this.openRequestedTask();
    } catch (_) { if (this.active && generation === this.generation) this.error = '待办加载失败，请重试'; }
    finally { if (this.active && generation === this.generation) this.loading = false; }
  }

  private receiveTaskRequest(): void {
    if (!this.initialTaskId) return;
    this.requestedTaskId = this.initialTaskId;
    this.onRequestHandled(this.initialTaskId);
  }

  private onTaskRequestChanged(): void {
    if (!this.active || !this.initialTaskId) return;
    this.receiveTaskRequest();
    if (!this.busy) void this.load();
  }

  private async openRequestedTask(): Promise<void> {
    if (this.busy || this.confirmingTaskSwitch || !this.requestedTaskId) return;
    if (this.editing && this.draftDirty && this.draft.id !== this.requestedTaskId &&
      this.tasks.some(item => item.id === this.requestedTaskId)) {
      this.confirmingTaskSwitch = true;
      let discard: boolean = false;
      try {
        const choice = await this.getUIContext().getPromptAction().showDialog({
          title: '当前待办尚未保存',
          message: '放弃本次修改，打开刚刚点选的待办？',
          buttons: [{ text: '继续编辑', color: $r('app.color.hita_primary') },
            { text: '放弃并切换', color: $r('app.color.hita_error') }]
        });
        discard = choice.index === 1;
      } catch (_) {} finally { this.confirmingTaskSwitch = false; }
      if (!this.active) return;
      if (!discard) { this.requestedTaskId = ''; return; }
    }
    // A second desktop tap can arrive while the decision is on screen.
    const task = this.tasks.find(item => item.id === this.requestedTaskId);
    this.requestedTaskId = '';
    if (task === undefined) {
      this.error = '这条待办已被删除';
      if (this.editing) this.getUIContext().getPromptAction().showToast({ message: this.error });
      return;
    }
    if (this.editing && this.draft.id === task.id) return;
    if (this.filterKind.length === 0) this.selectedKind = task.kind;
    this.edit(task, false);
  }

  private scoped(kind: string = this.selectedKind): LearningTask[] {
    return this.tasks.filter(task => {
      if (this.subjectId.length > 0 && (task.kind !== LearningTaskKind.HOMEWORK ||
        task.timetableId !== this.timetableId || LearningTaskRules.subject(task, this.data)?.id !== this.subjectId)) return false;
      if (this.examId.length > 0 && (task.examId !== this.examId || task.timetableId !== this.timetableId)) return false;
      return task.kind === kind;
    });
  }

  private grouped(group: number, kind: string): LearningTask[] {
    return LearningTaskRules.sort(this.scoped(kind).filter(task => LearningTaskRules.group(task, this.now) === group), this.now);
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
    if (this.editing || this.busy || this.loading || this.error.length > 0) return;
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
    this.draftDirty = false; this.draft = task; this.isNew = true;
    this.animatePage(() => { this.editing = true; });
  }

  private edit(task: LearningTask, animated: boolean = true): void {
    if ((animated && this.editing) || this.busy) return;
    this.draftDirty = false; this.draft = LearningTaskRules.copy(task); this.isNew = false;
    if (animated) this.animatePage(() => { this.editing = true; });
    else this.editing = true;
  }

  private animatePage(change: () => void): void {
    this.getUIContext().animateTo({ duration: TASK_PAGE_DURATION, curve: Curve.FastOutSlowIn }, change);
  }

  private async returnToList(): Promise<void> {
    if (!this.active || !this.editing) return;
    this.animatePage(() => { this.editing = false; });
    await this.load();
  }

  private setBusy(busy: boolean): void {
    this.busy = busy; this.onBusyChanged(busy);
    if (!busy && this.active && this.requestedTaskId) void this.load();
  }

  private showsCheck(task: LearningTask): boolean {
    return this.previewTaskId === task.id ? this.previewDone : task.completedAt > 0;
  }

  private async toggle(task: LearningTask): Promise<void> {
    if (!this.active || this.editing || this.busy) return;
    this.setBusy(true);
    const completed: boolean = task.completedAt === 0;
    this.previewDone = completed;
    this.getUIContext().animateTo({ duration: CHECK_DURATION, curve: Curve.EaseOut }, () => {
      this.previewTaskId = task.id;
    });
    // Start the write immediately; let the check finish before its row changes groups.
    const checkShown = new Promise<void>((resolve) => { setTimeout(resolve, CHECK_DURATION); });
    try {
      await RdbHelper.getInstance().setLearningTaskCompleted(task.id, completed);
      if (completed) await LearningTaskReminders.cancel(task.id);
      await checkShown;
      if (this.active) await this.load(true);
    } catch (_) { if (this.active) this.error = '状态保存失败，请重试'; }
    finally {
      if (this.active) {
        if (this.previewTaskId !== '') {
          this.getUIContext().animateTo({ duration: CHECK_DURATION, curve: Curve.EaseOut }, () => {
            this.previewTaskId = '';
          });
        }
        this.setBusy(false);
      }
    }
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
      await this.returnToList();
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

  private selectKind(index: number): void {
    if (index !== 0 && index !== 1) return;
    const kind: string = index === 0 ? LearningTaskKind.HOMEWORK : LearningTaskKind.REVIEW;
    if (kind !== this.selectedKind) this.animatePage(() => { this.selectedKind = kind; });
  }

  @Builder
  private completionButton(task: LearningTask) {
    Button({ type: ButtonType.Circle }) {
      Stack() {
        SymbolGlyph($r('sys.symbol.circle')).fontSize(HitaDesign.iconLg)
          .fontColor([$r('app.color.hita_text_secondary')]).opacity(this.showsCheck(task) ? 0 : 1)
        SymbolGlyph($r('sys.symbol.checkmark_circle_fill')).fontSize(HitaDesign.iconLg)
          .fontColor([$r('app.color.hita_success')]).opacity(this.showsCheck(task) ? 1 : 0)
          .scale({ x: this.showsCheck(task) ? 1 : 0.65, y: this.showsCheck(task) ? 1 : 0.65 })
      }.accessibilityLevel('no-hide-descendants')
    }.width(HitaDesign.minTouchTarget).height(HitaDesign.minTouchTarget).padding(0).backgroundColor(Color.Transparent)
      .accessibilityText((task.completedAt > 0 ? '恢复待办：' : '完成待办：') + task.title)
      .onClick(() => { void this.toggle(task); })
  }

  @Builder
  private taskRow(task: LearningTask) {
    Row({ space: HitaDesign.spaceXs }) {
      this.completionButton(task)
      Column({ space: HitaDesign.space2xs }) {
        Text(task.title).fontSize(HitaDesign.body).fontWeight(FontWeight.Medium)
          .fontColor(task.completedAt > 0 ? $r('app.color.hita_text_secondary') : $r('app.color.hita_text'))
          .decoration({ type: task.completedAt > 0 ? TextDecorationType.LineThrough : TextDecorationType.None })
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.courseLabel(task)).fontSize(HitaDesign.caption).fontColor($r('app.color.hita_text_secondary'))
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: HitaDesign.space2xs }) {
          SymbolGlyph($r('sys.symbol.clock')).fontSize(HitaDesign.iconXs)
            .fontColor([this.deadlineColor(task)]).accessibilityLevel('no')
          Text(this.deadlineText(task)).fontSize(HitaDesign.caption).fontColor(this.deadlineColor(task))
        }
        if (task.note.length > 0) {
          Text(task.note).fontSize(HitaDesign.caption).fontColor($r('app.color.hita_text_secondary'))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start).onClick(() => this.edit(task))
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(HitaDesign.iconSm).fontColor([$r('app.color.hita_text_secondary')])
        .onClick(() => this.edit(task))
    }.width('100%').padding({ left: HitaDesign.spaceXs, right: HitaDesign.inset,
      top: HitaDesign.spaceSm, bottom: HitaDesign.spaceSm }).borderRadius(HitaDesign.cardRadius)
      .backgroundColor(CompatibleSheetMaterial.cardColor($r('app.color.hita_surface')))
  }

  private deadlineColor(task: LearningTask): ResourceColor {
    return LearningTaskRules.group(task, this.now) === 0 ? $r('app.color.hita_error') : $r('app.color.hita_text_secondary');
  }

  @Builder
  private groupTitle(title: string, count: () => number) {
    Row() {
      Text(title).fontSize(HitaDesign.caption).fontWeight(FontWeight.Medium).fontColor($r('app.color.hita_text_secondary'))
      Blank()
      Text(count().toString() + ' 项').fontSize(HitaDesign.caption).fontColor($r('app.color.hita_text_secondary'))
    }.width('100%').padding({ top: HitaDesign.spaceSm, left: HitaDesign.inset, right: HitaDesign.inset })
  }

  @Builder
  private taskList(kind: string) {
    List({ space: HitaDesign.gap }) {
      if (this.error.length > 0) {
        ListItem() {
          Row({ space: 12 }) {
            Text(this.error).fontSize(HitaDesign.caption).fontColor($r('app.color.hita_error')).layoutWeight(1)
            HitaButton({ label: '重试', variant: HitaButtonVariant.SECONDARY,
              buttonHeight: HitaDesign.compactControlHeight, fitContent: true, onTap: () => { void this.load(); } })
          }.width('100%')
        }
      }
      if (this.changedExam() !== undefined) {
        ListItem() {
          HitaButton({ label: '考试已改期，调整复习日期', variant: HitaButtonVariant.SECONDARY,
            buttonHeight: HitaDesign.controlHeight, disabled: this.busy, onTap: () => this.confirmShift() })
        }
      }
      if (this.scoped(kind).length === 0 && this.error.length === 0) {
        ListItem() {
          Column({ space: HitaDesign.spaceXs }) {
            SymbolGlyph($r('sys.symbol.doc_text')).fontSize(HitaDesign.iconXl)
              .fontColor([$r('app.color.hita_text_secondary')]).accessibilityLevel('no')
            Text('暂无' + (kind === LearningTaskKind.REVIEW ? '复习任务' : '作业'))
              .fontSize(HitaDesign.body).fontWeight(FontWeight.Medium).fontColor($r('app.color.hita_text'))
            Text('点击右上角添加').fontSize(HitaDesign.caption).fontColor($r('app.color.hita_text_secondary'))
          }.width('100%').padding({ top: 48, bottom: 48 })
        }
      }
      ForEach([0, 1, 2, 3], (group: number) => {
        if (this.grouped(group, kind).length > 0) {
          ListItem() { this.groupTitle(['已逾期', '今天', '之后', '未设日期'][group], () => this.grouped(group, kind).length) }
          ForEach(this.grouped(group, kind), (task: LearningTask) => {
            ListItem() { this.taskRow(task) }
              .transition(TransitionEffect.translate({ y: HitaDesign.spaceXs }).combine(TransitionEffect.OPACITY))
          }, (task: LearningTask) => task.id + ':' + task.updatedAt.toString())
        }
      }, (group: number) => group.toString())
      if (this.grouped(4, kind).length > 0) {
        ListItem() {
          Row() {
            Text('已完成 ' + this.grouped(4, kind).length.toString() + ' 项').fontSize(HitaDesign.body)
              .fontColor($r('app.color.hita_text_secondary')).layoutWeight(1)
            SymbolGlyph(this.showCompleted ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
              .fontSize(HitaDesign.iconSm).fontColor([$r('app.color.hita_text_secondary')])
          }.width('100%').height(HitaDesign.buttonHeight).padding({ left: HitaDesign.inset, right: HitaDesign.inset })
            .onClick(() => { this.animatePage(() => { this.showCompleted = !this.showCompleted; }); })
        }
        if (this.showCompleted) {
          ForEach(this.grouped(4, kind), (task: LearningTask) => {
            ListItem() { this.taskRow(task) }
              .transition(TransitionEffect.translate({ y: HitaDesign.spaceXs }).combine(TransitionEffect.OPACITY))
          }, (task: LearningTask) => task.id + ':' + task.updatedAt.toString())
        }
      }
    }.width('100%').height('100%').scrollBar(BarState.Off)
      .padding({ left: 16, right: 16, bottom: this.navBarInset + 24 })
      .transition(TransitionEffect.translate({ x: kind === LearningTaskKind.REVIEW ? HitaDesign.spaceLg : -HitaDesign.spaceLg })
        .combine(TransitionEffect.OPACITY))
  }

  @Builder
  private overview() {
    Column() {
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
        Row() {
          CourseModeSegment({
            labels: ['作业', '复习'], selectedIndex: this.selectedKind === LearningTaskKind.REVIEW ? 1 : 0,
            onSelect: (index: number) => this.selectKind(index)
          })
        }.width('100%').padding({ left: HitaDesign.inset, right: HitaDesign.inset, bottom: HitaDesign.spaceXs })
      }
      if (this.loading) {
        LoadingProgress().width(36).height(36).color($r('app.color.hita_primary')).margin(24)
      } else {
        Stack() {
          if (this.selectedKind === LearningTaskKind.REVIEW) {
            this.taskList(LearningTaskKind.REVIEW)
          } else {
            this.taskList(LearningTaskKind.HOMEWORK)
          }
        }.width('100%').layoutWeight(1).clip(true)
      }
    }.width('100%').height('100%')
      .opacity(this.editing ? 0 : 1)
      .translate({ x: this.editing ? -HitaDesign.spaceMd : 0 })
      .enabled(!this.editing)
      .accessibilityLevel(this.editing ? 'no-hide-descendants' : 'auto')
  }

  build() {
    Stack() {
      this.overview()
      if (this.editing) {
        ForEach([this.draft], (task: LearningTask) => {
          LearningTaskEditor({ initialTask: task, data: this.data, isNew: this.isNew,
            onCancel: () => { void this.returnToList(); },
            onSaved: () => { void this.returnToList(); },
            onBusyChanged: (busy: boolean) => this.setBusy(busy),
            onDraftChanged: (dirty: boolean) => { this.draftDirty = dirty; },
            onDelete: () => this.remove(task)
          }).width('100%').height('100%')
            .transition(TransitionEffect.translate({ x: HitaDesign.spaceXl }).combine(TransitionEffect.OPACITY))
        }, (task: LearningTask) => task.id)
      }
    }.width('100%').height('100%').clip(true)
      .backgroundColor(CompatibleSheetMaterial.bodyColor($r('app.color.hita_page_f6f7fa')))
  }
}
