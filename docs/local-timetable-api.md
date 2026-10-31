# 本地课表获取接口

## 应用内调用

入口：`entry/src/main/ets/feature/assistant/LocalTimetableApi.ets`。

```ts
import { LocalTimetableApi } from '../feature/assistant/LocalTimetableApi';

// 查询当前选中课表，所有日期，第一页。
const response = await LocalTimetableApi.query(context);

// 按日期查询；也可以只传一个日期，表示查询该日。
const responseForDay = await LocalTimetableApi.query(context, {
  startDate: '2026-11-02',
  endDate: '2026-11-02'
});

// 教学周直接按应用的校历筛选，无需调用方换算日期。
const thirdFriday = await LocalTimetableApi.query(context, {
  teachingWeek: 3, dayOfWeek: 5, limit: 10
});
const nextClass = await LocalTimetableApi.query(context, { queryMode: 'nextClass', limit: 10 });
const exams = await LocalTimetableApi.query(context, { queryMode: 'upcomingExams', limit: 10 });

// hasMore 为 true 时，以相同日期条件继续读取。
const nextPage = await LocalTimetableApi.query(context, {
  offset: response.result.nextOffset,
  limit: 200
});
```

`context` 必须是 Hita 自己的应用/Ability 上下文。此接口读取设备本地 RDB，
不请求教务服务器，不调用大模型，不修改课程。首次打开数据库仍沿用现有 RdbHelper 的建表与旧数据修复流程。
课表 API 通过 `LocalTimetableReader` 读取当前课表及独立考试。应用内旧聊天助手已移除，
「更多 → 助手」通过官方 `FunctionComponent` 在 HITA 上方呼出小艺半屏 HITA 助手，
仍通过下述意图读取课表。入口的应用关联与签名要求见 `docs/xiaoyi-assistant-entry.md`。

## 后台意图入口

已增加 `TimetableIntentExecutor.ets`，并在 `module.json5` 注册
`$profile:insight_intent`。应用侧标识为：

| 项目 | 值 |
| --- | --- |
| 包名 | `cn.berry.hitanext` |
| UIAbility | `EntryAbility` |
| 意图/工具名称 | `Timetable` |
| 版本 | `0.1.0` |
| 应用自定义 domain | `hita` |
| 执行方式 | `background` |

这里的 `hita` 是本项目选择的自定义域，**不是已确认的小艺平台默认值**。
对接平台时需核对平台要求的完整意图标识、域和版本；如平台下发其他域，修改
`insight_intent.json` 使两端一致。本地注册和编译成功不等于平台已经绑定或发布。

后台执行器使用 EntryAbility 通过独立的 `TimetableExecutionContext` 模块提供的应用上下文，
并等待启动时备份恢复完成。不要把上下文存放在执行器入口类的静态字段上：
系统再次加载执行器入口时，该入口上的状态可能重新初始化。
Ability 销毁时只移除属于自己的上下文；等待启动期间若上下文已被替换，本次查询返回失败。
`InsightIntentExecutor.context` 不是数据库所需的应用 Context，因此不直接拿它打开数据库。

这是一项端侧能力，没有 HTTP 服务地址。截图中的 `ai_plugin`/`openapi` 描述不是应用的意图注册文件；
不要为此启动手机 HTTP 服务，也不要给 `servers` 填一个虚构的网址。

## 工具参数

所有输入参数均可选。平台可先配置为无必填参数工具，让 Agent 自行决定日期和分页条件。

| 参数 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `startDate` | String | 不限制日期 | `YYYY-MM-DD`，开始日期 |
| `endDate` | String | 与另一日期相同 | `YYYY-MM-DD`，结束日期，包含当天 |
| `teachingWeek` | Double（填整数） | 不限制教学周 | 1～1000；按当前选中课表起点计算，不与 startDate/endDate 混用 |
| `dayOfWeek` | Double（填整数） | 不限制星期 | 周一 1 至周日 7；配合教学周查询某天，省略时查询整周 |
| `queryMode` | String | `range` | `range` 普通范围；`nextClass` 下一节课；`currentClass` 正在上的课；`upcomingExams` 尚未结束的考试 |
| `offset` | Double（填整数） | `0` | 非负整数，跳过匹配记录的条数 |
| `limit` | Double（填整数） | `200` | 每页 1～500 条 |

日期按设备本地时区解释，与现有 Hita 课表一致；返回 `timeZone` 和带 UTC 偏移的时间字符串。
只提供开始或结束日期时查询这一天；两者均不提供时不限制日期。
跨午夜的记录只要与指定日期范围重叠就会返回。不存在的日期、日期倒置、字符串形式的分页数字都会返回参数错误。
上述严格类型约束用于应用内 API。端侧执行器另外兼容平台传来的纯数字字符串分页参数，
并省略可选字段的 null、空字符串默认值；仍校验日期、整数范围和每页上限。

`teachingWeek` / `dayOfWeek` 同样支持端侧入口的纯整数文本适配，应用内 API 仍严格要求数值。
教学周范围由 HITA 计算，并在返回的 startDate/endDate 中给出真实日历日期；
每条记录继续带有由应用模型计算的 teachingWeek/dayOfWeek。
`dayOfWeek` 也可单独用于日期范围内的星期筛选，按照记录开始时间所属星期判断。

`nextClass`、`currentClass`、`upcomingExams` 使用查询时的手机时钟，不能同时传日期、教学周或星期。
`nextClass` 只保留尚未开始、最早时刻的 CLASS，保留所有同一时刻并列课程；
`currentClass` 只保留已经开始且尚未结束的 CLASS；
`upcomingExams` 只保留尚未结束的 EXAM，按开始时间排序并支持分页。
这些模式的 total / hasMore 描述已筛选的结果，不需要模型从全学期课程中自行找下一节或考试。

## 返回结构

应用内 `LocalTimetableApi.query()` 返回 `{ code, result }`，`result` 是下文的结构化课表对象。

**端侧工具传输格式**保留平台固定的 `code`（数值）和 `result`（Object），
在 `result` 下只放一个 `data`（String）子字段，其值为结构化课表对象的完整 JSON 文本：

```ts
// 意图执行器返回给小艺；与应用内接口区分。
return { code: response.code, result: { data: JSON.stringify(response.result) } };
```

平台需要显式声明并启用 `result.data`。Agent 先解析该字符串，然后读取其中的
`courses`、`total`、`currentTime` 等字段。不要把传输字段改成 `result` 字符串，
也不要再直接读取传输对象的 `result.courses`。这样只需配置一个输出子字段，
减少平台嵌套字段配置与实际课程对象不一致的机会。

| code | 含义 |
| --- | --- |
| `0` | 查询成功；可能确实没有匹配记录 |
| `1` | 没有可用的本地课表 |
| `2` | 查询参数无效 |
| `3` | 数据读取失败或应用尚未准备好 |
| `4` | 后台执行器收到不支持的工具名称 |

应用内 `result`（亦即端侧 `result.data` 解析后的对象）包含以下字段：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `message` | String | 结果说明 |
| `source` | String | 固定为 `local`，仅代表本地已保存的数据 |
| `currentTime` / `timeZone` | String | 当前时间及设备时区 |
| `hasTimetable` | Boolean | 是否找到可用课表 |
| `timetableId` / `timetableName` | String | 当前选中课表的 ID、名称 |
| `termStart` / `termEnd` | String | 保存的学期起止时间 |
| `currentWeek` | 数值 | 当前教学周；学期外为 `-1` |
| `startDate` / `endDate` | String | 生效的日期筛选，空字符串表示不限日期 |
| `total` | 数值 | 本次条件下全部匹配记录数 |
| `offset` / `limit` / `returned` | 数值 | 当前页偏移、容量和实际返回条数 |
| `hasMore` | Boolean | 后面是否还有记录 |
| `nextOffset` | 数值 | 下一页偏移；无后续页时为 `-1` |
| `isComplete` | Boolean | 当前响应是否一次覆盖全部匹配记录；后续分页始终为 false |
| `courses` | Array&lt;Object&gt; | 本页课表项目，包含课程、考试和其他事项 |

`courses` 的子项：

- `id`、`subjectId`、`timetableId`：原始记录和关联 ID。
- `type`：`CLASS`、`EXAM` 或 `OTHER`；合成的 `TAG` 不返回。
- `name`、`teacher`、`place`：名称、教师和地点。
- `startTime`、`endTime`：包含时区偏移的时间，例如 `2026-11-02T08:00:00+08:00`。
- `startTimestamp`、`endTimestamp`：原始 Unix 毫秒时间戳。
- `dayOfWeek`：周一为 1，周日为 7。
- `teachingWeek`：该记录按当前课表计算的教学周，学期外为 -1。
- `firstPeriod`、`lastPeriod`：开始/结束节次，沿用本地记录；自由时间记录可能为 -1。

只有当前选中课表及无课表归属的独立记录会返回，不混入其他学期。
当前选中课表已删除时，沿用主页面的默认选择规则：优先导入课表，其次手动创建的课表。
接口保留每条记录的真实 ID，不合并同名同时段课程，避免把独立课次或考试隐藏掉。
不返回 Cookie、密码、学号或模型密钥。

## 给 Agent 的调用约定

可复制的完整角色指令见 [xiaoyi-timetable-agent-prompt.txt](xiaoyi-timetable-agent-prompt.txt)。
角色指令应填写在 **Agent 编排页面的「角色指令」** 中；工具描述只描述工具能力，
不能代替将工具添加到 Agent。

### 在单 Agent 中接入

1. 在 Agent 编排页面的插件区域添加自己的「课表查询」插件，选择 `Timetable`、版本 `0.1.0`。
   在资源库创建工具并不代表该 Agent 已经绑定它。检查当前测试的 Agent 中确实列出了该工具。
2. 打开已添加插件的「插件参数设置」。输入参数保持可选，允许模型传入日期及分页参数。
   在该 Agent 中将 `limit` 默认值设为 `10`，保留参数对模型可见，以便首次读取元数据时传 `1`。
   这是 Agent 的调用默认值；应用 API 自身未传 limit 时的默认值仍为 200。
3. 在资源库的 Timetable 工具编辑页，保留固定输出 `code`、`result`；
   点击 **result 行右侧「添加子项」**，名称填 `data`，类型选 `String`，
   描述填「本地课表查询结果的完整 JSON 文本，需解析后读取 courses、total、教学周、时间和分页信息」，设为必填。
   这里 `data` 是 `result` 的子项，不是与 `result` 同级的新输出，也不是输入参数。
   保存工具后，还需在资源库的插件「工具」页点击「升级」，填写版本说明并等待状态回到「已上架」。
   仅保存工具会更新编辑态，Agent 添加插件时仍可能取得旧的已发布定义。
   然后在 Agent 编排页移除旧绑定并重新添加该插件，以刷新输入和输出结构。
4. 在 Agent 的「插件参数设置 → 输出参数设置」开启「融合生成」，并启用 `code`、`result` 和 `result.data`。
   `result` 的父级开关开启不能代替确认 `data` 子字段已声明并启用。
5. 将上述文本文件内容放入角色指令，保存配置，点击「真机测试 → 重新发布」，
   将当前编排更新到开发测试态，再在手机新会话测试。
   如果端插件版本发生变化，需要在 Agent 编排页面移除旧版本并重新添加新版本。
6. 端插件读取手机应用数据需要真机调试。网页调试中的模拟集只验证模拟数据，不能证明已读到设备课表。

### 调测时先检查有没有调用

最初用户报告网页调测树里没有 `Timetable`，因此先核对 Agent 的工具绑定和角色指令。
2026-10-31 的后续真机日志已确认：小艺找到了注册的 `Timetable` 并进入 HITA 执行器，
当时由应用返回 `code=3`。本次复现的失败发生在应用内，不能继续按“未绑定工具”处理。

00:33:51 应用记录了 `attach application context`，00:34:00 执行器却记录
`execute supported=true context=false`、`failed stage=context`。当时上下文保存在执行器
入口类的静态字段上，入口重新加载后丢失。将状态移到独立共享模块后，覆盖安装修复包，
00:39:16 的同机调用记录 `context=true`，随后成功完成数据库、课表选择、课程和独立事项读取，
00:39:17 返回 `query completed code=0 returned=152 total=152`。
这证明应用侧本次读取并返回了全部 152 条本地记录。

之后用户反馈仍被回答“没有课”。00:46:53 的无参数调用，应用和系统调用日志均为 `code=0`，
应用返回数量仍为 152；用户要求小艺列字段时，它回答 `total`、`returned` 和第一条课程均缺失，
并确认已开启融合生成和 result 开关。尚未取得平台原始输出，不能仅凭模型答复确定是哪个环节丢字段。
为便于明确声明与验收，端侧输出改用单个 `result.data` JSON 文本字段；
必须同步更新平台子字段和角色指令，验证模型实际读取的条数与首条课程，不能只看 `code=0`。

00:44:44 的 `limit=1` 测试另返回 `code=2`，这是参数校验失败，不能视为没有课。
端侧入口新增数字字符串/可选空值适配及输入类型诊断；并未取得那次原始输入，具体触发字段尚未确认。

### 2026-10-31 平台字段缺失修复

01:02:28 真机调用已返回 `code=0 returned=1 total=152`，JSON 长度为 781 字符，
但小艺仍报告 `result.data` 缺失。直接检查平台资源库发现：

- 输出仅声明 `code` 和 `result`，`result.subOutputInfos` 为空，实际没有 `data` 子字段。
- 日期输入误写为 `startdate` / `enddate`，与执行器的 `startDate` / `endDate` 不一致。
- `offset` / `limit` 声明成 String；该次手机日志确认为字符串输入，入口兼容适配后读取成功。
- 最低应用版本填成 `0.4.1`，实际安装包版本为 `0.4.0`，因此改为 `0.4.0`；未改应用版本或签名。

上述配置已修正并保存，刷新工具页面后再次读取 JSON 确认 `result.data` 存在。
只保存并重新绑定时，Agent 仍显示旧参数；01:17 提交插件发布版本 V2 后状态回到「已上架」，
再次移除并添加 Timetable，Agent 才显示 `result → data（String）`，融合生成和该字段均开启。
插件发布版本 V2 与意图工具版本 `0.1.0` 是不同层级；此次保留工具版本以匹配应用注册信息。
01:21 完成 Agent 开发测试重新发布，未提交 Agent 正式上架。

01:23:06 真机日志再次返回 `code=0 returned=1 total=152`，用户确认小艺已能解析 `result.data`，
正确报告总数 152、本页 1 条及首条课程名称、地点。小页真实数据的应用到模型链路已验收。
原始教学周查询、下一节课回答以及其他设备场景需分别核对，不能用小页成功替代完整验收。

小页成功后的自然语言测试返回小艺系统兜底语句，未给出课程答案。01:23～01:24 的设备日志显示，
这些调用没有传日期和分页参数，每次返回全部 152 条记录，`result.data` 为 53,734 字符。
尚未取得云端原始报错，因此不能确认具体响应长度上限；已改为按问题缩小查询范围以避免大结果。
01:28 更新角色指令：先用 `limit=1` 读取本轮设备时间及学期起点，再以 `limit=10` 查询所需日期，
教学周问题用学期起点换算目标日，下一节课直接从当天起查询未来记录。
同时设置 Agent 的 limit 默认值为 10，并重新发布开发测试。自然语言结果待真机核对。

随后自然语言提问多次得到“没有课”，对应设备采集没有新的 `HitaIntent` / `HitaQuery` 记录。
手机对话仍保留此前的错误答案。关闭长期记忆并重新发布后，这一现象仍存在；
不能将关闭长期记忆等同于清除当前对话上下文。
01:52:51 显式要求重新调用 `Timetable(limit=1, offset=0)` 时，日志立即记录
`code=0 returned=1 total=152`，小艺正确报告同一时间的 `currentTime`、total 和 returned。
该对照说明此时工具链路和日志采集可用，普通提问的“没有课”没有本轮设备查询依据。

进一步检查模型设置发现“携带上下文轮数”为 20，独立于长期记忆开关。
为排除旧错误回答的影响，已临时设为 0，保存并确认开发测试提示“发布成功”。
01:55:56 的自然语言提问随后触发元数据查询，01:55:58 又触发日期查询并返回 1 条记录。
这说明该轮自然语言工具调用恢复，但不代表日期或答案已正确。
用户指出模型把第三周周五答成 10 月 16 日（应用中为第七周）。随后显式读取确认：
termStart 为 `2026-08-31T00:00:00+08:00`、currentWeek=9，首课是 9 月 14 日、teachingWeek=3。
应用教学周数据与页面一致；第三周周五应为 9 月 18 日，错误发生在模型日期换算/使用环节。
用户还报告“最近的考试”将 11 月 7 日的微积分 A 考试误答为 9 月 14 日课程日期。

### 2026-10-31 应用执行教学周、下一节及考试筛选

为避免模型自行换算教学周及混用课程/考试，新增 teachingWeek、dayOfWeek、queryMode 三个可选参数。
保留原日期与分页契约、工具名称及意图版本 `0.1.0`，仍通过 result.data 传输。
角色指令改为教学周直接传周次和星期；下一节、正在上的课、最近考试分别传对应 queryMode。
01:55 的对照后继续保留上下文轮数 0、长期记忆关闭，防止历史错误答案代替本轮查询。

相关原 69 项检查通过，新增未来考试回归后本地接口 28 项全部通过；静态检查及 ArkTS 编译通过，
签名 HAP 已保留数据覆盖安装。新增测试覆盖教学周 3/7 的实际日期差异、修改学期起点后的范围、
星期筛选和分页、下一节并列课程、当前课程边界、同名普通课程与未来考试区分、非法/冲突参数及端侧适配。
新日志增加模式、教学周、星期、解析后的日期范围和数量，不打印课程名称、地点或账号数据。

平台 02:07:09 发布插件 V3，Agent 已移除旧绑定并添加新定义；确认三个新增输入对模型可见，
limit 默认 10，融合生成与 code/result/data 均开启。
角色指令已刷新页面确认持久化，并重新发布开发测试、捕获“发布成功”。
02:18:34 真机自然语言查询记录 `mode=range week=3 weekday=5 from=2026-09-18 to=2026-09-18`，返回 1 条；
02:18:44 “下一节课在哪上”记录 `mode=nextClass`，返回 1 条；
02:18:53 “查询最近的考试”记录 `mode=upcomingExams`，返回 2 条，均为 code=0。
手机答复分别为 9 月 18 日的军事理论、下一节微积分 A 的真实教室、11 月 7 日微积分 A 期中考试及 11 月 15 日另一场考试。
用户已对照 HITA 确认三项全部一致，本轮原始自然语言问题及新增考试问题验收通过。
按用户随后要求，角色指令调整为日程默认显示“几月几日＋时间”，只在明确询问教学周时补充周次；
下一节课不能仅显示“第几周周几”。此项只改变回答格式，已刷新页面比对保存后的完整指令，
确认一致并重新发布开发测试成功。真机调用证据保存于 `.hvigor/timetable-natural-language-verified.log`，
本轮远端日志采集进程已停止。

诊断日志使用 `HitaIntent` / `HitaQuery` 标签，仅记录执行阶段、状态和数量，
不记录课程名称、地点或账号信息。

- 没有 `Timetable` 调用：检查上述 Agent 配置；此时具体课程或教室没有本轮工具数据依据。
- 有调用但未进入应用／返回平台错误：核对安装包、工具名称与版本、包名、执行方式及原始错误码。
- `code != 0`：按错误码处理，保留原始返回以定位。
- `code == 0` 但模型仍说无法读取／没有课：检查 `result.data` 是否存在、可解析，及子字段声明、融合生成和输出开关。
- 缺少 `data` 或解析后缺少 `courses`，以及 `returned` 与数组长度不一致，都属于数据缺失，不能当成无课。
- 模型收到完整课程数据仍答错：对照 `teachingWeek`、`dayOfWeek`、`currentTime`、`type`、
  `place` 和分页字段核对筛选过程。

验收先用：“请调用 Timetable，不传参数，解析 result.data，告诉我真实返回的 code、课表名称、
total、returned 和第一条课程的名称、地点；未得到工具返回或 data 缺失就如实说明。”调测记录中必须出现实际工具调用，
然后再测第三周周五与下一节课两种问题，并与 HITA 界面核对。

平台配置依据：华为《单Agent模式》中的“步骤三：编写角色指令”“步骤四：添加插件”及“输出参数设置”。
官方文档：https://developer.huawei.com/consumer/cn/doc/doccenter-celia/llm-mode-gent-0000002762843985

本接口是查询能力，不执行添加、修改或删除课程，也不代替教务系统实时查询。

## 验证

```powershell
$env:NODE_PATH = 'D:\deveco studio\Deveco studio\sdk\default\openharmony\ets\build-tools\ets-loader\node_modules'
node --test scripts/local-timetable-api.test.cjs scripts/database-integrity.test.cjs scripts/more-features-navigation.test.cjs
node scripts/static-checks.cjs
```

平台联调需安装包含该入口的构建，核对工具名称、域、版本和最低应用版本，并在小艺端绑定插件。
后台冷启动、切换课表后的查询、空课表、分页和应用关闭后的再次调用需要在设备上验收。

2026-10-31 共享上下文修复验证：相关测试共 59 项通过，ArkTS 编译、签名和保留数据的覆盖安装成功。
新增回归覆盖系统重新加载执行器入口、启动恢复等待、旧 Ability 销毁及上下文替换。
真机应用侧成功返回 152 条记录。
后续 JSON 文本传输及输入适配验证：相关测试共 63 项通过，静态检查通过（175 个文件、16 个路由）。
新增回归覆盖声明单一文本输出后的完整数据、转义字符、分页、参数适配与错误/空课表区分。
最新代码已通过 ArkTS 编译并签名，保留数据覆盖安装成功。
最新传输格式的平台配置及真机小页查询已验收；原始自然语言问题及其他设备场景仍需分别验收。
