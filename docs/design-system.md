# HITA NEXT 界面规范

以 harmony-design-frontend v1.2.0 为底，按 HITA 现有实现和 HarmonyOS 实际组件修订。数值以
`common/theme/HitaDesign.ets`、`HitaColors.ets` 和 `resources/*/element/color.json` 为准；本文与令牌不一致时，
先改正其中一方，不要在页面里另写一套值。

## 1. 原则

- **一致**：颜色、字号、间距、圆角都取自令牌，页面里不写散值。
- **层级**：每页一个视觉焦点。层级靠字号、字重和颜色拉开，不靠堆叠特效。
- **克制**：材质只用于浮层和沉浸卡面；每个操作最多一个主动效。
- **深浅色同等验收**：两种模式都要截图检查，只在一种模式下好看不算完成。

## 2. 颜色

| 用途 | 资源 | 浅色 | 深色 |
|---|---|---|---|
| 品牌主色（文字、图标、选中） | `hita_primary` | #0068D9 | #85B8FF |
| 实心主按钮 | `hita_primary_fill` | #0068D9 | #246AB6 |
| 品牌浅底（选中、次按钮、图标底） | `hita_selected` | #E8F3FF | #243A53 |
| 主文字 / 次文字 | `hita_text` / `hita_text_secondary` | #181C24 / #626873 | #ECEFF4 / #BCC3CF |
| 页面底 / 卡片 | `hita_page` / `hita_surface` | #F5F6F8 / #FFFFFF | #101214 / #1C1F23 |
| 成功 / 警告 / 错误 | `hita_success` / `hita_warning` / `hita_error`（各有 `_surface` 浅底） | | |

- 品牌色保留 #0068D9，不改成通用规范里的 #007DFF；白字压在它上面的对比度更高。
- 页面代码不新增 `'#RRGGBB'` 字面量。例外：Canvas 绘制、桌面服务卡片、课表配色算法。
- 新增颜色用语义名，不带色值后缀。历史上带后缀的名字（如 `hita_selected_e8f1fb`）以后分批改名。

## 3. 字体

| 角色 | 令牌 | 字号（fp） | 字重 |
|---|---|---|---|
| 日期、大数字 | `display` | 28 | Bold / Medium |
| 页面标题 | `title` | 22 | Medium |
| 内容区块标题（如“今日安排”） | `section` | 18 | Medium |
| 正文、列表标题 | `body` | 16 | Regular；卡片标题用 Medium |
| 说明、地点、时间 | `caption` | 14 | Regular |
| 列表分组标题（设置、功能列表） | `caption` | 14 | Medium，次要色 |
| 标签、角标 | `label` | 12 | Medium，只用于短标签 |

正文不加粗。课表格子和日期栏保留紧凑字号（10、11），属于例外，代码里用具名常量标明。

## 4. 间距（4 vp 基数）

| 令牌 | 值 | 用途 |
|---|---|---|
| `space2xs` | 4 | 标题与说明之间、分段控件轨道内边距 |
| `spaceXs` | 8 | 图标与文字之间、紧凑元素、分组标题与卡片之间 |
| `spaceSm` / `gap` | 12 | 卡片之间、行内元素之间 |
| `spaceMd` / `inset` | 16 | 页面左右边距、卡片内边距 |
| `spaceLg` / `sectionGap` | 24 | 区块之间 |
| `spaceXl` | 32 | 大区块 |

padding、margin 和 space 只用 4 的倍数；描边宽度和进度条粗细不算间距。

## 5. 圆角

| 令牌 | 值 | 用途 |
|---|---|---|
| `radiusSm` | 8 | 小控件 |
| `radiusMd` / `fieldRadius` | 12 | 输入框、分段控件内项、展开面板 |
| `radiusLg` / `cardRadius` | 16 | 卡片、列表分组 |
| `radiusXl` / `heroRadius` | 24 | 主视觉卡、弹层 |
| 胶囊 | 高度的一半 | 按钮、标签 |

嵌套圆角：紧贴容器边缘的内层元素（如分段控件里的项），内层圆角 = 外层圆角 − 内边距。例如圆角 16、内边距 4 的容器，里面的项用 12。
列表里普通的行或小块不受这条约束，用 `radiusSm` 或 `radiusMd`。

## 6. 层次：用材质，不叠阴影

- API 26 用 `CompatibleMaterialModifier` / `ImmersiveHeader` 表现层次，用了材质的表面不再加 `.shadow`。
- 平铺在页面底上的内容卡片，材质下面先垫一层实心卡面：浅色是白色，深色是透明。材质本身是半透明的，
  浅色页面底上会和背景同色，卡片就看不出来了。
- API 23 回退为实心面，不另加阴影。

## 7. 材质上的文字（硬规则）

- 材质上的文字和图标，要么用 `CompatibleMaterialModifier.foreground(...)` 跟随系统前景色，要么放在实心底上。
- 禁止把固定白字压在无着色材质上（`CompatibleMaterialModifier` 第二个参数为 `false` 或省略）：这种材质是半透明的，
  会替换原来的底色，浅色模式下白字就看不见了。着色材质（第二个参数为 `true`）只在 `ImmersiveHeader` 宿主或弹层里显出底色，
  这时才能配白字，如编辑页的主按钮；页面普通区域和列表滑动操作里它同样会变透明，白字、白图标的按钮改用实心底。
- 页面和弹层里的按钮统一用 `HitaButton`：它只有实心底，不接受材质修饰。

## 8. 组件

| 组件 | 规格 |
|---|---|
| `HitaButton` | 胶囊，默认高 48、行内高 40。PRIMARY 为实心主色加白字；SECONDARY 为品牌浅底加主色字，接近鸿蒙的 NORMAL 按钮，不用透明底描边；DANGER 为错误浅底加错误色字；NEUTRAL 为中性底，用于“取消”。默认填满所在容器，两个并排时各给 `width(0).layoutWeight(1)`；`fitContent` 按文字宽度，用于“重试”这类单个行内操作。一组按钮里只放一个 PRIMARY。 |
| `HeaderActionButton` | 标题栏右侧和详情卡末尾的紧凑文字操作，高 36 的胶囊，点击区域扩到 44（`minTouchTarget`）。材质可用时跟随系统前景色，不可用时为品牌浅底加主色字。 |
| `HitaTag` | 胶囊状态标签，12 Medium，左右 8、上下 4。颜色只由色调决定：BRAND、SUCCESS、DANGER、EXAM、NEUTRAL、ON_PRIMARY。 |
| `HitaListRow` | 40 vp 圆形图标底，标题 16，说明 14，右侧箭头，最小高度 64。分组卡片内第二行起显示分隔线，从文字起点画到右侧内边距。可展开的行用 DISCLOSURE，箭头随展开状态旋转，并朗读“已展开 / 已收起”。 |
| 列表分组标题 | 14 Medium 次要色，左缩进 16，上 24、下 8。 |
| 顶部导航 | 标题左对齐，返回键在左（`HeaderBackButton`，44 vp 圆形），不改成居中标题。 |
| 底部弹层 | 见 `AGENTS.md` 的底部弹层约定：最外层 `SheetContent`，顶部留白 24 vp。 |

## 9. 多端

- 内容最大宽度 720 vp（`contentMaxWidth`）；平板和三折叠使用侧边 Dock。
- 断点采用 GridRow 官方默认值 320 / 600 / 840 vp，不用 520。
- 待做：考试、成绩等列表页在宽度 ≥ 600 vp 时改为“列表 + 详情”分栏。

## 10. 检查

- 运行 `node --test scripts/design-system.test.cjs`。它检查：令牌刻度；公共组件只用令牌；按钮不把固定白字压在无着色材质上，宿主外的白图标按钮用实心底；
  除绘制例外以外的每个页面、弹层和对话框都没有 4 倍数以外的间距、写死的字号和圆角；全仓散值和硬编码颜色的数量只能减少。
- 绘制例外（尺寸跟随画布、Dock 绘制或桌面卡片）：`DockRail`、`FrostedDock`、`CourseColorEditor`、`WidgetBackgroundPage`、
  `NextClassCard`，以及课表配色、背景和资讯头像配色这类颜色算法文件。
- 改界面后，浅色和深色各截图验收。编译通过不等于验收通过。

## 11. 与原通用规范的差异

| 项 | 通用规范 | HITA |
|---|---|---|
| 品牌色 | #007DFF | 保留 #0068D9 |
| 层次 | 柔和阴影 | 沉浸材质，不叠阴影 |
| 顶部导航 | 标题居中 | 标题左对齐，返回键在左 |
| 次按钮 | 透明底描边 | 品牌浅底 |
| 卡片圆角 | 12 | 16 |
| md 断点 | 520 vp | 600 vp |
| 单位 | dp | vp（尺寸）、fp（字号） |
| 风格定位 | 轻拟物 | 沉浸材质 |
