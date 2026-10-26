import { HitaDesign } from '../common/theme/HitaDesign';
/**
 * NewsPage.ets — 功能中心「资讯」：博客与通知。
 */
import { common } from '@kit.AbilityKit';
import { HeaderBackButton } from '../common/components/HeaderBackButton';
import { deviceInfo } from '@kit.BasicServicesKit';
import lazy { ImmersiveNewsLayout } from '../common/components/ImmersiveNewsLayout';
import lazy { ImmersiveNewsTabs } from '../common/components/ImmersiveNewsTabs';
import { CompatibleMaterialModifier } from '../common/theme/CompatibleMaterialModifier';
import { HeaderFadeMask } from '../common/components/HeaderFadeMask';
import { HeaderFade } from '../common/theme/HeaderFade';
import { NAV_BAR_INSET_FALLBACK, STATUS_BAR_INSET_FALLBACK } from '../common/theme/StatusBarInset';
import { NewsCategory, NewsItem, NewsPage as NewsPageResult, NewsService } from '../feature/news/NewsService';
import { NewsPresentation, NewsRowModel } from '../feature/news/NewsPresentation';
import { EasCampus } from '../feature/eas/EasSession';
import { EasSessionStore } from '../feature/eas/EasSessionStore';

const COLOR_PRIMARY: ResourceColor = $r('app.color.hita_primary');
const SURFACE_RGB: string = '245,246,248';
const COLOR_CARD: ResourceColor = $r('app.color.hita_surface');
const COLOR_TEXT_PRIMARY: ResourceColor = $r('app.color.hita_text');
const COLOR_TEXT_SECONDARY: ResourceColor = $r('app.color.hita_text_secondary');
const COLOR_TEXT_HINT: ResourceColor = $r('app.color.hita_text_secondary_5a6880');
const COLOR_NAV_ACTIVE: ResourceColor = $r('app.color.hita_selected');
const COLOR_TAG_BG: ResourceColor = $r('app.color.hita_text_secondary_808080');
const COLOR_TAG_TEXT: ResourceColor = $r('app.color.hita_surface');
const AVATAR_SIZE: number = 46;

@Entry
@Component
struct NewsPage {
  @State selected: number = 0;
  @State items: NewsItem[] = [];
  @State loading: boolean = false;
  @State refreshing: boolean = false;
  @State hasMore: boolean = true;
  @State message: string = '';
  @State sourceUrl: string = '';
  @State fadeOpacity: number = 0;
  @StorageProp('hita_status_bar_vp') statusBarInset: number = STATUS_BAR_INSET_FALLBACK;
  @StorageProp('hita_nav_bar_vp') navBarInset: number = NAV_BAR_INSET_FALLBACK;
  private page: number = 0;
  private generation: number = 0;
  private campus: EasCampus = EasCampus.BENBU;
  private returningFromSource: boolean = false;
  private newsScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.reload();
  }

  aboutToDisappear(): void {
    this.generation++;
  }

  onPageShow(): void {
    if (this.returningFromSource) {
      this.returningFromSource = false;
      this.reload();
    }
  }

  private selectTab(index: number): void {
    if (index < 0 || index >= NewsService.CATEGORIES.length || this.selected === index) {
      return;
    }
    this.selected = index;
    this.fadeOpacity = 0;
    this.newsScroller.scrollEdge(Edge.Top);
    this.reload();
  }

  private async reload(): Promise<void> {
    this.generation++;
    this.page = 0;
    this.items = [];
    this.fadeOpacity = 0;
    this.hasMore = true;
    this.message = '';
    this.sourceUrl = '';
    this.loading = true;
    const generation: number = this.generation;
    if (NewsService.CATEGORIES[this.selected].id === '10') {
      const store: EasSessionStore = EasSessionStore.getInstance();
      await store.init(this.getUIContext().getHostContext() as common.Context);
      // Public notices follow the last login selection even after its EAS session expires.
      const campus: EasCampus | undefined = await store.loadLastCampus();
      if (generation !== this.generation) { return; }
      this.campus = campus === undefined ? EasCampus.BENBU : campus;
    }
    await this.loadPage();
    if (generation === this.generation) {
      this.refreshing = false;
    }
  }

  private async loadPage(): Promise<void> {
    if (this.loading && this.page > 0) {
      return;
    }
    const generation: number = this.generation;
    const category: NewsCategory = NewsService.CATEGORIES[this.selected];
    this.loading = true;
    const result: NewsPageResult = await NewsService.fetchCategory(category.id, this.page, this.campus);
    if (generation !== this.generation) {
      return;
    }
    this.loading = false;
    this.sourceUrl = result.sourceUrl;
    if (!result.ok) {
      this.message = result.message;
      this.hasMore = false;
      return;
    }
    const known: Set<string> = new Set<string>(this.items.map((item: NewsItem): string => item.url));
    const fresh: NewsItem[] = result.items.filter((item: NewsItem): boolean => !known.has(item.url));
    this.items = this.items.concat(fresh);
    this.hasMore = result.hasMore && fresh.length > 0;
    this.page++;
    this.message = this.items.length === 0 ? (result.message.length > 0 ? result.message : '暂无资讯') : '';
  }

  private open(url: string, title: string): void {
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/WebBrowserPage',
      params: { 'url': url, 'title': title }
    });
  }

  private openSource(): void {
    this.returningFromSource = true;
    this.open(this.sourceUrl, '校区通知');
  }

  build() {
    Column() {
      if (deviceInfo.apiAvailable('26.0.0')) {
        ImmersiveNewsLayout({
          titleHeight: 60 + this.statusBarInset,
          header: () => { this.headerContent(); },
          dock: () => { this.dockContent(); },
          content: () => { this.newsList(); }
        });
      } else {
        this.headerContent();
        this.dockContent();
        this.newsList();
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.hita_page'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM]);
  }

  @Builder
  headerContent() {
    Row() {
      HeaderBackButton({
        onBack: () => this.getUIContext().getRouter().back()
      })
        .margin({ right: 12 });
      Column() {
        Text('资讯')
          .fontSize(HitaDesign.title)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT_PRIMARY);
        Text('博客与通知')
          .fontSize(HitaDesign.label)
          .fontColor(COLOR_TEXT_SECONDARY)
          .margin({ top: 2 });
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start);
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.arrow_clockwise'))
          .fontSize(HitaDesign.section)
          .fontColor([CompatibleMaterialModifier.foreground(COLOR_PRIMARY)]);
      }
      .width(40)
      .height(40)
      .backgroundColor(COLOR_NAV_ACTIVE)
      .attributeModifier(new CompatibleMaterialModifier(COLOR_NAV_ACTIVE))
      .enabled(!this.loading)
      .accessibilityText('刷新')
      .onClick(() => {
        this.reload();
      });
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8 + this.statusBarInset, bottom: 8 })
    .alignItems(VerticalAlign.Center);
  }

  @Builder
  dockContent() {
    Column() {
      if (deviceInfo.apiAvailable('26.0.0')) {
        ImmersiveNewsTabs({
          selectedIndex: this.selected,
          onSelect: (index: number) => { this.selectTab(index); }
        });
      } else {
        Row({ space: 4 }) {
          ForEach(NewsService.CATEGORIES, (category: NewsCategory, index: number) => {
            this.segment(category.name, index);
          }, (category: NewsCategory) => category.id);
        }
        .width('100%')
        .padding(4)
        .backgroundColor($r('app.color.hita_control_eaf0f7'))
        .borderRadius(16);
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 16, right: 16, bottom: 8 });
  }

  @Builder
  segment(label: string, index: number) {
    Text(label)
      .fontSize(HitaDesign.caption)
      .fontWeight(this.selected === index ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.selected === index ? COLOR_TEXT_PRIMARY : COLOR_TEXT_SECONDARY)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(36)
      .borderRadius(12)
      .backgroundColor(this.selected === index ? COLOR_CARD : 'transparent')
      .onClick(() => {
        this.selectTab(index);
      });
  }

  @Builder
  newsList() {
    Stack({ alignContent: Alignment.Top }) {
      Refresh({ refreshing: $$this.refreshing }) {
        List({ scroller: this.newsScroller }) {
          if (deviceInfo.apiAvailable('26.0.0')) {
            ListItem() {
              Column().height(112 + this.statusBarInset);
            }
          }
          // One shared surface: the first and last rows round its corners.
          ForEach(this.items, (item: NewsItem, index: number) => {
            ListItem() {
              this.newsRow(item, this.rowModel(item), index === this.items.length - 1);
            }
            .backgroundColor(COLOR_CARD)
            .borderRadius({
              topLeft: index === 0 ? 20 : 0, topRight: index === 0 ? 20 : 0,
              bottomLeft: index === this.items.length - 1 ? 20 : 0,
              bottomRight: index === this.items.length - 1 ? 20 : 0
            })
            .clip(true);
          }, (item: NewsItem, index: number) => item.url + (index === this.items.length - 1 ? '#last' : '') +
            (index === 0 ? '#first' : ''));
          ListItem() {
            this.listFooter();
          }
          ListItem() {
            Column().height(12 + this.navBarInset);
          }
        }
        .width('100%')
        .height('100%')
        .padding({ left: 16, right: 16 })
        .scrollBar(BarState.Off)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
        .onDidScroll(() => {
          this.fadeOpacity = HeaderFade.opacity(this.newsScroller.currentOffset().yOffset);
        })
        .onReachEnd(() => {
          if (this.hasMore && !this.loading && this.items.length > 0) {
            this.loadPage();
          }
        });
      }
      .width('100%')
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .onRefreshing(() => {
        this.reload();
      });

      if (!deviceInfo.apiAvailable('26.0.0')) {
        HeaderFadeMask({ maskOpacity: this.fadeOpacity, rgb: SURFACE_RGB });
      }
    }
    .width('100%')
    .layoutWeight(1)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM]);
  }

  @Builder
  listFooter() {
    Column() {
      if (this.loading) {
        Row({ space: 8 }) {
          LoadingProgress()
            .width(20)
            .height(20)
            .color(COLOR_PRIMARY);
          Text(this.items.length === 0 ? '正在加载资讯…' : '正在加载更多…')
            .fontSize(HitaDesign.caption)
            .fontColor(COLOR_TEXT_HINT);
        }
      } else if (this.message.length > 0) {
        Text(this.message)
          .fontSize(HitaDesign.caption)
          .fontColor(COLOR_TEXT_HINT);
        Button('重试')
          .fontSize(HitaDesign.caption)
          .height(36)
          .fontColor(COLOR_PRIMARY)
          .backgroundColor(COLOR_NAV_ACTIVE)
          .borderRadius(HitaDesign.cardRadius)
          .margin({ top: 10 })
          .onClick(() => {
            this.reload();
          });
        if (this.sourceUrl.length > 0) {
          Button('打开通知网站')
            .fontSize(HitaDesign.caption)
            .height(36)
            .fontColor(COLOR_PRIMARY)
            .backgroundColor(COLOR_NAV_ACTIVE)
            .borderRadius(HitaDesign.cardRadius)
            .margin({ top: 10 })
            .onClick(() => {
              this.openSource();
            });
        }
      } else if (!this.hasMore && this.items.length > 0) {
        Text('没有更多了')
          .fontSize(HitaDesign.label)
          .fontColor(COLOR_TEXT_HINT);
      }
    }
    .width('100%')
    .padding({ top: 12 })
    .alignItems(HorizontalAlign.Center);
  }

  private rowModel(item: NewsItem): NewsRowModel {
    return NewsPresentation.row(item, NewsService.CATEGORIES[this.selected].id === 'blog', this.campus, Date.now());
  }

  /**
   * Message-list layout (HITA Aura): source avatar, bold title with a semantic date, then the
   * tag and source in grey and, for blog posts, an excerpt. Rows share one surface and are
   * separated by dividers inset past the avatar.
   */
  @Builder
  newsRow(item: NewsItem, row: NewsRowModel, last: boolean) {
    Column() {
      Row() {
        Stack() {
          Text(row.avatarText)
            .fontSize(NewsPresentation.avatarFontSize(row.avatarText))
            .lineHeight(row.avatarText.includes('\n') ? 13 : 18)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
            .textAlign(TextAlign.Center)
            .maxLines(row.avatarText.includes('\n') ? 2 : 1)
            .wordBreak(WordBreak.BREAK_ALL);
        }
        .width(AVATAR_SIZE)
        .height(AVATAR_SIZE)
        .borderRadius(AVATAR_SIZE / 2)
        .flexShrink(0)
        .linearGradient({
          angle: 180,
          colors: [[row.avatarColors[0], 0], [row.avatarColors[1], 1]]
        })
        .accessibilityLevel('no');

        Column() {
          // Title first, as on iOS; the date sits on its first line.
          Row() {
            Text(row.title)
              .fontSize(HitaDesign.body)
              .fontWeight(FontWeight.Medium)
              .fontColor(COLOR_TEXT_PRIMARY)
              .lineHeight(22)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1);
            if (row.date.length > 0) {
              Text(row.date)
                .fontSize(HitaDesign.caption)
                .lineHeight(22)
                .fontColor(COLOR_TEXT_HINT)
                .flexShrink(0)
                .margin({ left: 8 });
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Top);

          // Secondary line: inline tag chip, then the publishing department or author.
          Text() {
            if (row.tag.length > 0) {
              Span(row.tag)
                .fontSize(HitaDesign.label)
                .fontWeight(FontWeight.Medium)
                .fontColor(COLOR_TAG_TEXT)
                .textBackgroundStyle({ color: COLOR_TAG_BG, radius: 4 });
              Span('  ')
                .fontSize(HitaDesign.caption);
            }
            Span(row.source)
              .fontSize(HitaDesign.caption)
              .fontColor(COLOR_TEXT_SECONDARY);
          }
          .width('100%')
          .lineHeight(20)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 4 });

          if (row.body.length > 0) {
            Text(row.body)
              .fontSize(HitaDesign.caption)
              .lineHeight(20)
              .fontColor(COLOR_TEXT_SECONDARY)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .margin({ top: 2 });
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 12 });
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .padding({ left: 14, right: 14, top: 12, bottom: 12 });

      if (!last) {
        Divider()
          .strokeWidth(0.5)
          .color($r('app.color.hita_divider_edf1f7'))
          .margin({ left: 14 + AVATAR_SIZE + 12, right: 14 });
      }
    }
    .width('100%')
    .accessibilityGroup(true)
    .accessibilityText(row.title + '，' + row.source +
      (row.date.length > 0 ? '，' + row.date : ''))
    .onClick(() => {
      this.open(item.url, item.title);
    });
  }

}
