# Claude Code Island - 阶段 1: 需求与架构定稿

## 项目背景

项目 **${project_name}** 是一个跨设备 Agent HUD 系统，让 Claude Code 的运行状态在 Mac 和 iPhone 上可见且可控。通过原生 SwiftUI 界面，开发者可以在不打开终端窗口的情况下监控 Claude Code 的执行进度，并在需要危险操作（删除文件、git push 等）时在 macOS 菜单栏/刘海区或 iPhone 锁屏 Live Activity 中完成即时审批。本次交付范围为 **MVP**：核心事件流协议、macOS 菜单栏/刘海式 UI、基本审批弹窗、iOS 伴侣端远程审批通路，不包含复杂 UI 动画或多会话管理。

项目根目录：`${project_dir}`

## 本阶段目标

在 `${project_dir}/docs/` 下产出 4 份结构化文档，作为后续 macOS 与 iOS 实现阶段的唯一输入依据。Trae 需要在本阶段完成：功能列表与 MVP 范围界定、系统架构与组件交互设计、ClaudeEvent JSON Schema 定义（覆盖 9 种事件类型）、WebSocket 协议与 macOS→iOS 桥接方案文档。

## 输入

本阶段的参考草稿与规格来源：

- `${project_dir}/../loop-agent-trae-draft_副本.md`（本项目的设计草稿，包含总体架构、阶段划分、事件类型、状态机说明）
- `${project_dir}/state-schema.json`（如果已存在，可作为状态机参考）
- `${project_dir}/docs/requirements.md`（若已存在，本次覆盖重写）
- `${project_dir}/docs/architecture.md`（若已存在，本次覆盖重写）
- `${project_dir}/docs/event-schema.md`（若已存在，本次覆盖重写）
- `${project_dir}/docs/communication-protocol.md`（若已存在，本次覆盖重写）

## 执行要求

1. 在 `${project_dir}/docs/` 目录下创建/覆盖以下 4 个文件：
   - `${project_dir}/docs/requirements.md`
   - `${project_dir}/docs/architecture.md`
   - `${project_dir}/docs/event-schema.md`
   - `${project_dir}/docs/communication-protocol.md`
2. `requirements.md` 必须包含：功能列表、MVP 范围界定、至少 3 个用户故事、非目标（out-of-scope）说明。
3. `architecture.md` 必须包含：系统架构文字描述、组件交互说明、数据流（Claude Code → macOS Island → iOS Companion）、macOS → iOS 通信路径说明、错误与重试策略章节。
4. `event-schema.md` 必须包含 `ClaudeEvent` JSON Schema 定义，显式列出 9 种事件类型：TASK_STARTED、TASK_UPDATED、TOOL_CALLED、THINKING、WAITING_APPROVAL、APPROVED、REJECTED、TASK_COMPLETED、TASK_FAILED，并为每种事件给出 payload 字段说明。
5. `communication-protocol.md` 必须包含：WebSocket 连接 URL 约定、消息帧格式、心跳与重连策略、macOS 向 iOS 转发事件的桥接方案（WebSocket relay）。
6. 文档全部使用中文书写，结构使用标准 Markdown 标题（##、###），便于后续阶段读取引用。
7. 确保所有文件在执行完毕后**立即落盘**，不要只在对话中展示内容而不写入文件。

## 产出清单

- `${project_dir}/docs/requirements.md`
- `${project_dir}/docs/architecture.md`
- `${project_dir}/docs/event-schema.md`
- `${project_dir}/docs/communication-protocol.md`

## 质量标准

由 PhaseChecker（Phase A）在执行完毕后自动验证：

- [ ] `${project_dir}/docs/requirements.md` 文件存在
- [ ] `${project_dir}/docs/architecture.md` 文件存在
- [ ] `${project_dir}/docs/event-schema.md` 文件存在
- [ ] `${project_dir}/docs/communication-protocol.md` 文件存在
- [ ] `event-schema.md` 中覆盖的事件类型数量达到要求（>=9 种）
- [ ] `architecture.md` 中包含 "macOS"、"iOS"、"WebSocket" 关键字
- [ ] `communication-protocol.md` 中包含 WebSocket 协议说明

【重试上下文】
本阶段第 ${attempt} 次尝试执行。
上一次错误信息：${last_error}
上一次缺失文件：${missing_files}

如果本次是第 2 次及以后的尝试，请优先补齐上述缺失文件，并修正上一次的错误。

## 事件样例

Claude Code 通过 WebSocket 实时广播 `ClaudeEvent` 事件，Trae 在实现 macOS/iOS 端时需要理解以下事件格式。

9 种事件类型：
- TASK_STARTED
- TASK_UPDATED
- TOOL_CALLED
- THINKING
- WAITING_APPROVAL
- APPROVED
- REJECTED
- TASK_COMPLETED
- TASK_FAILED

示例 `WAITING_APPROVAL` 事件：

```json
{
  "id": "evt_abc123",
  "timestamp": "2026-06-21T10:00:00.000Z",
  "type": "WAITING_APPROVAL",
  "payload": {
    "taskId": "task_001",
    "description": "准备执行 git push",
    "command": "git push origin main",
    "riskLevel": "high",
    "details": "将推送 3 个 commit 到 main 分支"
  }
}
```
