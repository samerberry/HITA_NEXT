# HITA NEXT 小艺应用 Skill：实现与 API 26 真机测试

> 协作状态：截至2026-10-30，应用侧构建和本地测试通过，小艺端到端调用尚未打通。项目所有者已停止本轮真机测试；现象、临时平台描述及待办见[交接说明](xiaoyi-skill-handoff.md)。以下测试步骤供协作者继续验收，不代表已经全部通过。

本轮接入方式为 Ability Kit 的 ArkTS 应用 Skill。小艺负责理解自然语言并调用能力，HITA 负责读写当前设备的本地课表。不需要为本轮能力填写第三方大模型 API Key。原有应用内助手保持原有调用方式，这次增加的是小艺入口。

## 当前实现

| 能力 | 行为 |
| --- | --- |
| 查询课表 | 当前选中课表及独立日程，支持日期范围、课程名称筛选，最多93天、每次100条 |
| 下一节课 | 当前时刻之后开始的下一次课程，返回时间、地点、教师 |
| 查询考试 | 本地已导入的考试，默认今天至30天后，含结束当天 |
| 添加日程 | 小艺生成草稿，打开 HITA 确认页；点击确认保存后才写入 |
| 调整课程 | 先查询准确的单次课程，再调整时间、地点；保留同课程的其他周次 |
| 查询结果 | 区分待确认、已保存、已取消、已过期；待确认不能回答已保存 |

确认页展示目标课表、课程名称、原安排、新时间与地点，显示时间冲突；采用现有字号、颜色、按钮和沉浸光感标题组件。保存后通知现有卡片、提醒、日历同步机制；日历同步仍取决于用户已启用同步及权限。

同一 requestKey 的相同参数复用同一草稿，记录保留7天；草稿30分钟过期。确认时在数据库事务内重新核对原课程，拒绝覆盖期间的其他编辑、恢复已删除课程或向已删除课表写入。日期早于课表开始时间也会拒绝。

本轮没有开放整学期批量编辑、删除、作业写入或系统情景模式控制。只读取 HITA 本地数据，不会因小艺查询自动登录教务或刷新教务。

## 华为官方依据

- [基于 ArkTS 脚本的应用 Skill 开发指导](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/arkts-skill-development-guide)：API 26 起支持，Stage 模型；描述文件、入口脚本、skillProfiles 注册与系统结果回传；完成后上传 HAP 再真机测试。
- [导入 Skill](https://developer.huawei.com/consumer/cn/doc/doccenter-celia/import-skill-0000002592931542)：小艺开放平台 → Skill → 新建 Skill → 导入 Skill。
- [真机测试](https://developer.huawei.com/consumer/cn/doc/doccenter-celia/skill-real-machine-testing-0000002592771628)：可在上架前测试；在开发界面选择真机测试用户组，发布至小艺主对话或小艺 Claw；发布可取消和重新发布，每次有效15天。团队账号管理用户组需管理员权限。
- [小艺开放平台](https://developer.huawei.com/consumer/cn/hag/hagindex.html)。

以上平台路径于2026-10-30核对。界面和账号可用能力以平台实际显示为准；没有入口时先确认开发者权限与应用归属，不能靠本地安装 HAP 代替平台的 Skill 注册。

## 1. 准备手机和数据

1. 使用 API 26 真机，升级系统和小艺到支持该能力的版本。手机登录待加入测试组的华为账号。
2. 手机开启开发者模式和 USB/无线调试，连接 DevEco Studio，允许调试连接。DevEco 的设备列表应显示该手机。
3. 在 HITA 里先导出一份备份。使用“测试课表”做首次写入验证，准备明天的一节课及一场未来考试，并将它选为当前课表。
4. 工程目标 SDK 为26，现有最低兼容版本保持23。Skill 仅在API26进行试验；API23设备不会因此获得小艺 Skill 能力，旧系统安装运行兼容性仍需回归。

## 2. 构建和安装同一版本

2026-10-30 本次已构建并核验签名的测试包为：

- 文件：`entry/build/default/outputs/default/HITA-NEXT-0.4.1-xiaoyi-week-axis-debug.hap`
- 包名：`cn.berry.hitanext`；版本：`0.4.1`；用途：debug；目标API26，最低兼容API23。
- SHA-256：`DAF350435EA59E6091A938E862B90472ACB31B9E00DCBE17B3351CF71FF820D6`。
- 包含此前的小艺能力，以及“仅当前查看周有早课/晚课时才扩展时间轴”的修正。没有相应日程的周恢复08:00–23:00，不修改课程本身的时间。

直接使用本次成品时，无需再次构建。连接手机后，可执行：

```powershell
& 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe' install -r 'C:\heyiwei\HITA_NEXT-0.3.0\entry\build\default\outputs\default\HITA-NEXT-0.4.1-xiaoyi-week-axis-debug.hap'
```

该命令安装到手机，不会替你在小艺平台导入或发布。先备份数据；调试Profile须包含该手机，多设备和签名问题见下文。

用 DevEco Studio 打开工程，等待依赖同步完成。在 Signing Configs 选择调试签名，确保调试 Profile 包含测试手机。点击 Run 安装并启动。

命令行等效操作（PowerShell，在仓库根目录执行，路径为本机已核实的 DevEco 安装位置）：

```powershell
$campusDevEco = 'C:\Program Files\Huawei\DevEco Studio'
$env:DEVECO_SDK_HOME = Join-Path $campusDevEco 'sdk'
$env:JAVA_HOME = Join-Path $campusDevEco 'jbr'
& (Join-Path $campusDevEco 'tools\node\node.exe') (Join-Path $campusDevEco 'tools\hvigor\bin\hvigorw.js') assembleHap --mode module -p module=entry@default -p product=default -p buildMode=debug --no-daemon
& (Join-Path $campusDevEco 'sdk\default\openharmony\toolchains\hdc.exe') list targets
```

构建产物：`entry/build/default/outputs/default/entry-default-signed.hap`。先确认是这次新构建的文件，签名用途为debug且设备在 Profile 内，然后安装：

```powershell
& (Join-Path $campusDevEco 'sdk\default\openharmony\toolchains\hdc.exe') install -r 'entry\build\default\outputs\default\entry-default-signed.hap'
```

多设备时在 `hdc` 后加 `-t <目标设备>`。遇到签名不匹配，不要卸载现有 HITA 来硬装；先备份并在 DevEco 修正签名。卸载会清除本地数据。

## 3. 将应用 Skill 导入小艺平台

1. 登录上面的小艺开放平台，使用有权管理 HITA 的开发者账号。
2. 打开 **Skill → 新建 Skill → 导入 Skill**。
3. 使用含 `hita-campus` 的本轮 HAP 走应用 Skill 导入流程，等待平台解读。包内已经包含 `skills/hita-campus/SKILL.md` 和编译的入口代码，模块的 `skillProfiles` 绑定 `EntryAbility`。
4. 核对解析出的 Skill 名 `hita-campus`、应用包名 `cn.berry.hitanext` 和六项能力。按平台提示补全必填资料、校验信息；不清楚的账号准入或关联应用要求以该账号实际页面为准。
5. 平台导入的版本应与手机安装的版本对应。修改代码后重新构建、安装并更新平台导入内容，不要用旧的描述测试新的脚本。

本次请选择上面带 `week-axis-debug` 的新包。若之前已经创建Skill，进入原Skill更新导入内容，并重新发布真机测试；若当前账号界面没有替换包入口，则用“新建Skill → 导入Skill”创建本次测试草稿，测试时确认进入新草稿。不要仅安装手机端而继续使用旧的测试发布。

这里是小艺应用 Skill 的 HAP 导入流程。应用市场上架/公开测试使用 APP 包，属于另一个流程；不要把源码技能目录当作本轮 ArkTS 应用 Skill 的完整可执行包上传。

## 4. 发布真机测试

1. 在 Skill 开发界面右侧管理真机测试用户组，将手机上登录的华为账号加入组中；团队账号需要相应管理员权限。
2. 勾选该测试组，发布到 **小艺主对话** 进行首次测试（本轮以主对话为目标）。官方也提供小艺 Claw 测试入口，需另行验证交互体验。
3. 官方限制：团队最多100个组、每组最多100人、一次最多勾选10组，每次发布有效15天。到期或修改后可重新发布，也可取消。
4. 官方表述是在“小艺应用对话列表页中体验该Skill”，并未明确承诺自动新增一条同名会话或提供可搜索添加的独立条目。首次验证可在小艺主对话中新建对话，输入“使用HITA校园助手，查询HITA NEXT今天的课表”，观察是否召回Skill；这是验证触发的操作建议，具体入口以手机端实际界面为准。发布至小艺Claw时需在对应入口测试。
5. 发布成功但手机端无入口或不能召回时，回到真机测试弹窗，展开“步骤二：升级完成后，确认设备支持小艺Skill真机测试校验步骤”，按平台要求完成设备侧校验。还需核对发布目标、有效期、系统与小艺版本，以及手机是否安装本轮HAP；不能仅凭API26和账号一致判断端侧能力已就绪。记录具体界面与回复再定位，不凭空假定“我的Skill”等菜单存在。

这里的真机测试可在 Skill 上架前进行。本文没有把“小艺真机测试”等同于“AGC公开测试”，也不保证所有开发者账号默认获得相同入口；缺少能力入口时应按平台提示申请或联系华为支持。

## 5. 按顺序验证

| 测试话术或操作 | 预期结果 |
| --- | --- |
| “用 HITA 看看明天的课表” | 与 HITA 当前测试课表一致；时间按手机本地时区展示 |
| “HITA 下一节课在哪里” | 返回未来的下一节课；没有则说明本地未找到 |
| “帮我看看 HITA 最近有什么考试” | 只返回已导入的考试，不把复习日程当考试 |
| “在 HITA 加一个明晚七点到八点的高数复习，地点图书馆” | 打开确认页，保存前课表没有新增 |
| 点“取消”后再查询 | 没有新增；操作状态为cancelled |
| 重新发起，点“确认保存” | 课表出现一个日程；回到小艺说“我已确认，查一下结果”，应查询并回复saved |
| “将 HITA 明天高数这一次改到下午两点至三点四十五，地点正心101” | 先查询准确课程；有多条先选择；确认后仅这一次改变 |
| 同一调用重试 | 复用相同requestKey与参数，不重复新增 |
| 准备修改后，在HITA另行编辑或删除原课程，再回确认页保存 | 拒绝覆盖，提示重新查询 |
| 制造时间重叠 | 确认页显示冲突课程；由用户判断后保存或取消 |
| 直接返回、等待超过30分钟 | 不写入；超时后无法确认旧草稿 |
| 将HITA切到后台后发起添加 | 尝试拉起确认；若系统拦截，回复仍待确认。手动打开HITA可承接当前进程的待确认操作；进程被清理后需在小艺重试同一请求 |

本次时间轴专项验证：在测试课表日期范围内，让小艺添加一条07:30–08:00的日程，确认保存后查看它所在的周，应从07:00显示；切到没有早课的周，应从08:00显示。再添加另一周的23:15–23:45日程，只有该周延长到24:00。来回切换到普通周和空周，都应恢复08:00–23:00。提前/延后只影响周视图范围，不改变已保存的时间。

随后检查桌面下一节课卡片、开启过的课程提醒及已启用的手机日历同步是否跟随更新。浅色、深色各检查确认页一次，检查长名称、冲突文案、滚动和侧滑返回。

## 定位问题

DevEco 的 HiLog 搜索标签 **HitaCampusSkill**：

- 没有 `begin`：尚未捕获到HITA入口执行的证据。检查平台实际发布版本、测试组、发布状态、过期时间、系统与小艺版本，并排查脚本加载阶段失败和日志可见性；不能仅据此断言具体失败原因，也不假定手机存在Skill选择列表。
- 有 `begin`、返回failed：看小艺结果中的message，核对当前课表、日期、eventId、requestKey；不要通过重复生成新key绕过错误。
- 有 `complete` 且pending：请求已进入HITA，仍待用户确认。`confirmationOpened=false`说明打开确认页被拒绝，不代表已保存。
- 有 `system completion failed`：本地完成了业务处理，但系统回包失败；不要再次新建，先用原operationId查询。
- 课表保存成功但日历无变化：核对该课表是否启用了同步及日历权限，不要把它归为小艺未调用。

日志只记录能力名和结果码，不主动记录完整课程或输入文本。平台端的解析、触发选择和最终自然语言回复必须实际联调后验收。

## 本轮验证记录

- ArkTS SDK编译及签名HAP打包通过，包内Skill描述与模块注册已核对。
- 本轮业务和回归测试139项通过，包含当前周时间轴扩展、普通/空周恢复、早晚日程绘制位置、小艺业务、数据库事务（平台RDB边界使用mock）、保存后状态写入失败、确认期间收到新草稿，以及提醒、日历、课表显示等回归。
- 用户已在平台导入并发布真机测试，但小艺仍返回无法操作HITA。手机已出现“Skill真机测试中”；读取系统版本为OpenHarmony-7.0.0.105、API26，小艺版本为11.7.8.303，符合平台弹窗列出的环境条件。
- 用户确认保存的Skill配置为“是否依赖沙箱：否；目标API：26；最小API：26”，并确认保存后已重新发布真机测试，仍无法调用。
- 平台导出的hita-campus.zip仅含SKILL.md，该文件与本地原文SHA-256一致（BE3F59AB86BFBA33397A42CAFAFE6CD8DE0481EE099FEA594143253F59A851AB），六项能力及调用命令未被扫描流程改写。
- 上次用户重试期间未捕获到HitaCampusSkill入口日志；尚未定位召回、部署或脚本加载中的具体故障。小艺端到端调用、后台拉起和确认页浅/深色视觉验收尚未通过。
- 官方[系统CLI文档](https://developer.huawei.com/consumer/cn/doc/doccenter-celia/skil-cli-0000002623371047)提供“@ → 系统CLI → 添加工具到当前Skill”的操作。用户确认该列表没有ohos-arkTSScript；文档未明确该应用Skill命令必须手动添加，列表缺失不能作为根因，不据此要求开启沙箱或更改API版本。
- 本轮扩大抓取范围后，用户在北京时间21:05:49左右发送请求，客户端日志出现SimulatingOperation/UpdateJarvisTaskState、intentName=APP_OPERATION，最后intentName=CHAT；未见ArkTS调度或HITA入口日志。推断优先排查Skill召回和调度，具体故障仍未定位。
- 已在本地.analysis/campus-skill生成脱离CLI的临时描述加载验证包及供华为定位的排障记录。原始功能Skill源码及HAP未修改；临时包仅用于平台诊断，不能当作功能修复包。
- 随后用户提供临时验证的手机截图：输入“HITA联调检查”，小艺回复能力未正常返回，没有输出验证口令。本轮描述加载验证未通过；平台当前实际发布的SKILL.md尚未取到，不能确定临时描述是否已被发布或采用。小艺的自然语言回复不是ArkTS执行错误码，不能据此判定课程业务或工具执行失败。本轮未实时抓取，事后日志缓冲不覆盖该请求，不能将未见入口日志作为此次请求的完整调用证据。
- 用户随后提供平台新导出的hita-campus (1).zip。包内SKILL.md为746字节，与本地临时验证描述逐字节一致，SHA-256均为2927A925CDC7BC12BB24B7C555542E645C825D90B166DBEB47B45181E8310613，口令未被改写。当前导出内容已确认；它与测试时实际下发版本的对应关系、云端候选及描述采用情况仍待平台记录核实。排障材料已更新，尚未对外提交。
- 源码及交接文档随本次提交交付；签名、构建产物和原始设备日志留在本地，未发布应用市场。
