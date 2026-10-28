<p align="center">
  <img src="AppScope/resources/base/media/app_icon.png" width="128" alt="HITA NEXT 图标">
</p>

# HITA NEXT

当前版本：**0.4.1**。

HITA NEXT 是基于开源项目 [HITA Android](https://github.com/HIT-A/HITA_Android) 开发的 HarmonyOS NEXT 客户端，采用 ArkTS 与 ArkUI 原生实现，为哈尔滨工业大学一校三区学生提供课表查看、教务登录和本地学习信息管理功能。

项目在功能逻辑上参考 HITA Android，在界面结构与交互体验上同时参考 [HITA Aura](https://github.com/HIT-A/HITA-Aura)，尽量保持不同平台之间一致的使用习惯。

## 核心功能

开发和 AI 修改请先阅读 [项目约定](AGENTS.md)。底部弹层统一使用 `SheetContent` 提供拖拽条下方的内容留白；相关检查见 `scripts/sheet-layout.test.cjs`。

### 今日

- 显示当前日期、星期和教学周。
- 展示正在进行或即将开始的课程。
- 显示下一节课的时间、地点和倒计时。
- 按时间顺序展示当天全部课程及完成状态。

### 时间表

- 按周查看当前学期课程表。
- 显示周数、校区、学期、星期和日期。
- 支持左右滑动切换周次，并带有页面切换动画
- 课程按照真实开始时间和持续时间绘制。
- 默认显示约 08:00–19:00，晚间课程可继续向下滚动查看。
- 查看周存在晚间课程时，右下角显示下箭头；点击滚动至课表底部。
- 显示课程名称、地点以及不同课程对应的颜色。
- 时间表右上角“显示设置”支持时间虚线开关与配色、晚间课程提示开关、壁纸蒙版深度和课表文字颜色，设置自动保存在本地。
- 关闭时间网格时同时隐藏横线和每天分隔线。文字、网格线和今日列高亮可根据壁纸明暗及蒙版深度自适应，文字和网格线也可通过调色盘切换为手动配色。

### 教务

- 提供深圳、本部和威海校区的 ArkWeb 网页登录入口。
- 保存登录会话，并在再次启动应用时恢复当前登录状态。
- 支持深圳、威海和本部本科生课表导入。
- 自动获取当前学期，将课程、科目和每周课次写入本地数据库。
- 支持三校区本科成绩查询、学期和类型选择；分别展示教务官方统计与当前列表的本地统计。
- 学分查询沿用安卓端逻辑：深圳读取教务培养方案完成度、学分类别要求、培养课组与课程成绩明细；本部、威海及未登录时按本地课表去重统计分类学分，支持设置目标和查看领域、课程明细。本地统计不等同于已获学分或毕业审核结果。
- 支持本部、威海本科教务考试查询，合并期末、期中与补考安排；保留深圳查询及手动考试管理，已确定时间的考试可导入当前课表。
- 支持三校区本科教务空教室查询：沿用安卓 3.0.0 的教学楼／学期／周次自动查询、双列教室卡片及底部每日节次详情。

### 更多

- 查看当前账号、校区和会话状态。
- 按校区管理会话并退出登录。
- 管理课表、手动添加课程，以及导入和导出 ICS 课表。
- 一键将当前课表导出至手机系统日历，重复导出更新已有日程。
- 添加桌面服务卡片，显示下一节课的开始倒计时、地点和教师（见 [桌面服务卡片说明](docs/desktop-service-widget.md)）。
- 查看版本更新、服务与故障公告。
- “关于”页列出制作者与鸣谢，并提供隐私政策；文案集中在 `feature/about/AboutContent.ets`。隐私政策正文与[华为协议托管服务上的版本](https://agreement-drcn.hispace.dbankcloud.cn/index.html?lang=zh&agreementId=2056866492535841728)一致，修改托管版本后需同步更新该文件。

## 技术基线

- UI：ArkUI 声明式界面。
- 开发语言：ArkTS。
- 网页登录：ArkWeb。
- 网络访问：HarmonyOS NetworkKit。
- 本地课表：RelationalStore 关系型数据库。
- 会话与轻量配置：Preferences。
- 目标平台：HarmonyOS NEXT，模块声明支持 phone、tablet 和 2in1 设备。
- 最低兼容 SDK：6.1.0(23)；编译与目标 SDK：26.0.0。
- API 23～25 使用雾面玻璃底栏，图标和文字随背景亮度反色；API 26 保留原生悬浮栏与沉浸光感。
- 兼容行为、Cookie 接口边界和设备检查项见 [API 23 兼容说明](docs/api23-compatibility.md)。

教务数据流：

```text
ArkUI 页面 -> EasDataProvider -> EasApiClient -> 校区教务系统
```

课表导入与本地展示数据流：

```text
教务会话 -> EasTimetableImporter -> RdbHelper -> 今日 / 时间表
```

## 关键结构

```text
HitaNEXT/
├── AppScope/                         # 应用级名称、图标与配置
├── entry/
│   └── src/main/
│       ├── ets/
│       │   ├── entryability/         # EntryAbility 应用入口
│       │   ├── pages/                # 今日、时间表、更多及功能页面
│       │   ├── feature/eas/          # 登录、会话、教务请求与课表导入
│       │   ├── feature/timetable/    # 周课表绘制、课表选择与 ICS 导入
│       │   └── common/               # 数据库、模型与通用工具
│       └── resources/                # 字符串、颜色、图标等资源
├── docs/                             # 使用、构建验证与图标设计文档
├── scripts/                          # 构建工具、静态检查与回归测试
├── build-profile.json5
└── hvigorfile.ts
```

主要入口：

- `entry/src/main/ets/pages/Home.ets`：今日、时间表、更多三个主页面。
- `entry/src/main/ets/feature/eas/webLogin/`：ArkWeb 登录和 Cookie 会话采集。
- `entry/src/main/ets/feature/eas/EasDataProvider.ets`：深圳、本部本科与威海课表数据适配。
- `entry/src/main/ets/feature/eas/ScoreService.ets`：三校区成绩及官方统计查询；本部、威海研究生接口尚未接入。
- `entry/src/main/ets/feature/eas/EasTimetableImporter.ets`：远端课程到本地课表的转换与写入。
- `entry/src/main/ets/feature/timetable/views/TimetableWeekDraw.ets`：周课表网格及课程卡片绘制。
- `entry/src/main/ets/common/db/RdbHelper.ets`：本地课表、科目和事件数据库。

仓库仅维护当前鸿蒙实现、应用资源、构建工具和测试，不收录安卓源码副本、
反编译材料或临时抓取截图。`scratch/`、`.analysis/` 和 `HITA_Android_src/`
属于本地参考目录，已加入 `.gitignore`。

## 开发与构建

### 环境要求

- DevEco Studio 5.0 或更新版本。
- HarmonyOS NEXT SDK 26.0.0 或兼容版本。
- 用于运行辅助脚本的 Node.js 环境。

### 使用 DevEco Studio

1. 克隆仓库：

   ```bash
   git clone https://github.com/samerberry/HITA_NEXT.git
   ```

2. 使用 DevEco Studio 打开仓库根目录并等待工程同步完成。
3. 在 `File > Project Structure > Signing Configs` 中为本机重新配置自动签名。
4. 选择 `entry` 模块并执行 Build 或 Run。

签名配置包含设备和开发者相关材料，不同电脑需要使用自己的证书与 Profile，不能直接复用其他开发环境中的签名文件。

### 命令行构建

在 Windows PowerShell 中进入仓库根目录：

```powershell
$env:NODE_HOME = 'C:\Program Files\nodejs'
$env:DEVECO_SDK_HOME = 'C:\Program Files\Huawei\DevEco Studio\sdk'

& 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' `
  --mode module -p product=default assembleHap --no-daemon
```

构建产物位于：

```text
entry/build/default/outputs/default/
```

配置签名后通常生成 `entry-default-signed.hap`。仓库中的 `install_and_run.bat` 可用于构建、检测 HDC 设备并安装已签名 HAP。

### 静态检查

```bash
node scripts/static-checks.cjs
```

使用和验证说明：

- [0.4.0 版本说明](docs/release-0.4.0.md)
- [0.3.0 版本说明](docs/release-0.3.0.md)
- [0.2.1 版本说明](docs/release-0.2.1.md)

- [使用说明](docs/usage.md)
- [构建与设备验证](docs/DEVICE-RUNBOOK.md)
- [应用功能边界与回归检查](docs/production-surface.md)

## 数据与隐私

- 教务登录和数据请求直接访问哈尔滨工业大学各校区的统一认证及教务系统。
- 登录后的 Cookie 和会话信息当前保存在应用本地 Preferences 中，尚未接入 HUKS 加密，用于恢复登录状态和请求教务数据。
- 本地备份包含课表、科目和事件信息，请妥善保管，不要公开分享。
- 校方页面、认证方式或接口发生变化时，相关功能可能需要同步适配。

本项目不是哈尔滨工业大学官方应用。教务数据的所有权与使用规则以学校相关规定为准。

## 致谢

- [HITA Android](https://github.com/HIT-A/HITA_Android)：主要功能逻辑、数据结构和 Android 端交互参考。
- [HITA Aura](https://github.com/HIT-A/HITA-Aura)：iOS 端界面布局和跨平台体验参考。
- HITA 系列项目的开发者与贡献者。

## 授权状态

本仓库当前未附带正式的 `LICENSE` 文件。除非后续另行声明，当前代码与文档默认保留全部权利，不授予再分发、商用、二次上架或衍生发布许可。
