# Claude Code Island — Agent Loop Scope

> 本文件是 trae-loop 编排器的唯一执行输入。Trae Agent 在单次循环内自主决策执行顺序，完成全部交付清单。

---

## 任务目标

构建 **Claude Code Island** — 一个跨设备 Agent HUD 系统，让 Claude Code 的运行状态在 Mac 和 iPhone 上可见可控。

用户在 Mac 上运行 Claude Code 时可以：
1. 在 Dynamic Island UI 中实时看到 Agent 状态
2. 在 Mac 或 iPhone 上批准/拒绝操作
3. 在不打开终端的情况下在 iPhone 上实时监控 Claude Code 执行

---

## 交付清单

> 全部放在项目目录 `${project_dir}/` 下。

### 文档（Phase A）

- [ ] `docs/requirements.md` — 功能列表、MVP 范围、用户故事
- [ ] `docs/architecture.md` — 系统架构文字描述、组件交互、数据流、macOS→iOS 通信路径
- [ ] `docs/event-schema.md` — ClaudeEvent JSON Schema，列出全部 9 种事件类型
- [ ] `docs/communication-protocol.md` — WebSocket 协议、macOS→iOS 桥接方案

### macOS Island App（Phase B）

- [ ] `macos-island/ClaudeEvent.swift` — JSON 事件模型解码（Codable）
- [ ] `macos-island/EventStreamManager.swift` — WebSocket 客户端，连接 Claude Code localhost WebSocket
- [ ] `macos-island/IslandView.swift` — 菜单/刘海式 UI，显示当前任务、状态（thinking/coding/waiting）、进度
- [ ] `macos-island/ApprovalView.swift` — 审批弹窗：命令摘要、风险等级、Approve/Reject/Inspect 按钮，支持键盘和点击
- [ ] `macos-island/main.swift` — App 入口：MenuBarExtra + SwiftUI Window
- [ ] `macos-island/*.xcodeproj/` — Xcode 项目目录

### iOS Companion App（Phase C）

- [ ] `ios-island/WebSocketBridge.swift` — 通过 Mac 作为 WebSocket relay 接收事件
- [ ] `ios-island/LiveActivityManager.swift` — 锁屏 Live Activity：当前任务、状态、进度
- [ ] `ios-island/RemoteApprovalView.swift` — 远程审批界面：命令摘要、风险等级、Approve/Reject 按钮
- [ ] `ios-island/main.swift` — App 入口
- [ ] `ios-island/*.xcodeproj/` — Xcode 项目目录

### 集成验证（Phase D）

- [ ] `verification-report.md` — 包含至少 3 条 `#` 开头的章节标题，列出：关键功能路径验证、文件完整性检查、xcodebuild 构建命令说明

---

## 约束条件

### 技术栈
- Swift 5.9+ / SwiftUI
- macOS 13+（MenuBarExtra 需要 macOS 13）
- iOS 16.1+（LiveActivity 需要 iOS 16.1）
- WebSocket（URLSession WebSocket）
- JSON 事件协议

### 禁止事项
- 不处理 iOS 代码签名和真机部署
- 不实现真实 Claude Code WebSocket 服务器（协议定义即可）
- 不修改 macOS 系统文件
- 不使用第三方 Swift 包（零依赖）

### 已知边界
- macOS 和 iOS App 需在同一局域网或通过互联网 relay 通信
- LiveActivity 在 iOS 锁屏界面显示，内容更新依赖 App 在前台或通过推送

---

## 质量标准

### 文件存在性
- 每个交付清单项对应的文件必须存在（非空）
- `.xcodeproj` 必须是目录而非文件

### 内容最低要求
- Swift 文件：至少包含类/struct 定义（不为空文件）
- Markdown 文件：至少包含一个 `#` 标题

### 事件协议覆盖
- `docs/event-schema.md` 中必须定义全部 9 种事件类型：
  `TASK_STARTED`, `TASK_UPDATED`, `TOOL_CALLED`, `THINKING`,
  `WAITING_APPROVAL`, `APPROVED`, `REJECTED`, `TASK_COMPLETED`, `TASK_FAILED`

---

## 已知上下文

### 项目背景（来自 agent-loop-workflow 草稿）

Claude Code Island 是一个跨设备 Agent HUD 系统：
- **macOS 主运行环境**：Claude Code 运行任务，通过 WebSocket 实时广播事件
- **macOS 灵动岛 UI**：SwiftUI 原生 macOS 应用，在菜单栏/刘海区显示 Agent 状态
- **审批系统**：当 Claude Code 需要高危操作确认时（删文件、git push 等），岛展开显示确认界面
- **iOS 伴侣 App**：SwiftUI iOS 应用，锁屏 Live Activity + 远程审批
- **事件协议**：统一的 JSON 事件模型，定义 `ClaudeEvent` 六种状态（实际为 9 种）

### ClaudeEvent JSON 样例

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

### 完整事件类型（9 种）

```
TASK_STARTED  |  TASK_UPDATED  |  TOOL_CALLED  |  THINKING
WAITING_APPROVAL  |  APPROVED  |  REJECTED  |  TASK_COMPLETED  |  TASK_FAILED
```

---

## 风险提示

1. **Xcode 依赖**：构建需要 macOS + Xcode，未安装 Xcode 时 Phase 0 会提示安装
2. **LiveActivity 需要 iOS 16.1+**：在更早版本 iOS 上 LiveActivity 不会显示
3. **WebSocket 连接**：Claude Code 尚未内置 WebSocket 服务器；本项目先完成协议定义和 UI，通信层留作后续实现
4. **SwiftUI Dynamic Island**：macOS Dynamic Island 目前仅支持硬件刘海 Mac，MenuBarExtra 是更通用的替代方案

---

## 检查点配置

- `checkpoint: highrisk` — 高危操作（git push、删除文件）前暂停，等人工确认
- `checkpoint: never` — 全自动模式，不暂停（本 scope 默认）

---

## 执行规则

| 规则 | 说明 |
|------|------|
| **一次给足** | 本 scope 包含全部上下文，执行期间不补充新信息 |
| **交付物导向** | 以交付清单为终点，不偏离 scope |
| **自主决策** | Agent 自主决定文件创建顺序和实现策略 |
| **自检自查** | 每个文件创建后 Agent 自行验证正确性 |
| **不猜测需求** | scope 中未定义的不做 |

---

## 输出要求

完成后请：
1. 确认所有交付清单项均已创建
2. 运行 `xcodebuild` 验证 macOS 和 iOS 项目语法正确（如果环境支持）
3. 确认 `verification-report.md` 存在且内容完整
