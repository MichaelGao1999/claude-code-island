# Claude Code Island - 阶段 3: iOS Companion 实现

## 项目背景

项目 **${project_name}** 是一个跨设备 Agent HUD 系统，让 Claude Code 的运行状态在 Mac 和 iPhone 上可见且可控。本阶段聚焦 iOS 伴侣端的实现：通过 SwiftUI 构建一个 iOS 应用，接收来自 macOS Island 转发的事件流，在锁屏 Live Activity 中展示当前任务状态，并支持远程审批。

项目根目录：`${project_dir}`

## 本阶段目标

在 `${project_dir}/ios-island/` 下创建一个完整可编译的 SwiftUI iOS 应用项目，包含 WebSocket 桥接、Live Activity 管理、远程审批界面、App 入口，以及 Xcode 项目结构。

## 输入

本阶段读取以下文件作为参考与设计依据：

- `${project_dir}/../loop-agent-trae-draft_副本.md`
- `${project_dir}/docs/requirements.md`
- `${project_dir}/docs/architecture.md`
- `${project_dir}/docs/event-schema.md`
- `${project_dir}/docs/communication-protocol.md`
- `${project_dir}/macos-island/ClaudeCodeIsland/ClaudeEvent.swift`（事件模型可复用）
- `${project_dir}/macos-island/ClaudeCodeIsland/EventStreamManager.swift`（WebSocket 客户端模式可复用）

## 执行要求

1. 在 `${project_dir}/ios-island/` 下创建 Xcode 项目结构，包含 `ClaudeCodeIsland.xcodeproj`。
2. 实现 `${project_dir}/ios-island/ClaudeCodeIsland/WebSocketBridge.swift`：
   - `class WebSocketBridge`，通过 Mac 作为 WebSocket relay 接收事件
   - 支持连接 URL 配置（从环境/设置读取）
   - 自动重连、心跳、错误处理
3. 实现 `${project_dir}/ios-island/ClaudeCodeIsland/LiveActivityManager.swift`：
   - `class LiveActivityManager`，管理锁屏 Live Activity 的启动/更新/结束
   - Live Activity 中展示：当前任务描述、状态（thinking / coding / waiting）、进度
   - 当接收到新事件时更新 Live Activity
4. 实现 `${project_dir}/ios-island/ClaudeCodeIsland/RemoteApprovalView.swift`：
   - `class RemoteApprovalView` SwiftUI `View`
   - 展示命令摘要、风险等级、高亮颜色（low/medium/high）
   - 提供 Approve / Reject 按钮，点击后通过 WebSocket 发送回 macOS
5. 实现 `${project_dir}/ios-island/ClaudeCodeIsland/main.swift`：
   - App 入口，实例化 `WebSocketBridge` 与 `LiveActivityManager` 作为环境对象
6. 提供 `ClaudeCodeIsland.xcodeproj`（或等效的可构建配置），使项目可通过 `xcodebuild` 构建
7. 所有 Swift 源码必须为合法语法，无编译期错误
8. 完成后**立即落盘所有文件到磁盘

## 产出清单

- `${project_dir}/ios-island/ClaudeCodeIsland.xcodeproj`（或等效项目文件）
- `${project_dir}/ios-island/ClaudeCodeIsland/main.swift`
- `${project_dir}/ios-island/ClaudeCodeIsland/WebSocketBridge.swift`
- `${project_dir}/ios-island/ClaudeCodeIsland/LiveActivityManager.swift`
- `${project_dir}/ios-island/ClaudeCodeIsland/RemoteApprovalView.swift`

## 质量标准

由 PhaseChecker（Phase C）在执行完毕后自动验证：

- [ ] `WebSocketBridge.swift` 文件存在
- [ ] `LiveActivityManager.swift` 文件存在
- [ ] `RemoteApprovalView.swift` 文件存在
- [ ] `main.swift` 文件存在
- [ ] `ClaudeCodeIsland.xcodeproj` 目录存在（或 `*.xcodeproj` 文件存在）
- [ ] `WebSocketBridge.swift` 中包含 `class WebSocketBridge` 关键字
- [ ] `LiveActivityManager.swift` 中包含 `class LiveActivityManager` 关键字
- [ ] `RemoteApprovalView.swift` 中包含 `class RemoteApprovalView` 关键字
- [ ] 可通过 `xcodebuild` 无错构建（若环境具备 Xcode）

【重试上下文】
本阶段第 ${attempt} 次尝试执行。
上一次错误信息：${last_error}
上一次缺失文件：${missing_files}

如果本次是第 2 次及以后的尝试，请优先补齐上述缺失文件，并修正上一次的错误。

## 事件样例

Claude Code 通过 WebSocket 实时广播 `ClaudeEvent` 事件，iOS Companion 需要通过 macOS relay 接收并展示。

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
