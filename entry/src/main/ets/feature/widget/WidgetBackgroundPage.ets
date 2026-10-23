/**
 * WidgetBackgroundPage.ets — 桌面服务卡片自定义背景半模态面板。
 *
 * 用户在与卡片同比例的取景框中拖动、双指缩放，自行决定图片在 2×2 与 2×4 卡片中显示的部分；
 * 保存时按各自比例烘焙，卡片端不再拉伸或二次裁切。未保存的选图只存在缓存草稿中。
 */
import { common } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { HeaderBackButton } from '../../common/components/HeaderBackButton';
import { HeaderFadeMask } from '../../common/components/HeaderFadeMask';
import { ImmersiveHeader } from '../../common/components/ImmersiveHeader';
import { CompatibleLightModifier } from '../../common/theme/CompatibleLightModifier';
import { CompatibleMaterialModifier } from '../../common/theme/CompatibleMaterialModifier';
import { CompatibleSheetMaterial } from '../../common/theme/CompatibleSheetMaterial';
import { HeaderFade } from '../../common/theme/HeaderFade';
import { HitaColors } from '../../common/theme/HitaColors';
import { NAV_BAR_INSET_FALLBACK } from '../../common/theme/StatusBarInset';
import { CourseControlHost } from '../timetable/views/CourseControlHost';
import { CourseModeSegment } from '../timetable/views/CourseModeSegment';
import { ImmersiveFollowButton } from './ImmersiveWidgetBackgroundControls';
import {
  WIDGET_BG_COMPACT_ASPECT,
  WIDGET_BG_DEFAULT_VEIL,
  WIDGET_BG_MAX_SCALE,
  WIDGET_BG_MAX_VEIL,
  WIDGET_CARD_CORNER_RADIUS,
  WIDGET_BG_WIDE_ASPECT,
  WidgetBackgroundFrame,
  WidgetBackgroundModel,
  WidgetBackgroundPlacement,
  WidgetBackgroundState
} from './WidgetBackgroundModel';
import { WidgetBackgroundStore } from './WidgetBackgroundStore';
import { NextClassWidgetService } from './NextClassWidgetService';

const HEADER_HEIGHT: number = 60;
const PAGE_BG: ResourceColor = $r('app.color.hita_page_f6f7fa');
const CARD_BG: ResourceColor = $r('app.color.hita_surface');
const TEXT_PRIMARY: ResourceColor = $r('app.color.hita_text');
const TEXT_SECONDARY: ResourceColor = $r('app.color.hita_text_secondary');
const SIZE_COMPACT: number = 2;
const SIZE_WIDE: number = 3;
const COMPACT_PREVIEW_MAX: number = 260;
const WIDE_PREVIEW_MAX: number = 560;
// 实测卡片高度约 146 vp；预览的圆角和示例文字按此比例缩放。
const CARD_NOMINAL_HEIGHT: number = 146;

@Component
export struct WidgetBackgroundPage {
  @StorageProp('hita_nav_bar_vp') navBarInset: number = NAV_BAR_INSET_FALLBACK;
  onBackgroundChanged: (enabled: boolean) => void = (_enabled: boolean) => {};
  onDirtyChanged: (dirty: boolean) => void = (_dirty: boolean) => {};
  onBusyChanged: (busy: boolean) => void = (_busy: boolean) => {};
  onConfirmDismissReady: (confirm: (dismiss: () => void, springBack: () => void) => void) => void =
    (_confirm: (dismiss: () => void, springBack: () => void) => void) => {};
  onClose: () => void = () => {};
  @State sourcePath: string = '';
  @State sourceUri: string = '';
  @State sourceWidth: number = 0;
  @State sourceHeight: number = 0;
  @State compactFrame: WidgetBackgroundFrame = WidgetBackgroundModel.coverFrame();
  @State wideFrame: WidgetBackgroundFrame = WidgetBackgroundModel.coverFrame();
  @State veil: number = WIDGET_BG_DEFAULT_VEIL;
  @State activeSize: number = SIZE_COMPACT;
  @State contentWidth: number = 328;
  @State cardCornerRadius: number = WIDGET_CARD_CORNER_RADIUS;
  @State adjustmentsFadeOpacity: number = 0;
  @State hasSaved: boolean = false;
  @State dirty: boolean = false;
  @State busy: boolean = false;
  // A pressed immersive control lifts its row so the enlarged material is not painted over.
  @State sizeControlPressing: boolean = false;
  private leaving: boolean = false;
  private confirmingLeave: boolean = false;
  private adjustmentsScroller: Scroller = new Scroller();
  private panStart: WidgetBackgroundFrame = new WidgetBackgroundFrame();
  private pinchStart: WidgetBackgroundFrame = new WidgetBackgroundFrame();
  private pinchStartX: number = 0;
  private pinchStartY: number = 0;
  private pinching: boolean = false;
  private panOriginX: number = 0;
  private panOriginY: number = 0;
  private panLastX: number = 0;
  private panLastY: number = 0;

  aboutToAppear(): void {
    this.onConfirmDismissReady((dismiss: () => void, springBack: () => void) =>
      this.confirmLeave(dismiss, springBack));
    const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
    try {
      const systemRadius: number = ctx.resourceManager.getNumberByName('ohos_id_corner_radius_card');
      if (Number.isFinite(systemRadius) && systemRadius > 0) {
        this.cardCornerRadius = systemRadius;
      }
    } catch (_) {
      this.cardCornerRadius = WIDGET_CARD_CORNER_RADIUS;
    }
    const state: WidgetBackgroundState | undefined = WidgetBackgroundStore.load(ctx);
    if (state === undefined) {
      return;
    }
    this.hasSaved = true;
    this.sourcePath = WidgetBackgroundStore.sourcePath(ctx, state);
    this.sourceUri = WidgetBackgroundStore.displayUri(this.sourcePath);
    this.sourceWidth = state.sourceWidth;
    this.sourceHeight = state.sourceHeight;
    this.compactFrame = state.compact;
    this.wideFrame = state.wide;
    this.veil = state.veil;
  }

  aboutToDisappear(): void {
    WidgetBackgroundStore.clearDrafts(this.getUIContext().getHostContext() as common.Context);
  }

  private goBack(): void {
    if (this.busy) {
      return;
    }
    if (this.dirty && !this.leaving) {
      this.confirmLeave();
      return;
    }
    this.leaving = true;
    this.onClose();
  }

  private confirmLeave(dismiss: () => void = () => this.onClose(), springBack: () => void = () => {}): void {
    if (this.busy || this.leaving) {
      springBack();
      return;
    }
    if (this.confirmingLeave) {
      springBack();
      return;
    }
    this.confirmingLeave = true;
    this.getUIContext().getPromptAction().showDialog({
      title: '放弃未保存的背景？',
      message: '当前取景和蒙版调整还没有应用到桌面卡片。',
      buttons: [
        { text: '继续编辑', color: $r('app.color.hita_text_secondary_7b8190') },
        { text: '放弃', color: HitaColors.error }
      ]
    }).then((ret) => {
      this.confirmingLeave = false;
      if (ret.index === 1) {
        this.leaving = true;
        setTimeout(() => dismiss(), 0);
      } else {
        springBack();
      }
    }).catch(() => {
      this.confirmingLeave = false;
      springBack();
    });
  }

  private markDirty(): void {
    if (this.dirty) {
      return;
    }
    this.dirty = true;
    this.onDirtyChanged(true);
  }

  private markClean(): void {
    this.dirty = false;
    this.onDirtyChanged(false);
  }

  private frameWidth(): number {
    if (this.activeSize === SIZE_WIDE) {
      return Math.min(this.contentWidth, WIDE_PREVIEW_MAX);
    }
    return Math.min(this.contentWidth * 0.72, COMPACT_PREVIEW_MAX);
  }

  private activeSizeIndex(): number {
    return this.activeSize === SIZE_WIDE ? 1 : 0;
  }

  private selectSize(index: number): void {
    this.activeSize = index === 1 ? SIZE_WIDE : SIZE_COMPACT;
  }

  private usesApi26ImmersiveControls(): boolean {
    return deviceInfo.apiAvailable('26.0.0') && !deviceInfo.apiAvailable('27.0.0');
  }

  private frameHeight(): number {
    return this.frameWidth() / (this.activeSize === SIZE_WIDE ? WIDGET_BG_WIDE_ASPECT : WIDGET_BG_COMPACT_ASPECT);
  }

  private previewAreaHeight(): number {
    const compact: number = Math.min(this.contentWidth * 0.72, COMPACT_PREVIEW_MAX) / WIDGET_BG_COMPACT_ASPECT;
    const wide: number = Math.min(this.contentWidth, WIDE_PREVIEW_MAX) / WIDGET_BG_WIDE_ASPECT;
    return Math.max(compact, wide) + 24;
  }

  /** 示例文字按实际卡片高度等比缩放，便于判断图片主体是否被文字遮挡。 */
  private mockScale(): number {
    return this.frameHeight() / CARD_NOMINAL_HEIGHT;
  }

  private currentFrame(): WidgetBackgroundFrame {
    return this.activeSize === SIZE_WIDE ? this.wideFrame : this.compactFrame;
  }

  private setFrame(frame: WidgetBackgroundFrame): void {
    if (this.activeSize === SIZE_WIDE) {
      this.wideFrame = frame;
    } else {
      this.compactFrame = frame;
    }
    this.markDirty();
  }

  private placement(): WidgetBackgroundPlacement {
    return WidgetBackgroundModel.place(this.currentFrame(), this.sourceWidth, this.sourceHeight,
      this.frameWidth(), this.frameHeight());
  }

  private minScale(): number {
    return WidgetBackgroundModel.minScale(this.sourceWidth, this.sourceHeight, this.frameWidth(), this.frameHeight());
  }

  private onPanStart(event: GestureEvent): void {
    this.panStart = this.currentFrame();
    this.panOriginX = event.offsetX;
    this.panOriginY = event.offsetY;
    this.panLastX = event.offsetX;
    this.panLastY = event.offsetY;
  }

  private onPanUpdate(event: GestureEvent): void {
    this.panLastX = event.offsetX;
    this.panLastY = event.offsetY;
    // 双指时位置由缩放手势统一计算，避免两种手势同时移动图片。
    if (this.pinching) {
      return;
    }
    this.setFrame(WidgetBackgroundModel.pan(this.panStart, event.offsetX - this.panOriginX,
      event.offsetY - this.panOriginY, this.sourceWidth, this.sourceHeight, this.frameWidth(), this.frameHeight()));
  }

  private onPinchStart(event: GestureEvent): void {
    this.pinching = true;
    this.pinchStart = this.currentFrame();
    this.pinchStartX = event.pinchCenterX;
    this.pinchStartY = event.pinchCenterY;
  }

  private onPinchUpdate(event: GestureEvent): void {
    this.setFrame(WidgetBackgroundModel.zoom(this.pinchStart, event.scale, this.pinchStartX, this.pinchStartY,
      event.pinchCenterX, event.pinchCenterY, this.sourceWidth, this.sourceHeight,
      this.frameWidth(), this.frameHeight()));
  }

  private onPinchEnd(): void {
    this.pinching = false;
    // 抬起一指后继续单指拖动时，从当前位置接着移动。
    this.panStart = this.currentFrame();
    this.panOriginX = this.panLastX;
    this.panOriginY = this.panLastY;
  }

  private async pickImage(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.onBusyChanged(true);
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const draft = await WidgetBackgroundStore.pickDraft(ctx);
      if (draft === undefined) {
        return;
      }
      this.sourcePath = draft.path;
      this.sourceUri = WidgetBackgroundStore.displayUri(draft.path);
      this.sourceWidth = draft.width;
      this.sourceHeight = draft.height;
      this.compactFrame = WidgetBackgroundModel.coverFrame();
      this.wideFrame = WidgetBackgroundModel.coverFrame();
      this.markDirty();
    } catch (_) {
      this.getUIContext().getPromptAction().showToast({ message: '无法读取这张图片，请换一张试试' });
    } finally {
      this.busy = false;
      this.onBusyChanged(false);
    }
  }

  private async save(): Promise<void> {
    if (this.busy || this.sourcePath.length === 0) {
      return;
    }
    this.busy = true;
    this.onBusyChanged(true);
    try {
      const ctx = this.getUIContext().getHostContext() as common.Context;
      await WidgetBackgroundStore.save(ctx, this.sourcePath, this.sourceWidth, this.sourceHeight,
        this.compactFrame, this.wideFrame, this.veil);
      this.markClean();
      this.onBackgroundChanged(true);
      this.leaving = true;
      NextClassWidgetService.scheduleRefresh();
      this.getUIContext().getPromptAction().showToast({ message: '已应用到桌面服务卡片' });
      this.onClose();
    } catch (_) {
      this.getUIContext().getPromptAction().showToast({ message: '保存失败，请重试' });
    } finally {
      this.busy = false;
      this.onBusyChanged(false);
    }
  }

  private confirmRemove(): void {
    if (this.busy) {
      return;
    }
    this.getUIContext().getPromptAction().showDialog({
      title: '移除卡片背景',
      message: '桌面服务卡片将恢复默认白色背景。',
      buttons: [
        { text: '取消', color: $r('app.color.hita_text_secondary_7b8190') },
        { text: '移除', color: HitaColors.error }
      ]
    }).then((ret) => {
      if (ret.index !== 1) {
        return;
      }
      setTimeout(() => {
        WidgetBackgroundStore.remove(this.getUIContext().getHostContext() as common.Context);
        NextClassWidgetService.scheduleRefresh();
        this.markClean();
        this.onBackgroundChanged(false);
        this.leaving = true;
        this.getUIContext().getPromptAction().showToast({ message: '已恢复默认背景' });
        this.onClose();
      }, 0);
    }).catch(() => {
    });
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Column() {
        if (this.sourceUri.length === 0) {
          this.emptyState()
        } else {
          this.editor()
        }
      }
      .width('100%')
      .height('100%')
      .padding({ top: HEADER_HEIGHT })
      .onAreaChange((_old: Area, area: Area) => {
        const width: number = Number(area.width) - 32;
        if (width > 0 && Math.abs(width - this.contentWidth) > 0.5) {
          this.contentWidth = width;
        }
      })

      ImmersiveHeader({ barHeight: HEADER_HEIGHT }) {
        Row() {
          HeaderBackButton({ onBack: () => this.goBack() })
            .margin({ right: 12 })
          Text('自定义背景')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(TEXT_PRIMARY)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.sourceUri.length > 0) {
            Text(this.busy ? '处理中' : '保存')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(CompatibleMaterialModifier.foreground($r('app.color.hita_primary_3390ec')))
              .height(32)
              .padding({ left: 12, right: 12 })
              .borderRadius(16)
              .backgroundColor($r('app.color.hita_selected_ebf4fc'))
              .attributeModifier(new CompatibleMaterialModifier($r('app.color.hita_selected_ebf4fc')))
              .textAlign(TextAlign.Center)
              .flexShrink(0)
              .opacity(this.dirty && !this.busy ? 1 : 0.5)
              .enabled(this.dirty && !this.busy)
              .accessibilityText('保存并应用到桌面服务卡片')
              .onClick(() => { void this.save(); })
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
    .backgroundColor(CompatibleSheetMaterial.bodyColor(PAGE_BG))
    .attributeModifier(new CompatibleLightModifier(24, CompatibleSheetMaterial.isEnabled(), true))
  }

  @Builder
  emptyState() {
    Column({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.picture'))
        .fontSize(40)
        .fontColor([HitaColors.primary])
      Text('选择背景图')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(TEXT_PRIMARY)
      if (this.usesApi26ImmersiveControls()) {
        // API 26 renders the button material only inside the native title host the course editor uses.
        Column() {
          CourseControlHost({ barHeight: 40 }) {
            ImmersiveFollowButton({
              label: this.busy ? '正在读取…' : '从图库选择',
              isEnabled: !this.busy,
              primary: true,
              fill: false,
              onPress: () => { void this.pickImage(); }
            })
          }
        }
        .margin({ top: 8 })
        .clip(false)
      } else {
        Button(this.busy ? '正在读取…' : '从图库选择')
          .height(40)
          .padding({ left: 24, right: 24 })
          .fontSize(14)
          .fontColor(Color.White)
          .backgroundColor(HitaColors.primary)
          .enabled(!this.busy)
          .margin({ top: 8 })
          .onClick(() => { void this.pickImage(); })
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 32, bottom: 32 })
    .margin({ top: 12 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  editor() {
    Column() {
      this.sizeSelector()

      Column() {
        this.previewFrame()
      }
      .width('100%')
      // 两种尺寸共用同一高度，切换时下方控件不跳动。
      .height(this.previewAreaHeight())
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .padding({ left: 16, right: 16 })

    Stack({ alignContent: Alignment.Top }) {
      Scroll(this.adjustmentsScroller) {
        Column() {
          this.adjustments()
          Blank().height(this.navBarInset + 20)
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .onDidScroll(() => {
        this.adjustmentsFadeOpacity = HeaderFade.opacity(this.adjustmentsScroller.currentOffset().yOffset);
      })

      HeaderFadeMask({ maskOpacity: this.adjustmentsFadeOpacity, rgb: '246,247,250' })
        .align(Alignment.Top)
    }
    .width('100%')
    .layoutWeight(1)
    .margin({ top: 12 })
  }

  @Builder
  sizeSelector() {
    // Same control as the course editor's 具体时间/按节次 segment, including its API 26 material host.
    Column() {
      CourseModeSegment({
        labels: ['2×2 卡片', '2×4 卡片'],
        selectedIndex: this.activeSizeIndex(),
        onSelect: (index: number) => this.selectSize(index),
        onControlPressingChanged: (pressing: boolean) => { this.sizeControlPressing = pressing; }
      })
    }
    .width('100%')
    .margin({ top: 8 })
    .clip(false)
    .zIndex(this.sizeControlPressing ? 3 : 1)
  }

  @Builder
  previewFrame() {
    Stack({ alignContent: Alignment.TopStart }) {
      Image(this.sourceUri)
        .width(this.placement().width)
        .height(this.placement().height)
        .position({ x: this.placement().left, y: this.placement().top })
        .objectFit(ImageFit.Fill)
        .autoResize(false)
        .interpolation(ImageInterpolation.High)
        .draggable(false)
      // 与烘焙时的白色蒙版相同。
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.White)
        .opacity(this.veil / 100)
      this.cardMock()
    }
    .width(this.frameWidth())
    .height(this.frameHeight())
    .backgroundColor(Color.White)
    // Match the live service card's system radius directly; unlike mock content sizing,
    // the system card corner radius is not proportional to the preview's content scale.
    .borderRadius(this.cardCornerRadius)
    .clip(true)
    .shadow({ radius: 12, color: '#1F000000', offsetY: 2 })
    .gesture(
      GestureGroup(GestureMode.Parallel,
        PanGesture({ fingers: 1, distance: 1 })
          .onActionStart((event: GestureEvent) => this.onPanStart(event))
          .onActionUpdate((event: GestureEvent) => this.onPanUpdate(event)),
        PinchGesture({ fingers: 2 })
          .onActionStart((event: GestureEvent) => this.onPinchStart(event))
          .onActionUpdate((event: GestureEvent) => this.onPinchUpdate(event))
          .onActionEnd(() => this.onPinchEnd())
          .onActionCancel(() => this.onPinchEnd())
      )
    )
    .accessibilityText(this.activeSize === SIZE_WIDE ? '2×4 卡片背景取景' : '2×2 卡片背景取景')
    .accessibilityDescription('拖动调整位置，双指缩放。也可以使用下方的缩放滑杆')
  }

  /** 与 NextClassCard 布局相近的示例内容，仅用于判断可读性，不参与烘焙。 */
  @Builder
  cardMock() {
    Column() {
      Row({ space: 6 * this.mockScale() }) {
        Image($r('app.media.app_icon'))
          .width(16 * this.mockScale())
          .height(16 * this.mockScale())
          .borderRadius(5 * this.mockScale())
        Text('HITA NEXT')
          .fontSize(10 * this.mockScale())
          .fontWeight(FontWeight.Medium)
          .fontColor('#515A67')
      }
      if (this.activeSize === SIZE_WIDE) {
        Row({ space: 14 * this.mockScale() }) {
          Column() {
            this.mockCountdown()
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          Column() {
            this.mockCourse()
          }
          .layoutWeight(1.2)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .layoutWeight(1)
      } else {
        Column() {
          this.mockCountdown()
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Start)
        this.mockCourse()
      }
    }
    .width('100%')
    .height('100%')
    .padding(12 * this.mockScale())
    .alignItems(HorizontalAlign.Start)
    .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  mockCountdown() {
    Text('15')
      .fontSize(24 * this.mockScale())
      .fontWeight(FontWeight.Bold)
      .fontColor('#182230')
    Text('分钟后上课')
      .fontSize(10 * this.mockScale())
      .fontColor('#515A67')
  }

  @Builder
  mockCourse() {
    Text('高等数学')
      .fontSize(14 * this.mockScale())
      .fontWeight(FontWeight.Bold)
      .fontColor('#182230')
    Text('正心楼 101 · 王老师')
      .fontSize(10 * this.mockScale())
      .fontColor('#515A67')
      .maxLines(1)
      .margin({ top: 3 * this.mockScale() })
    Text('今天 08:00')
      .fontSize(10 * this.mockScale())
      .fontColor('#515A67')
      .margin({ top: 3 * this.mockScale() })
  }

  @Builder
  adjustments() {
    Column() {
      Row() {
        Text('缩放')
          .fontSize(14)
          .fontColor(TEXT_PRIMARY)
          .layoutWeight(1)
        Text(Math.round(this.currentFrame().scale * 100).toString() + '%')
          .fontSize(13)
          .fontColor(TEXT_SECONDARY)
      }
      .width('100%')
      Slider({
        value: Math.round(this.currentFrame().scale * 100),
        min: Math.floor(this.minScale() * 100),
        max: WIDGET_BG_MAX_SCALE * 100,
        step: 1
      })
        .width('100%')
        .selectedColor(HitaColors.primary)
        .enabled(!this.busy)
        .accessibilityText('背景缩放')
        .onChange((value: number) => {
          this.setFrame(WidgetBackgroundModel.withScale(this.currentFrame(), value / 100,
            this.sourceWidth, this.sourceHeight, this.frameWidth(), this.frameHeight()));
        })
      // The Button spec spaces side-by-side buttons 12 vp apart.
      Row({ space: this.usesApi26ImmersiveControls() ? 12 : 8 }) {
        this.presetChip('铺满卡片', () => {
          this.setFrame(WidgetBackgroundModel.coverFrame());
        })
        this.presetChip('完整显示', () => {
          this.setFrame(WidgetBackgroundModel.containFrame(this.sourceWidth, this.sourceHeight,
            this.frameWidth(), this.frameHeight()));
        })
      }
      .width('100%')
      .margin({ top: 4 })
    }
    .width('100%')
    .padding(16)
    .backgroundColor(CARD_BG)
    .borderRadius(16)

    Column() {
      Row() {
        Text('白色蒙版')
          .fontSize(14)
          .fontColor(TEXT_PRIMARY)
          .layoutWeight(1)
        Text(this.veil.toString() + '%')
          .fontSize(13)
          .fontColor(TEXT_SECONDARY)
      }
      .width('100%')
      Slider({ value: this.veil, min: 0, max: WIDGET_BG_MAX_VEIL, step: 1 })
        .width('100%')
        .selectedColor(HitaColors.primary)
        .enabled(!this.busy)
        .accessibilityText('白色蒙版深度')

        .onChange((value: number) => {
          this.veil = Math.round(value);
          this.markDirty();
        })
    }
    .width('100%')
    .padding(16)
    .margin({ top: 12 })
    .backgroundColor(CARD_BG)
    .borderRadius(16)

    Column() {
      this.actionRow('更换图片', TEXT_PRIMARY, () => { void this.pickImage(); })
      if (this.hasSaved) {
        Divider()
          .color($r('app.color.hita_divider_eef1f6'))
          .margin({ left: 16, right: 16 })
        this.actionRow('移除背景', HitaColors.error, () => { this.confirmRemove(); })
      }
    }
    .width('100%')
    .margin({ top: 12 })
    .backgroundColor(CARD_BG)
    .borderRadius(16)
  }

  @Builder
  presetChip(label: string, action: () => void) {
    if (this.usesApi26ImmersiveControls()) {
      CourseControlHost({ barHeight: 40, itemWeight: 1 }) {
        ImmersiveFollowButton({ label: label, isEnabled: !this.busy, onPress: action })
      }
    } else {
      Text(label)
        .fontSize(13)
        .fontColor(HitaColors.primary)
        .textAlign(TextAlign.Center)
        .height(34)
        .layoutWeight(1)
        .borderRadius(10)
        .backgroundColor($r('app.color.hita_control'))
        .enabled(!this.busy)
        .onClick(action)
    }
  }

  @Builder
  actionRow(label: string, color: ResourceColor, action: () => void) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor(color)
        .layoutWeight(1)
      Text('›')
        .fontSize(20)
        .fontColor($r('app.color.hita_text_hint_b2b8c4'))
    }
    .width('100%')
    .height(48)
    .padding({ left: 16, right: 16 })
    .enabled(!this.busy)
    .onClick(action)
  }
}
