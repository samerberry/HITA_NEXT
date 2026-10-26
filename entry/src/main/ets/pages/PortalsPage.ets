import { HitaDesign } from '../common/theme/HitaDesign';
import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { HeaderBackButton } from '../common/components/HeaderBackButton';
import { ImmersiveHeader } from '../common/components/ImmersiveHeader';
import { HeaderFadeMask } from '../common/components/HeaderFadeMask';
import { HeaderFade } from '../common/theme/HeaderFade';
import { NAV_BAR_INSET_FALLBACK, STATUS_BAR_INSET_FALLBACK } from '../common/theme/StatusBarInset';
import { CampusPortal, CampusPortalGroup } from '../feature/portal/CampusPortal';
import { EasCampus } from '../feature/eas/EasSession';
import { EasSessionStore, EAS_SESSION_REVISION_KEY } from '../feature/eas/EasSessionStore';

const HEADER_HEIGHT: number = 60;
const PAGE_BG: ResourceColor = $r('app.color.hita_page');
const PAGE_BG_RGB: string = '245,246,248';
const COLOR_PRIMARY: ResourceColor = $r('app.color.hita_primary');
const COLOR_TEXT_PRIMARY: ResourceColor = $r('app.color.hita_text');
const COLOR_TEXT_SECONDARY: ResourceColor = $r('app.color.hita_text_secondary');

@Entry
@Component
struct PortalsPage {
  @State fadeOpacity: number = 0;
  @State groups: CampusPortalGroup[] = [];
  @State campus: EasCampus | undefined = undefined;
  @State loading: boolean = true;
  @StorageProp(EAS_SESSION_REVISION_KEY) @Watch('onSessionChanged') sessionRevision: number = 0;
  @StorageProp('hita_status_bar_vp') statusBarInset: number = STATUS_BAR_INSET_FALLBACK;
  @StorageProp('hita_nav_bar_vp') navBarInset: number = NAV_BAR_INSET_FALLBACK;
  private listScroller: Scroller = new Scroller();
  private generation: number = 0;
  private pageVisible: boolean = false;

  aboutToAppear(): void {
    this.pageVisible = true;
    this.reload();
  }

  onPageShow(): void {
    if (!this.pageVisible) {
      this.pageVisible = true;
      this.reload();
    }
  }

  onPageHide(): void {
    this.pageVisible = false;
    this.generation++;
  }

  aboutToDisappear(): void {
    this.onPageHide();
  }

  private onSessionChanged(): void {
    if (this.pageVisible) this.reload();
  }

  private async reload(): Promise<void> {
    const generation: number = ++this.generation;
    const store: EasSessionStore = EasSessionStore.getInstance();
    let campus: EasCampus | undefined = undefined;
    try {
      await store.init(this.getUIContext().getHostContext() as common.Context);
      // Public links follow the selected local account, including an expired session.
      campus = (await store.loadPreferred())?.campus;
    } catch (_) {}
    if (generation !== this.generation || !this.pageVisible) return;
    if (this.campus !== campus) {
      this.fadeOpacity = 0;
      if (this.groups.length > 0) this.listScroller.scrollEdge(Edge.Top);
    }
    this.campus = campus;
    this.groups = CampusPortal.groupsFor(campus);
    this.loading = false;
  }

  private async open(portal: CampusPortal): Promise<void> {
    try {
      await this.getUIContext().getRouter().pushUrl({
        url: 'pages/WebBrowserPage',
        params: { 'url': portal.url, 'title': portal.title }
      });
    } catch (_) {
      await this.copy(portal);
    }
  }

  private async copy(portal: CampusPortal): Promise<void> {
    try {
      await pasteboard.getSystemPasteboard().setData(
        pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, portal.url));
    } catch (_) {
      if (this.pageVisible) {
        this.getUIContext().getPromptAction().showToast({ message: '复制失败，请重试' });
      }
      return;
    }
    if (this.pageVisible) {
      this.getUIContext().getPromptAction().showToast({ message: '已复制链接' });
    }
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      if (this.loading) {
        LoadingProgress().width(32).height(32).color(COLOR_PRIMARY)
          .margin({ top: HEADER_HEIGHT + 60 });
      } else if (this.groups.length === 0) {
        Column() {
          Text('请先登录教务系统')
            .fontSize(HitaDesign.body)
            .fontColor(COLOR_TEXT_SECONDARY);
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center);
      } else {
        this.portalList();
      }

      HeaderFadeMask({ maskOpacity: this.fadeOpacity, rgb: PAGE_BG_RGB, headerHeight: HEADER_HEIGHT });

      ImmersiveHeader({ barHeight: HEADER_HEIGHT }) {
        Row() {
          HeaderBackButton({
            onBack: () => this.getUIContext().getRouter().back()
          })
            .margin({ right: 12 });
          Text('常用入口')
            .fontSize(HitaDesign.title)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLOR_TEXT_PRIMARY)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
          if (this.campus !== undefined) {
            Text(CampusPortal.campusName(this.campus))
              .fontSize(HitaDesign.caption)
              .fontColor(COLOR_TEXT_SECONDARY)
              .margin({ left: 12 });
          }
        }
        .width('100%')
        .height(HEADER_HEIGHT)
        .padding({ left: 16, right: 16 })
        .alignItems(VerticalAlign.Center)
        .hitTestBehavior(HitTestMode.Transparent);
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.statusBarInset })
    .backgroundColor(PAGE_BG)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM]);
  }

  @Builder
  portalList() {
    List({ space: 10, scroller: this.listScroller }) {
      ListItem() {
        Column().width('100%').height(HEADER_HEIGHT);
      }
      ForEach(this.groups, (group: CampusPortalGroup) => {
        ListItemGroup({ header: this.groupHeader(group.title), space: 10 }) {
          ForEach(group.portals, (portal: CampusPortal) => {
            ListItem() {
              this.portalRow(portal);
            }
          }, (portal: CampusPortal) => portal.url);
        }
      }, (group: CampusPortalGroup) => (this.campus ?? '') + ':' + group.title);
      ListItem() {
        Column().height(12 + this.navBarInset);
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16 })
    .scrollBar(BarState.Off)
    .onDidScroll(() => {
      this.fadeOpacity = HeaderFade.opacity(this.listScroller.currentOffset().yOffset);
    });
  }

  @Builder
  groupHeader(title: string) {
    Text(title)
      .fontSize(HitaDesign.body)
      .fontWeight(FontWeight.Medium)
      .fontColor(COLOR_TEXT_PRIMARY)
      .width('100%')
      .padding({ top: 8, bottom: 12 });
  }

  @Builder
  portalRow(portal: CampusPortal) {
    Row() {
      Stack() {
        SymbolGlyph(portal.icon)
          .fontSize(20)
          .fontColor([COLOR_PRIMARY]);
      }
      .width(40)
      .height(40)
      .flexShrink(0)
      .borderRadius(HitaDesign.cardRadius)
      .backgroundColor($r('app.color.hita_selected'))
      .alignContent(Alignment.Center);
      Column() {
        Text(portal.title)
          .fontSize(HitaDesign.body)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(portal.url)
          .fontSize(HitaDesign.label)
          .fontColor(COLOR_TEXT_SECONDARY)
          .margin({ top: 4 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12, right: 12 });
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(HitaDesign.body)
        .fontColor([COLOR_TEXT_SECONDARY])
        .flexShrink(0);
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor($r('app.color.hita_surface'))
    .borderRadius(16)
    .accessibilityText(portal.title + '，' + portal.url)
    .gesture(
      GestureGroup(GestureMode.Exclusive,
        LongPressGesture({ repeat: false }).onAction(() => { this.copy(portal); }),
        TapGesture().onAction(() => { this.open(portal); })
      )
    );
  }
}
