# 小艺课程与作业工具

端插件支持查询课表、搜索课程、向当前课表添加一次课程，以及添加、查询、完成课程作业。
沿用现有 Agent Framework Kit 小艺入口和已接通的 Timetable，不需要重建智能体或启用手机 HTTP 服务。
课程修改/删除、考试增删改和复习任务操作尚未开放。课程添加只支持明确日期和起止时刻的一次安排。

已有作业工具可跳转的用户，本次只需新增 PrepareCourse、更新 ConfirmLearningOperation 描述和角色指令，
保留其余已验证的输入输出配置。逐项填写步骤见 [添加课程同步说明](xiaoyi-course-setup.md)。

## 安装与平台同步

1. 安装本次编译的调试 HAP，保留现有数据。
2. 在小艺平台**现有端插件**的工具列表配置下面6个工具（另保留原有 Timetable）。所有工具的应用包名是 `cn.berry.hitanext`，
   UIAbility 是 `EntryAbility`，domain 是现有的 `hita`，意图版本均为 `0.1.0`。
   如果平台绑定的域不是 hita，应沿用已验证的绑定并同步调整应用声明，不能只改一侧。
3. 输入类型和必填项见下表。其余参数可选，不填时应省略或留空，不要注入0、false等无关默认值。
4. 每个工具固定输出 `code`、`result`；**result 下添加必填的 String 子字段 data**。
   工具执行结果是 `{code, result:{data:"JSON文本"}}`，不是根节点 data。
5. 保存后在插件工具页执行“升级”，等待上架，再在智能体编排中移除旧绑定并重新添加新版插件。
   打开输出参数的融合生成，启用 code、result 和 result.data。
6. 用 [xiaoyi-timetable-agent-prompt.txt](xiaoyi-timetable-agent-prompt.txt) 全文替换角色指令。
   保存后**重新发布真机测试**，手机新建对话测试。插件发布版本与这里的意图版本是两个概念。

完整参数清单另见 [xiaoyi-study-tools.json](xiaoyi-study-tools.json)。该文件是配置对照表，**不是华为官方一键导入包**。
平台不同版本的菜单名称可能变化；关键是绑定到当前 Agent 的已发布工具、输入、输出和执行模式都更新。

| 工具/意图名称 | 执行模式 | 必填输入 | 可选输入 |
| --- | --- | --- | --- |
| StudyQuery | background | action（String：courses / tasks） | keyword、subjectId、status、dueDate（String），offset、limit（Double，整数） |
| PrepareCourse | background | requestKey、courseName、date、startTime、endTime（String） | place、teacher、subjectId（String） |
| PrepareHomework | background | requestKey（String） | courseName、subjectId、title、note、dueDate、dueTime、remindDate、remindTime（String）；courseName/subjectId至少提供一个 |
| PrepareTaskCompletion | background | requestKey、taskId（String） | 无 |
| LearningOperation | background | operationId（String） | 无 |
| ConfirmLearningOperation | **foreground** | operationId（String） | 无 |

**不要将确认工具配置成后台执行，也不要在平台添加“自动确认”参数。** 后台工具只准备草稿；确认工具只打开本机确认页。
用户在本机点击确认后才会修改课表或学习待办。工具不等待用户操作，因此打开页面后返回 needs_confirmation；
用户返回对话时通过 LearningOperation 获取最终状态，不依赖长时间阻塞或连续轮询。

## 参数与结果

- `PrepareCourse`：添加一节 CLASS 课程，必填课程名、日期和 HH:mm 起止时间；地点、教师可省略。
  课表中没有该课程时创建新科目，唯一精确同名时关联已有科目；同名歧义返回 needs_selection/candidates。
  不模糊关联名称相似的课程，不跨课表匹配；subjectId仅接受当前课表中与名称一致的真实ID。
  只创建待确认草稿，确认页展示课表、完整年月日、时间、地点和教师；用户确认后科目、CLASS事件和saved回执在同一事务提交。
  当日结束时间必须晚于开始时间，日期不能早于该课表第一周；超过学期末时沿用手动加课规则扩展到对应教学周。
  返回 course（eventId/subjectId/timetableId/name/type/date/startTime/endTime/place/teacher），不返回作业task。
  同样安排已存在返回 already_exists；确认前关联科目被修改/删除、学期开始日期变化或被手动添加时拒绝旧草稿。
- `StudyQuery`：courses 按名称/课程代码查找，精确匹配优先；同名不同subjectId均返回。
  tasks 仅查询当前课表的 HOMEWORK，默认 status=pending；也支持 completed/all。
  keyword 匹配作业标题或课程名称，subjectId 精确关联，dueDate 查询该日截止的作业。
  默认 limit=10，范围1～50；offset为非负整数。结果包含 records、total、returned、hasMore、nextOffset。
  records 中课程有 subjectId/timetableId/name/courseCode，作业有 taskId/title/note/courseName/dueDate/dueTime/allDay/remindAt/completed等。
- `PrepareHomework`：支持课程名直接匹配；匹配多门返回 needs_selection/candidates，请用户选择后使用 subjectId。
  找不到返回 course_not_found。名称缺省时使用“课程名+作业”，不要求地点；note最多4000字符。
  未设置 dueDate 时允许无截止日期的作业。只给日期时是全天截止，沿用学习待办的当日结束语义。
  dueTime 必须是 HH:mm；remindDate/remindTime 必须成对提供，提醒不能晚于截止时间，且需要本机通知权限。
- 日期支持 YYYY-MM-DD、MM-DD、M月D日、今天/明天/后天/下周一等明确某天的相对日期。
  日期由设备本地时区计算，星期一到星期日为日历周。未指定年份取下一次到来的该月该日（今天也可），
  非法日期、只有“下周”等不确定具体日期会报错，不能由模型猜。2月29日需明确有效年份。
- `PrepareTaskCompletion`：必须使用刚查询到的 taskId；仅完成当前课表课程作业。
  完成后取消该作业已发布的通知，后续提醒循环不会再次提醒它。
- `requestKey`：8～80位字母、数字、`-`、`_`。相同请求重试复用；同一key改变内容会拒绝。
  在平台设为必填且对模型可见，**不要填写固定缺省值**。每次新操作生成新的随机UUID，参数完全相同的重试复用；
  课程、标题、备注、截止日期、提醒或taskId改变时必须换新值。返回 `request_key_conflict` 时本次未创建草稿，
  不含旧 operationId，保持当前参数、换新标识重试一次；仍失败就停止并说明原因。
  相同未确认内容即使换key也尽量复用草稿，但不同课表、不同任务修订和不同实际截止时间不会混用。
  已保存的相同作业返回 already_exists；已完成的作业返回 already_completed。
- `LearningOperation` 和 `ConfirmLearningOperation`：operationId 必须来自准备工具，不接收模型自造的ID。
  操作状态为 needs_confirmation、saved、cancelled 或 expired；草稿30分钟过期。
  查询 saved 是该次操作的历史回执，任务之后可能被用户编辑或删除，查当前状态应重新 StudyQuery。
- 错误：code=2 参数错误，code=3 读取/执行失败，code=4 工具或前后台模式不支持。
  错误和未确认不能解释为无数据或保存成功。
  `request_key_conflict` 与 `needs_selection` 一样是 code=0 的业务状态，仅表示收到并处理请求，不能解释为添加成功。

## 2026-11-03 真机问题记录

手机日志确认 PrepareHomework 以 background 到达 HITA，返回 `requestKey 已用于其他操作，请重新发起`（旧版 code=2）。
输入中 requestKey/courseName/dueDate 均为字符串，其余可选字段未传；因此此次卡住并非请求未送达或HAP缺少工具。
此次更新让冲突通过 `request_key_conflict` 明确返回，同时修正角色指令中容易被照抄的固定标识示例。
仍需在平台更新 requestKey 参数描述和角色指令，不能只安装HAP。

同次系统日志还有 `is not function type or methodResult is invalid`，小艺未拿到可供后续调用的结果项。
PrepareHomework 当时“是否涉及端侧 App 操控”为“是”；当前正通过改为“否”、保留 background 和 result.data 融合生成做对照验证。
这是一项待真机确认的关联，不能把该开关与执行模式视作同一字段，也不能把它认定为已经证实的唯一原因。
用户更新平台配置后再次测试，15:15:03 HITA 返回 `code=0/status=request_key_conflict`；
系统仍记录相同的结果处理提示，未记录 ConfirmLearningOperation 调用，用户收到“请打开HITA确认”但未跳转。
后续用户确认平台输出参数缺少 result.data，补上该字段后已能跳转添加作业确认页。
这验证了作业草稿回传和前台跳转；保存结果、取消及重试仍需按下列步骤验收。不能将该结果视为新增课程工具已同步。
新版端插件需在Agent中移除旧版再重新添加，参见[华为插件升级文档](https://developer.huawei.com/consumer/cn/doc/doccenter-celia/plugin-upgrade-0000002525143219)。

## 真机验收示例

1. “搜索概率论课程”：只返回当前课表的匹配课程；同名课程全部展示。
2. “帮我添加一个11月10日截止的概率论作业”：调用准备工具，展示课程、课表和实际截止年月日的确认页；
   不询问地点或具体时间。点击确认后，学习待办中新增一条全天截止作业。
3. 原样重试、返回确认页重复点击、查询相同requestKey：仅保留一条作业。
4. “我有哪些没完成的作业”：从真实作业表查询，保留逾期未完成项，记录多时分页。
5. “把概率论作业标为完成”：先选准确作业，再显示完成确认页。确认后在已完成列表查看；提醒被取消。
6. 添加/完成时取消确认、返回离开、等待草稿过期：不修改任务，不报告成功。
7. 在确认前手动编辑/删除任务或删除课程：确认会拒绝过时操作，让用户重新查询。
8. 按设备本地日期测试跨年、午夜、下周一；开启提醒时测试拒绝通知权限再重试。
9. “帮我在11月11日13:00到15:45之间添加一门集成运算放大器的应用电路，地点H702”：调用 PrepareCourse，
   即使当前课表没有该科目，也打开课程确认页。取消不加课；确认后课表中应有该日期13:00—15:45的CLASS和H702地点。
   重复相同指令不应再添加一条。试验新课程日期时以手机本地日期和当前课表为准。

## 本地验证与限制

数据库事务测试使用真实内存 SQLite，覆盖原子提交、失败回滚、重试、取消、过期、课程变化和任务修订冲突。
后台/前台执行器与确认页控制逻辑另有回归测试。数据库与确认回执存于本机，不上传账号、Cookie或密码。
学习待办内容通过用户配置的小艺端插件返回给智能体处理，查询默认限定当前选中课表。

现有 Agent Framework Kit 入口依赖真机的小艺组件，本地 API23 模拟器缺少该组件、API26镜像尚未安装。
本次本地编译及逻辑回归不能替代平台联调和浅/深色真机界面验收。
需要在上述插件绑定、发布完成后检查前台工具能否实际打开确认页，以及确认返回后模型是否重新获取 saved 回执。
