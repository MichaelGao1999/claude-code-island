# Claude Code Island — 系统架构文档

> 版本：1.0 | 更新时间：2026-06-22

---

## 一、架构概述

Claude Code Island 采用三层架构：

```
┌─────────────────────────────────────────────────────────────┐
│                     Claude Code (Agent)                      │
│                    WebSocket Server (待实现)                  │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ WebSocket (localhost:8080)
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    macOS Island App                          │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐          │
│  │ EventStream │  │  IslandView │  │ ApprovalView│          │
│  │  Manager    │──│  (MenuBar)  │──│   (Sheet)   │          │
│  └─────────────┘  └─────────────┘  └─────────────┘          │
│         │                                                    │
│         │ Relay (localhost:8081)                             │
│         ▼                                                    │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ WebSocket Relay
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    iOS Companion App                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐          │
│  │ WebSocket   │  │ LiveActivity│  │ RemoteApproval│         │
│  │   Bridge    │──│   Manager   │──│     View     │          │
│  └─────────────┘  └─────────────┘  └─────────────┘          │
└─────────────────────────────────────────────────────────────┘
```

---

## 二、组件说明

### 2.1 Claude Code Agent

**职责：**
- 执行用户任务
- 生成事件流（TASK_STARTED, THINKING, TOOL_CALLED 等）
- 等待审批响应

**接口：**
- WebSocket Server（localhost:8080）
- 事件 JSON 格式（见 event-schema.md）

### 2.2 macOS Island App

**核心组件：**

| 组件 | 文件 | 职责 |
|------|------|------|
| EventStreamManager | EventStreamManager.swift | WebSocket 客户端，接收事件 |
| IslandView | IslandView.swift | MenuBarExtra UI |
| ApprovalView | ApprovalView.swift | 审批弹窗 |
| ClaudeEvent | ClaudeEvent.swift | 事件数据模型 |

**数据流：**

```
WebSocket Message → EventStreamManager → ClaudeEvent → IslandView
                                              ↓
                                        ApprovalView (if needed)
```

### 2.3 iOS Companion App

**核心组件：**

| 组件 | 文件 | 职责 |
|------|------|------|
| WebSocketBridge | WebSocketBridge.swift | Relay 客户端 |
| LiveActivityManager | LiveActivityManager.swift | ActivityKit 管理 |
| RemoteApprovalView | RemoteApprovalView.swift | 远程审批界面 |

**数据流：**

```
Relay Message → WebSocketBridge → ClaudeEvent → LiveActivityManager
                                          ↓
                                   RemoteApprovalView (if needed)
```

---

## 三、通信路径

### 3.1 事件流向

```
Claude Code → macOS App → iOS App → Live Activity
     │            │           │
     │            │           └──→ RemoteApprovalView
     │            │
     │            └──→ ApprovalView
     │
     └──→ 等待审批响应 ←──┘
```

### 3.2 审批响应流向

```
用户点击 Approve/Reject
     │
     ├──→ macOS ApprovalView → EventStreamManager → Claude Code
     │
     └──→ iOS RemoteApprovalView → WebSocketBridge → Relay → macOS → Claude Code
```

---

## 四、数据模型

### 4.1 ClaudeEvent

```swift
struct ClaudeEvent: Codable, Identifiable {
    let id: UUID
    let type: EventType
    let payload: EventPayload
    let receivedAt: Date
}
```

### 4.2 EventType

```swift
enum EventType: String, Codable {
    case thinking
    case coding
    case waiting
    case approvalRequired
    case approved
    case rejected
    case error
    case connected
    case disconnected
}
```

### 4.3 RiskLevel

```swift
enum RiskLevel: String, Codable {
    case low
    case medium
    case high
    case critical
}
```

---

## 五、状态管理

### 5.1 macOS App 状态

```swift
@Published var isConnected: Bool
@Published var currentEvent: ClaudeEvent?
@Published var eventHistory: [ClaudeEvent]
@Published var connectionError: String?
```

### 5.2 iOS App 状态

```swift
@Published var isConnected: Bool
@Published var currentEvent: ClaudeEvent?
@Published var eventHistory: [ClaudeEvent]
@Published var isActive: Bool  // Live Activity
```

---

## 六、错误处理

### 6.1 连接错误

- WebSocket 断开 → 自动重连（最多 5 次）
- 重连失败 → 显示错误信息
- Mock 模式 → 无需真实连接

### 6.2 事件解析错误

- JSON 解析失败 → 打印日志，丢弃事件
- 未知事件类型 → 使用默认显示

---

## 七、性能考虑

### 7.1 事件历史限制

- macOS：最多 100 条
- iOS：最多 50 条
- 超出后自动移除最旧记录

### 7.2 UI 更新频率

- 事件到达时立即更新
- 进度条实时刷新
- Live Activity 按需更新

---

## 八、安全考虑

### 8.1 当前状态

- 无签名验证（待实现 HMAC）
- 无加密传输（WebSocket 明文）
- 无身份认证

### 8.2 未来增强

- HMAC 签名验证（见 HMACSigner.swift）
- TLS 加密传输
- Token 认证

---

## 九、扩展性

### 9.1 新事件类型

- 扩展 EventType enum
- 更新 event-schema.md
- 添加对应 UI 显示

### 9.2 新平台支持

- 当前：macOS + iOS
- 可扩展：watchOS, iPadOS