# 应用内半屏缺少单 Agent 预置开场内容

## 复现环境

- 日期：2026-10-31。
- HITA NEXT：`cn.berry.hitanext`，应用版本 `0.4.0`（4000000）。
- 真机 API：26；小艺版本：11.7.8.342。
- 接入：Agent Framework Kit `FunctionComponent`，`queryText: ''`。
- Agent：HITA NEXT校园助手，单 Agent，已发布开发测试，测试用户已加入白名单。
- Agent ID：`agent26e52f2a50ad42059267f9077d548b6c`。
- 公开组件由系统管理半屏，HITA 未自建聊天 UI。

## 复现步骤与结果

1. 小艺开放平台选择「预置开场对话」。
2. 开场语为「你好，我是 HITA 助手。可以问我课表相关的问题。」。
3. 配置三条问题：「明天有什么课」「第三周周五的课」「下一节课在哪上」。
4. 从小艺 App 进入带「开发中」标记的 HITA 助手并新建对话：用户确认开场语和三条引导均显示。
5. 从 HITA → 更多 → 助手进入：系统半屏能显示 HITA 助手标题和输入栏，但开场语和引导均缺失。
6. 把组件 `title` 从「助手」改为空，采用官方图标主入口，重新构建并覆盖安装：用户确认仍缺失。
7. 已撤回步骤 6 的无效变更，保留原生半屏与「助手」按钮。

预期：不携带初始查询文本时，应用内半屏展示当前测试版本配置的开场语和三条引导。

本轮未发送问题测试课表插件；此前课表与考试查询已由用户验收。不能把此次开场展示缺失解释为课表数据为空。

## 已检查范围

- 平台的预置开场选中状态、完整开场文本及三条引导均存在。
- 官方图标入口示意图展示开场内容，但指南没有明确说明各 Agent 模式和小艺版本的差异。
- 当前 SDK 的 FunctionOptions 没有 openingText/openingQuestions 等参数，FunctionController 没有公开 open 或对话内容控制方法。
- 定向 HiLog 抓取结果为空，尚无系统端异常栈或服务端响应证明具体失败原因。
- 自动签名 appIdentifier 与平台关联 appId 存在历史差异，已在入口文档记录；半屏实际已成功弹出，不能将此差异认定为本问题根因。

## 待华为确认

1. 当前小艺版本的 FunctionComponent 半屏是否支持单 Agent 的预置开场语和开场预置引导？
2. 同一开发测试 Agent 在全屏正常、半屏空白时，是否有额外的关联应用配置或明确的版本前提？
3. 若属于异常，应采集哪个系统组件的日志来定位开场元数据的获取和渲染？

本文件仅为本地诊断记录，未提交社区、工单或发送给他人。

## 参考

- https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/hmaf-function
- https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/hmaf-function-component
- https://developer.huawei.com/consumer/cn/doc/service/related-applications-0000002437785706
- https://developer.huawei.com/consumer/cn/doc/doccenter-celia/dynamic-opening-lines-0000002765284429
