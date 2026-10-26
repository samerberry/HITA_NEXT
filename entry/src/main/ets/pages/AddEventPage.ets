import { HitaDesign } from '../common/theme/HitaDesign';
import { CourseBatchEdit } from '../feature/timetable/CourseBatchEdit';
/**
 * AddEventPage.ets — 新建/编辑事件（HITA_X ui/event/add 语义 → ArkUI 表单）。
 *
 * Both timetable entry points share single-date/calendar and weekly course creation.
 * Weekly occurrences are committed atomically; editing supports explicit occurrence scopes with atomic writes.
 */
import { common } from '@kit.AbilityKit';
import { LengthMetrics } from '@kit.ArkUI';
import { CourseDateSelection } from '../feature/timetable/CourseDateSelection';
import { CourseWeekPicker } from '../feature/timetable/views/CourseWeekPicker';
import { CourseModeSegment } from '../feature/timetable/views/CourseModeSegment';
import { CourseControlHost } from '../feature/timetable/views/CourseControlHost';
import { CourseTimePickerDialog } from '../feature/timetable/views/CourseTimePickerDialog';
import { CourseTextPickerDialog } from '../feature/timetable/views/CourseTextPickerDialog';
import { HeaderBackButton } from '../common/components/HeaderBackButton';
import { ImmersiveHeader } from '../common/components/ImmersiveHeader';
import { CompatibleMaterialModifier } from '../common/theme/CompatibleMaterialModifier';
import { CompatibleSheetMaterial } from '../common/theme/CompatibleSheetMaterial';
import { CompatiblePickerMaterial } from '../common/theme/CompatiblePickerMaterial';
import { CompatibleLightModifier } from '../common/theme/CompatibleLightModifier';
import { HeaderFade } from '../common/theme/HeaderFade';
import { STATUS_BAR_INSET_FALLBACK } from '../common/theme/StatusBarInset';
import { RdbHelper } from '../common/db/RdbHelper';
import { TimetableResolver } from '../feature/timetable/data/TimetableResolver';
import { TimetableSelectionStore } from '../feature/timetable/data/TimetableSelectionStore';
import {
  EasEventItem,
  EasEventType,
  EasSubjectType,
  EasTermSubject,
  EasTimetable,
  newId
} from '../common/model/timetable/TimetableModels';

const DAY_MS: number = 24 * 60 * 60 * 1000;
const MAX_DAY_OFFSET: number = 370;
const TYPE_ITEMS: string[] = ['日程', '课程', '考试', '备忘'];

@Component
export struct EventEditorForm {
  /**
   * The editor is also used as a bottom sheet from TimetableDetailPage.
   * Route parameters remain supported for the standalone timeline flow.
   */
  @Prop eventId: string = '';
  @Prop targetTimetableId: string = '';
  @Prop initialType: string = '';
  @Prop sheetMode: boolean = false;
  onCancel: () => void = () => {};
  onChanged: () => Promise<void> = async () => {};
  onSaved: (event: EasEventItem, occurrences: EasEventItem[]) => void =
    (_event: EasEventItem, _occurrences: EasEventItem[]) => {};

  @State courseEntry: boolean = false;
  @State timeMode: number = 0;
  @State fromPeriod: number = 0;
  @State toPeriod: number = 0;
  @State selectedSubjectId: string = '';
  @State pickingExisting: boolean = false;
  @State typeIdx: number = 0;
  @State name: string = '';
  @State place: string = '';
  @State teacher: string = '';
  @State dayOffset: number = 0;
  @State dateMode: number = 0;
  @State selectedWeeks: number[] = [];
  @State selectedWeekdays: number[] = [];
  @State weekChoices: number[] = [];
  @State choosingWeeks: boolean = false;
  @State activeCourseControl: boolean = false;
  @State courseTimetable: EasTimetable | undefined = undefined;
  private initialWeek: number = 0;
  private todayBase: number = new Date(new Date().setHours(0, 0, 0, 0)).getTime();
  @State hour: number = 14;
  @State minute: number = 0;
  @State endHour: number = 15;
  @State endMinute: number = 0;
  @State hint: string = '';
  @State saved: boolean = false;
  @State loading: boolean = true;
  @State loadFailed: boolean = false;
  @State saving: boolean = false;
  @State editScope: number = 0;
  @State stoppingCourse: boolean = false;
  @State relatedCourses: EasEventItem[] = [];
  private originalCourse: EasEventItem | undefined = undefined;
  private editId: string = '';
  private timetableId: string = '';
  private subjectId: string = '';
  private editorActive: boolean = false;
  private leavingEditor: boolean = false;
  private timePicker: CustomDialogController | undefined = undefined;
  private coursePicker: CustomDialogController | undefined = undefined;

  async aboutToAppear(): Promise<void> {
    this.editorActive = true;
    this.leavingEditor = false;
    try {
      await this.loadEvent();
    } catch (_) {
      this.loadFailed = true;
      this.hint = '读取失败，请关闭后重试';
    } finally {
      this.loading = false;
    }
  }

  aboutToDisappear(): void {
    this.editorActive = false;
    this.timePicker?.close();
    this.timePicker = undefined;
    this.coursePicker?.close();
    this.coursePicker = undefined;
  }

  private leaveEditor(): void {
    // Ignore repeated close requests while the page or sheet is leaving.
    if (!this.editorActive || this.leavingEditor) return;
    this.leavingEditor = true;
    this.choosingWeeks = false;
    if (this.sheetMode) {
      this.onCancel();
    } else {
      this.getUIContext().getRouter().back();
    }
  }

  private async loadEvent(): Promise<void> {
    const params: Object | undefined = this.getUIContext().getRouter().getParams();
    let id: string = this.eventId;
    this.timetableId = this.targetTimetableId;
    let routeType: string = this.initialType;
    let offsetRaw: string = '';
    if (!this.sheetMode && params !== undefined && params !== null) {
      const record = params as Record<string, string>;
      if (id.length === 0) {
        id = record['id'] === undefined ? '' : record['id'] as string;
      }
      if (this.timetableId.length === 0) {
        this.timetableId = record['timetableId'] === undefined ? '' : record['timetableId'] as string;
      }
      if (routeType.length === 0) {
        routeType = record['type'] === undefined ? '' : record['type'] as string;
      }
      offsetRaw = record['offset'] === undefined ? '' : record['offset'] as string;
      this.initialWeek = Number(record['week'] || '0');
    }
    this.courseEntry = routeType === 'CLASS';
    if (id.length === 0 && routeType.length > 0) {
      // 新建时按调用方指定类型初始化（CLASS=课程 / EXAM=考试；缺省为日程）。
      this.typeIdx = EventEditorForm.idxOf(EventEditorForm.typeFromName(routeType));
    }
    if (id.length === 0) {
      // 新建：若从时间线某天进入，沿用该天（offset 参数）
      if (offsetRaw.length > 0) {
        const n: number = Number(offsetRaw);
        if (!Number.isNaN(n)) {
          let off: number = n;
          if (off < -MAX_DAY_OFFSET) {
            off = -MAX_DAY_OFFSET;
          }
          if (off > MAX_DAY_OFFSET) {
            off = MAX_DAY_OFFSET;
          }
          this.dayOffset = off;
        }
      }
      if (this.typeIdx === 1) {
        this.timeMode = 1;
        await this.loadCourseTimetable();
      }
      return;
    }
    this.editId = id;
    const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
    await RdbHelper.getInstance().init(ctx);
    const ev: EasEventItem | undefined = await RdbHelper.getInstance().getEventById(id);
    if (ev === undefined) {
      this.loadFailed = true;
      this.hint = '这条记录已不存在，请关闭后刷新列表';
      return;
    }
    this.timetableId = ev.timetableId.length > 0 ? ev.timetableId : this.timetableId;
    this.originalCourse = CourseBatchEdit.copy(ev);
    if (ev.type === EasEventType.CLASS) {
      this.courseEntry = true;
      await this.loadCourseTimetable(false);
      this.relatedCourses = await RdbHelper.getInstance().getEventsOfTimetable(ev.timetableId);
      if (this.courseTimetable !== undefined) {
        this.selectedWeeks = [this.courseTimetable.getWeekNumber(ev.from)];
      }
    }
    this.name = ev.name;
    this.place = ev.place;
    this.teacher = ev.teacher;
    this.timetableId = ev.timetableId.length > 0 ? ev.timetableId : this.timetableId;
    this.subjectId = ev.subjectId;
    this.typeIdx = EventEditorForm.idxOf(ev.type);
    const d: Date = new Date(ev.from);
    this.hour = d.getHours();
    this.minute = d.getMinutes();
    const end: Date = new Date(ev.to);
    this.endHour = end.getHours();
    this.endMinute = end.getMinutes();
    const todayMidnight: number = new Date(new Date().setHours(0, 0, 0, 0)).getTime();
    const fromMidnight: number = new Date(new Date(ev.from).setHours(0, 0, 0, 0)).getTime();
    // Editing an older record must not silently move its original date.
    this.dayOffset = Math.round((fromMidnight - todayMidnight) / DAY_MS);
  }

  private static pad2(n: number): string {
    return n < 10 ? '0' + n.toString() : n.toString();
  }

  private dateText(): string {
    const d: Date = new Date(this.todayBase + this.dayOffset * DAY_MS);
    return d.getFullYear().toString() + '-' + EventEditorForm.pad2(d.getMonth() + 1) + '-' +
      EventEditorForm.pad2(d.getDate());
  }

  /** Native month calendar instead of the rolling year/month/day selector. */
  private chooseDate(): void {
    CalendarPickerDialog.show({
      selected: new Date(this.todayBase + this.dayOffset * DAY_MS),
      onAccept: (date: Date) => {
        const selected: Date = new Date(date.getFullYear(), date.getMonth(), date.getDate());
        this.dayOffset = Math.round((selected.getTime() - this.todayBase) / DAY_MS);
      }
    });
  }

  private async loadCourseTimetable(initializeSelection: boolean = true): Promise<void> {
    const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
    const rdb: RdbHelper = RdbHelper.getInstance();
    await rdb.init(ctx);
    let timetable: EasTimetable | undefined;
    if (this.timetableId.length > 0) {
      timetable = await rdb.getTimetableById(this.timetableId);
    } else {
      const selection: TimetableSelectionStore = TimetableSelectionStore.getInstance();
      await selection.init(ctx);
      const selectedId: string = await selection.load();
      timetable = selectedId.length > 0 ? await rdb.getTimetableById(selectedId) : undefined;
      if (timetable === undefined) timetable = await TimetableResolver.getForDisplay(rdb);
    }
    this.courseTimetable = timetable;
    if (timetable === undefined) {
      this.hint = '请先新建或导入课表，再添加课程';
      return;
    }
    this.timetableId = timetable.id;
    this.weekChoices = CourseDateSelection.numbers(Math.max(CourseDateSelection.weekCount(timetable),
      initializeSelection ? 0 : this.weekChoices.length));
    if (initializeSelection && this.selectedWeeks.length === 0 && this.weekChoices.length > 0) {
      const week: number = this.initialWeek > 0 ? this.initialWeek : timetable.getWeekNumber(Date.now());
      this.selectedWeeks = [Math.max(1, Math.min(this.weekChoices.length, week))];
    }
    if (initializeSelection && this.selectedWeekdays.length === 0) {
      const day: number = new Date(this.todayBase + this.dayOffset * DAY_MS).getDay();
      this.selectedWeekdays = [day === 0 ? 7 : day];
    }
  }

  private selectWeekPreset(mode: number): void {
    this.selectedWeeks = this.weekChoices.filter((week: number): boolean =>
      mode === 0 || (mode === 1 && week % 2 === 1) || (mode === 2 && week % 2 === 0));
  }

  private usesPeriods(): boolean { return this.typeIdx === 1 && this.editId.length === 0 && this.timeMode === 1; }

  private selectedTime(): number[] {
    if (!this.usesPeriods()) return [this.hour * 60 + this.minute, this.endHour * 60 + this.endMinute];
    const periods = this.courseTimetable?.scheduleStructure;
    if (periods === undefined || this.fromPeriod < 1 || this.toPeriod < this.fromPeriod ||
      this.toPeriod > periods.length) return [-1, -1];
    const start = periods[this.fromPeriod - 1].from;
    const end = periods[this.toPeriod - 1].to;
    return [start.hour * 60 + start.minute, end.hour * 60 + end.minute];
  }

  private static minuteLabel(value: number): string {
    return value < 0 ? '未选择' : EventEditorForm.pad2(Math.floor(value / 60)) + ':' + EventEditorForm.pad2(value % 60);
  }

  private startLabel(): string { return EventEditorForm.minuteLabel(this.selectedTime()[0]); }
  private endLabel(): string { return EventEditorForm.minuteLabel(this.selectedTime()[1]); }

  private choosePeriod(start: boolean): void {
    const timetable = this.courseTimetable;
    if (timetable === undefined || timetable.scheduleStructure.length === 0) return;
    this.showCourseTextPicker({
      range: timetable.scheduleStructure.map((period, index: number): string =>
        '第 ' + (index + 1).toString() + ' 节  ' + EventEditorForm.minuteLabel(period.from.hour * 60 + period.from.minute) +
        '–' + EventEditorForm.minuteLabel(period.to.hour * 60 + period.to.minute)),
      selected: Math.max(0, (start ? this.fromPeriod : this.toPeriod) - 1),
      canLoop: false,
      onAccept: (result: TextPickerResult) => {
        if (typeof result.index !== 'number' || result.index < 0 || result.index >= timetable.scheduleStructure.length) return;
        if (start) {
          this.fromPeriod = result.index + 1;
          if (this.toPeriod < this.fromPeriod) this.toPeriod = this.fromPeriod;
        } else {
          this.toPeriod = result.index + 1;
          if (this.fromPeriod === 0 || this.fromPeriod > this.toPeriod) this.fromPeriod = this.toPeriod;
        }
        this.hint = '';
      }
    });
  }

  private selectExistingCourse(event: EasEventItem): void {
    this.selectedSubjectId = event.subjectId;
    this.name = event.name;
    this.place = event.place;
    this.teacher = event.teacher;
    this.hint = '';
  }

  private async chooseExistingCourse(): Promise<void> {
    if (this.pickingExisting || this.loading || this.saving) return;
    this.pickingExisting = true;
    try {
      const rdb = RdbHelper.getInstance();
      const subjects = await rdb.getSubjectsOfTimetable(this.timetableId);
      const events = await rdb.getEventsOfTimetable(this.timetableId);
      const choices: EasEventItem[] = [];
      const seen: Set<string> = new Set<string>();
      for (const event of events) {
        if (event.type !== EasEventType.CLASS || !subjects.some((subject: EasTermSubject): boolean => subject.id === event.subjectId)) continue;
        const key: string = JSON.stringify([event.subjectId, event.name, event.place, event.teacher]);
        if (seen.has(key)) continue;
        seen.add(key);
        choices.push(event);
      }
      for (const subject of subjects) {
        if (choices.some((event: EasEventItem): boolean => event.subjectId === subject.id)) continue;
        const event = new EasEventItem();
        event.subjectId = subject.id;
        event.name = subject.name;
        choices.push(event);
      }
      choices.sort((a: EasEventItem, b: EasEventItem): number => a.name.localeCompare(b.name));
      if (!this.editorActive) return;
      if (choices.length === 0) { this.hint = '当前课表还没有课程，请手动填写'; return; }
      this.showCourseTextPicker({
        range: choices.map((event: EasEventItem): string => [event.name, event.place, event.teacher]
          .filter((value: string): boolean => value.length > 0).join(' · ')),
        selected: Math.max(0, choices.findIndex((event: EasEventItem): boolean => event.subjectId === this.selectedSubjectId)),
        canLoop: false,
        onAccept: (result: TextPickerResult) => {
          if (this.editorActive && typeof result.index === 'number' && choices[result.index] !== undefined) {
            this.selectExistingCourse(choices[result.index]);
          }
        }
      });
    } catch (_) { this.hint = '读取已有课程失败，请重试'; }
    finally { this.pickingExisting = false; }
  }

  private validationHint(): string {
    if (this.name.trim().length === 0) return this.typeIdx === 1 ? '请填写课程名称' : '请填写名称';
    if (this.typeIdx === 1 && this.editId.length === 0) {
      const timetable = this.courseTimetable;
      if (timetable === undefined) return '请先新建或导入课表';
      if (this.dateMode === 1) {
        try { CourseDateSelection.weeklyDates(timetable, this.selectedWeeks, this.selectedWeekdays, this.weekChoices.length); }
        catch (error) { return error instanceof Error ? error.message : '请检查日期选择'; }
      } else if (this.todayBase + this.dayOffset * DAY_MS < EasTimetable.mondayMsOf(timetable.startTime)) {
        return '日期早于开学日期，请选择本学期内或之后的日期';
      }
    }
    const time = this.selectedTime();
    if (time[0] < 0 || time[1] < 0) return '请选择上课节次';
    if (time[1] <= time[0]) return '结束时间必须晚于开始时间';
    return '';
  }

  private showCourseTextPicker(options: TextPickerDialogOptionsExt): void {
    if (this.typeIdx !== 1 || !CompatiblePickerMaterial.isEnabled()) {
      this.getUIContext().showTextPickerDialog(options);
      return;
    }
    this.coursePicker?.close();
    this.coursePicker = new CustomDialogController({
      builder: CourseTextPickerDialog({ options: options }),
      alignment: DialogAlignment.Bottom,
      autoCancel: true,
      backgroundColor: Color.Transparent,
      systemMaterial: CompatiblePickerMaterial.dialogMaterial(true),
      cornerRadius: 24,
      cancel: () => options.onCancel?.()
    });
    this.coursePicker.open();
  }

  private canSave(): boolean {
    return !this.loading && !this.loadFailed && !this.saving && !this.saved && !this.pickingExisting &&
      (this.stoppingCourse || this.validationHint().length === 0) &&
      (this.editId.length === 0 || this.typeIdx !== 1 || this.editTargets().length > 0);
  }

  private extensionHint(): string {
    const timetable = this.courseTimetable;
    if (timetable === undefined || this.editId.length > 0) return '';
    const lastDate: number = this.dateMode === 0 ? this.todayBase + this.dayOffset * DAY_MS :
      EasTimetable.mondayMsOf(timetable.startTime) +
      (Math.max(1, ...this.selectedWeeks) - 1) * 7 * DAY_MS + (Math.max(1, ...this.selectedWeekdays) - 1) * DAY_MS;
    const end: number = lastDate + this.selectedTime()[1] * 60000;
    if (end <= timetable.endTime) return '';
    const date: Date = new Date(CourseDateSelection.weekEnd(end));
    return '保存后课表将延长至 ' + date.getFullYear().toString() + '-' +
      EventEditorForm.pad2(date.getMonth() + 1) + '-' + EventEditorForm.pad2(date.getDate());
  }

  private acceptTime(start: boolean, hour: number, minute: number): boolean {
    if (!this.editorActive) return false;
    const selectedMinutes: number = hour * 60 + minute;
    if ((start && selectedMinutes >= this.endHour * 60 + this.endMinute) ||
      (!start && selectedMinutes <= this.hour * 60 + this.minute)) {
      this.getUIContext().getPromptAction().showToast({
        message: start ? '开始时间必须早于结束时间' : '结束时间必须晚于开始时间'
      });
      return false;
    }
    if (start) {
      this.hour = hour;
      this.minute = minute;
    } else {
      this.endHour = hour;
      this.endMinute = minute;
    }
    this.hint = '';
    return true;
  }

  private pickTime(start: boolean): void {
    if (this.typeIdx !== 1) {
      this.getUIContext().showTimePickerDialog({
        selected: new Date(2000, 0, 1, start ? this.hour : this.endHour, start ? this.minute : this.endMinute),
        useMilitaryTime: true,
        onAccept: (value: TimePickerResult) => { this.acceptTime(start, value.hour, value.minute); }
      });
      return;
    }
    this.timePicker?.close();
    const material: SystemUiMaterial | undefined = CompatiblePickerMaterial.dialogMaterial(true);
    // ArkUI only lowers the custom dialog builder inside a direct options literal.
    this.timePicker = new CustomDialogController({
      builder: CourseTimePickerDialog({
        title: start ? '开始时间' : '结束时间',
        initialHour: start ? this.hour : this.endHour,
        initialMinute: start ? this.minute : this.endMinute,
        immersive: true,
        onAccept: (hour: number, minute: number): boolean => this.acceptTime(start, hour, minute)
      }),
      alignment: DialogAlignment.Bottom,
      autoCancel: true,
      backgroundColor: material === undefined ? $r('app.color.hita_surface') : Color.Transparent,
      systemMaterial: material,
      cornerRadius: 24
    });
    this.timePicker.open();
  }

  private pickStartTime(): void { this.pickTime(true); }

  private pickEndTime(): void { this.pickTime(false); }

  private courseMaterialsEnabled(): boolean {
    return this.typeIdx === 1 && CompatibleSheetMaterial.isEnabled();
  }

  private editorBackground(): ResourceColor {
    return this.sheetMode && this.courseMaterialsEnabled() ? Color.Transparent :
      (this.sheetMode ? $r('app.color.hita_surface_soft') : $r('app.color.hita_page_f5f6f8'));
  }

  private courseCardColor(): ResourceColor {
    return this.sheetMode && this.courseMaterialsEnabled() ?
      CompatibleSheetMaterial.cardColor($r('app.color.hita_surface')) : $r('app.color.hita_surface');
  }

  private async save(): Promise<void> {
    if (this.loading || this.loadFailed || this.saving || this.saved) {
      return;
    }
    if (this.editId.length > 0 && this.typeIdx === 1 && this.editTargets().length === 0) {
      this.hint = '所选范围没有课次，请重新选择'; return;
    }
    const invalid: string = this.stoppingCourse ? '' : this.validationHint();
    if (invalid.length > 0) { this.hint = invalid; return; }
    this.saving = true;
    try {
      if (this.editId.length > 0 && this.typeIdx === 1) {
        await this.persistCourseEdit();
      } else {
        await this.persistEvent();
      }
    } catch (_) {
      this.hint = '保存失败，请重试';
    } finally {
      this.saving = false;
    }
  }

  private editTargets(): EasEventItem[] {
    if (this.originalCourse === undefined) return [];
    return CourseBatchEdit.targets(this.relatedCourses, this.originalCourse, this.editScope,
      this.selectedWeeks, this.courseTimetable);
  }

  private async persistCourseEdit(): Promise<void> {
    const original: EasEventItem | undefined = this.originalCourse;
    if (original === undefined) return;
    const before: EasEventItem[] = this.editTargets();
    if (before.length === 0) { this.hint = '所选范围没有课次'; return; }
    const edited: EasEventItem = CourseBatchEdit.copy(original);
    edited.name = this.name.trim(); edited.place = this.place.trim(); edited.teacher = this.teacher.trim();
    const date: Date = new Date(this.todayBase + this.dayOffset * DAY_MS);
    date.setHours(this.hour, this.minute, 0, 0); edited.from = date.getTime();
    date.setHours(this.endHour, this.endMinute, 0, 0); edited.to = date.getTime();
    const after: EasEventItem[] = this.stoppingCourse ? [] : CourseBatchEdit.update(before, original, edited);
    const operation: string = this.stoppingCourse ? '停课' : '修改';
    let confirmed: boolean = false;
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: operation + ' ' + before.length.toString() + ' 个课次？',
        message: this.editScope === 0 ? '仅本次课程' :
          (this.editScope === 1 ? '所选教学周内本课程的全部课次' : '从当前课次起本课程的全部后续课次'),
        buttons: [
          { text: '取消', color: $r('app.color.hita_text_secondary_72809a') },
          { text: '确认' + operation, color: $r('app.color.hita_primary_3390ec') }
        ]
      });
      confirmed = result.index === 1;
    } catch (_) { return; }
    if (!confirmed || !this.editorActive) return;
    const rdb: RdbHelper = RdbHelper.getInstance();
    await rdb.replaceCourseOccurrences(before, after, original.timetableId);
    await this.onChanged().catch(() => {});
    // Keep the snapshot until the user finishes or restores it. A failed undo stays retryable.
    let undone: boolean = false;
    if (this.editorActive) {
      let finished: boolean = false;
      while (!finished && this.editorActive) {
        try {
          const result = await this.getUIContext().getPromptAction().showDialog({
            title: '已' + operation + ' ' + before.length.toString() + ' 个课次',
            buttons: [{ text: '完成', color: $r('app.color.hita_text_secondary_72809a') }, { text: '撤销', color: $r('app.color.hita_primary_3390ec') }]
          });
          if (result.index === 1) {
            try {
              await rdb.replaceCourseOccurrences(after, before, original.timetableId);
              undone = true; finished = true;
              await this.onChanged().catch(() => {});
            } catch (_) {
              this.getUIContext().getPromptAction().showToast({ message: '撤销失败，课表可能已变更，请重试或刷新后检查' });
            }
          } else { finished = true; }
        } catch (_) { finished = true; }
      }
    }
    if (!this.editorActive) return;
    this.saved = true;
    if (this.sheetMode) this.onSaved(undone ? original : edited, undone ? before : after);
    else this.getUIContext().getRouter().back();
  }

  private async persistEvent(): Promise<void> {
    const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
    const rdb: RdbHelper = RdbHelper.getInstance();
    await rdb.init(ctx);
    const base: number = this.todayBase + this.dayOffset * DAY_MS;
    let ev: EasEventItem = new EasEventItem();
    if (this.editId.length > 0) {
      const existing: EasEventItem | undefined = await rdb.getEventById(this.editId);
      if (existing === undefined) {
        this.loadFailed = true;
        this.hint = '这条记录已不存在，请关闭后刷新列表';
        return;
      }
      ev = existing;
    }
    ev.type = EventEditorForm.typeOf(this.typeIdx);
    ev.name = this.name.trim();
    ev.place = this.place.trim();
    ev.teacher = this.teacher.trim();
    ev.subjectId = this.subjectId;
    // Prefer the explicit target, then the user's current timetable.
    ev.timetableId = this.timetableId;
    let occurrences: EasEventItem[] = [ev];
    if (this.typeIdx === 1 && this.editId.length === 0) {
      // Resolve the explicit target again before writing; never fall back to another timetable if it was deleted.
      await this.loadCourseTimetable(false);
      const timetable: EasTimetable | undefined = this.courseTimetable;
      if (timetable === undefined) return;
      const invalid: string = this.validationHint();
      if (invalid.length > 0) { this.hint = invalid; return; }
      ev.timetableId = timetable.id;
      let dates: number[] = [base];
      if (this.dateMode === 1) {
        try {
          dates = CourseDateSelection.weeklyDates(timetable, this.selectedWeeks, this.selectedWeekdays, this.weekChoices.length);
        } catch (error) {
          this.hint = error instanceof Error ? error.message : '日期选择无效';
          return;
        }
      }
      const subjects: EasTermSubject[] = await rdb.getSubjectsOfTimetable(timetable.id);
      let matched: EasTermSubject | undefined = subjects.find((subject: EasTermSubject): boolean =>
        this.selectedSubjectId.length > 0 ? subject.id === this.selectedSubjectId : subject.name === ev.name);
      if (this.selectedSubjectId.length > 0 && matched === undefined) {
        this.hint = '所选课程已不存在，请重新选择或手动填写';
        return;
      }
      const newSubject: boolean = matched === undefined;
      if (matched === undefined) {
        matched = new EasTermSubject();
        matched.name = ev.name;
        matched.timetableId = timetable.id;
        matched.type = EasSubjectType.COM_B;
        matched.field = 'manual';
        matched.countInSPA = false;
      }
      occurrences = [];
      const selectedTime: number[] = this.selectedTime();
      for (const date of dates) {
        const occurrence: EasEventItem = new EasEventItem();
        occurrence.type = EasEventType.CLASS;
        occurrence.name = ev.name;
        occurrence.place = ev.place;
        occurrence.teacher = ev.teacher;
        occurrence.timetableId = timetable.id;
        occurrence.subjectId = matched.id;
        occurrence.color = matched.color;
        const from: Date = new Date(date);
        const to: Date = new Date(date);
        from.setHours(Math.floor(selectedTime[0] / 60), selectedTime[0] % 60, 0, 0);
        to.setHours(Math.floor(selectedTime[1] / 60), selectedTime[1] % 60, 0, 0);
        occurrence.fromNumber = this.usesPeriods() ? this.fromPeriod : 0;
        occurrence.lastNumber = this.usesPeriods() ? this.toPeriod : 0;
        occurrence.from = from.getTime();
        occurrence.to = to.getTime();
        occurrences.push(occurrence);
      }
      await rdb.saveCourseOccurrences(matched, occurrences, newSubject);
      ev = occurrences[0];
    } else {
      // Clock edits must not retain now-inaccurate period metadata from a period-based course.
      if (this.editId.length > 0 && ev.type === EasEventType.CLASS &&
        (new Date(ev.from).getHours() !== this.hour || new Date(ev.from).getMinutes() !== this.minute ||
         new Date(ev.to).getHours() !== this.endHour || new Date(ev.to).getMinutes() !== this.endMinute)) {
        ev.fromNumber = 0;
        ev.lastNumber = 0;
      }
      ev.from = base + this.hour * 60 * 60 * 1000 + this.minute * 60 * 1000;
      ev.to = base + this.endHour * 60 * 60 * 1000 + this.endMinute * 60 * 1000;
      if (this.editId.length === 0 || ev.color === 0) ev.color = EventEditorForm.typeColor(ev.type);
      if (this.editId.length > 0) {
        await rdb.updateEvent(ev);
      } else {
        await rdb.saveEvent(ev);
      }
    }
    // A pending write may finish after the user has closed this editor.
    if (!this.editorActive) {
      return;
    }
    this.saved = true;
    this.hint = this.editId.length > 0 ? '已更新' :
      (this.typeIdx === 1 ? '已添加 ' + occurrences.length.toString() + ' 个课次' : '已保存');
    this.getUIContext().getPromptAction().showToast({ message: this.hint });
    if (this.sheetMode) {
      this.onSaved(ev, occurrences);
    } else {
      this.getUIContext().getRouter().back();
    }
  }

  static idxOf(t: EasEventType): number {
    if (t === EasEventType.CLASS) {
      return 1;
    }
    if (t === EasEventType.EXAM) {
      return 2;
    }
    if (t === EasEventType.TAG) {
      return 3;
    }
    return 0;
  }

  static typeFromName(name: string): EasEventType {
    if (name === 'CLASS') {
      return EasEventType.CLASS;
    }
    if (name === 'EXAM') {
      return EasEventType.EXAM;
    }
    if (name === 'TAG') {
      return EasEventType.TAG;
    }
    return EasEventType.OTHER;
  }

  static typeOf(idx: number): EasEventType {
    if (idx === 1) {
      return EasEventType.CLASS;
    }
    if (idx === 2) {
      return EasEventType.EXAM;
    }
    if (idx === 3) {
      return EasEventType.TAG;
    }
    return EasEventType.OTHER;
  }

  static typeColor(t: EasEventType): number {
    if (t === EasEventType.EXAM) {
      return 0xFFD93025;
    }
    if (t === EasEventType.OTHER) {
      return 0xFF5C6BC0;
    }
    if (t === EasEventType.TAG) {
      return 0xFF26A69A;
    }
    return 0xFF3390EC;
  }

  private sheetTitle(): string {
    if (this.editId.length > 0) {
      return this.typeIdx === 2 ? '编辑考试' : '编辑课程';
    }
    return this.typeIdx === 2 ? '添加考试' : '添加课程';
  }

  private sheetSubtitle(): string {
    if (this.editId.length > 0) {
      return '修改信息';
    }
    return this.typeIdx === 2 ? '考试将添加到当前课表' : '将课程添加到当前课表';
  }

  private courseSaveSummary(): string {
    if (this.stoppingCourse) return '将停课 ' + this.editTargets().length.toString() + ' 个课次';
    if (this.name.trim().length === 0) return '';
    const invalid: string = this.validationHint();
    if (invalid.length > 0) return invalid;
    if (this.editId.length > 0) return '将' + (this.stoppingCourse ? '停课 ' : '修改 ') + this.editTargets().length.toString() + ' 个课次';
    if (this.dateMode === 0) return this.dateText() + ' · ' + this.startLabel() + '–' + this.endLabel();
    if (this.selectedWeekdays.length === 0) return '请选择上课的星期';
    if (this.selectedWeeks.length === 0) return '请选择教学周';
    return '将添加 ' + (this.selectedWeeks.length * this.selectedWeekdays.length).toString() +
      ' 个课次 · ' + this.startLabel() + '–' + this.endLabel();
  }

  build() {
    Column() {
      if (this.sheetMode) {
        ImmersiveHeader({ barHeight: 58 }) {
          Row() {
            HeaderBackButton({
              onBack: () => this.leaveEditor()
            })
              .margin({ right: 12 })
            Column() {
              Text(this.sheetTitle())
                .fontSize(HitaDesign.title)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.hita_text_1d2b45'))
              Text(this.sheetSubtitle())
                .fontSize(HitaDesign.label)
                .fontColor($r('app.color.hita_text_secondary_72809a'))
                .margin({ top: 4 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .height(58)
          .padding({ left: 20, right: 16 })
          .alignItems(VerticalAlign.Center)
        }
      } else {
        ImmersiveHeader({ barHeight: 56 }) {
          Row() {
            HeaderBackButton({
              onBack: () => this.getUIContext().getRouter().back()
            })
              .margin({ right: 12 })
            Text(this.typeIdx === 1 ? this.sheetTitle() : (this.editId.length > 0 ? '编辑事件' : '新建事件'))
              .fontSize(HitaDesign.title)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.hita_text'))
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .height(56)
          .padding({ left: 16, right: 16 })
          .backgroundColor(Color.Transparent)
          .alignItems(VerticalAlign.Center)
        }
      }

      List({ space: 12 }) {
        if (!this.sheetMode && !this.courseEntry) {
          ListItem() {
            this.typeRow()
          }
        }
        if (this.typeIdx === 1) {
          if (this.editId.length > 0) {
            ListItem() { this.editScopeCard() }
              .clip(false).zIndex(this.activeCourseControl || this.choosingWeeks ? 3 : 1)
          }
          if (!this.stoppingCourse) {
            ListItem() { this.courseInfoCard() }
            ListItem() { this.timeRow() }
          }
        } else {
          ListItem() { this.eventInfoCard() }
        }
        if (!this.stoppingCourse) {
        ListItem() {
          if (this.typeIdx === 1 && this.editId.length === 0) {
            this.courseDateRow()
          } else {
            this.dateRow()
          }
        }
        .clip(false)
        .zIndex(this.activeCourseControl || this.choosingWeeks ? 3 : 1)
        if (this.typeIdx !== 1) {
          ListItem() { this.timeRow() }
        }
        }
      }
      .width('100%')
      .layoutWeight(1)
      .padding({
        left: this.sheetMode ? 20 : 16,
        right: this.sheetMode ? 20 : 16,
        top: this.typeIdx === 1 ? 0 : 8,
        bottom: this.typeIdx === 1 ? 0 : 16
      })
      // Scroll the end spacing with the form so its first and last controls clear the fades.
      .contentStartOffset(this.typeIdx === 1 ? HeaderFade.HEIGHT + 8 : 0)
      .contentEndOffset(this.typeIdx === 1 ? HeaderFade.HEIGHT + 16 : 0)
      .fadingEdge(this.typeIdx === 1, { fadingEdgeLength: LengthMetrics.vp(HeaderFade.HEIGHT) })
      .scrollBar(BarState.Off)
      .enableScrollInteraction(!this.choosingWeeks)
      .enabled(!this.loading && !this.loadFailed && !this.saving && !this.saved)

      Column() {
        if (this.typeIdx === 1 && !this.loading && this.hint.length === 0 &&
          this.courseSaveSummary().length > 0) {
          Text(this.courseSaveSummary())
            .fontSize(HitaDesign.label)
            .fontColor($r('app.color.hita_text_secondary_72809a'))
            .width('100%')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ bottom: 8 })
        }
        if (this.hint.length > 0) {
          Text(this.hint)
            .fontSize(HitaDesign.label)
            .fontColor(this.saved ? $r('app.color.hita_success_2e7d32') : $r('app.color.hita_error'))
            .width('100%')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ bottom: 6 })
        }
        ImmersiveHeader({ barHeight: 56 }) {
          Button(this.loading ? '正在读取' : (this.saving ? '正在保存' :
            (this.typeIdx === 1 ? (this.stoppingCourse ? '停课' : (this.editId.length > 0 ? '保存修改' : '添加课程')) : '保存')), { type: ButtonType.Capsule })
            .width('100%')
            .height(HitaDesign.buttonHeight)
            .fontSize(HitaDesign.body)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.hita_on_primary'))
            .backgroundColor($r('app.color.hita_primary_fill'))
            .borderRadius(22)
            .attributeModifier(new CompatibleMaterialModifier($r('app.color.hita_primary_fill'), true))
            .enabled(this.canSave())
            .onClick(() => {
              this.save();
            })
        }
      }
      .width('100%')
      .padding({
        left: HitaDesign.inset,
        right: HitaDesign.inset,
        top: 8,
        bottom: 10
      })
      .backgroundColor(this.editorBackground())
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.editorBackground())
    .attributeModifier(new CompatibleLightModifier(24, this.sheetMode && this.courseMaterialsEnabled(), true))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  @Builder
  editScopeCard() {
    Column({ space: 12 }) {
      Text('应用范围').fontSize(HitaDesign.body).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.hita_text_202b45'))
      CourseModeSegment({ labels: ['仅本次', '选定周次', '之后所有'], selectedIndex: this.editScope,
        onSelect: (index: number) => {
          if (index > 0 && this.subjectId.length === 0) {
            this.hint = '当前课次没有关联课程，仅支持修改本次'; return;
          }
          this.editScope = index; this.hint = '';
        },
        onControlPressingChanged: (pressing: boolean) => { this.activeCourseControl = pressing; }
      })
      if (this.editScope === 1) {
        CourseWeekPicker({ weeks: this.weekChoices, chosen: $selectedWeeks,
          onChoosingChanged: (choosing: boolean) => { this.choosingWeeks = choosing; }
        })
      }
      Row() {
        Text('停课').fontSize(HitaDesign.caption).fontColor($r('app.color.hita_text_202b45'))
        Blank()
        Toggle({ type: ToggleType.Switch, isOn: this.stoppingCourse })
          .onChange((value: boolean) => { this.stoppingCourse = value; this.hint = ''; })
      }.width('100%')
      Text('已选 ' + this.editTargets().length.toString() + ' 个课次')
        .fontSize(HitaDesign.label).fontColor($r('app.color.hita_text_secondary_72809a'))
    }.width('100%').padding(16).borderRadius(HitaDesign.cardRadius)
    .alignItems(HorizontalAlign.Start).backgroundColor(this.courseCardColor())
  }

  @Builder
  courseInfoCard() {
    Column({ space: 12 }) {
      Row() {
        Text('课程信息')
          .fontSize(HitaDesign.body).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.hita_text_202b45'))
      }.width('100%')
      if (this.courseTimetable !== undefined) {
        Text('添加至 ' + this.courseTimetable.name)
          .fontSize(HitaDesign.label).fontColor($r('app.color.hita_text_secondary_72809a'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      if (this.editId.length === 0) {
        ImmersiveHeader({ barHeight: 36, materialEnabled: this.courseMaterialsEnabled() }) {
          Row({ space: 8 }) {
            Button(this.pickingExisting ? '正在读取…' : '选择已有课程')
              .layoutWeight(1).height(36).fontSize(HitaDesign.caption)
              .backgroundColor($r('app.color.hita_surface_soft'))
              .fontColor($r('app.color.hita_primary_3390ec'))
              .attributeModifier(new CompatibleMaterialModifier($r('app.color.hita_surface_soft'), false,
                this.courseMaterialsEnabled()))
              .enabled(!this.pickingExisting)
              .onClick(() => { void this.chooseExistingCourse(); })
            if (this.selectedSubjectId.length > 0) {
              Button('手动填写').height(36).fontSize(HitaDesign.caption)
                .backgroundColor($r('app.color.hita_surface_soft'))
                .fontColor($r('app.color.hita_text_secondary_72809a'))
                .attributeModifier(new CompatibleMaterialModifier($r('app.color.hita_surface_soft'), false,
                  this.courseMaterialsEnabled()))
                .onClick(() => {
                  this.selectedSubjectId = ''; this.name = ''; this.place = ''; this.teacher = ''; this.hint = '';
                })
            }
          }.width('100%')
        }
      }
      Row({ space: 12 }) {
        Text('名称').fontSize(HitaDesign.body).fontColor($r('app.color.hita_text_secondary'))
          .width(40).flexShrink(0)
        TextInput({ text: this.name })
          .accessibilityText('名称')
          .enabled(this.selectedSubjectId.length === 0)
          .fontSize(HitaDesign.body).height(HitaDesign.buttonHeight).layoutWeight(1)
          .padding({ left: 12, right: 12 }).borderRadius(12)
          .backgroundColor($r('app.color.hita_surface_soft'))
          .onChange((value: string) => { this.name = value; this.hint = ''; })
      }.width('100%')
      Row({ space: 12 }) {
        Text('教室').fontSize(HitaDesign.body).fontColor($r('app.color.hita_text_secondary'))
          .width(40).flexShrink(0)
        TextInput({ text: this.place })
          .accessibilityText('教室')
          .fontSize(HitaDesign.body).height(HitaDesign.buttonHeight).layoutWeight(1)
          .padding({ left: 12, right: 12 }).borderRadius(12)
          .backgroundColor($r('app.color.hita_surface_soft'))
          .onChange((value: string) => { this.place = value; })
      }.width('100%')
      Row({ space: 12 }) {
        Text('教师').fontSize(HitaDesign.body).fontColor($r('app.color.hita_text_secondary'))
          .width(40).flexShrink(0)
        TextInput({ text: this.teacher })
          .accessibilityText('教师')
          .fontSize(HitaDesign.body).height(HitaDesign.buttonHeight).layoutWeight(1)
          .padding({ left: 12, right: 12 }).borderRadius(12)
          .backgroundColor($r('app.color.hita_surface_soft'))
          .onChange((value: string) => { this.teacher = value; })
      }.width('100%')
    }
    .width('100%').padding(16).borderRadius(HitaDesign.cardRadius)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(this.courseCardColor())
  }

  @Builder
  private eventInfoCard() {
    Column({ space: HitaDesign.gap }) {
      Row({ space: HitaDesign.gap }) {
        Text('名称').fontSize(HitaDesign.body).fontColor($r('app.color.hita_text_secondary'))
          .width(56).flexShrink(0)
        TextInput({ text: this.name })
          .accessibilityText('名称')
          .fontSize(HitaDesign.body).height(HitaDesign.buttonHeight).layoutWeight(1)
          .padding({ left: 12, right: 12 }).borderRadius(HitaDesign.fieldRadius)
          .backgroundColor($r('app.color.hita_surface_soft'))
          .onChange((value: string) => { this.name = value; this.hint = ''; })
      }.width('100%')
      Row({ space: HitaDesign.gap }) {
        Text('地点').fontSize(HitaDesign.body).fontColor($r('app.color.hita_text_secondary'))
          .width(56).flexShrink(0)
        TextInput({ text: this.place })
          .accessibilityText('地点，选填')
          .fontSize(HitaDesign.body).height(HitaDesign.buttonHeight).layoutWeight(1)
          .padding({ left: 12, right: 12 }).borderRadius(HitaDesign.fieldRadius)
          .backgroundColor($r('app.color.hita_surface_soft'))
          .onChange((value: string) => { this.place = value; })
      }.width('100%')
      Row({ space: HitaDesign.gap }) {
        Text(this.typeIdx === 2 ? '教师' : '联系人')
          .fontSize(HitaDesign.body).fontColor($r('app.color.hita_text_secondary'))
          .width(56).flexShrink(0)
        TextInput({ text: this.teacher })
          .accessibilityText(this.typeIdx === 2 ? '教师，选填' : '联系人，选填')
          .fontSize(HitaDesign.body).height(HitaDesign.buttonHeight).layoutWeight(1)
          .padding({ left: 12, right: 12 }).borderRadius(HitaDesign.fieldRadius)
          .backgroundColor($r('app.color.hita_surface_soft'))
          .onChange((value: string) => { this.teacher = value; })
      }.width('100%')
    }
    .width('100%').padding(HitaDesign.inset).borderRadius(HitaDesign.cardRadius)
    .backgroundColor($r('app.color.hita_surface'))
  }

  @Builder
  typeRow() {
    Row() {
      ForEach(TYPE_ITEMS, (item: string, index: number) => {
        Button(item)
          .fontSize(HitaDesign.caption)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
          .height(38)
          .margin({ left: index === 0 ? 0 : 3, right: index === TYPE_ITEMS.length - 1 ? 0 : 3 })
          .backgroundColor(this.typeIdx === index ? $r('app.color.hita_primary_fill') : $r('app.color.hita_surface'))
          .fontColor(this.typeIdx === index ? '#FFFFFF' : $r('app.color.hita_text_333333'))
          .borderRadius(10)
          .onClick(() => {
            this.typeIdx = index;
            if (index === 1 && this.editId.length === 0) {
              this.loadCourseTimetable().catch(() => { this.hint = '读取课表失败，请重试'; });
            }
          })
      }, (item: string) => item)
    }
    .width('100%')
    .height(48)
    .padding(5)
    .backgroundColor($r('app.color.hita_control_e8edf4'))
    .borderRadius(HitaDesign.cardRadius)
  }

  @Builder
  courseDateRow() {
    Column({ space: 12 }) {
      Text('上课日期').fontSize(HitaDesign.body).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.hita_text_202b45'))
      CourseModeSegment({
        labels: ['单日', '每周'], selectedIndex: this.dateMode,
        onSelect: (index: number) => { this.dateMode = index; this.hint = ''; },
        onControlPressingChanged: (pressing: boolean) => { this.activeCourseControl = pressing; }
      })
      if (this.dateMode === 0) {
        this.dateRow()
      } else if (this.weekChoices.length === 0) {
        Text('请先设置课表的起止日期')
          .fontColor($r('app.color.hita_text_secondary_72809a'))
      } else {
        Text('星期').fontSize(HitaDesign.caption).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.hita_text_202b45'))
        CourseWeekPicker({ weeks: [1, 2, 3, 4, 5, 6, 7], chosen: $selectedWeekdays, weekdayMode: true,
          onChoosingChanged: (choosing: boolean) => { this.choosingWeeks = choosing; } })
        Text('教学周').fontSize(HitaDesign.caption).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.hita_text_202b45'))
        Row({ space: 6 }) {
          ForEach(['全部', '单周', '双周', '清空'], (label: string, index: number) => {
            CourseControlHost({
              barHeight: 32, materialEnabled: this.courseMaterialsEnabled(), itemWeight: 1,
              onPressingChanged: (pressing: boolean) => { this.activeCourseControl = pressing; }
            }) {
              this.weekPresetButton(label, index);
            }
          }, (label: string) => label)
        }.width('100%').clip(false)
        CourseWeekPicker({ weeks: this.weekChoices, chosen: $selectedWeeks,
          onChoosingChanged: (choosing: boolean) => { this.choosingWeeks = choosing; },
          onAddWeeks: () => {
            this.weekChoices = CourseDateSelection.numbers(this.weekChoices.length + 5);
            this.hint = '';
          } })
        Text('已选 ' + this.selectedWeeks.length.toString() + ' 周 · ' +
          this.selectedWeekdays.length.toString() + ' 天/周，共 ' +
          (this.selectedWeeks.length * this.selectedWeekdays.length).toString() + ' 个课次')
          .fontSize(HitaDesign.label)
          .fontColor($r('app.color.hita_text_secondary_72809a'))
      }
      if (this.extensionHint().length > 0) {
        Text(this.extensionHint()).fontSize(HitaDesign.label)
          .fontColor($r('app.color.hita_primary_3390ec'))
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(HitaDesign.inset)
    .backgroundColor(this.courseCardColor())
    .borderRadius(16)
    .clip(false)
  }

  @Builder
  weekPresetButton(label: string, index: number) {
    Button(label)
      .width('100%')
      .height(32)
      .fontSize(HitaDesign.caption)
      .padding({ left: 4, right: 4 })
      .backgroundColor($r('app.color.hita_surface_soft'))
      .fontColor($r('app.color.hita_primary_3390ec'))
      .attributeModifier(new CompatibleMaterialModifier($r('app.color.hita_surface_soft'), false,
        this.courseMaterialsEnabled()))
      .onClick(() => this.selectWeekPreset(index))
  }

  @Builder
  dateRow() {
    Row() {
      Column() {
        Text('日期')
          .fontSize(HitaDesign.caption)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.hita_text_202b45'))
        Text(this.dateText())
          .fontSize(HitaDesign.section)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.hita_text_1d2b45'))
          .margin({ top: 8 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      SymbolGlyph($r('sys.symbol.calendar'))
        .fontSize(24)
        .fontColor([$r('app.color.hita_primary_3390ec')])
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding(HitaDesign.inset)
    .backgroundColor(this.courseCardColor())
    .borderRadius(16)
    .onClick(() => {
      this.chooseDate();
    })
  }

  @Builder
  timeRow() {
    Column() {
      Text(this.typeIdx === 1 ? '上课时间' : '时间')
        .fontSize(HitaDesign.caption)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.hita_text_202b45'))
      if (this.typeIdx === 1 && this.editId.length === 0) {
        CourseModeSegment({
          labels: ['具体时间', '按节次'], selectedIndex: this.timeMode,
          onSelect: (index: number) => { this.timeMode = index; this.hint = ''; }
        })
          .width('100%').margin({ top: 10 })
      }
      Row({ space: HitaDesign.gap }) {
        Row() {
          Column() {
            Text(this.usesPeriods() ? '开始节次' : '开始时间')
              .fontSize(HitaDesign.label)
              .fontColor($r('app.color.hita_text_secondary_72809a'))
            Text(this.usesPeriods() ? (this.fromPeriod > 0 ? '第 ' + this.fromPeriod.toString() + ' 节' : '请选择') : this.startLabel())
              .fontSize(HitaDesign.section)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.hita_text_1d2b45'))
              .margin({ top: 8 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          SymbolGlyph($r('sys.symbol.clock'))
            .fontSize(HitaDesign.title)
            .fontColor([$r('app.color.hita_primary_3390ec')])
        }
        .layoutWeight(1)
        .alignItems(VerticalAlign.Center)
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .backgroundColor($r('app.color.hita_surface_soft'))
        .borderRadius(12)
        .onClick(() => {
          if (this.usesPeriods()) this.choosePeriod(true); else this.pickStartTime();
        })
        Row() {
          Column() {
            Text(this.usesPeriods() ? '结束节次' : '结束时间')
              .fontSize(HitaDesign.label)
              .fontColor($r('app.color.hita_text_secondary_72809a'))
            Text(this.usesPeriods() ? (this.toPeriod > 0 ? '第 ' + this.toPeriod.toString() + ' 节' : '请选择') : this.endLabel())
              .fontSize(HitaDesign.section)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.hita_text_1d2b45'))
              .margin({ top: 8 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          SymbolGlyph($r('sys.symbol.clock'))
            .fontSize(HitaDesign.title)
            .fontColor([$r('app.color.hita_primary_3390ec')])
        }
        .layoutWeight(1)
        .alignItems(VerticalAlign.Center)
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .backgroundColor($r('app.color.hita_surface_soft'))
        .borderRadius(12)
        .onClick(() => {
          if (this.usesPeriods()) this.choosePeriod(false); else this.pickEndTime();
        })
      }
      .width('100%')
      .margin({ top: 8 })
      if (this.usesPeriods() && this.selectedTime()[0] >= 0) {
        Text(this.startLabel() + '–' + this.endLabel())
          .fontSize(HitaDesign.label).fontColor($r('app.color.hita_text_secondary_72809a')).margin({ top: 8 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(HitaDesign.inset)
    .backgroundColor(this.courseCardColor())
    .borderRadius(16)
  }

}

/** Route wrapper kept for the standalone timeline editor. */
@Entry
@Component
struct AddEventPage {
  @StorageProp('hita_status_bar_vp') statusBarInset: number = STATUS_BAR_INSET_FALLBACK;
  build() {
    Column() {
      EventEditorForm()
        .width('100%')
        .height('100%');
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.statusBarInset })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM]);
  }
}
