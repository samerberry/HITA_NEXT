import { common } from '@kit.AbilityKit';
import { RdbHelper } from '../../common/db/RdbHelper';
import { LearningContext, LearningTask, LearningTaskKind, LearningTaskRules } from '../../common/model/learning/LearningTask';
import { EasEventItem, EasEventType, EasTermSubject } from '../../common/model/timetable/TimetableModels';
import { EasTimeTools } from '../../common/util/EasTimeTools';
import { HitaDesign } from '../../common/theme/HitaDesign';
import { CompatibleMaterialModifier } from '../../common/theme/CompatibleMaterialModifier';
import { CompatiblePickerMaterial } from '../../common/theme/CompatiblePickerMaterial';
import { CompatibleSheetMaterial } from '../../common/theme/CompatibleSheetMaterial';
import { ImmersiveHeader } from '../../common/components/ImmersiveHeader';
import { HeaderBackButton } from '../../common/components/HeaderBackButton';
import { ClassReminderScheduler } from '../timetable/data/ClassReminderScheduler';
import { LearningTaskReminders } from './LearningTaskReminders';

@Component
export struct LearningTaskEditor {
  @Prop initialTask: LearningTask = new LearningTask();
  @Prop data: LearningContext = new LearningContext();
  @Prop isNew: boolean = true;
  onCancel: () => void = () => {};
  onSaved: () => void = () => {};
  onDelete: () => void = () => {};
  onBusyChanged: (busy: boolean) => void = () => {};
  @State draft: LearningTask = new LearningTask();
  @State title: string = '';
  @State note: string = '';
  @State saving: boolean = false;
  @State error: string = '';
  @StorageProp('hita_nav_bar_vp') navBarInset: number = 16;
  private active: boolean = false;

  aboutToAppear(): void {
    this.active = true;
    this.draft = LearningTaskRules.copy(this.initialTask);
    this.title = this.draft.title;
    this.note = this.draft.note;
  }

  aboutToDisappear(): void { this.active = false; }

  private update(task: LearningTask): void {
    if (!this.active || this.saving) return;
    this.draft = task;
    this.error = '';
  }

  private subjectText(): string {
    const subject: EasTermSubject | undefined = LearningTaskRules.subject(this.draft, this.data);
    return subject?.name ?? (this.draft.courseName.length > 0 ? this.draft.courseName + '（已移除）' : '选择课程');
  }

  private examText(): string {
    const exam: EasEventItem | undefined = LearningTaskRules.exam(this.draft, this.data);
    return exam === undefined ? (this.draft.examName.length > 0 ? this.draft.examName + '（已移除）' : '选择考试') :
      exam.name + ' · ' + EasTimeTools.printDate(exam.from);
  }

  private selectSubject(): void {
    if (this.saving) return;
    const choices: EasTermSubject[] = this.data.subjects;
    if (choices.length === 0) { this.error = '请先新建或导入课程'; return; }
    this.getUIContext().showTextPickerDialog(CompatiblePickerMaterial.textOptions({
      range: choices.map((subject: EasTermSubject): string => subject.name + ' · ' +
        (this.data.timetables.find(table => table.id === subject.timetableId)?.name ?? '课表')),
      selected: Math.max(0, choices.findIndex(subject => subject.id === this.draft.subjectId)), canLoop: false,
      onAccept: (result: TextPickerResult) => {
        const subject: EasTermSubject | undefined = choices[Number(result.index)];
        if (subject === undefined) return;
        const next: LearningTask = LearningTaskRules.copy(this.draft);
        next.subjectId = subject.id; next.timetableId = subject.timetableId;
        next.courseName = subject.name; next.courseCode = subject.code;
        this.update(next);
      }
    }, true));
  }

  private selectExam(): void {
    if (this.saving) return;
    const choices: EasEventItem[] = this.data.events.filter(event => event.type === EasEventType.EXAM)
      .sort((a, b) => a.from - b.from);
    if (choices.length === 0) { this.error = '请先在考试页面导入或添加考试'; return; }
    this.getUIContext().showTextPickerDialog(CompatiblePickerMaterial.textOptions({
      range: choices.map(exam => exam.name + ' · ' + EasTimeTools.printDate(exam.from) + ' · ' +
        (this.data.timetables.find(table => table.id === exam.timetableId)?.name ?? '课表')),
      selected: Math.max(0, choices.findIndex(exam => exam.id === this.draft.examId)), canLoop: false,
      onAccept: (result: TextPickerResult) => {
        const exam: EasEventItem | undefined = choices[Number(result.index)];
        if (exam === undefined) return;
        const next: LearningTask = LearningTaskRules.copy(this.draft);
        next.examId = exam.id; next.examName = exam.name; next.examAt = exam.from; next.timetableId = exam.timetableId;
        const matches: EasTermSubject[] = this.data.subjects.filter(subject => subject.timetableId === exam.timetableId &&
          (exam.subjectId.length > 0 ? subject.id === exam.subjectId : subject.name === exam.name));
        const subject: EasTermSubject | undefined = matches.length === 1 ? matches[0] : undefined;
        next.subjectId = subject?.id ?? ''; next.courseName = subject?.name ?? ''; next.courseCode = subject?.code ?? '';
        this.update(next);
      }
    }, true));
  }

  private pickDate(reminder: boolean = false): void {
    if (this.saving) return;
    const previous: number = reminder ? this.draft.remindAt : this.draft.dueAt;
    this.getUIContext().showDatePickerDialog({
      selected: new Date(previous || Date.now()), start: new Date(2000, 0, 1), end: new Date(2100, 11, 31),
      onDateAccept: (date: Date) => {
        const next: LearningTask = LearningTaskRules.copy(this.draft);
        const old: Date = new Date(previous || Date.now());
        const time: number = new Date(date.getFullYear(), date.getMonth(), date.getDate(),
          previous > 0 ? old.getHours() : (reminder ? 9 : 23), previous > 0 ? old.getMinutes() : (reminder ? 0 : 59)).getTime();
        if (reminder) { next.remindAt = time; this.update(next); this.pickTime(true); }
        else { next.dueAt = time; this.update(next); }
      }
    });
  }

  private pickTime(reminder: boolean = false): void {
    if (this.saving) return;
    const time: number = reminder ? this.draft.remindAt : this.draft.dueAt;
    if (time === 0) { this.pickDate(reminder); return; }
    this.getUIContext().showTimePickerDialog({
      selected: new Date(time), useMilitaryTime: true,
      onAccept: (result: TimePickerResult) => {
        const date: Date = new Date(time);
        const next: LearningTask = LearningTaskRules.copy(this.draft);
        const picked: number = new Date(date.getFullYear(), date.getMonth(), date.getDate(), result.hour, result.minute).getTime();
        if (reminder) next.remindAt = picked;
        else { next.dueAt = picked; next.allDay = false; }
        this.update(next);
      }
    });
  }

  private nextClassDeadline(): void {
    const subject: EasTermSubject | undefined = LearningTaskRules.subject(this.draft, this.data);
    const event: EasEventItem | undefined = subject === undefined ? undefined :
      LearningTaskRules.nextClass(subject, this.data.events, Date.now());
    if (event === undefined) { this.error = '这门课程没有后续课次，请选择截止日期'; return; }
    const next: LearningTask = LearningTaskRules.copy(this.draft);
    next.dueAt = event.from; next.allDay = false;
    this.update(next);
  }

  private chooseReminder(): void {
    const options: string[] = ['不提醒', '截止时', '提前 1 小时', '提前 1 天', '自定义时间'];
    this.getUIContext().showTextPickerDialog(CompatiblePickerMaterial.textOptions({
      range: options, selected: this.draft.remindAt > 0 ? 4 : 0, canLoop: false,
      onAccept: (result: TextPickerResult) => {
        const index: number = Number(result.index);
        if (index === 4) { this.pickDate(true); return; }
        if (index > 0 && this.draft.dueAt === 0) { this.error = '请先选择截止日期，或使用自定义提醒时间'; return; }
        const next: LearningTask = LearningTaskRules.copy(this.draft);
        next.remindAt = index === 0 ? 0 : LearningTaskRules.deadline(next) - (index === 2 ? 3600000 : index === 3 ? 86400000 : 0);
        this.update(next);
      }
    }, true));
  }

  private async save(): Promise<void> {
    if (this.saving || !this.active) return;
    const next: LearningTask = LearningTaskRules.copy(this.draft);
    next.title = this.title.trim(); next.note = this.note.trim();
    const subject: EasTermSubject | undefined = LearningTaskRules.subject(next, this.data);
    if (next.kind === LearningTaskKind.HOMEWORK && subject === undefined &&
      (this.isNew || next.subjectId !== this.initialTask.subjectId)) { this.error = '请选择关联课程'; return; }
    if (next.kind === LearningTaskKind.REVIEW && LearningTaskRules.exam(next, this.data) === undefined &&
      (this.isNew || next.examId !== this.initialTask.examId)) { this.error = '请选择关联考试'; return; }
    if (subject !== undefined) {
      next.subjectId = subject.id; next.courseName = subject.name; next.courseCode = subject.code;
    }
    this.error = LearningTaskRules.validation(next);
    if (this.error.length > 0) return;
    if (next.remindAt > 0 && (this.isNew || next.remindAt !== this.initialTask.remindAt) && next.remindAt <= Date.now()) {
      this.error = '请选择未来的提醒时间'; return;
    }
    this.saving = true; this.onBusyChanged(true);
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (next.remindAt > 0 && (this.isNew || next.remindAt !== this.initialTask.remindAt) &&
        !(await ClassReminderScheduler.requestNotification(context))) {
        this.error = '请开启通知权限，或将提醒设置为不提醒'; return;
      }
      const rdb: RdbHelper = RdbHelper.getInstance();
      await rdb.init(context);
      await rdb.saveLearningTask(next, this.isNew);
      if (next.remindAt !== this.initialTask.remindAt) await LearningTaskReminders.cancel(next.id);
      if (this.active) this.onSaved();
    } catch (error) {
      if (this.active) this.error = error instanceof Error && /[\u4e00-\u9fff]/.test(error.message) ? error.message : '保存失败，请重试';
    } finally { this.saving = false; this.onBusyChanged(false); }
  }

  @Builder
  private field(label: string, value: () => string, action: () => void) {
    Row({ space: 12 }) {
      Text(label).fontSize(HitaDesign.body).fontColor($r('app.color.hita_text')).flexShrink(0)
      Blank()
      Text(value()).fontSize(HitaDesign.caption).fontColor($r('app.color.hita_text_secondary'))
        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).textAlign(TextAlign.End).constraintSize({ maxWidth: '65%' })
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(HitaDesign.iconSm).fontColor([$r('app.color.hita_text_secondary')])
    }.width('100%').constraintSize({ minHeight: 52 }).padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .onClick(action).enabled(!this.saving).accessibilityText(label + '，' + value())
  }

  build() {
    Column() {
      ImmersiveHeader({ barHeight: 60, materialEnabled: CompatibleSheetMaterial.isEnabled() }) {
        Row({ space: 12 }) {
          HeaderBackButton({ onBack: () => { if (!this.saving) this.onCancel(); } }).enabled(!this.saving)
          Text(this.isNew ? (this.draft.kind === LearningTaskKind.REVIEW ? '添加复习任务' : '添加作业') : '编辑待办')
            .fontSize(HitaDesign.section).fontWeight(FontWeight.Medium).fontColor($r('app.color.hita_text')).layoutWeight(1)
          Button(this.saving ? '保存中' : '保存', { type: ButtonType.Capsule }).height(36).fontSize(HitaDesign.caption)
            .backgroundColor($r('app.color.hita_primary_fill')).fontColor($r('app.color.hita_on_primary'))
            .attributeModifier(new CompatibleMaterialModifier($r('app.color.hita_primary_fill'), true))
            .enabled(!this.saving).onClick(() => { void this.save(); })
        }.width('100%').height(60).padding({ left: 16, right: 16 })
      }
      Scroll() {
        Column({ space: 16 }) {
          Column() {
            TextInput({ text: this.title, placeholder: '待办名称' }).fontSize(HitaDesign.body).height(56)
              .backgroundColor(Color.Transparent).maxLength(120).onChange(value => { this.title = value; this.error = ''; })
              .enabled(!this.saving)
            if (this.draft.kind === LearningTaskKind.HOMEWORK) {
              this.field('关联课程', () => this.subjectText(), () => this.selectSubject())
            } else {
              this.field('关联考试', () => this.examText(), () => this.selectExam())
            }
          }.width('100%').borderRadius(HitaDesign.cardRadius).backgroundColor(CompatibleSheetMaterial.cardColor($r('app.color.hita_surface')))

          Column() {
            this.field('截止日期', () => this.draft.dueAt > 0 ? EasTimeTools.printDate(this.draft.dueAt) : '未设置', () => this.pickDate())
            if (this.draft.dueAt > 0) {
              Row() {
                Text('全天').fontSize(HitaDesign.body).fontColor($r('app.color.hita_text')).layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.draft.allDay }).enabled(!this.saving).onChange(value => {
                  const next = LearningTaskRules.copy(this.draft); next.allDay = value; this.update(next);
                })
              }.width('100%').height(52).padding({ left: 16, right: 16 })
              if (!this.draft.allDay) this.field('截止时间', () => EasTimeTools.printTime(this.draft.dueAt), () => this.pickTime())
            }
            Row({ space: 12 }) {
              if (this.draft.kind === LearningTaskKind.HOMEWORK) {
                Button('下次课前').fontSize(HitaDesign.caption).height(36).backgroundColor($r('app.color.hita_selected'))
                  .fontColor($r('app.color.hita_primary')).onClick(() => this.nextClassDeadline())
              }
              if (this.draft.dueAt > 0) {
                Button('清除日期').fontSize(HitaDesign.caption).height(36).backgroundColor(Color.Transparent)
                  .fontColor($r('app.color.hita_text_secondary')).onClick(() => {
                    const next = LearningTaskRules.copy(this.draft); next.dueAt = 0; next.allDay = false; this.update(next);
                  })
              }
            }.width('100%').padding({ left: 12, right: 12, bottom: 12 }).enabled(!this.saving)
          }.width('100%').borderRadius(HitaDesign.cardRadius).backgroundColor(CompatibleSheetMaterial.cardColor($r('app.color.hita_surface')))

          Column() {
            this.field('提醒', () => this.draft.remindAt > 0 ? EasTimeTools.printDate(this.draft.remindAt) + ' ' +
              EasTimeTools.printTime(this.draft.remindAt) : '不提醒', () => this.chooseReminder())
          }.width('100%').borderRadius(HitaDesign.cardRadius).backgroundColor(CompatibleSheetMaterial.cardColor($r('app.color.hita_surface')))
          if (this.draft.remindAt > 0) {
            Text('应用在前台或后台运行时会通知。').fontSize(HitaDesign.caption)
              .fontColor($r('app.color.hita_text_secondary')).width('100%').padding({ left: 4, right: 4 })
          }
          TextArea({ text: this.note, placeholder: '备注（选填）' }).fontSize(HitaDesign.body).constraintSize({ minHeight: 112 })
            .maxLength(4000).backgroundColor(CompatibleSheetMaterial.cardColor($r('app.color.hita_surface')))
            .borderRadius(HitaDesign.cardRadius).onChange(value => { this.note = value; }).enabled(!this.saving)
          if (this.error.length > 0) {
            Text(this.error).fontSize(HitaDesign.caption).fontColor($r('app.color.hita_error')).width('100%')
          }
          if (!this.isNew) {
            Button('删除待办').height(44).fontSize(HitaDesign.body).width('100%')
              .backgroundColor($r('app.color.hita_error_surface')).fontColor($r('app.color.hita_error'))
              .enabled(!this.saving).onClick(() => this.onDelete())
          }
        }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: this.navBarInset + 24 })
      }.width('100%').layoutWeight(1).scrollBar(BarState.Off).align(Alignment.Top)
    }.width('100%').height('100%')
  }
}
