# 小艺应用内半屏助手

用户参考视频展示的是应用保持可见、底部浮出智能体对话卡片与输入栏的效果。
本次改用 Agent Framework Kit 的 `FunctionComponent`，原生组件负责点击和系统半屏对话框，
不再以 `startAbility` 启动小艺全屏页面，也不创建 HITA 自己的聊天弹层。

## 官方依据（2026-10-31 核对）

- [通过 Function 组件拉起智能体](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/hmaf-function)
- [FunctionComponent API](https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/hmaf-function-component)
- [关联应用：调试及发布、签名与授权 FAQ](https://developer.huawei.com/consumer/cn/doc/service/related-applications-0000002437785706)
- [Agent Framework Kit 简介及设备限制](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/hmaf-introduction)

Function 组件从 API 20 起提供，当前支持手机、平板，官方明确暂不支持模拟器。
关联应用文档确认：Agent 发布真机测试、设备加入白名单后，可以从应用的组件图标呼出半屏态 Agent。
文档还指出自动签名生成的应用标识可能与平台应用不一致，出现“Agent未授权给该应用”。

## 当前接入

- 组件：`entry/src/main/ets/feature/assistant/XiaoyiAssistantEntry.ets`。
- 入口：「今日、时间表、更多」导航胶囊旁的独立「助手」圆形按钮，图标位置沿用原 Dock 第四项；「更多」列表中的原入口已移除。
- `AssistantDockItem.ets` 统一提供系统能力判断与不支持时的提示，手机底栏、旧版底栏、平板侧栏均复用它；支持的设备延迟加载 `XiaoyiAssistantEntry.ets`。
- 官方控件使用透明背景的 `ButtonType.CAPSULE`，真实点击框为 36×36 vp，可见图标保持 20 vp；下方标签为与其他项共用的 11 fp `HitaDesign.dockLabel`。外围是独立的 56 vp 圆形系统材质。原生控件直接响应单击，不使用蓝色底或模拟点击。
- Agent ID：`agent26e52f2a50ad42059267f9077d548b6c`，直接从当前已登录平台的 HITA Agent 配置地址读取。
- `queryText` 为空：只呼出助手，不自动提交问题。使用者自行提问，继续走既有 `Timetable` 插件。
- 使用 `agentDialogOpened` / `agentDialogClosed` 记录打开和关闭，离开组件时注销对应回调。错误日志只记录错误码。
- 通过系统能力及设备类型判断，并延迟加载组件；不支持的设备显示说明。
- FunctionController 当前公开接口没有程序化 `open()`，因此保留可见的原生按钮，不使用透明覆盖层或合成点击。

## Dock 入口迁移验证（2026-10-31）

Dock 共四个操作，页面数为三。`Tabs` 保留三页及页面滑动，隐藏自身底栏。API 26 及以上由 `SplitDock`
显示三项导航与独立的 `AssistantDockButton`，材质通过 `ImmersiveHeader` 承载；不为助手保留空白 TabContent。
`DockNavigationGuard(4, 3)` 保持动作与页面导航分离。
手机导航胶囊宽 216 vp，助手圆形直径 56 vp，两者间隔 8 vp，合计 280 vp 整体居中。
前三项保留原先的图标位置并关于导航胶囊对称；助手按用户追加的「稍加长、整体居中」要求放在组合的右端。
旧版底栏和侧栏同样拆分，沿用各自的原图标中心。光效分别裁剪，按住后在间隔中释放不会切换页面。

134 项相关检查及 ArkTS 编译、签名通过，已覆盖安装。用户实机确认第四项显示正常，点击能呼出半屏。
本轮没有在电脑测试 Agent，浅色外观及平板侧栏的实机截图尚未补齐。
日志：`.hvigor/assistant-dock-tests.log`、`.hvigor/assistant-dock-build.log`。
修改前备份：`.hvigor/assistant-dock-before/`。

透明入口的图文对齐及流光定位修复后，用户回复「好了」。深色截图及布局证据为
`.hvigor/hita-dock-aligned-2.jpeg`、`.hvigor/hita-dock-aligned-2.json`：图标中心横坐标为
280、472、664、856 px，四项图标和文字分别位于相同的纵坐标。

随后按用户要求拆分为导航胶囊与独立助手按钮。首版截图 `.hvigor/hita-dock-split-1.jpeg` 及布局确认
图标位置保持一致，但用户指出导航胶囊与前三项不居中、助手需要双击。按追加要求将导航胶囊加长至 216 vp，
取消逐项补偿内边距，组合整体居中；将过小的原生圆形按钮改为有完整点击框的透明原生控件。
151 项检查及签名构建通过并覆盖安装，后续单击及握姿修正见下。该轮日志为
`.hvigor/assistant-split-centered-tests.log`、`.hvigor/assistant-split-centered-build.log`；
源码备份为 `.hvigor/assistant-split-before/`。

## 单击与智感握姿修正（2026-10-31）

原生 SMALL 按钮实际高度为 36 vp，将其外框同步为 36×36 vp；图标布局行保持 20 vp，
响应区扩展到真实按钮范围，最外层 56 vp 助手容器使用 Default 命中，避免点击穿透到页面。
用户单击等待测试回复「好了」。日志记录 03:48:16.030 Down、16.081 Up、16.354 dialog opened，
确认一次点击即可呼出；此前 48 vp 高外框导致图标与真实按钮范围不一致。

拆分后的握姿回归由导航先移动、助手和光层逐帧追随引起。现将三者置于同一 280×56 vp 父容器，
移除 800 ms 位置轮询；仅在触摸开始时读取整组实际变换坐标用于命中，不用测量结果驱动绘制位置。
174 项检查及签名构建通过后覆盖安装，用户确认双屏连续换手、同步移动和助手单击正常。
深色双屏截图与布局为 `.hvigor/hita-grip-shared-1.jpeg`、`.hvigor/hita-grip-shared-1.json`：
左握时整组边界为 [48,1944]–[888,2112] px，前三项标签 y=2042–2081 px。

最终按用户偏好使用屏幕内 300 ms 平滑换边，保留整组同步移动，不使用底部栏离屏换边。
回归日志为 `.hvigor/grip-restored-tests.log`，构建日志为 `.hvigor/grip-restored-build.log`，
修改前备份为 `.hvigor/grip-shared-before/`。浅色及平板侧栏完整视觉验收尚未补齐。

## 开场内容排查（2026-10-31）

用户确认半屏能够弹出，但没有开场语和开场预置引导。平台当前选中「预置开场对话」，
开场语为「你好，我是 HITA 助手。可以问我课表相关的问题。」，已有三条引导：
「明天有什么课」「第三周周五的课」「下一节课在哪上」。本次没有修改这些平台配置。

官方指南区分带标题的功能按钮和不带用户意图的综合型图标入口，并在图标入口示例中展示开场语与引导。
曾将 `title` 由「助手」改为空，保留空 `queryText`，与官方主入口示例一致，可见标签放在图标旁。
此对比用于验证入口形式是否影响开场展示；文档未明确保证两种形式的开场行为不同。
用户实机验证图标入口仍没有开场语和引导，因此撤回这项试验，恢复带标题的原生按钮。

用户另行确认：从小艺 App 进入同一个带「开发中」标记的 HITA 助手并新建对话，能看到开场语和三条引导；
只有应用内系统半屏缺失。该对比排除了「平台未填写开场配置」的解释，问题范围集中于半屏展示路径。
目前没有证据确定是小艺版本兼容问题、单 Agent 模式差异还是其他系统端异常，不能断言官方半屏一律不支持开场内容。

当前 SDK 的 `FunctionOptions` 只提供初始问题与入口外观配置，`FunctionController` 提供能力查询和打开/关闭事件，
未发现显示开场语、注入引导问题或操作系统对话内容的公开参数。官方另有 A2A 的动态开场协议，
那是另一种接入方式，不能直接套入当前单 Agent 的端插件实现。本次没有修改 Agent 模式或平台配置。
没有自动发送问候消息模拟开场，也没有用 HITA 自建聊天层替换系统半屏。

03:00 的图标入口版本已通过 58 项相关检查并完成签名覆盖安装，包大小为 6,625,213 字节。
日志为 `.hvigor/xiaoyi-opening-tests.log`、`.hvigor/xiaoyi-opening-build.log`，
修改前备份位于 `.hvigor/xiaoyi-opening-before/`。该图标实验经用户确认无效，已撤回。
定向读取本次 HiLog 返回空文件，不能据此判断系统没有调用接口或取得服务端错误码。
复现信息与官方核查问题见 `docs/xiaoyi-opening-issue.md`；开场缺失尚未修复。
恢复原按钮后再次通过 58 项检查及签名构建，已覆盖安装。
最终日志为 `.hvigor/xiaoyi-opening-restored-tests.log`、`.hvigor/xiaoyi-opening-restored-build.log`。

## 应用关联与实机结果

平台已关联 HITA NEXT 的手机与平板两条记录，包名均为 `cn.berry.hitanext`，
平台 appId 均为 `6917618056356232874`。

当前工程默认调试签名的 Profile 与已安装应用的 appIdentifier 是 `6918743957079883363`，
与上述平台 appId 不一致。已找到本机若干标识正确的旧签名 Profile，但其证书公钥均与当前调试包不同；
当前工程只有默认调试签名配置，没有可直接切换的匹配配置。
本轮未修改签名配置、密钥、应用版本或清除数据。

02:53 的实机截图已确认：点击后底部出现「HITA NEXT校园助手」卡片及「点击或按住说话」输入栏，
HITA 的功能中心仍在背景中，达到了参考视频的半屏形式。本次没有观察到该标识差异阻止半屏弹出，
因此不能仅凭差异认定当前调用失败。签名差异保留为后续正式签名配置核对信息。

## 本轮验证

- 58 项相关检查通过，覆盖原生回调生命周期、错误提示、入口绑定、课表 API、设计规范及现有 API 兼容性检查。
- 静态检查 171 文件、15 路由通过；ArkTS 编译及签名通过。
- 新调试 HAP 已覆盖安装；深色实机截图确认 HITA 保持可见并出现原生助手卡片和输入栏。
- 截图证据：`.hvigor/hita-inline-entry.jpeg`。首次截图只确认半屏外观，未据此确认新对话回答；关闭/重开、浅色外观待补充验证。
- 日志：`.hvigor/xiaoyi-inline-tests.log`、`.hvigor/xiaoyi-inline-build.log`。
- 修改前文件：`.hvigor/xiaoyi-inline-before/`。
