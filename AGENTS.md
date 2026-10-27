# HITA NEXT 项目约定

适用于本仓库内的人工和 AI 修改。修改前检查当前分支与未提交内容，不覆盖本地签名配置、凭据或无关工作。

## 底部弹层

- 点击遮罩、返回键或下滑等系统关闭路径必须同步页面的可见状态（使用 `$$` 双向绑定或明确的生命周期回调）。退出动画完成前保留内容与高度，待 `onDisappear` 后再清空选中项和模式；修改关闭逻辑后检查这三种关闭方式及再次打开，避免残留空面板或遮罩。
- 所有带系统拖拽条的 `bindSheet` 内容，最外层必须使用 `common/components/SheetContent.ets` 的 `SheetContent`。
- 拖拽条下方的内容顶部留白统一由该容器提供，目前为 24 vp。页面内部不要再叠加整块顶部 padding，也不要用负 margin、偏移或改成 4 vp 来压缩这段留白。
- 高度固定或为百分比的弹层使用 `fillHeight: true`；`FIT_CONTENT` 弹层使用默认值。只包一层，不改变原有关闭、返回、键盘和滚动行为。
- 普通整页的状态栏避让与弹层顶部留白分开处理，不能把整页状态栏高度重复加到弹层中。
- 改动公共容器或新增弹层后，运行 `scripts/sheet-layout.test.cjs`，并在模拟器检查实际拖拽条、标题、内容间距；同时覆盖自适应高度和固定高度各一种。编译通过不等于布局已验收。

## 界面规范

- 完整规范见 `docs/design-system.md`。字号、间距、圆角取自 `HitaDesign`，颜色取自 `HitaColors` 或颜色资源。页面里不新增 `'#RRGGBB'`、`fontSize(数字)`、`borderRadius(数字)`，也不使用 4 的倍数以外的间距（Canvas、桌面卡片、课表格子除外）。
- 品牌色保留 `hita_primary`（#0068D9）。层次用材质表现，用了材质的表面不加阴影。顶部标题左对齐，返回键在左。
- 材质上的文字要么跟随系统前景色（`CompatibleMaterialModifier.foreground`），要么放在实心底或着色材质上；固定白字不能压在无着色材质上。按钮统一用 `HitaButton`，它只用实心底；标题栏文字操作用 `HeaderActionButton`；状态标签用 `HitaTag`；设置和功能列表的行用 `HitaListRow`。
- 改界面后运行 `scripts/design-system.test.cjs`，并在模拟器上分别截取浅色和深色截图检查。该测试的基线数字只能调低，不能为了让新代码通过而调高。

## 教务状态

- “更多”和教务账号弹层只读取本地会话状态，不主动发请求验证登录。
- 实际教务请求只有在明确收到认证失效证据时，才由 `EasApiClient` 调用 `EasSessionStore.markExpired` 标记对应校区。网络超时、普通 403/405/5xx、解析失败不得直接标为过期。
- 过期状态需要持久化，更多页显示“已过期教务”和红底图标；不清除课表、身份资料或凭据。
- 重新登录成功后通过 `EasSessionStore.save` 清除过期标记；修改会话状态必须保留请求所属会话的校验，防止旧请求覆盖新登录。
- 修改这部分后运行 `scripts/session-status.test.cjs`、`scripts/home-sheet-lifecycle.test.cjs` 和相关教务功能测试。

这些约定属于产品行为，不应为了通过测试而删除相应检查。确需改变约定时，先按用户的新要求同步修改公共实现、说明和检查。
