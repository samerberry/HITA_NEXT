/** Android-style timetable import configuration page. */
import { common } from '@kit.AbilityKit';
import { RdbHelper } from '../common/db/RdbHelper';
import { HeaderBackButton } from '../common/components/HeaderBackButton';
import { ImmersiveHeader } from '../common/components/ImmersiveHeader';
import { CompatibleMaterialModifier } from '../common/theme/CompatibleMaterialModifier';
import { HeaderFadeMask } from '../common/components/HeaderFadeMask';
import { HeaderFade } from '../common/theme/HeaderFade';
import { NAV_BAR_INSET_FALLBACK, STATUS_BAR_INSET_FALLBACK } from '../common/theme/StatusBarInset';
import { CompatibleLightModifier } from '../common/theme/CompatibleLightModifier';
import { CompatibleSheetMaterial } from '../common/theme/CompatibleSheetMaterial';
import { EasApiClient } from '../feature/eas/EasApiClient';
import { EasCampus, EasSession } from '../feature/eas/EasSession';
import { EasSessionStore } from '../feature/eas/EasSessionStore';
import { EasDataProvider } from '../feature/eas/EasDataProvider';
import { EasUserMessages } from '../feature/eas/EasUserMessages';
import { EasImportResult, EasTermStartResult, EasTimetableImporter } from '../feature/eas/EasTimetableImporter';
import { EasTermItem } from '../feature/eas/model/EasModels';
import { EasTimeInDay, EasTimePeriodInDay, EasTimetable } from '../common/model/timetable/TimetableModels';
import { TimetableSelectionStore } from '../feature/timetable/data/TimetableSelectionStore';
import { HitaColors } from '../common/theme/HitaColors';

const HEADER_HEIGHT: number = 64;
const PAGE_BG: ResourceColor = $r('app.color.hita_page');
const PAGE_BG_RGB: string = '244,247,252';
const CARD_BG: ResourceColor = $r('app.color.hita_surface');
const TEXT_PRIMARY: ResourceColor = $r('app.color.hita_text');
const TEXT_SECONDARY: ResourceColor = $r('app.color.hita_text_secondary');

@Component
export struct ImportTimetablePanel {
  @Prop presentedAsSheet: boolean = false;
  onClose: () => void = () => {};
  onImported: () => void = () => {};
  @State terms: EasTermItem[] = [];
  @State selectedTermIndex: number = -1;
  @State startTime: number = 0;
  @State detailsLoading: boolean = false;
  @State dateNotice: string = '';
  @State schedule: EasTimePeriodInDay[] = [];
  @State loading: boolean = true;
  @State importing: boolean = false;
  @State message: string = '';
  @State error: string = '';
  @State fadeOpacity: number = 0;
  @StorageProp('hita_status_bar_vp') statusBarInset: number = STATUS_BAR_INSET_FALLBACK;
  @StorageProp('hita_nav_bar_vp') navBarInset: number = NAV_BAR_INSET_FALLBACK;
  private session: EasSession | undefined = undefined;
  private pageScroller: Scroller = new Scroller();
  private detailsGeneration: number = 0;

  async aboutToAppear(): Promise<void> {
    await this.load();
  }

  private async load(): Promise<void> {
    this.loading = true;
    this.error = '';
    const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
    await EasSessionStore.getInstance().init(ctx);
    const campus: EasCampus | undefined = await EasSessionStore.getInstance().loadLastCampus();
    if (campus === undefined) {
      this.loading = false;
      this.error = '请先登录教务系统';
      return;
    }
    this.session = await EasSessionStore.getInstance().load(campus);
    if (this.session === undefined || !this.session.isLogin()) {
      this.loading = false;
      this.error = '请先登录教务系统';
      return;
    }
    try {
      const provider: EasDataProvider = new EasDataProvider(new EasApiClient());
      this.terms = await provider.getAllTerms(this.session as EasSession);
      this.selectedTermIndex = 0;
      for (let i: number = 0; i < this.terms.length; i++) {
        if (this.terms[i].isCurrent) {
          this.selectedTermIndex = i;
          break;
        }
      }
      await this.loadTermDetails();
    } catch (e) {
      this.error = EasUserMessages.fromError(e instanceof Error ? e.message : String(e),
        '无法加载课表信息，请稍后重试');
    } finally {
      this.loading = false;
    }
  }

  aboutToDisappear(): void {
    this.detailsGeneration++;
  }

  private async loadTermDetails(): Promise<void> {
    const generation: number = ++this.detailsGeneration;
    const term: EasTermItem | undefined = this.selectedTerm();
    const session: EasSession | undefined = this.session;
    this.startTime = 0;
    this.dateNotice = '';
    this.error = '';
    if (term === undefined || session === undefined) {
      this.detailsLoading = false;
      return;
    }
    this.detailsLoading = true;
    this.schedule = ImportTimetablePanel.defaultSchedule(session.campus);
    try {
      const rdb: RdbHelper = RdbHelper.getInstance();
      await rdb.init(this.getUIContext().getHostContext() as common.Context);
      const provider: EasDataProvider = new EasDataProvider(new EasApiClient());
      const start: EasTermStartResult = await EasTimetableImporter.loadStartDate(rdb, provider, session, term);
      let schedule: EasTimePeriodInDay[] = ImportTimetablePanel.defaultSchedule(session.campus);
      if (session.campus === EasCampus.SHENZHEN) {
        try {
          const remote: EasTimePeriodInDay[] = await provider.getShenzhenScheduleStructure(session, term);
          if (remote.length > 0) {
            schedule = remote;
          }
        } catch (e) {
          // The optional bell schedule does not invalidate the calendar date.
        }
      }
      if (generation !== this.detailsGeneration) {
        return;
      }
      this.startTime = start.startTime;
      this.schedule = schedule;
      this.dateNotice = start.fromSaved ? '校历暂不可用，已保留本地日期，请核对' :
        start.startTime > 0 ? '' : '未获取到开学日期，请手动选择';
    } catch (e) {
      if (generation === this.detailsGeneration) {
        this.error = EasUserMessages.fromError(e instanceof Error ? e.message : String(e),
          '无法读取教务校历，请稍后重试或手动选择日期');
      }
    } finally {
      if (generation === this.detailsGeneration) {
        this.detailsLoading = false;
      }
    }
  }

  private selectedTerm(): EasTermItem | undefined {
    if (this.selectedTermIndex < 0 || this.selectedTermIndex >= this.terms.length) {
      return undefined;
    }
    return this.terms[this.selectedTermIndex];
  }

  private chooseTerm(): void {
    if (this.terms.length === 0 || this.importing) {
      return;
    }
    const range: string[] = [];
    for (let i: number = 0; i < this.terms.length; i++) {
      range.push(this.terms[i].name);
    }
    this.getUIContext().showTextPickerDialog({
      range: range,
      selected: this.selectedTermIndex,
      canLoop: false,
      onAccept: async (result: TextPickerResult) => {
        const index: number = typeof result.index === 'number' ? result.index : 0;
        if (index < 0 || index >= this.terms.length) {
          return;
        }
        this.selectedTermIndex = index;
        await this.loadTermDetails();
      }
    });
  }

  private chooseStartDate(): void {
    if (this.detailsLoading || this.importing) {
      return;
    }
    const generation: number = this.detailsGeneration;
    this.getUIContext().showDatePickerDialog({
      selected: this.startTime > 0 ? new Date(this.startTime) : new Date(),
      onDateAccept: (date: Date) => {
        if (generation !== this.detailsGeneration || this.importing) {
          return;
        }
        this.startTime = EasTimetable.mondayMsOf(date.getTime());
        this.dateNotice = '';
        this.error = '';
      }
    });
  }

  private editPeriod(index: number): void {
    if (this.detailsLoading || this.importing || index < 0 || index >= this.schedule.length) {
      return;
    }
    const period: EasTimePeriodInDay = this.schedule[index];
    this.getUIContext().getPromptAction().showActionMenu({
      title: '第 ' + (index + 1).toString() + ' 节',
      buttons: [
        { text: '调整开始时间', color: HitaColors.primary },
        { text: '调整结束时间', color: HitaColors.primary },
        { text: '恢复默认时间', color: HitaColors.primary }
      ]
    }).then((result) => {
      if (result.index === 0) {
        this.pickPeriodTime(index, true);
      } else if (result.index === 1) {
        this.pickPeriodTime(index, false);
      } else if (result.index === 2) {
        const defaults: EasTimePeriodInDay[] = this.session === undefined ?
          EasTimetable.getDefaultTimeStructure() : ImportTimetablePanel.defaultSchedule(this.session.campus);
        if (index < defaults.length) {
          const next: EasTimePeriodInDay[] = this.schedule.slice();
          next[index] = defaults[index].clone();
          this.schedule = next;
        }
      }
    }).catch(() => {
    });
  }

  private pickPeriodTime(index: number, from: boolean): void {
    const current: EasTimeInDay = from ? this.schedule[index].from : this.schedule[index].to;
    const selected: Date = new Date(2000, 0, 1, current.hour, current.minute, 0, 0);
    this.getUIContext().showTimePickerDialog({
      selected: selected,
      useMilitaryTime: true,
      onAccept: (value: TimePickerResult) => {
        const existing: EasTimePeriodInDay = this.schedule[index];
        const nextFrom: EasTimeInDay = from ? new EasTimeInDay(value.hour, value.minute) : existing.from;
        const nextTo: EasTimeInDay = from ? existing.to : new EasTimeInDay(value.hour, value.minute);
        if (nextTo.compareTo(nextFrom) <= 0) {
          this.getUIContext().getPromptAction().showToast({ message: '结束时间必须晚于开始时间' });
          return;
        }
        const next: EasTimePeriodInDay[] = this.schedule.slice();
        next[index] = new EasTimePeriodInDay(nextFrom, nextTo);
        this.schedule = next;
      }
    });
  }

  private async import(): Promise<void> {
    if (this.importing || this.detailsLoading || this.startTime <= 0 ||
      this.selectedTerm() === undefined || this.session === undefined) {
      return;
    }
    this.importing = true;
    this.message = '';
    this.error = '';
    try {
      const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
      const result: EasImportResult = await EasTimetableImporter.importCurrent(ctx,
        this.selectedTerm() as EasTermItem, this.startTime, this.schedule);
      if (result.success && result.timetable !== undefined) {
        await TimetableSelectionStore.getInstance().init(ctx);
        await TimetableSelectionStore.getInstance().save(result.timetable.id);
        this.message = result.message;
        this.getUIContext().getPromptAction().showToast({ message: result.message });
        this.onImported();
        setTimeout(() => {
          this.close();
        }, 500);
      } else {
        this.error = result.message.length > 0 ? result.message : '导入课表失败';
      }
    } catch (e) {
      this.error = EasUserMessages.fromError(e instanceof Error ? e.message : String(e),
        '导入课表失败，请稍后重试');
    } finally {
      this.importing = false;
    }
  }

  private close(): void {
    if (this.presentedAsSheet) {
      this.onClose();
    } else {
      this.getUIContext().getRouter().back();
    }
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      if (this.loading) {
        LoadingProgress()
          .width(32)
          .height(32)
          .color(HitaColors.primary)
          .margin({ top: HEADER_HEIGHT + 80 });
      } else if (this.error.length > 0 && this.terms.length === 0) {
        Column() {
          Text(this.error)
            .fontSize(16)
            .fontColor(TEXT_PRIMARY);
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center);
      } else {
        Scroll(this.pageScroller) {
          Column({ space: 12 }) {
            Blank().height(HEADER_HEIGHT);
            this.termCard();
            this.dateCard();
            this.scheduleCard();
            if (this.error.length > 0) {
              Text(this.error)
                .fontSize(13)
                .fontColor($r('app.color.hita_error_c23b4a'))
                .width('100%');
            }
            if (this.message.length > 0) {
              Text(this.message)
                .fontSize(13)
                .fontColor($r('app.color.hita_success'))
                .width('100%');
            }
            Blank().height(this.presentedAsSheet ? this.navBarInset + 20 : 36);
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 20 });
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .onDidScroll(() => {
          this.fadeOpacity = HeaderFade.opacity(this.pageScroller.currentOffset().yOffset);
        });
      }

      HeaderFadeMask({
        maskOpacity: this.fadeOpacity,
        rgb: PAGE_BG_RGB,
        headerHeight: HEADER_HEIGHT
      })

      ImmersiveHeader({ barHeight: HEADER_HEIGHT, materialEnabled: !this.presentedAsSheet ||
        CompatibleSheetMaterial.isEnabled() }) {
        Row() {
          HeaderBackButton({
            onBack: () => this.close()
          })
            .margin({ right: 12 });
          Text('导入课表')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(TEXT_PRIMARY)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
          Text(this.importing ? '导入中' : '导入')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(CompatibleMaterialModifier.foreground($r('app.color.hita_primary_3390ec')))
            .height(32)
            .padding({ left: 12, right: 12 })
            .borderRadius(16)
            .backgroundColor($r('app.color.hita_selected_ebf4fc'))
            .attributeModifier(new CompatibleMaterialModifier($r('app.color.hita_selected_ebf4fc'), false,
              !this.presentedAsSheet || CompatibleSheetMaterial.isEnabled()))
            .textAlign(TextAlign.Center)
            .margin({ left: 8 })
            .flexShrink(0)
            .enabled(!this.importing && !this.loading && !this.detailsLoading &&
              this.startTime > 0 && this.selectedTerm() !== undefined)
            .onClick(() => this.import());
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
    .padding({ top: this.presentedAsSheet ? 0 : this.statusBarInset })
    .backgroundColor(this.presentedAsSheet ? CompatibleSheetMaterial.bodyColor(PAGE_BG) : PAGE_BG)
    .attributeModifier(new CompatibleLightModifier(24, this.presentedAsSheet &&
      CompatibleSheetMaterial.isEnabled(), true));
  }

  @Builder
  private termCard() {
    Column() {
      Text('导入学期')
        .fontSize(13)
        .fontColor(TEXT_SECONDARY)
        .width('100%');
      Row() {
        Column() {
          Text(this.selectedTerm() === undefined ? '未选择学期' : (this.selectedTerm() as EasTermItem).name)
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor(TEXT_PRIMARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
          Text(this.selectedTerm() === undefined ? '点击选择教务学期' :
            (this.selectedTerm() as EasTermItem).getCode())
            .fontSize(12)
            .fontColor(TEXT_SECONDARY)
            .margin({ top: 4 });
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start);
        Text('›')
          .fontSize(24)
          .fontColor(TEXT_SECONDARY);
      }
      .width('100%')
      .margin({ top: 10 })
      .onClick(() => this.chooseTerm());
    }
    .width('100%')
    .padding(18)
    .backgroundColor(CARD_BG)
    .borderRadius(18);
  }

  @Builder
  private dateCard() {
    Row() {
      Column() {
        Text('开学日期 · 第一教学周周一')
          .fontSize(13)
          .fontColor(TEXT_SECONDARY);
        Text(this.detailsLoading ? '读取校历中' : this.startTime > 0 ?
          ImportTimetablePanel.dateText(this.startTime) : '请选择日期')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(TEXT_PRIMARY)
          .margin({ top: 6 });
        if (this.dateNotice.length > 0) {
          Text(this.dateNotice)
            .fontSize(12)
            .fontColor($r('app.color.hita_warning'))
            .margin({ top: 4 });
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start);
      SymbolGlyph($r('sys.symbol.calendar'))
        .fontSize(24)
        .fontColor([HitaColors.primary]);
    }
    .width('100%')
    .padding(18)
    .backgroundColor(CARD_BG)
    .borderRadius(18)
    .onClick(() => this.chooseStartDate());
  }

  @Builder
  private scheduleCard() {
    Column() {
      Row() {
        Text('每日节次')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_PRIMARY)
          .layoutWeight(1);
        Text(this.schedule.length.toString() + ' 节')
          .fontSize(13)
          .fontColor(TEXT_SECONDARY);
      }
      .width('100%');
      Text('点击任意一节可修改开始或结束时间')
        .fontSize(12)
        .fontColor(TEXT_SECONDARY)
        .width('100%')
        .margin({ top: 5, bottom: 10 });
      Column() {
        ForEach(this.schedule, (period: EasTimePeriodInDay, index: number) => {
          Row() {
            Stack() {
              Text((index + 1).toString())
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor(HitaColors.primary);
            }
            .width(34)
            .height(34)
            .borderRadius(17)
            .backgroundColor($r('app.color.hita_selected_e8f3fd'))
            .alignContent(Alignment.Center);
            Column() {
              Text('第 ' + (index + 1).toString() + ' 节')
                .fontSize(15)
                .fontColor(TEXT_PRIMARY);
              Text(period.from.toString() + ' - ' + period.to.toString())
                .fontSize(13)
                .fontColor(TEXT_SECONDARY)
                .margin({ top: 3 });
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            .margin({ left: 12 });
            Text('›')
              .fontSize(22)
              .fontColor($r('app.color.hita_text_hint_a3adbb'));
          }
          .width('100%')
          .height(58)
          .alignItems(VerticalAlign.Center)
          .onClick(() => this.editPeriod(index));
          if (index < this.schedule.length - 1) {
            Divider()
              .strokeWidth(1)
              .color($r('app.color.hita_divider_eef1f5'))
              .margin({ left: 46 });
          }
        }, (period: EasTimePeriodInDay, index: number) => index.toString() + period.toString());
      }
      .width('100%');
    }
    .width('100%')
    .padding(18)
    .backgroundColor(CARD_BG)
    .borderRadius(18);
  }

  private static dateText(timestamp: number): string {
    const d: Date = new Date(timestamp);
    return d.getFullYear().toString() + '年' + (d.getMonth() + 1).toString() + '月' + d.getDate().toString() + '日';
  }

  private static defaultSchedule(campus: EasCampus): EasTimePeriodInDay[] {
    return EasTimetableImporter.scheduleStructure(campus);
  }
}

