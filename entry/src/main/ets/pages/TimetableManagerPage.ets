import { HitaDesign } from '../common/theme/HitaDesign';
/** Android HITA-style timetable library. */
import { common } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { DeleteParticleCard } from '../common/components/DeleteParticleCard';
import { DeleteEffectController } from '../common/util/DeleteEffectController';
import { HeaderBackButton } from '../common/components/HeaderBackButton';
import { ImmersiveHeader } from '../common/components/ImmersiveHeader';
import { CompatibleMaterialModifier } from '../common/theme/CompatibleMaterialModifier';
import { HeaderFadeMask } from '../common/components/HeaderFadeMask';
import { HeaderFade } from '../common/theme/HeaderFade';
import { STATUS_BAR_INSET_FALLBACK } from '../common/theme/StatusBarInset';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo } from '@kit.CoreFileKit';
import { RdbHelper } from '../common/db/RdbHelper';
import { EasTimetable } from '../common/model/timetable/TimetableModels';
import { HitaColors } from '../common/theme/HitaColors';
import { IcsExporter } from '../common/util/ICSExport';
import { TimetableSelectionStore } from '../feature/timetable/data/TimetableSelectionStore';
import { IcsImportResult, TimetableIcsImporter } from '../feature/timetable/data/TimetableIcsImporter';

const WEEK_MS: number = 7 * 24 * 60 * 60 * 1000;
const DOMAIN: number = 0x0000;
const TAG: string = 'HitaTimetableMgr';
const HEADER_HEIGHT: number = 64;
const PAGE_BG: ResourceColor = $r('app.color.hita_page_f6f7fa');
const PAGE_BG_RGB: string = '245,246,248';

@Entry
@Component
struct TimetableManagerPage {
  @StorageProp('hita_status_bar_vp') statusBarInset: number = STATUS_BAR_INSET_FALLBACK;
  @State timetables: EasTimetable[] = [];
  @State selectedIds: string[] = [];
  @State selectionMode: boolean = false;
  @State loading: boolean = true;
  @State exporting: boolean = false;
  @State deleting: boolean = false;
  @State adding: boolean = false;
  @State activeTimetableId: string = '';
  @State fadeOpacity: number = 0;
  @State contentWidth: number = 360;
  private pageScroller: Scroller = new Scroller();
  private deleteEffects: DeleteEffectController = new DeleteEffectController();

  async onPageShow(): Promise<void> {
    this.deleteEffects.resume();
    await this.load();
  }

  onPageHide(): void {
    this.deleteEffects.pause();
  }

  aboutToDisappear(): void {
    this.deleteEffects.pause();
  }

  private async load(): Promise<void> {
    const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
    await TimetableSelectionStore.getInstance().init(ctx);
    const rdb: RdbHelper = RdbHelper.getInstance();
    await rdb.init(ctx);
    this.timetables = await rdb.getTimetables();
    this.activeTimetableId = await TimetableSelectionStore.getInstance().load();
    this.loading = false;
  }

  private selected(id: string): boolean {
    return this.selectedIds.indexOf(id) >= 0;
  }

  private toggleSelection(id: string): void {
    if (this.deleting) {
      return;
    }
    const next: string[] = [];
    let found: boolean = false;
    for (let i: number = 0; i < this.selectedIds.length; i++) {
      if (this.selectedIds[i] === id) {
        found = true;
      } else {
        next.push(this.selectedIds[i]);
      }
    }
    if (!found) {
      next.push(id);
    }
    this.selectedIds = next;
    this.selectionMode = next.length > 0;
  }

  private async openTimetable(timetable: EasTimetable): Promise<void> {
    if (this.deleting) {
      return;
    }
    if (this.selectionMode) {
      this.toggleSelection(timetable.id);
      return;
    }
    await TimetableSelectionStore.getInstance().save(timetable.id);
    this.activeTimetableId = timetable.id;
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/TimetableDetailPage',
      params: { 'timetableId': timetable.id }
    });
  }

  private async importIcs(): Promise<void> {
    if (this.adding || this.loading || this.deleting) return;
    this.adding = true;
    const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      const result: IcsImportResult | undefined = await TimetableIcsImporter.pickAndImport(ctx);
      if (result === undefined) {
        return;
      }
      this.getUIContext().getPromptAction().showToast({ message: result.message });
      if (result.success) {
        this.activeTimetableId = result.timetableId;
        await this.load();
        this.getUIContext().getRouter().pushUrl({
          url: 'pages/TimetableDetailPage',
          params: { 'timetableId': result.timetableId }
        });
      }
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '导入 ICS 失败' });
    } finally {
      this.adding = false;
    }
  }

  private openImportPage(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/ImportTimetablePage' });
  }

  private async createEmptyTimetable(): Promise<void> {
    if (this.adding || this.loading || this.deleting) return;
    this.adding = true;
    try {
      const now: number = Date.now();
      const timetable: EasTimetable = new EasTimetable();
      timetable.name = TimetableManagerPage.defaultName(now);
      timetable.code = 'LOCAL:' + timetable.id;
      timetable.startTime = EasTimetable.mondayMsOf(now);
      timetable.endTime = timetable.startTime + 20 * WEEK_MS - 1;
      timetable.createdAt = now;
      await RdbHelper.getInstance().saveTimetable(timetable);
      await TimetableSelectionStore.getInstance().save(timetable.id);
      this.activeTimetableId = timetable.id;
      await this.load();
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/TimetableDetailPage',
        params: { 'timetableId': timetable.id }
      });
    } catch (_) {
      this.getUIContext().getPromptAction().showToast({ message: '新建课表失败，请重试' });
    } finally {
      this.adding = false;
    }
  }

  /** Export the selected/current timetable into the app sandbox as an ICS file. */
  private async exportTimetable(timetable: EasTimetable): Promise<void> {
    if (this.exporting) {
      return;
    }
    this.exporting = true;
    try {
      const events = await RdbHelper.getInstance().getEventsOfTimetable(timetable.id);
      if (events.length === 0) {
        this.getUIContext().getPromptAction().showToast({ message: '当前课表没有可导出的课程' });
        return;
      }
      const ics: string = IcsExporter.fromEvents(events, timetable.name);
      const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const path: string = ctx.filesDir + '/hita-' + timetable.id + '.ics';
      const file = fileIo.openSync(path,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try {
        fileIo.writeSync(file.fd, ics);
      } finally {
        fileIo.closeSync(file);
      }
      this.getUIContext().getPromptAction().showToast({
        message: '已导出 ICS（' + ics.length.toString() + 'B）'
      });
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '导出 ICS 失败' });
    } finally {
      this.exporting = false;
    }
  }

  private showExportMenu(): void {
    if (this.timetables.length === 0 || this.exporting) {
      this.getUIContext().getPromptAction().showToast({ message: '暂无可导出的课表' });
      return;
    }
    const current: EasTimetable | undefined =
      this.timetables.find((item: EasTimetable): boolean => item.id === this.activeTimetableId);
    this.exportTimetable(current ?? this.timetables[0]);
  }

  private confirmDelete(): void {
    const ids: string[] = this.selectedIds.slice();
    const count: number = ids.length;
    if (count === 0 || this.deleting) {
      return;
    }
    this.getUIContext().getPromptAction().showDialog({
      title: '删除课表',
      message: '确定删除选中的 ' + count.toString() + ' 张课表及其全部课程吗？',
      buttons: [
        { text: '取消', color: $r('app.color.hita_text_secondary_7b8190') },
        { text: '删除', color: HitaColors.error }
      ]
    }).then((ret) => {
      if (ret.index !== 1) {
        return;
      }
      // 不在弹窗回调里做长耗时异步操作：部分版本上回调未返回会阻塞 UI 线程。
      setTimeout(() => {
        this.performDelete(ids);
      }, 0);
    }).catch(() => {
    });
  }

  private async performDelete(ids: string[]): Promise<void> {
    if (this.deleting) {
      return;
    }
    this.deleting = true;
    try {
      hilog.info(DOMAIN, TAG, 'delete timetables start count=%{public}d', ids.length);
      await RdbHelper.getInstance().deleteTimetablesCascade(ids);
      hilog.info(DOMAIN, TAG, 'delete timetables rows done');
      await this.deleteEffects.play(ids);
      this.getUIContext().animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
        this.timetables = this.timetables.filter((item: EasTimetable): boolean => ids.indexOf(item.id) < 0);
      });
      for (let i: number = 0; i < ids.length; i++) {
        await TimetableSelectionStore.getInstance().clearIf(ids[i]);
      }
      this.selectedIds = [];
      this.selectionMode = false;
      await this.load();
      hilog.info(DOMAIN, TAG, 'delete timetables done');
      this.getUIContext().getPromptAction().showToast({ message: '课表已删除' });
    } catch (e) {
      const text: string = e instanceof Error ? e.message : String(e);
      hilog.error(DOMAIN, TAG, 'delete timetables failed %{public}s', text);
      this.getUIContext().getPromptAction().showToast({ message: '删除失败，请重试' });
      // 出错时退出选择模式并刷新，避免界面停留在无效的多选状态。
      this.selectedIds = [];
      this.selectionMode = false;
      await this.load();
    } finally {
      this.deleting = false;
    }
  }

  @Builder
  private timetableCard(timetable: EasTimetable) {
    Row({ space: HitaDesign.gap }) {
      Stack() {
        SymbolGlyph($r('sys.symbol.calendar'))
          .fontSize(28).fontColor([HitaColors.primary])
      }
      .width(56).height(56).borderRadius(HitaDesign.cardRadius)
      .backgroundColor($r('app.color.hita_selected'))
      .alignContent(Alignment.Center).flexShrink(0)
      Column({ space: 8 }) {
        Text(timetable.name.length > 0 ? timetable.name : '未命名课表')
          .fontSize(HitaDesign.section).fontWeight(FontWeight.Medium)
          .fontColor(HitaColors.onSurface).maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(TimetableManagerPage.dateRange(timetable))
          .fontSize(HitaDesign.label).fontColor(HitaColors.onSurfaceVariant)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (!this.selectionMode && this.activeTimetableId === timetable.id) {
          Text('当前课表').fontSize(HitaDesign.label).fontColor(HitaColors.primary)
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor($r('app.color.hita_selected')).borderRadius(8)
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      if (this.selectionMode) {
        Text(this.selected(timetable.id) ? '✓' : '')
          .fontSize(HitaDesign.body).fontColor(Color.White)
          .width(28).height(28).textAlign(TextAlign.Center).borderRadius(HitaDesign.cardRadius)
          .backgroundColor(this.selected(timetable.id) ? HitaColors.primaryFill : HitaColors.divider)
      } else {
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(12)
          .fontColor([HitaColors.onSurfaceVariant]).width(16).height(24)
          .accessibilityLevel('no')
      }
    }
    .width('100%')
    .height(this.activeTimetableId === timetable.id && !this.selectionMode ? 136 : 112)
    .padding(HitaDesign.inset)
    .backgroundColor($r('app.color.hita_surface')).borderRadius(HitaDesign.cardRadius)
    .border({ width: this.selected(timetable.id) ? 2 : 0, color: HitaColors.primary })
    .accessibilityText(timetable.name + (this.activeTimetableId === timetable.id ? '，当前课表' : ''))
    .accessibilityDescription('点击查看，长按选择课表')
    .accessibilitySelected(this.selected(timetable.id))
    .onClick(() => { this.openTimetable(timetable); })
    .gesture(LongPressGesture({ repeat: false }).onAction(() => { this.toggleSelection(timetable.id); }))
  }

  @Builder
  private addCard() {
    Column({ space: 4 }) {
      this.addActionGlyph($r('sys.symbol.plus'), '新建课表', () => { this.createEmptyTimetable(); });
      this.addActionGlyph($r('sys.symbol.repeat_1'), '教务导入', () => { this.openImportPage(); });
      this.addActionGlyph($r('sys.symbol.doc_plaintext'), '导入日历文件', () => { this.importIcs(); });
    }
    .width('100%').padding(8).backgroundColor($r('app.color.hita_surface'))
    .borderRadius(HitaDesign.cardRadius)
  }

  @Builder
  private addActionGlyph(symbol: Resource, label: string, action: () => void) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: HitaDesign.gap }) {
        SymbolGlyph(symbol).fontSize(20).fontColor([HitaColors.primary]).width(32)
        Text(label).fontSize(HitaDesign.body).fontColor(HitaColors.onSurface).layoutWeight(1)
          .textAlign(TextAlign.Start)
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(12)
          .fontColor([HitaColors.onSurfaceVariant]).width(16).accessibilityLevel('no')
      }.width('100%')
    }
    .width('100%').height(HitaDesign.buttonHeight).padding({ left: 8, right: 8 })
    .backgroundColor(Color.Transparent).borderRadius(HitaDesign.fieldRadius)
    .accessibilityText(label).enabled(!this.adding && !this.loading && !this.deleting)
    .onClick(action)
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      if (this.loading) {
        LoadingProgress()
          .width(32)
          .height(32)
          .color(HitaColors.primary)
          .margin({ top: HEADER_HEIGHT + 80 })
      } else {
        Grid(this.pageScroller) {
          if (!this.selectionMode) {
            GridItem() { this.addCard() }
          }
          ForEach(this.timetables, (timetable: EasTimetable) => {
            GridItem() {
              DeleteParticleCard({
                controller: this.deleteEffects,
                effectId: timetable.id
              }) {
                this.timetableCard(timetable)
              }
            }
            .transition(TransitionEffect.OPACITY)
          }, (timetable: EasTimetable) => timetable.id)
        }
        .columnsTemplate(this.contentWidth >= 600 ? '1fr 1fr' : '1fr')
        .columnsGap(12)
        .rowsGap(HitaDesign.gap)
        .width('100%')
        .height('100%')
        .padding({ left: 16, right: 16, top: HEADER_HEIGHT + 8, bottom: 28 })
        .scrollBar(BarState.Off)
        .enabled(!this.deleting)
        .onDidScroll(() => {
          this.fadeOpacity = HeaderFade.opacity(this.pageScroller.currentOffset().yOffset);
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
            onBack: () => {
              if (this.selectionMode) {
                this.selectedIds = [];
                this.selectionMode = false;
              } else {
                this.getUIContext().getRouter().back();
              }
            }
          })
            .margin({ right: 12 });
          Text(this.selectionMode ? '已选择 ' + this.selectedIds.length.toString() + ' 项' : '课表管理')
            .fontSize(HitaDesign.title)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.hita_text_202633'))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.selectionMode) {
            Text('删除')
              .fontSize(HitaDesign.body)
              .fontWeight(FontWeight.Medium)
              .fontColor(HitaColors.error)
              .padding({ left: 14, right: 14, top: 10, bottom: 10 })
              .borderRadius(22)
              .attributeModifier(new CompatibleMaterialModifier(Color.Transparent))
              .onClick(() => {
                this.confirmDelete();
              })
          } else if (deviceInfo.apiAvailable('26.0.0')) {
            Button({ type: ButtonType.Circle }) {
              SymbolGlyph($r('sys.symbol.doc_plaintext'))
                .fontSize(20)
                .fontColor([CompatibleMaterialModifier.foreground(HitaColors.primary)]);
            }
            .width(44)
            .height(44)
            .padding(0)
            .flexShrink(0)
            .backgroundColor(Color.Transparent)
            .attributeModifier(new CompatibleMaterialModifier(Color.Transparent))
            .accessibilityText('导出课表')
            .onClick(() => {
              this.showExportMenu();
            });
          } else {
            SymbolGlyph($r('sys.symbol.doc_plaintext'))
              .fontSize(20)
              .fontColor([HitaColors.primary])
              .width(44)
              .height(44)
              .onClick(() => {
                this.showExportMenu();
              });
          }
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
    .backgroundColor(PAGE_BG)
    .onAreaChange((_old: Area, area: Area) => { this.contentWidth = Number(area.width); })
  }

  private static defaultName(now: number): string {
    const d: Date = new Date(now);
    const season: string = d.getMonth() < 6 ? '春季学期' : '秋季学期';
    return d.getFullYear().toString() + ' ' + season;
  }

  private static dateRange(timetable: EasTimetable): string {
    return TimetableManagerPage.dateText(timetable.startTime) + ' - ' +
      TimetableManagerPage.dateText(timetable.endTime);
  }

  private static dateText(ms: number): string {
    const d: Date = new Date(ms);
    const m: number = d.getMonth() + 1;
    const day: number = d.getDate();
    return d.getFullYear().toString() + '.' + (m < 10 ? '0' : '') + m.toString() + '.' +
      (day < 10 ? '0' : '') + day.toString();
  }

}
