import { HitaDesign } from '../common/theme/HitaDesign';
import { CourseDetailContent } from '../feature/timetable/views/CourseDetailContent';
import { SheetContent } from '../common/components/SheetContent';
/** Android HITA-style timetable detail and course management. */
import { common } from '@kit.AbilityKit';
import { HeaderBackButton } from '../common/components/HeaderBackButton';
import { ImmersiveHeader } from '../common/components/ImmersiveHeader';
import { CompatibleMaterialModifier } from '../common/theme/CompatibleMaterialModifier';
import { CompatibleSheetMaterial } from '../common/theme/CompatibleSheetMaterial';
import { DeleteParticleCard } from '../common/components/DeleteParticleCard';
import { DeleteEffectController } from '../common/util/DeleteEffectController';
import { HeaderFadeMask } from '../common/components/HeaderFadeMask';
import { HeaderFade } from '../common/theme/HeaderFade';
import { STATUS_BAR_INSET_FALLBACK } from '../common/theme/StatusBarInset';
import { promptAction } from '@kit.ArkUI';
import { CourseDateSelection } from '../feature/timetable/CourseDateSelection';
import { RdbHelper } from '../common/db/RdbHelper';
import {
  EasEventItem,
  EasEventType,
  EasSubjectType,
  EasTermSubject,
  EasTimePeriodInDay,
  EasTimetable
} from '../common/model/timetable/TimetableModels';
import { HitaColors } from '../common/theme/HitaColors';
import { DOW_FULL, EasTimeTools } from '../common/util/EasTimeTools';
import { EventEditorForm } from './AddEventPage';
import { ClassReminderStore } from '../feature/timetable/data/ClassReminderStore';
import { ClassReminderScheduler } from '../feature/timetable/data/ClassReminderScheduler';

const HEADER_HEIGHT: number = 64;
const PAGE_BG: ResourceColor = $r('app.color.hita_page_f6f7fa');
const PAGE_BG_RGB: string = '245,246,248';
const DAY_MS: number = 24 * 60 * 60 * 1000;

class TimetableSubjectRow {
  subject: EasTermSubject = new EasTermSubject();
  classCount: number = 0;
  /** 该科目的全部上课记录（按开始时间升序）。 */
  sessions: EasEventItem[] = [];
}

@Entry
@Component
struct TimetableDetailPage {
  @StorageProp('hita_status_bar_vp') statusBarInset: number = STATUS_BAR_INSET_FALLBACK;
  @State timetable: EasTimetable | undefined = undefined;
  @State subjectRows: TimetableSubjectRow[] = [];
  @State eventRows: EasEventItem[] = [];
  @State loading: boolean = true;
  /** 0=closed, 1=course detail, 2=course editor. */
  @State eventSheetMode: number = 0;
  /** bindSheet 只看这一个开关；内容状态在收起动画结束前保持不变。 */
  @State sheetVisible: boolean = false;
  @State selectedEvent: EasEventItem | undefined = undefined;
  @State courseColorEditing: boolean = false;
  @State courseColorPreview: number = 0;
  @State deletingEvent: boolean = false;
  @State sheetEventId: string = '';
  /** 当前展开课时列表的科目 id（空串 = 全部收起）。 */
  @State expandedSubjectId: string = '';
  /** 展开科目里“学分”输入框的草稿值。 */
  @State creditDraft: string = '';
  @State fadeOpacity: number = 0;
  @State pendingDeleteCourseId: string = '';
  @State changingStartDate: boolean = false;
  private deleteEffects: DeleteEffectController = new DeleteEffectController();
  private detailScroller: ListScroller = new ListScroller();
  private timetableId: string = '';
  private subjectTypeMenuOpen: boolean = false;

  async aboutToAppear(): Promise<void> {
    const params: Object | undefined = this.getUIContext().getRouter().getParams();
    if (params !== undefined && params !== null) {
      const record: Record<string, string> = params as Record<string, string>;
      const timetableParam: string = record['timetableId'] === undefined ? '' : record['timetableId'];
      const legacyParam: string = record['id'] === undefined ? '' : record['id'];
      this.timetableId = timetableParam.length > 0 ? timetableParam : legacyParam;
    }
    await this.load();
  }

  async onPageShow(): Promise<void> {
    this.deleteEffects.resume();
    if (!this.loading) {
      await this.load();
    }
  }

  onPageHide(): void {
    this.deleteEffects.pause();
  }

  aboutToDisappear(): void {
    this.deleteEffects.pause();
  }

  private async load(): Promise<void> {
    const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
    const rdb: RdbHelper = RdbHelper.getInstance();
    await rdb.init(ctx);
    this.timetable = await rdb.getTimetableById(this.timetableId);
    const rows: TimetableSubjectRow[] = [];
    const events: EasEventItem[] = [];
    if (this.timetable !== undefined) {
      const subjects: EasTermSubject[] = await rdb.getSubjectsOfTimetable(this.timetable.id);
      const colorById: Map<string, number> = new Map<string, number>();
      for (let i: number = 0; i < subjects.length; i++) {
        colorById.set(subjects[i].id, subjects[i].color);
        const subjectEvents: EasEventItem[] = await rdb.getClassesOfSubject(subjects[i].id);
        const sessions: EasEventItem[] = [];
        for (let j: number = 0; j < subjectEvents.length; j++) {
          if (subjectEvents[j].type !== EasEventType.CLASS) {
            continue;
          }
          subjectEvents[j].color = subjects[i].color;
          sessions.push(subjectEvents[j]);
        }
        const row: TimetableSubjectRow = new TimetableSubjectRow();
        row.subject = subjects[i];
        row.classCount = sessions.length;
        row.sessions = sessions;
        rows.push(row);
      }
      const timetableEvents: EasEventItem[] = await rdb.getEventsOfTimetable(this.timetable.id);
      for (let i: number = 0; i < timetableEvents.length; i++) {
        const event: EasEventItem = timetableEvents[i];
        const subjectColor: number | undefined = colorById.get(event.subjectId);
        if (event.type === EasEventType.EXAM) {
          event.color = event.color === 0 ? TimetableDetailPage.eventColor(event.type) : event.color;
        } else {
          event.color = subjectColor === undefined ? TimetableDetailPage.eventColor(event.type) : subjectColor;
        }
        events.push(event);
      }
    }
    this.subjectRows = rows;
    this.eventRows = events;
    this.loading = false;
  }

  private openAddEvent(): void {
    this.sheetEventId = '';
    this.selectedEvent = undefined;
    this.eventSheetMode = 2;
    this.sheetVisible = true;
  }

  private chooseStartDate(): void {
    if (this.timetable === undefined || this.changingStartDate) {
      return;
    }
    this.getUIContext().showDatePickerDialog({
      selected: new Date(this.timetable.startTime),
      onDateAccept: (date: Date) => {
        void this.applyStartDate(date);
      }
    });
  }

  private async applyStartDate(date: Date): Promise<void> {
    const timetable: EasTimetable | undefined = this.timetable;
    if (timetable === undefined || this.changingStartDate) {
      return;
    }
    const picked: number = new Date(date.getFullYear(), date.getMonth(), date.getDate(), 0, 0, 0, 0).getTime();
    const nextStart: number = EasTimetable.mondayMsOf(picked);
    const delta: number = nextStart - EasTimetable.mondayMsOf(timetable.startTime);
    if (!Number.isFinite(nextStart) || nextStart <= 0 || delta === 0) {
      return;
    }
    this.changingStartDate = true;
    try {
      const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
      const rdb: RdbHelper = RdbHelper.getInstance();
      await rdb.init(ctx);
      await rdb.shiftTimetableStart(timetable.id, timetable.startTime, timetable.endTime, nextStart);
      await this.load();
      void this.resyncReminders().catch(() => {});
      this.getUIContext().getPromptAction().showToast({ message: '开学日期已更新，课程已同步平移' });
    } catch (_) {
      this.getUIContext().getPromptAction().showToast({ message: '修改开学日期失败，请刷新后重试' });
    } finally {
      this.changingStartDate = false;
    }
  }

  private openEditEvent(event: EasEventItem): void {
    this.sheetEventId = event.id;
    this.selectedEvent = event;
    this.eventSheetMode = 2;
    this.sheetVisible = true;
  }

  /** 保存后只改对应课程/课时，不重新 load 整页，避免滚动和展开状态被清掉。 */
  private applySavedEvent(event: EasEventItem, syncReminders: boolean = true): void {
    const nextEvents: EasEventItem[] = [];
    let foundEvent: boolean = false;
    for (let i: number = 0; i < this.eventRows.length; i++) {
      if (this.eventRows[i].id === event.id) {
        nextEvents.push(event);
        foundEvent = true;
      } else {
        nextEvents.push(this.eventRows[i]);
      }
    }
    if (!foundEvent) {
      nextEvents.push(event);
    }
    this.eventRows = nextEvents;

    const nextRows: TimetableSubjectRow[] = [];
    let foundSubject: boolean = false;
    for (let i: number = 0; i < this.subjectRows.length; i++) {
      const prev: TimetableSubjectRow = this.subjectRows[i];
      if (prev.subject.id !== event.subjectId) {
        nextRows.push(prev);
        continue;
      }
      foundSubject = true;
      const next: TimetableSubjectRow = new TimetableSubjectRow();
      next.subject = prev.subject;
      const sessions: EasEventItem[] = [];
      let foundSession: boolean = false;
      for (let j: number = 0; j < prev.sessions.length; j++) {
        if (prev.sessions[j].id === event.id) {
          sessions.push(event);
          foundSession = true;
        } else {
          sessions.push(prev.sessions[j]);
        }
      }
      if (!foundSession && event.type === EasEventType.CLASS) {
        sessions.push(event);
      }
      sessions.sort((a: EasEventItem, b: EasEventItem): number => a.from - b.from);
      next.sessions = sessions;
      next.classCount = sessions.length;
      nextRows.push(next);
    }
    if (!foundSubject && event.subjectId.length > 0) {
      const row: TimetableSubjectRow = new TimetableSubjectRow();
      const subject: EasTermSubject = new EasTermSubject();
      subject.id = event.subjectId;
      subject.timetableId = event.timetableId;
      subject.name = event.name;
      subject.color = event.color;
      row.subject = subject;
      row.sessions = event.type === EasEventType.CLASS ? [event] : [];
      row.classCount = row.sessions.length;
      nextRows.push(row);
    }
    this.subjectRows = nextRows;
    if (this.selectedEvent !== undefined && this.selectedEvent.id === event.id) {
      this.selectedEvent = event;
    }
    if (syncReminders) void this.resyncReminders();
  }

  private async resyncReminders(): Promise<void> {
    const enabled: boolean = await ClassReminderStore.getInstance().loadEnabled();
    if (!enabled) {
      return;
    }
    const host: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    await ClassReminderScheduler.sync(host, this.eventRows, true);
  }

  private openEventDetail(event: EasEventItem): void {
    this.courseColorEditing = false;
    this.sheetEventId = event.id;
    this.selectedEvent = event;
    this.eventSheetMode = 1;
    this.sheetVisible = true;
  }

  /**
   * 关闭弹层只翻可见性。若在同一帧里清空内容/模式，bindSheet 的显示条件、
   * builder 内容和高度会同时变化，退场动画被打断（真机上残留空白半屏弹层）。
   * 内容状态统一在 onDisappear 里清空。
   */
  private closeSheet(): void {
    this.sheetVisible = false;
  }

  private resetSheetState(): void {
    this.eventSheetMode = 0;
    this.selectedEvent = undefined;
    this.sheetEventId = '';
  }

  private toggleSubject(row: TimetableSubjectRow): void {
    this.detailScroller.closeAllSwipeActions();
    this.getUIContext().animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
      if (this.expandedSubjectId === row.subject.id) {
        this.expandedSubjectId = '';
      } else {
        this.expandedSubjectId = row.subject.id;
        this.creditDraft = row.subject.credit > 0 ? TimetableDetailPage.numberText(row.subject.credit) : '';
      }
    });
  }

  /** 手动修正学分（教务属性表缺失或同名多Variant时自动读取会失败）。 */
  private async saveSubjectCredit(row: TimetableSubjectRow): Promise<void> {
    const text: string = this.creditDraft.trim();
    if (text.length === 0) {
      return;
    }
    const value: number = Number(text);
    if (Number.isNaN(value) || value < 0 || value > 100) {
      this.getUIContext().getPromptAction().showToast({ message: '学分应为 0-100 的数字' });
      return;
    }
    if (value === row.subject.credit) {
      return;
    }
    row.subject.credit = value;
    await RdbHelper.getInstance().saveSubject(row.subject);
    await this.load();
    this.creditDraft = value > 0 ? TimetableDetailPage.numberText(value) : '';
    this.getUIContext().getPromptAction().showToast({ message: '学分已更新' });
  }

  private currentSubjectRow(row: TimetableSubjectRow): TimetableSubjectRow {
    // 稳定 key 的卡片会保留 builder；删除或重排后不能再使用创建时的数组下标。
    const current: TimetableSubjectRow | undefined = this.subjectRows.find((item: TimetableSubjectRow): boolean =>
      item.subject.id === row.subject.id && item.subject.timetableId === row.subject.timetableId);
    // 离场动画结束前，已删除的节点仍可能读取 builder 参数。
    return current === undefined ? row : current;
  }

  private confirmDeleteCourse(row: TimetableSubjectRow): void {
    if (this.pendingDeleteCourseId.length > 0) {
      return;
    }
    const subjectId: string = row.subject.id;
    const timetableId: string = row.subject.timetableId;
    this.pendingDeleteCourseId = subjectId;
    this.detailScroller.closeAllSwipeActions();
    this.getUIContext().getPromptAction().showDialog({
      title: '删除整门课程',
      message: '确定删除「' + row.subject.name + '」及其全部 ' + row.classCount.toString() + ' 次课吗？此操作无法撤销。',
      buttons: [
        { text: '取消', color: $r('app.color.hita_text_secondary_7b8190') },
        { text: '删除', color: HitaColors.error }
      ]
    }).then(async (ret) => {
      if (ret.index !== 1) {
        return;
      }
      try {
        await RdbHelper.getInstance().deleteCourseWithClasses(subjectId, timetableId);
        await this.deleteEffects.play([subjectId]);
        this.getUIContext().animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
          this.subjectRows = this.subjectRows.filter((item: TimetableSubjectRow): boolean =>
            item.subject.id !== subjectId || item.subject.timetableId !== timetableId);
          this.eventRows = this.eventRows.filter((event: EasEventItem): boolean =>
            event.subjectId !== subjectId || event.timetableId !== timetableId || event.type !== EasEventType.CLASS);
          if (this.expandedSubjectId === subjectId) {
            this.expandedSubjectId = '';
          }
        });
        let message: string = '课程及全部课时已删除';
        try {
          await this.resyncReminders();
        } catch (reminderError) {
          message = '课程已删除，但提醒同步失败';
        }
        this.getUIContext().getPromptAction().showToast({ message: message });
      } catch (e) {
        this.getUIContext().getPromptAction().showToast({ message: '删除失败，请重试' });
      }
    }).catch(() => {
    }).finally(() => {
      this.pendingDeleteCourseId = '';
    });
  }

  /** 教务数据未提供考核方式时，允许手动纠正课程类型。 */
  private async chooseSubjectType(row: TimetableSubjectRow): Promise<void> {
    if (this.subjectTypeMenuOpen) {
      return;
    }
    this.subjectTypeMenuOpen = true;
    const types: EasSubjectType[] = [EasSubjectType.COM_A, EasSubjectType.COM_B, EasSubjectType.OPT_A,
      EasSubjectType.OPT_B, EasSubjectType.MOOC, EasSubjectType.TAG];
    const button = (type: EasSubjectType): promptAction.Button => {
      const item: promptAction.Button = {
        text: TimetableDetailPage.typeName(type),
        color: type === row.subject.type ? HitaColors.primary : $r('app.color.hita_text_303746')
      };
      return item;
    };
    try {
      const ret = await this.getUIContext().getPromptAction().showActionMenu({
        title: '课程类型',
        buttons: [button(types[0]), button(types[1]), button(types[2]), button(types[3]), button(types[4]),
          button(types[5])]
      });
      const next: EasSubjectType | undefined = types[ret.index];
      if (next === undefined) {
        return;
      }
      await this.applySubjectType(row.subject.id, row.subject.timetableId, next);
    } catch (e) {
      // Cancelling the system action menu leaves the course unchanged.
    } finally {
      this.subjectTypeMenuOpen = false;
    }
  }

  private async applySubjectType(subjectId: string, timetableId: string, type: EasSubjectType): Promise<void> {
    let index: number = this.subjectRows.findIndex((item: TimetableSubjectRow): boolean =>
      item.subject.id === subjectId && item.subject.timetableId === timetableId);
    if (index < 0) {
      return;
    }
    if (this.subjectRows[index].subject.type !== type) {
      try {
        await RdbHelper.getInstance().saveSubjectType(subjectId, timetableId, type);
      } catch (e) {
        this.getUIContext().getPromptAction().showToast({ message: '课程类型保存失败，请重试' });
        return;
      }
      index = this.subjectRows.findIndex((item: TimetableSubjectRow): boolean =>
        item.subject.id === subjectId && item.subject.timetableId === timetableId);
      if (index < 0) {
        return;
      }
      const current: TimetableSubjectRow = this.subjectRows[index];
      const previous: EasTermSubject = current.subject;
      const updated: TimetableSubjectRow = new TimetableSubjectRow();
      updated.subject = {
        id: previous.id, timetableId: previous.timetableId, name: previous.name, type: type,
        field: previous.field, credit: previous.credit, school: previous.school,
        countInSPA: previous.countInSPA, code: previous.code, key: previous.key,
        createdAt: previous.createdAt, color: previous.color
      };
      updated.classCount = current.classCount;
      updated.sessions = current.sessions;
      this.subjectRows = this.subjectRows.map((item: TimetableSubjectRow, rowIndex: number): TimetableSubjectRow =>
        rowIndex === index ? updated : item);
    }
  }

  @Builder
  private infoCard(timetable: EasTimetable) {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Text(timetable.name.length > 0 ? timetable.name : '未命名课表')
          .fontSize(HitaDesign.title).fontWeight(FontWeight.Medium)
          .fontColor(HitaColors.onSurface).layoutWeight(1).maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(TimetableDetailPage.weekCount(timetable).toString() + ' 周')
          .fontSize(HitaDesign.label).fontColor(HitaColors.primary)
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor($r('app.color.hita_selected')).borderRadius(8).flexShrink(0)
      }.width('100%')
      Row() {
        Text('开学日期').fontSize(HitaDesign.body).fontColor(HitaColors.onSurfaceVariant)
        Blank()
        Text(TimetableDetailPage.dateText(timetable.startTime))
          .fontSize(HitaDesign.body).fontColor(HitaColors.onSurface)
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(12)
          .fontColor([HitaColors.onSurfaceVariant]).width(16).margin({ left: 8 }).accessibilityLevel('no')
      }.width('100%').constraintSize({ minHeight: 48 })
        .accessibilityText('开学日期，' + TimetableDetailPage.dateText(timetable.startTime) + '，点击修改')
        .onClick(() => { this.chooseStartDate(); })
      ImmersiveHeader({ barHeight: 56, materialEnabled: CompatibleSheetMaterial.isEnabled() }) {
        Button('添加课程', { type: ButtonType.Capsule })
          .width('100%').height(HitaDesign.buttonHeight).fontSize(HitaDesign.body)
          .fontColor(HitaColors.primary).backgroundColor($r('app.color.hita_selected'))
          .attributeModifier(new CompatibleMaterialModifier($r('app.color.hita_selected'), false,
            CompatibleSheetMaterial.isEnabled(), undefined, false))
          .onClick(() => { this.openAddEvent(); })
      }
    }.width('100%').padding(HitaDesign.inset)
      .alignItems(HorizontalAlign.Start)
      .backgroundColor($r('app.color.hita_surface')).borderRadius(HitaDesign.cardRadius)
  }

  @Builder
  private subjectCard(row: TimetableSubjectRow) {
    Row() {
      Row()
        .width(4)
        .height(44)
        .borderRadius(2)
        .backgroundColor(TimetableDetailPage.css(row.subject.color))
      Column() {
        Text(row.subject.name)
          .fontSize(HitaDesign.body)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.hita_text_242a36'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(TimetableDetailPage.typeName(row.subject.type) + ' · ' +
          TimetableDetailPage.numberText(row.subject.credit) + ' 学分 · ' +
          row.classCount.toString() + ' 次课')
          .fontSize(HitaDesign.label)
          .fontColor($r('app.color.hita_text_secondary_7b8498'))
          .margin({ top: 8 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(12)
        .fontColor([$r('app.color.hita_text_hint_b2b8c4')])
        .width(16).height(24).flexShrink(0)
        .accessibilityLevel('no')
        .rotate({ angle: this.expandedSubjectId === row.subject.id ? 90 : 0 })
    }
    .width('100%')
    .constraintSize({ minHeight: 88 })
    .padding({ left: 14, right: 14 })
    .onClick(() => {
      this.toggleSubject(row);
    })
  }

  /** 一门课程一栏：科目行 + 点击展开后的课时列表。 */
  @Builder
  private courseGroupCard(row: TimetableSubjectRow) {
    Column() {
      this.subjectCard({ subject: row.subject, classCount: row.classCount, sessions: row.sessions })
      if (this.expandedSubjectId === row.subject.id) {
        Column() {
          Divider()
            .color($r('app.color.hita_divider_eef1f6'))
            .margin({ left: 14, right: 14 })
          Row() {
            Text('课程类型')
              .fontSize(HitaDesign.caption)
              .fontColor($r('app.color.hita_text_secondary_7b8498'))
            Blank()
            Text(TimetableDetailPage.typeName(row.subject.type))
              .fontSize(HitaDesign.caption)
              .fontWeight(FontWeight.Medium)
              .fontColor(HitaColors.primary)
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(12)
              .fontColor([$r('app.color.hita_text_hint_b2b8c4')])
              .width(16).height(24).flexShrink(0)
              .accessibilityLevel('no')
              .margin({ left: 6 })
          }
          .width('100%')
          .height(44)
          .padding({ left: 14, right: 14 })
          .onClick(() => {
            this.chooseSubjectType(row);
          })
          Row() {
            Text('学分')
              .fontSize(HitaDesign.caption)
              .fontColor($r('app.color.hita_text_secondary_7b8498'))
            Blank()
            TextInput({ text: this.creditDraft, placeholder: '未设置' })
              .fontSize(HitaDesign.caption)
              .fontWeight(FontWeight.Medium)
              .fontColor(HitaColors.primary)
              .textAlign(TextAlign.End)
              .width(84)
              .height(32)
              .padding({ left: 8, right: 8 })
              .backgroundColor($r('app.color.hita_surface_soft_f4f7fb'))
              .borderRadius(8)
              .enterKeyType(EnterKeyType.Done)
              .onChange((value: string) => {
                this.creditDraft = value;
              })
              .onSubmit(() => {
                this.saveSubjectCredit(row);
              })
          }
          .width('100%')
          .height(44)
          .padding({ left: 14, right: 14 })
          if (row.sessions.length === 0) {
            Text('暂无课时记录')
              .fontSize(HitaDesign.label)
              .fontColor($r('app.color.hita_text_hint_9aa2b1'))
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: 12, bottom: 14 })
          } else {
            Column({ space: 6 }) {
              ForEach(row.sessions, (session: EasEventItem) => {
                this.sessionRow(session)
              }, (session: EasEventItem) => session.id)
            }
            .width('100%')
            .padding({ left: 10, right: 10, top: 10, bottom: 10 })
          }
        }
        .width('100%')
        .transition(TransitionEffect.OPACITY)
      }
    }
    .width('100%')
    .backgroundColor($r('app.color.hita_surface'))
    .borderRadius(16)
    .clip(true)
  }

  @Builder
  private courseDeleteAction(row: TimetableSubjectRow) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 4 }) {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(HitaDesign.title)
          .fontColor([Color.White])
        Text('删除')
          .fontSize(HitaDesign.label)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
      }
    }
    .width(76)
    .height('100%')
    .margin({ left: 8 })
    .borderRadius(HitaDesign.cardRadius)
    .backgroundColor(HitaColors.error)
    .accessibilityText('删除' + row.subject.name + '及全部课时')
    .onClick(() => {
      this.confirmDeleteCourse(row);
    })
  }

  @Builder
  private sessionRow(session: EasEventItem) {
    Row() {
      Text(TimetableDetailPage.sessionDateText(session.from))
        .fontSize(HitaDesign.caption)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.hita_text_303746'))
      Text(TimetableDetailPage.timeRange(session))
        .fontSize(HitaDesign.label)
        .fontColor($r('app.color.hita_text_secondary_7b8498'))
        .margin({ left: 10 })
      Blank()
      Text(TimetableDetailPage.sessionPlaceText(session))
        .fontSize(HitaDesign.label)
        .fontColor($r('app.color.hita_text_hint'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: '38%' })
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(12)
        .fontColor([$r('app.color.hita_text_hint_b2b8c4')])
        .width(16).height(24).flexShrink(0)
        .accessibilityLevel('no')
        .margin({ left: 6 })
    }
    .width('100%')
    .height(44)
    .padding({ left: 12, right: 12 })
    .backgroundColor($r('app.color.hita_surface_soft'))
    .borderRadius(10)
    .onClick(() => {
      this.openEventDetail(session);
    })
  }

  @Builder
  private scheduleRow(period: EasTimePeriodInDay, index: number) {
    Row() {
      Row() {
        Text((index + 1).toString())
          .fontSize(HitaDesign.caption)
          .fontWeight(FontWeight.Medium)
          .fontColor(HitaColors.primary)
      }
      .width(32)
      .height(32)
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('app.color.hita_selected_e8f3fd'))
      .borderRadius(16)
      Text(period.from.toString())
        .fontSize(HitaDesign.caption)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.hita_text_303746'))
        .margin({ left: 12 })
      Text('-')
        .fontSize(HitaDesign.label)
        .fontColor($r('app.color.hita_text_hint_a0a7b5'))
        .margin({ left: 7, right: 7 })
      Text(period.to.toString())
        .fontSize(HitaDesign.caption)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.hita_text_303746'))
      Blank()
      Text(period.getLengthInMinutes().toString() + ' 分钟')
        .fontSize(HitaDesign.label)
        .fontColor($r('app.color.hita_text_hint'))
    }
    .width('100%')
    .height(52)
    .padding({ left: 12, right: 12 })
    .backgroundColor($r('app.color.hita_surface'))
  }

  @Builder
  private eventSheetContent() {
    SheetContent({ fillHeight: this.eventSheetMode === 2 }) {
      if (this.eventSheetMode === 2) {
        EventEditorForm({
          eventId: this.sheetEventId,
          targetTimetableId: this.timetableId,
          initialType: 'CLASS',
          sheetMode: true,
          onCancel: () => {
            this.closeSheet();
          },
          onChanged: async () => {
            await this.load();
            await this.resyncReminders();
          },
          onSaved: (_event: EasEventItem, _occurrences: EasEventItem[]) => {
            void this.load().then(() => this.resyncReminders()).catch(() => {});
            this.closeSheet();
          }
        })
          .width('100%')
          .height('100%');
      } else if (this.selectedEvent !== undefined) {
        this.courseDetailSheet(this.selectedEvent as EasEventItem);
      }
    }
  }

  @Builder
  private courseDetailSheet(event: EasEventItem) {
    CourseDetailContent({
      event: event, endTime: event.to, periodText: TimetableDetailPage.coursePeriodText(event),
      dateText: TimetableDetailPage.courseDateText(event.from), progressText: this.courseProgressText(event),
      deleteLabel: '删除', busy: this.deletingEvent,
      courseColorEditing: $courseColorEditing, courseColorPreview: $courseColorPreview,
      onSaveColor: async (color: number) => {
        await RdbHelper.getInstance().saveCourseColor(event.subjectId, event.timetableId, color);
        await this.load();
        this.selectedEvent = this.eventRows.find((item: EasEventItem): boolean => item.id === event.id);
        this.courseColorEditing = false;
      },
      onEdit: () => { this.openEditEvent(event); },
      onDelete: () => { void this.deleteOccurrence(event); }
    })
  }

  private async deleteOccurrence(event: EasEventItem): Promise<void> {
    if (this.deletingEvent) return;
    this.deletingEvent = true;
    let confirmed: boolean = false;
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: '删除这次课程？', message: '仅删除当前课次。',
        buttons: [{ text: '取消', color: $r('app.color.hita_text_secondary_72809a') }, { text: '删除', color: HitaColors.error }]
      });
      if (result.index !== 1 || !this.sheetVisible || this.selectedEvent?.id !== event.id) return;
      confirmed = true;
      await RdbHelper.getInstance().deleteClassOccurrences([event.id], event.timetableId);
      this.closeSheet();
      await this.load();
      void this.resyncReminders().catch(() => {});
    } catch (_) {
      if (confirmed) this.getUIContext().getPromptAction().showToast({ message: '未能删除，请重试' });
    } finally { this.deletingEvent = false; }
  }

  private courseProgressText(event: EasEventItem): string {
    const instances: EasEventItem[] = this.eventRows.filter((item: EasEventItem): boolean =>
      item.type === EasEventType.CLASS && item.subjectId === event.subjectId);
    instances.sort((a: EasEventItem, b: EasEventItem): number => a.from - b.from);
    let index: number = 0;
    for (let i: number = 0; i < instances.length; i++) {
      if (instances[i].id === event.id) {
        index = i + 1;
        break;
      }
    }
    return index > 0 ? '第 ' + index.toString() + ' / ' + instances.length.toString() + ' 次课' :
      '共 ' + instances.length.toString() + ' 次课';
  }

  private static courseDateText(timestamp: number): string {
    const date: Date = new Date(timestamp);
    return date.getFullYear().toString() + '年' + (date.getMonth() + 1).toString() + '月' +
      date.getDate().toString() + '日 · ' + DOW_FULL[EasTimeTools.getDow(timestamp)];
  }

  private static coursePeriodText(event: EasEventItem): string {
    if (event.fromNumber <= 0 || event.lastNumber <= 0) {
      return '未记录节次';
    }
    return event.fromNumber === event.lastNumber ? '第 ' + event.fromNumber.toString() + ' 节' :
      '第 ' + event.fromNumber.toString() + ' - ' + event.lastNumber.toString() + ' 节';
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      if (this.loading) {
        LoadingProgress()
          .width(32)
          .height(32)
          .color(HitaColors.primary)
          .margin({ top: HEADER_HEIGHT + 80 })
      } else if (this.timetable === undefined) {
        Text('课表不存在或已删除')
          .fontSize(HitaDesign.body)
          .fontColor($r('app.color.hita_text_secondary_7b8498'))
          .margin({ top: HEADER_HEIGHT + 80 })
      } else {
        List({ scroller: this.detailScroller }) {
          ListItem() {
            Column() {
              Blank().height(HEADER_HEIGHT)
              this.infoCard(this.timetable as EasTimetable)
              Row() {
                Text('我的课程')
                  .fontSize(HitaDesign.section)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.hita_text_202633'))
                  .layoutWeight(1)
                Text(this.subjectRows.length.toString() + ' 门')
                  .fontSize(HitaDesign.label)
                  .fontColor($r('app.color.hita_text_hint_9aa2b1'))
              }
              .width('100%')
              .margin({ top: 24, bottom: 10 })
              if (this.subjectRows.length === 0) {
                Column() {
                  Text('暂无课程')
                    .fontSize(HitaDesign.body)
                    .fontColor($r('app.color.hita_text_secondary_7b8498'))
                  Text('从教务导入或点击上方“添加课程”后显示在这里')
                    .fontSize(HitaDesign.label)
                    .fontColor($r('app.color.hita_text_hint_a0a7b5'))
                    .margin({ top: 8 })
                }
                .width('100%')
                .padding({ top: 26, bottom: 26 })
                .backgroundColor($r('app.color.hita_surface'))
                .borderRadius(16)
              }
            }
            .width('100%')
          }
          ForEach(this.subjectRows, (row: TimetableSubjectRow) => {
            ListItem() {
              DeleteParticleCard({
                controller: this.deleteEffects,
                effectId: row.subject.id
              }) {
                this.courseGroupCard({
                  subject: this.currentSubjectRow(row).subject,
                  classCount: this.currentSubjectRow(row).classCount,
                  sessions: this.currentSubjectRow(row).sessions
                })
              }
            }
            .enabled(this.pendingDeleteCourseId.length === 0)
            .swipeAction({
              end: { builder: () => { this.courseDeleteAction(row) } },
              edgeEffect: SwipeEdgeEffect.None
            })
            .margin({ bottom: 8 })
            .transition(TransitionEffect.OPACITY)
          }, (row: TimetableSubjectRow) => row.subject.id)
          ListItem() {
            Column() {
              Text('课表结构')
                .fontSize(HitaDesign.section)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.hita_text_202633'))
                .width('100%')
                .margin({ top: 16, bottom: 10 })
              Column() {
                ForEach((this.timetable as EasTimetable).scheduleStructure,
                  (period: EasTimePeriodInDay, index: number) => {
                    this.scheduleRow(period, index)
                  }, (period: EasTimePeriodInDay, index: number) => index.toString() + period.toString())
              }
              .width('100%')
              .borderRadius(HitaDesign.cardRadius)
              .clip(true)
              Text('左滑课程可删除整门课程')
                .fontSize(HitaDesign.label)
                .fontColor($r('app.color.hita_text_hint_9aa2b1'))
                .margin({ top: 14, bottom: 36 })
              Blank().height(72)
            }
            .width('100%')
          }
        }
        .width('100%')
        .height('100%')
        .padding({ left: 16, right: 16 })
        .enableScrollInteraction(this.pendingDeleteCourseId.length === 0)
        .edgeEffect(EdgeEffect.None)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
        .scrollBar(BarState.Off)
        .onDidScroll(() => {
          this.fadeOpacity = HeaderFade.opacity(this.detailScroller.currentOffset().yOffset);
        })
      }

      HeaderFadeMask({
        maskOpacity: this.fadeOpacity,
        rgb: PAGE_BG_RGB,
        headerHeight: HEADER_HEIGHT
      })

      ImmersiveHeader({ barHeight: HEADER_HEIGHT }) {
        Row() {
          HeaderBackButton({
            onBack: () => this.getUIContext().getRouter().back()
          })
            .margin({ right: 12 })
          Text('课表详情')
            .fontSize(HitaDesign.title)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.hita_text_202633'))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .height(HEADER_HEIGHT)
        .padding({ left: 16, right: 16 })
        .alignItems(VerticalAlign.Center)
        .hitTestBehavior(HitTestMode.Transparent)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.statusBarInset })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .backgroundColor(PAGE_BG)
    .bindSheet($$this.sheetVisible, this.eventSheetContent(), CompatibleSheetMaterial.options({
      height: this.eventSheetMode === 2 ? '78%' : SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: false,
      preferType: SheetType.BOTTOM,
      backgroundColor: $r('app.color.hita_surface_soft'),
      maskColor: $r('app.color.hita_sheet_mask'),
      onWillDisappear: () => {
        this.closeSheet();
      },
      onDisappear: () => {
        this.sheetVisible = false;
        this.resetSheetState();
      }
    }, this.eventSheetMode === 2))
  }

  private static dateText(ms: number): string {
    const d: Date = new Date(ms);
    return d.getFullYear().toString() + '年' + (d.getMonth() + 1).toString() + '月' + d.getDate().toString() + '日';
  }

  private static pad2(value: number): string {
    return value < 10 ? '0' + value.toString() : value.toString();
  }

  private static weekCount(timetable: EasTimetable): number {
    return Math.max(1, Math.ceil((timetable.endTime - timetable.startTime + 1) / (7 * DAY_MS)));
  }

  private static numberText(value: number): string {
    const text: string = value.toString();
    return text.indexOf('.') >= 0 ? text : text + '.0';
  }

  private static typeName(type: EasSubjectType): string {
    if (type === EasSubjectType.COM_A) {
      return '必修·考试';
    }
    if (type === EasSubjectType.COM_B) {
      return '必修·考查';
    }
    if (type === EasSubjectType.OPT_A) {
      return '选修·专选';
    }
    if (type === EasSubjectType.OPT_B) {
      return '选修·任选';
    }
    if (type === EasSubjectType.MOOC) {
      return '慕课';
    }
    return '其他';
  }

  private static sessionDateText(ms: number): string {
    const d: Date = new Date(ms);
    return (d.getMonth() + 1).toString() + '月' + d.getDate().toString() + '日 · ' +
      DOW_FULL[EasTimeTools.getDow(ms)];
  }

  private static sessionPlaceText(session: EasEventItem): string {
    const place: string = session.place.trim();
    if (place.length > 0) {
      return place;
    }
    const teacher: string = session.teacher.trim();
    return teacher.length > 0 ? teacher : '未填写地点';
  }

  private static timeRange(event: EasEventItem): string {
    const from: Date = new Date(event.from);
    const to: Date = new Date(event.to);
    return TimetableDetailPage.pad2(from.getHours()) + ':' + TimetableDetailPage.pad2(from.getMinutes()) + ' - ' +
      TimetableDetailPage.pad2(to.getHours()) + ':' + TimetableDetailPage.pad2(to.getMinutes());
  }

  private static eventColor(type: EasEventType): number {
    if (type === EasEventType.EXAM) {
      return 0xFFD93025;
    }
    if (type === EasEventType.TAG) {
      return 0xFF26A69A;
    }
    if (type === EasEventType.OTHER) {
      return 0xFF5C6BC0;
    }
    return 0xFF3390EC;
  }

  private static css(argb: number): string {
    const r: number = (argb >> 16) & 0xFF;
    const g: number = (argb >> 8) & 0xFF;
    const b: number = argb & 0xFF;
    return 'rgb(' + r.toString() + ',' + g.toString() + ',' + b.toString() + ')';
  }
}
