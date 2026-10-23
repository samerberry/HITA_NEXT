import { SheetContent } from '../common/components/SheetContent';
import { common } from '@kit.AbilityKit';
import { HeaderBackButton } from '../common/components/HeaderBackButton';
import { ImmersiveHeader } from '../common/components/ImmersiveHeader';
import { CompatibleMaterialModifier } from '../common/theme/CompatibleMaterialModifier';
import { CompatibleLightModifier } from '../common/theme/CompatibleLightModifier';
import { CompatibleSheetMaterial } from '../common/theme/CompatibleSheetMaterial';
import { STATUS_BAR_INSET_FALLBACK, NAV_BAR_INSET_FALLBACK } from '../common/theme/StatusBarInset';
import { RdbHelper } from '../common/db/RdbHelper';
import { EasTimePeriodInDay, EasTimetable } from '../common/model/timetable/TimetableModels';
import { EasTimeTools } from '../common/util/EasTimeTools';
import { EasApiClient } from '../feature/eas/EasApiClient';
import { EasCampus, EasSession } from '../feature/eas/EasSession';
import { EasSessionStore } from '../feature/eas/EasSessionStore';
import { EasDataProvider } from '../feature/eas/EasDataProvider';
import { EasTimetableImporter } from '../feature/eas/EasTimetableImporter';
import { EasTermItem } from '../feature/eas/model/EasModels';
import { EasUserMessages } from '../feature/eas/EasUserMessages';
import { ClassroomBuilding, ClassroomQueryError, ClassroomRoom } from '../feature/eas/classroom/EmptyClassroomData';
import { EmptyClassroomService } from '../feature/eas/classroom/EmptyClassroomService';
import { ClassroomScheduleRow, EmptyClassroomDisplay } from '../feature/eas/classroom/EmptyClassroomDisplay';
import { ClassroomSnapshot, EmptyClassroomCache } from '../feature/eas/classroom/EmptyClassroomCache';

const DAYS: string[] = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
const TEXT: ResourceColor = $r('app.color.hita_text');
const SECONDARY: ResourceColor = $r('app.color.hita_text_secondary');
const PRIMARY: ResourceColor = $r('app.color.hita_primary');

@Entry
@Component
export struct EmptyClassroomPage {
  @Prop presentedAsSheet: boolean = false;
  onClose: () => void = () => {};
  @State terms: EasTermItem[] = [];
  @State buildings: ClassroomBuilding[] = [];
  @State termIndex: number = 0;
  @State buildingIndex: number = 0;
  @State selectedWeek: number = 1;
  @State rooms: ClassroomRoom[] = [];
  @State resultVersion: number = 0;
  @State schedule: EasTimePeriodInDay[] = [];
  @State loading: boolean = true;
  @State querying: boolean = false;
  @State queried: boolean = false;
  @State loginNeeded: boolean = false;
  @State error: string = '';
  @State cachedAt: number = 0;
  @State sheetVisible: boolean = false;
  @State detailRoom: ClassroomRoom = new ClassroomRoom();
  @State detailDay: number = EasTimeTools.currentDOW();
  @State detailRows: ClassroomScheduleRow[] = [];
  @StorageProp('hita_status_bar_vp') statusBarInset: number = STATUS_BAR_INSET_FALLBACK;
  @StorageProp('hita_nav_bar_vp') navBarInset: number = NAV_BAR_INSET_FALLBACK;
  private session: EasSession | undefined = undefined;
  private cache: EmptyClassroomCache = new EmptyClassroomCache();
  private generation: number = 0;
  private returningFromLogin: boolean = false;
  private sheetLoadStarted: boolean = false;

  async aboutToAppear(): Promise<void> {
    if (this.presentedAsSheet && !this.sheetLoadStarted) await this.onPageShow();
  }

  async onPageShow(): Promise<void> {
    if (this.presentedAsSheet) {
      if (this.sheetLoadStarted) return;
      this.sheetLoadStarted = true;
    }
    await this.loadOptions(this.returningFromLogin);
    this.returningFromLogin = false;
  }

  onPageHide(): void {
    this.generation++;
    this.sheetLoadStarted = false;
    this.sheetVisible = false;
  }

  aboutToDisappear(): void {
    this.onPageHide();
  }

  private clearResults(): void {
    this.generation++;
    this.rooms = [];
    this.queried = false;
    this.querying = false;
    this.cachedAt = 0;
    this.sheetVisible = false;
    this.error = '';
  }

  private showFailure(error: Object): void {
    if (error instanceof ClassroomQueryError) {
      this.error = error.message;
      this.loginNeeded = error.kind === 'AUTH';
    } else {
      const message: string = error instanceof Error ? error.message : String(error);
      this.error = EasUserMessages.fromError(message, '无法加载教务数据，请稍后重试');
      this.loginNeeded = /登录|会话/.test(this.error);
    }
  }

  private async loadOptions(preserveSelection: boolean = false): Promise<void> {
    const previousSession: EasSession | undefined = this.session;
    const previousTerm: string = this.terms[this.termIndex]?.getCode() || '';
    const previousBuilding: string = this.buildings[this.buildingIndex]?.key() || '';
    const previousWeek: number = this.selectedWeek;
    this.clearResults();
    const generation: number = this.generation;
    this.loading = true;
    this.loginNeeded = false;
    this.terms = [];
    this.buildings = [];
    this.schedule = [];
    this.session = undefined;
    try {
      const context: common.Context = this.getUIContext().getHostContext() as common.Context;
      const store: EasSessionStore = EasSessionStore.getInstance();
      await store.init(context);
      const session: EasSession | undefined = await store.loadPreferred();
      if (generation !== this.generation) { return; }
      if (session === undefined) { throw new ClassroomQueryError('AUTH', '请先登录教务系统'); }
      EmptyClassroomService.assertSession(session);
      this.session = session;
      await this.cache.init(context);
      const provider: EasDataProvider = new EasDataProvider(new EasApiClient());
      const terms: EasTermItem[] = await provider.getAllTerms(session);
      if (generation !== this.generation) { return; }
      this.terms = EmptyClassroomDisplay.currentYearTerms(terms);
      const buildings: ClassroomBuilding[] = await new EmptyClassroomService(new EasApiClient()).getBuildings(session);
      if (generation !== this.generation) { return; }
      this.buildings = buildings;
      if (this.terms.length === 0 || buildings.length === 0) {
        this.error = this.terms.length === 0 ? '教务系统未返回可查询的学期' : '教务系统未返回可查询的教学楼';
        return;
      }
      const keep: boolean = preserveSelection && previousSession !== undefined &&
        previousSession.campus === session.campus &&
        (previousSession.stuId || previousSession.username) === (session.stuId || session.username);
      const previousIndex: number = keep ? this.terms.findIndex((term: EasTermItem): boolean =>
        term.getCode() === previousTerm) : -1;
      this.termIndex = previousIndex >= 0 ? previousIndex :
        Math.max(0, this.terms.findIndex((term: EasTermItem): boolean => term.isCurrent));
      this.buildingIndex = keep ? Math.max(0, buildings.findIndex((building: ClassroomBuilding): boolean =>
        building.key() === previousBuilding)) : 0;
      await this.loadTermContext(generation);
      if (generation !== this.generation) { return; }
      if (keep && previousIndex >= 0) { this.selectedWeek = previousWeek; }
      this.loading = false;
      await this.query();
    } catch (e) {
      if (generation === this.generation) { this.showFailure(e as Object); }
    } finally {
      if (generation === this.generation) { this.loading = false; }
    }
  }

  private async loadTermContext(generation: number): Promise<void> {
    const session: EasSession | undefined = this.session;
    const term: EasTermItem | undefined = this.terms[this.termIndex];
    if (session === undefined || term === undefined) { return; }
    let week: number = 1;
    // Android initializes the week from the imported timetable, otherwise week 1.
    try {
      const rdb: RdbHelper = RdbHelper.getInstance();
      await rdb.init(this.getUIContext().getHostContext() as common.Context);
      const saved: EasTimetable | undefined = await rdb.getTimetableByEasCode(
        session.campus.toString() + ':' + term.getCode());
      week = saved === undefined ? 1 : Math.max(1, saved.getWeekNumber(Date.now()));
    } catch (e) { week = 1; }
    let schedule: EasTimePeriodInDay[] = EasTimetableImporter.scheduleStructure(session.campus);
    if (session.campus === EasCampus.SHENZHEN) {
      schedule = [];
      try {
        const remote: EasTimePeriodInDay[] = await new EasDataProvider(new EasApiClient())
          .getShenzhenScheduleStructure(session, term);
        if (remote.length > 0) { schedule = remote; }
      } catch (e) {
        // Shenzhen web mode requires the actual bell schedule; keep the card state unknown on failure.
      }
    }
    if (generation === this.generation) {
      this.selectedWeek = Math.min(EmptyClassroomDisplay.PICKER_WEEKS, week);
      this.schedule = schedule;
    }
  }

  private chooseTerm(): void {
    if (this.loading || this.terms.length === 0) { return; }
    const options: EasTermItem[] = EmptyClassroomDisplay.pickerTerms(this.terms, this.session?.grade || '');
    const selected: EasTermItem = this.terms[this.termIndex];
    this.getUIContext().showTextPickerDialog({
      range: options.map((term: EasTermItem): string => EmptyClassroomDisplay.termName(term)),
      selected: Math.max(0, options.findIndex((term: EasTermItem): boolean => term.equalsKey(selected))),
      canLoop: false,
      onAccept: async (result: TextPickerResult) => {
        if (typeof result.index === 'number' && options[result.index] !== undefined) {
          const chosen: EasTermItem = options[result.index];
          await this.changeTerm(this.terms.findIndex((term: EasTermItem): boolean => term.equalsKey(chosen)));
        }
      }
    });
  }

  private async changeTerm(index: number): Promise<void> {
    if (index < 0 || index >= this.terms.length || index === this.termIndex || this.loading) { return; }
    this.clearResults();
    this.termIndex = index;
    this.loading = true;
    const generation: number = this.generation;
    await this.loadTermContext(generation);
    if (generation === this.generation) {
      this.loading = false;
      await this.query();
    }
  }

  private chooseBuilding(): void {
    if (this.loading || this.buildings.length === 0) { return; }
    this.getUIContext().showTextPickerDialog({
      range: this.buildings.map((building: ClassroomBuilding): string => building.name),
      selected: this.buildingIndex, canLoop: false,
      onAccept: async (result: TextPickerResult) => {
        if (typeof result.index === 'number') { await this.changeBuilding(result.index); }
      }
    });
  }

  private async changeBuilding(index: number): Promise<void> {
    if (index < 0 || index >= this.buildings.length || index === this.buildingIndex || this.loading) { return; }
    this.buildingIndex = index;
    await this.query();
  }

  private async changeWeek(week: number): Promise<void> {
    if (!Number.isInteger(week) || week < 1 || week > EmptyClassroomDisplay.PICKER_WEEKS ||
      this.loading || week === this.selectedWeek) { return; }
    this.selectedWeek = week;
    await this.query();
  }

  private chooseWeek(): void {
    if (this.loading || this.terms.length === 0) { return; }
    const weeks: string[] = [];
    for (let i: number = 1; i <= EmptyClassroomDisplay.PICKER_WEEKS; i++) { weeks.push('第 ' + i.toString() + ' 周'); }
    this.getUIContext().showTextPickerDialog({
      range: weeks, selected: this.selectedWeek - 1, canLoop: false,
      onAccept: async (result: TextPickerResult) => {
        if (typeof result.index === 'number') { await this.changeWeek(result.index + 1); }
      }
    });
  }

  private async query(): Promise<void> {
    const session: EasSession | undefined = this.session;
    const term: EasTermItem | undefined = this.terms[this.termIndex];
    const building: ClassroomBuilding | undefined = this.buildings[this.buildingIndex];
    if (this.loading || session === undefined || term === undefined || building === undefined) { return; }
    this.clearResults();
    this.loginNeeded = false;
    const generation: number = this.generation;
    const week: number = this.selectedWeek;
    const key: string = EmptyClassroomCache.key(session, term, building, week);
    this.querying = true;
    try {
      const cached: ClassroomSnapshot | undefined = await this.cache.read(key);
      if (generation !== this.generation) { return; }
      if (cached !== undefined) {
        this.resultVersion++;
        this.rooms = cached.rooms;
        this.cachedAt = cached.savedAt;
        this.queried = true;
      }
      const rooms: ClassroomRoom[] = await new EmptyClassroomService(new EasApiClient()).query(session, term, building, week);
      if (generation !== this.generation) { return; }
      this.resultVersion++;
      this.rooms = rooms;
      this.queried = true;
      this.cachedAt = 0;
      if (this.sheetVisible) {
        const refreshed: ClassroomRoom | undefined = rooms.find((room: ClassroomRoom): boolean => room.id === this.detailRoom.id);
        if (refreshed === undefined) {
          this.sheetVisible = false;
        } else {
          this.detailRoom = refreshed;
          this.selectDay(this.detailDay);
        }
      }
      await this.cache.write(key, rooms);
    } catch (e) {
      if (generation === this.generation) { this.showFailure(e as Object); }
    } finally {
      if (generation === this.generation) { this.querying = false; }
    }
  }

  private openLogin(): void {
    this.returningFromLogin = true;
    try {
      this.getUIContext().getRouter().pushUrl({ url: 'pages/Home', params: { 'openSession': '1' } })
        .catch(() => { this.error = '无法打开登录页面，请返回“更多”登录教务'; });
    } catch (e) { this.error = '无法打开登录页面，请返回“更多”登录教务'; }
  }

  private roomState(room: ClassroomRoom): string {
    return EmptyClassroomDisplay.state(room, EasTimeTools.currentDOW(),
      EasTimeTools.getCurrentScheduleNumber(this.schedule), this.schedule.length > 0);
  }

  private openDetail(room: ClassroomRoom): void {
    if (this.schedule.length === 0) {
      this.error = '未获取到节次时间，请刷新后再查看教室详情';
      return;
    }
    this.detailRoom = room;
    this.selectDay(EasTimeTools.currentDOW());
    this.sheetVisible = true;
  }

  private selectDay(day: number): void {
    this.detailDay = day;
    this.detailRows = EmptyClassroomDisplay.rows(this.detailRoom, day, this.schedule);
  }

  private termLabel(): string {
    return this.terms[this.termIndex] === undefined ? '加载失败' :
      EmptyClassroomDisplay.termName(this.terms[this.termIndex]);
  }

  private cacheLabel(): string {
    return '缓存于 ' + EasTimeTools.printDate(this.cachedAt) + ' ' + EasTimeTools.printTime(this.cachedAt) +
      (this.querying ? ' · 正在更新' : ' · 本次更新未成功');
  }

  private filterLabel(kind: number): string {
    if (kind === 0) { return this.buildings[this.buildingIndex]?.name || (this.loading ? '加载中' : '加载失败'); }
    if (kind === 1) { return this.terms.length === 0 && this.loading ? '加载中' : this.termLabel(); }
    return '第 ' + this.selectedWeek.toString() + ' 周';
  }

  build() {
    Column({ space: 8 }) {
      ImmersiveHeader({ barHeight: 60, materialEnabled: !this.presentedAsSheet ||
        CompatibleSheetMaterial.isEnabled() }) {
        Row({ space: 12 }) {
        HeaderBackButton({ onBack: () => {
          if (this.presentedAsSheet) this.onClose();
          else this.getUIContext().getRouter().back();
        } })
          Text('空教室查询').fontSize(20).fontWeight(FontWeight.Bold).fontColor(TEXT).layoutWeight(1)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Button({ type: ButtonType.Circle }) {
            if (this.loading || this.querying) {
              LoadingProgress().width(22).height(22).color(PRIMARY)
            } else {
              SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(22)
                .fontColor([CompatibleMaterialModifier.foreground(PRIMARY)])
            }
          }
          .width(44).height(44).backgroundColor(Color.Transparent)
          .attributeModifier(new CompatibleMaterialModifier(Color.Transparent, false,
            !this.presentedAsSheet || CompatibleSheetMaterial.isEnabled()))
          .accessibilityText('刷新空教室').enabled(!this.loading && !this.querying)
          .onClick(async () => { await this.loadOptions(); })
        }.width('100%').height(60).padding({ left: 4, right: 4 })
      }
      Row({ space: 4 }) {
        this.selector(0, '选择教学楼', FlexAlign.Start, () => this.chooseBuilding())
        this.selector(1, '选择学期', FlexAlign.Center, () => this.chooseTerm())
        this.selector(2, '选择周次', FlexAlign.End, () => this.chooseWeek())
      }.width('100%').padding({ left: 12, right: 12 }).backgroundColor($r('app.color.hita_surface')).borderRadius(16)
      if (this.cachedAt > 0) {
        Text(this.cacheLabel()).fontSize(12).fontColor(SECONDARY).padding({ left: 8, right: 8 }).width('100%')
      }
      if (this.error.length > 0) {
        Text(this.error).fontSize(14).fontColor(SECONDARY).textAlign(TextAlign.Center)
          .width('100%').padding(20)
      }
      Stack({ alignContent: Alignment.Center }) {
        Grid() {
          ForEach(this.rooms, (room: ClassroomRoom) => {
            GridItem() { this.roomCard(room) }
          }, (room: ClassroomRoom): string => this.resultVersion.toString() + ':' + room.id)
        }.columnsTemplate('1fr 1fr').columnsGap(12).rowsGap(12).width('100%').height('100%')
          .padding({ top: 8, left: 4, right: 4, bottom: this.navBarInset + 12 })
        if ((this.loading || this.querying) && this.rooms.length === 0) {
          LoadingProgress().width(40).height(40).color(PRIMARY)
        } else if (this.queried && this.rooms.length === 0 && this.error.length === 0) {
          Text('该教学楼本周暂无教室数据').fontSize(14).fontColor(SECONDARY)
        }
      }.layoutWeight(1).width('100%')
    }.padding({ top: this.presentedAsSheet ? 0 : this.statusBarInset, left: 12, right: 12 })
      .width('100%').height('100%')
      .backgroundColor(this.presentedAsSheet ? CompatibleSheetMaterial.bodyColor($r('app.color.hita_page')) :
        $r('app.color.hita_page'))
      .bindSheet(this.sheetVisible, this.classroomSheet(), {
        height: '80%', dragBar: true, showClose: false, preferType: SheetType.BOTTOM,
        backgroundColor: $r('app.color.hita_surface'), maskColor: $r('app.color.hita_sheet_mask'),
        onDisappear: () => { this.sheetVisible = false; }
      })
      .attributeModifier(new CompatibleLightModifier(24, this.presentedAsSheet &&
        CompatibleSheetMaterial.isEnabled(), true))
  }

  @Builder
  private selector(kind: number, description: string, alignment: FlexAlign, action: () => void) {
    Row({ space: 4 }) {
      Text(this.filterLabel(kind)).fontSize(14).fontColor(TEXT).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).flexShrink(1)
      SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(12).fontColor([SECONDARY])
    }.height(52).layoutWeight(1).justifyContent(alignment).enabled(!this.loading)
      .accessibilityText(description + '，' + this.filterLabel(kind)).onClick(action)
  }

  @Builder
  private roomCard(room: ClassroomRoom) {
    Row({ space: 8 }) {
      Text(room.name).fontSize(16).fontColor(TEXT).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.roomState(room)).fontSize(14).fontWeight(FontWeight.Bold)
        .fontColor(this.roomState(room) === '空闲' ? PRIMARY : SECONDARY)
        .backgroundColor(this.roomState(room) === '空闲' ? $r('app.color.hita_selected') : $r('app.color.hita_control'))
        .padding({ left: 10, right: 10, top: 4, bottom: 4 }).borderRadius(16)
    }.width('100%').height(76).padding(16).backgroundColor($r('app.color.hita_surface')).borderRadius(16)
      .accessibilityText(room.name + '，' + this.roomState(room)).onClick(() => this.openDetail(room))
  }

  @Builder
  private classroomSheet() {
    SheetContent({ fillHeight: true }) {
      Column({ space: 16 }) {
        Row({ space: 8 }) {
          Text(this.detailRoom.name + ' 空闲情况').fontSize(24).fontWeight(FontWeight.Bold).fontColor(TEXT)
            .layoutWeight(1).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.termLabel() + '\n第 ' + this.selectedWeek.toString() + ' 周')
            .fontSize(12).fontColor(SECONDARY).padding(8).borderRadius(12).backgroundColor($r('app.color.hita_control'))
        }.width('100%')
        Row({ space: 4 }) {
          ForEach(DAYS, (day: string, index: number) => {
            Text(day).fontSize(14).height(34).layoutWeight(1).textAlign(TextAlign.Center).borderRadius(17)
              .fontColor(this.detailDay === index + 1 ? PRIMARY : SECONDARY)
              .backgroundColor(this.detailDay === index + 1 ? $r('app.color.hita_selected') : Color.Transparent)
              .onClick(() => this.selectDay(index + 1))
          })
        }.width('100%')
        Divider().color($r('app.color.hita_control'))
        List({ space: 12 }) {
          ForEach(this.detailRows, (row: ClassroomScheduleRow) => {
            ListItem() {
              Row({ space: 8 }) {
                Text('第 ' + row.number.toString() + ' 节').fontSize(16).fontColor(TEXT).layoutWeight(1)
                Text(row.time).fontSize(14).fontColor(SECONDARY).padding(8).borderRadius(8)
                  .backgroundColor($r('app.color.hita_control'))
                Blank().layoutWeight(1)
                Text(row.state).fontSize(14).fontWeight(FontWeight.Bold).width(40).height(40).borderRadius(20)
                  .textAlign(TextAlign.Center).fontColor(row.state === '空' ? PRIMARY : SECONDARY)
                  .backgroundColor(row.state === '空' ? $r('app.color.hita_selected') : $r('app.color.hita_control'))
              }.width('100%').padding({ right: 12 })
            }
          }, (row: ClassroomScheduleRow): string => this.detailDay.toString() + ':' + row.number.toString() + ':' + row.time + ':' + row.state)
        }.layoutWeight(1).width('100%').padding({ bottom: this.navBarInset + 16 })
      }.width('100%').height('100%').padding({ left: 20, right: 20 })
    }
  }
}
