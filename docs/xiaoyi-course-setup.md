# 小艺平台同步：添加课程

先安装包含 `PrepareCourse` 接口的最新版 HITA NEXT（本次版本为 0.4.2）。真机联调使用同一源码编译并签名的调试 HAP，覆盖安装以保留数据。
仅安装HAP或仅修改角色指令都不够；新工具需要在平台端插件中注册并绑定到 Agent。

## 1. 在现有端插件中新建工具

显示名称可填“添加课程”，工具意图名称必须为 **PrepareCourse**，大小写一致。

| 配置 | 填写值 |
| --- | --- |
| 应用包名 | cn.berry.hitanext |
| UIAbility | EntryAbility |
| domain | hita（沿用当前已验证的域绑定） |
| 意图版本 | 0.1.0 |
| 执行模式 | 后台执行 background |
| 是否涉及端侧 App 页面操控 | 否 |

工具描述可直接复制：

> 向当前课表添加一节课程，准备草稿后调用ConfirmLearningOperation确认。允许课表中尚不存在的新课程，不要用PrepareHomework替代。只支持一次明确日期的课程，不直接保存。

## 2. 输入参数

以下全部是 **String**，缺省值全部留空。描述可逐行复制。

| 名称 | 必填 | 描述 |
| --- | --- | --- |
| requestKey | 是 | 每次新操作生成新的随机UUID，8至80位字母数字横线下划线，无固定缺省值。相同参数重试复用；参数改变或返回request_key_conflict时换新值。 |
| courseName | 是 | 要添加的完整课程名称，最多120字符。无需先在已有课表中找到；同名唯一课程自动关联，否则新建课程。 |
| date | 是 | 上课日期，如11月11日、明天、下周一或YYYY-MM-DD。未说年份就原样传，由HITA按手机时间计算，不要猜年份。 |
| startTime | 是 | 课程开始时间，24小时HH:mm，如13:00。缺少时询问用户，不编造。 |
| endTime | 是 | 同一天的课程结束时间，24小时HH:mm，如15:45，必须晚于startTime。 |
| place | 否 | 上课地点，如H702。未提供可以省略，不必追问。最多120字符。 |
| teacher | 否 | 教师姓名，仅用户明确提供时填写，最多120字符。 |
| subjectId | 否 | 仅同名课程歧义时使用candidates中用户选定的真实ID，不能编造。新课程省略。 |

## 3. 输出参数

与当前已经修好的 PrepareHomework 保持相同结构，并开启**融合生成**：

```text
code     Double
result   Object
  data   String，必填
```

data 描述可填：完整JSON文本，解析后读取status、operationId、course和message；needs_confirmation仅代表草稿，必须调用ConfirmLearningOperation打开确认页，LearningOperation返回saved后才算保存。

data 必须是 result 的子字段。不要另建根字段 course 或根字段 data；真实课程字段封装在data的JSON文本里。

## 4. 更新现有确认工具和 Agent

1. ConfirmLearningOperation 保留**前台执行 foreground**及当前已能跳转的绑定；输入仍只有必填String operationId。
   将描述改为：打开HITA本机确认页，让用户确认添加课程、添加作业或完成作业。operationId必须取自对应准备工具。返回needs_confirmation仅代表等待确认，不能报告已经保存。
2. LearningOperation 继续用现有后台配置和 result.data 输出，无需新增参数。
3. 保存并升级端插件。在 Agent 编排中移除旧版插件绑定，重新添加最新版，确认能看到 PrepareCourse。
4. 用 [完整角色指令](xiaoyi-timetable-agent-prompt.txt) 全文替换当前角色指令；新版移除了“课程新增尚未开放”的旧限制，
   并明确区分添加课程与添加作业。不要将新旧指令简单叠加，以免互相矛盾。
5. 保存 Agent，重新发布真机测试；手机新建对话。

## 5. 测试原来的指令

> 帮我在11月11日13:00到15:45之间添加一门集成运算放大器的应用电路，地点H702

预期依次调用 PrepareCourse → ConfirmLearningOperation，出现“确认添加课程”页面，核对年月日、时间、地点和目标课表。
点击取消不写入；重新发起并确认后，应能在课表中看到这一次课程。回到小艺查询结果时，由LearningOperation读取saved回执。
新课程无需事先导入；地点/教师可以省略。每周重复、按节次、批量多日期的自然语言加课尚未开放。

若仍提示“当前课表未找到对应课程”，先在平台调试记录核对是否误调用PrepareHomework或仍绑定旧版工具/角色指令。
若返回工具不支持或未找到意图，核对已安装版本是否包含本次添加课程接口，以及意图名是否为PrepareCourse；不要卸载应用重试。

本地逻辑测试和编译不代表已完成平台联调；新增工具仍需按以上流程验证手机上的实际跳转与保存。
