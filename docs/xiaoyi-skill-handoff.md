# 小艺应用 Skill 协作交接（2026-10-30）

## 当前状态

应用侧实现、自动化测试和签名 HAP 构建已完成，但小艺到 HITA 的端到端调用尚未打通，不能作为已可用功能验收。项目所有者已停止本轮真机测试，后续由协作者继续定位。使用方法与能力契约见 [测试说明](xiaoyi-skill-testing.md) 和 [功能描述](../entry/skills/hita-campus/SKILL.md)。

本次同时修正课表时间轴：只根据当前查看周的日程扩展默认 08:00–23:00 范围；其他周的早课、晚课不再影响当前周。

## 代码入口

| 文件 | 职责 |
| --- | --- |
| `entry/skills/hita-campus/SKILL.md` | 六项能力及调用参数；仓库内保留完整功能描述 |
| `entry/skills/hita-campus/scripts/CampusSkill.ets` | ArkTS 脚本入口、参数验证、系统回包，日志标签 `HitaCampusSkill` |
| `entry/src/main/ets/feature/assistant/CampusSkillService.ets` | 本地查询、草稿、幂等操作、确认与状态查询 |
| `entry/src/main/ets/pages/CampusSkillConfirmPage.ets` | 用户确认后才保存课程或日程 |
| `entry/src/main/ets/common/db/RdbHelper.ets` | 保存事务及并发修改、删除校验 |
| `entry/src/main/ets/entryability/EntryAbility.ets` | 承接确认页拉起和前台恢复 |
| `entry/src/main/module.json5` | `skillProfiles` 注册并绑定 `EntryAbility` |
| `scripts/campus-skill.test.cjs` | 应用侧业务、入口和确认状态回归测试；系统边界使用 mock |

## 已确认的环境和现象

- 设备系统 `OpenHarmony-7.0.0.105`，API 26；小艺 `11.7.8.303`，可见“Skill 真机测试中”。
- 应用包名 `cn.berry.hitanext`，版本 `0.4.1`。HAP 目标 API 26，最低兼容 API 23；平台 Skill 配置为“不依赖沙箱、目标 API 26、最小 API 26”。两处最低版本不同是目前实际配置，不能据此单独推断故障。
- 测试组与手机账号一致；用户确认保存配置后重新发布，仍未成功。
- 原始平台导出的 ZIP 仅含功能版 `SKILL.md`，与仓库原文逐字节一致；六项命令没有被平台扫描过程改写。HAP 中已核对描述、模块注册及编译脚本。ZIP 没有单独的 `.ets` 文件本身不足以证明缺包。
- 一次课表请求期间，小艺日志依次出现 `APP_OPERATION` 和 `CHAT`，捕获范围内未见 `ohos-arkTSScript` 调度及 `HitaCampusSkill` 的 `begin` / `complete`。这提示应优先核查召回、实际发布版本和调度；不是已经证明某一处的根因。
- 平台“@ → 系统 CLI”列表没有 `ohos-arkTSScript`；现有官方资料未明确应用 Skill 必须手动添加该内置命令，不能据此要求开启沙箱或安装虚构工具。

## 平台可能仍保留临时诊断描述

最后一次平台实验将同名 `hita-campus` 暂时改为仅回复固定口令的描述，不调用任何 CLI。输入“HITA联调检查”后，小艺回复相关能力没有正常返回，未输出口令。

随后导出的 `hita-campus (1).zip` 内描述为 746 字节，SHA-256 为 `2927A925CDC7BC12BB24B7C555542E645C825D90B166DBEB47B45181E8310613`，与本地临时描述一致。这只确认导出内容，尚未确认测试请求实际使用了哪一发布版本。该次未实时捕获完整日志，不能根据自然语言回复认定应用脚本执行报错。

协作者开始前先检查平台当前草稿和实际发布内容；测试完整能力时恢复仓库内的功能描述并重新发布。临时诊断描述没有覆盖仓库源码或已构建的功能 HAP。

## 后续定位与验收

1. 优先取得平台侧实际发布版本、候选 Skill、描述采用和工具调度记录；必要时通过 [华为官方反馈](https://developer.huawei.com/consumer/cn/support/feedback/#/) 查询。公开仓库不附账号、会话标识或原始设备日志；原始材料留在原开发机，需另行私下提供。
2. 确认请求实际采用功能 Skill 后，再检查系统脚本加载、`HitaCampusSkill begin` 和 `complete`，将调度问题与应用业务错误分开定位。
3. 完成只读查询后再验收添加、改单次课程、取消、超时、幂等重试、后台拉起，以及提醒/卡片/日历更新。写入始终需要用户在 HITA 确认。
4. 确认页浅色、深色视觉检查及低版本兼容回归仍待完成。自动化通过和编译通过不代表这些验收已通过。

构建需协作者自行配置本地签名、证书与设备 Profile；这些资料及原始日志不进入 Git。保留版本号 0.4.1，未发布应用市场。

## 提交前本地检查

2026-10-30 提交前复跑相关测试，共 154 项通过，包含小艺业务、数据库事务、时间轴、课表管理、日历、提醒、卡片、页面生命周期、设计规范及仓库检查。初次直接运行缺少 TypeScript 模块，按仓库既有方式设置 DevEco 的 `NODE_PATH` 后通过，无需新增应用依赖：

```powershell
$env:NODE_PATH = 'C:\Program Files\Huawei\DevEco Studio\plugins\codelinter\node_modules'
node --test scripts/campus-skill.test.cjs scripts/timetable-marquee.test.cjs scripts/database-integrity.test.cjs scripts/timetable-manager.test.cjs scripts/timetable-update.test.cjs scripts/home-sheet-lifecycle.test.cjs scripts/design-system.test.cjs scripts/sheet-layout.test.cjs scripts/api23-compatibility.test.cjs scripts/calendar-sync.test.cjs scripts/class-reminder.test.cjs scripts/next-class-widget.test.cjs scripts/reminder-navigation.test.cjs scripts/repository-hygiene.test.cjs
```

DevEco 安装在其他目录时相应修改路径。这次交付未继续进行手机测试。
