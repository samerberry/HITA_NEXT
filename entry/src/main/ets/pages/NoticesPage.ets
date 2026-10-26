import { HitaDesign } from '../common/theme/HitaDesign';
/**
 * NoticesPage.ets — 公告列表（Android AppNoticesActivity 同源）。
 *
 * 先渲染缓存，再拉取最新并刷新；仅展示生效中的公告（时间窗 + 版本范围），
 * critical 排前。空态“暂无公告”。
 */
import { common } from '@kit.AbilityKit';
import { HeaderBackButton } from '../common/components/HeaderBackButton';
import { ImmersiveHeader } from '../common/components/ImmersiveHeader';
import { HeaderFadeMask } from '../common/components/HeaderFadeMask';
import { HeaderFade } from '../common/theme/HeaderFade';
import { STATUS_BAR_INSET_FALLBACK } from '../common/theme/StatusBarInset';
import { AppNotice, AppNoticeCenter } from '../feature/notice/AppNoticeCenter';

const HEADER_HEIGHT: number = 60;
const PAGE_BG: ResourceColor = $r('app.color.hita_page_f6f7fa');
const PAGE_BG_RGB: string = '245,246,248';

@Entry
@Component
struct NoticesPage {
  @State notices: AppNotice[] = [];
  @State loading: boolean = true;
  @State fadeOpacity: number = 0;
  @StorageProp('hita_status_bar_vp') statusBarInset: number = STATUS_BAR_INSET_FALLBACK;
  private listScroller: Scroller = new Scroller();

  async aboutToAppear(): Promise<void> {
    const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
    try {
      this.notices = AppNoticeCenter.activeNotices(await AppNoticeCenter.cachedNotices(ctx));
    } catch (e) {
      this.notices = [];
    }
    // 有缓存时立即显示；没有缓存时保留加载态，避免把网络等待误报成空公告。
    this.loading = this.notices.length === 0;
    try {
      const fetched: AppNotice[] = await AppNoticeCenter.fetch(ctx);
      this.notices = AppNoticeCenter.activeNotices(fetched);
    } catch (e) {
      // fetch 内部会回落缓存；这里只兜底处理页面生命周期中的异常。
    } finally {
      this.loading = false;
    }
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      if (this.loading) {
        LoadingProgress()
          .width(32)
          .height(32)
          .color($r('app.color.hita_primary_3390ec'))
          .margin({ top: HEADER_HEIGHT + 80 })
      } else if (this.notices.length === 0) {
        Text('暂无公告')
          .fontSize(HitaDesign.caption)
          .fontColor($r('app.color.hita_text_secondary_5a6880'))
          .margin({ top: HEADER_HEIGHT + 60 })
      } else {
        this.noticeList()
      }

      // 与功能中心一致：内容滚入抬头下方时淡入，由下至上不透明度渐高，标题区完全遮住下层内容。
      HeaderFadeMask({ maskOpacity: this.fadeOpacity, rgb: PAGE_BG_RGB, headerHeight: HEADER_HEIGHT })

      ImmersiveHeader({ barHeight: HEADER_HEIGHT }) {
        Row() {
          HeaderBackButton({
            onBack: () => this.getUIContext().getRouter().back()
          })
            .margin({ right: 12 })
          Text('公告')
            .fontSize(HitaDesign.title)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.hita_text_1a1a1a'))
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
    .backgroundColor(PAGE_BG)
  }

  @Builder
  noticeList() {
    List({ space: 12, scroller: this.listScroller }) {
      // 让出抬头高度：列表从页面顶部开始，滚动时内容经过抬头下方。
      ListItem() {
        Column()
          .width('100%')
          .height(HEADER_HEIGHT)
      }

      ForEach(this.notices, (notice: AppNotice) => {
        ListItem() {
          Column() {
            Row() {
              Text(notice.title)
                .fontSize(HitaDesign.body)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.hita_text_1a1a1a'))
                .layoutWeight(1)
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              if (notice.isCritical()) {
                Text('重要')
                  .fontSize(HitaDesign.label)
                  .fontColor($r('app.color.hita_error'))
                  .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                  .backgroundColor($r('app.color.hita_surface'))
                  .borderRadius(10)
              }
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)

            Text(notice.body)
              .fontSize(HitaDesign.caption)
              .lineHeight(20)
              .fontColor(notice.isCritical() ? $r('app.color.hita_error_8c3a3a') : $r('app.color.hita_text_secondary_566276'))
              .width('100%')
              .margin({ top: 8 })
          }
          .width('100%')
          .padding(16)
          .backgroundColor(notice.isCritical() ? $r('app.color.hita_error_surface_fdecec') : $r('app.color.hita_surface'))
          .borderRadius(16)
        }
      }, (notice: AppNotice) => notice.id)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, bottom: 16 })
    .scrollBar(BarState.Off)
    .onDidScroll(() => {
      this.fadeOpacity = HeaderFade.opacity(this.listScroller.currentOffset().yOffset);
    })
  }
}
