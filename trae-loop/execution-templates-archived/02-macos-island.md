# Claude Code Island - 阶段 2: macOS Island 实现

## 项目背景

项目 **${project_name}** 是一个跨设备 Agent HUD 系统，让 Claude Code 的运行状态在 Mac 和 iPhone 上可见且可控。本阶段聚焦 macOS 端的实现：通过 SwiftUI 构建一个菜单栏/刘海式应用，监听 Claude Code 的 WebSocket 事件流，在菜单栏中展示当前任务、状态与进度，并在需要审批时弹出 ApprovalView 弹窗。

项目根目录：`${project_dir}`

## 本阶段目标

在 `${project_dir}/macos-island/` 下创建一个完整可编译的 SwiftUI macOS 应用项目，包含事件模型、WebSocket 客户端、菜单栏 UI、审批弹窗、App 入口，以及 Xcode 项目结构。

## 输入

本阶段读取以下文件作为参考与设计依据：

- `${project_dir}/../loop-agent-trae-draft_副本.md`
- `${project_dir}/docs/requirements.md`
- `${project_dir}/docs/architecture.md`
- `${project_dir}/docs/event-schema.md`
- `${project_dir}/docs/communication-protocol.md`

## 执行要求

1. 在 `${project_dir}/macos-island/` 下创建 Xcode 项目结构，包含 `ClaudeCodeIsland.xcodeproj`。
2. 实现 `${project_dir}/macos-island/ClaudeCodeIsland/ClaudeEvent.swift`：
   - `struct ClaudeEvent: Codable`，包含 `id`、`timestamp`、`type`、`payload` 字段
   - 使用 `Codable` 进行 JSON 解码，支持 `WAITING_APPROVAL` 等 9 种事件类型
3. 实现 `${project_dir}/macos-island/ClaudeCodeIsland/EventStreamManager.swift`：
   - `class EventStreamManager`，作为 `ObservableObject`
   - 实现 `URLSessionWebSocketTask` 连接 `ws://localhost:PORT`（从 `Claude Code` 的 WebSocket
   - 自动重连与心跳机制
   - 将接收到的事件解码为 `ClaudeEvent`，并通过 `@Published` 供 UI 使用
4. 实现 `${project_dir}/macos-island/ClaudeCodeIsland/IslandView.swift`：
   - `class IslandView` / SwiftUI `View`，显示菜单栏/刘海式 UI
   - 展示：当前任务描述、当前状态（thinking / coding / waiting）、进度百分比
   - 当事件流有重大变化时展开/折叠
5. 实现 `${project_dir}/macos-island/ClaudeCodeIsland/ApprovalView.swift`：
   - `class ApprovalView` SwiftUI `View`
   - 显示命令摘要、风险等级、风险等级高亮（low/medium/high）
   - 提供 Approve / Reject / Inspect 三个按钮
   - 同时支持键盘快捷键（如 A=Approve, R=Reject, I=Inspect）与鼠标点击
6. 实现 `${project_dir}/macos-island/ClaudeCodeIsland/main.swift`：
   - App 入口：`MenuBarExtra` + SwiftUI `Window`，实例化 `EventStreamManager` 作为环境对象
7. 提供 `ClaudeCodeIsland.xcodeproj`（或等效的可构建配置），使项目可通过 `xcodebuild` 构建
8. 所有 Swift 源码必须为合法语法，无编译期错误
9. 完成后**立即落盘所有文件到磁盘

## 产出清单

- `${project_dir}/macos-island/ClaudeCodeIsland.xcodeproj`（或等效项目文件）
- `${project_dir}/macos-island/ClaudeCodeIsland/main.swift`
- `${project_dir}/macos-island/ClaudeCodeIsland/ClaudeEvent.swift`
- `${project_dir}/macos-island/ClaudeCodeIsland/EventStreamManager.swift`
- `${project_dir}/macos-island/ClaudeCodeIsland/IslandView.swift`
- `${project_dir}/macos-island/ClaudeCodeIsland/ApprovalView.swift`

## 质量标准

由 PhaseChecker（Phase B）在执行完毕后自动验证：

- [ ] `ClaudeEvent.swift` 文件存在
- [ ] `EventStreamManager.swift` 文件存在
- [ ] `IslandView.swift` 文件存在
- [ ] `ApprovalView.swift` 文件存在
- [ ] `main.swift` 文件存在
- [ ] `ClaudeCodeIsland.xcodeproj` 目录存在（或 `*.xcodeproj` 文件存在）
- [ ] `EventStreamManager.swift` 中包含 `class EventStreamManager` 关键字
- [ ] `IslandView.swift` 中包含 `class IslandView` 关键字
- [ ] `ApprovalView.swift` 中包含 `class ApprovalView` 关键字
- [ ] `ClaudeEvent.swift` 中包含 `struct ClaudeEvent` 关键字
- [ ] 可通过 `xcodebuild` 无错构建（若环境具备 Xcode）

【重试上下文】
本阶段第 ${attempt} 次尝试执行。
上一次错误信息：${last_error}
上一次缺失文件：${missing_files}

如果本次是第 2 次及以后的尝试，请优先补齐上述缺失文件，并修正上一次的错误。

## 事件样例

Claude Code 通过 WebSocket 实时广播 `ClaudeEvent` 事件，macOS Island 需要解码并展示。

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
