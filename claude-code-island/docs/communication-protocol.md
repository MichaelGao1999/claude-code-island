# Claude Code Island — WebSocket 通信协议

> 版本：1.0 | 更新时间：2026-06-22

---

## 一、协议概述

Claude Code Island 使用 WebSocket 进行实时通信：

- **Claude Code → macOS App**：localhost:8080
- **macOS App → iOS App**：localhost:8081（Relay）

---

## 二、连接流程

### 2.1 macOS App 连接

```
macOS App                    Claude Code
    │                              │
    │──── WebSocket Connect ──────│
    │         (ws://localhost:8080/events)
    │                              │
    │◄─── Connection Ack ─────────│
    │                              │
    │◄─── Event Stream ───────────│
    │                              │
    │──── Approval Response ─────►│
    │                              │
```

### 2.2 iOS App 连接

```
iOS App                       macOS App (Relay)
    │                              │
    │──── WebSocket Connect ──────│
    │         (ws://localhost:8081/relay)
    │                              │
    │◄─── Connection Ack ─────────│
    │                              │
    │◄─── Event Stream ───────────│
    │                              │
    │──── Approval Response ─────►│
    │                              │
```

---

## 三、消息格式

### 3.1 事件消息

所有事件使用 JSON 格式：

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "type": "THINKING",
  "payload": {
    "taskDescription": "分析项目结构",
    "message": "正在读取文件..."
  },
  "timestamp": "2026-06-22T10:00:00.000Z"
}
```

### 3.2 审批响应消息

```json
{
  "type": "APPROVED",
  "eventId": "evt_abc123",
  "timestamp": "2026-06-22T10:05:00.000Z",
  "source": "macOS"
}
```

或

```json
{
  "type": "REJECTED",
  "eventId": "evt_abc123",
  "timestamp": "2026-06-22T10:05:00.000Z",
  "source": "iOS",
  "reason": "操作风险过高"
}
```

---

## 四、事件类型

### 4.1 状态事件

| 类型 | 方向 | 说明 |
|------|------|------|
| TASK_STARTED | Claude → macOS/iOS | 任务开始 |
| TASK_UPDATED | Claude → macOS/iOS | 进度更新 |
| TOOL_CALLED | Claude → macOS/iOS | 工具调用 |
| THINKING | Claude → macOS/iOS | AI 思考 |
| TASK_COMPLETED | Claude → macOS/iOS | 任务完成 |
| TASK_FAILED | Claude → macOS/iOS | 任务失败 |

### 4.2 审批事件

| 类型 | 方向 | 说明 |
|------|------|------|
| WAITING_APPROVAL | Claude → macOS/iOS | 等待审批 |
| APPROVED | macOS/iOS → Claude | 已批准 |
| REJECTED | macOS/iOS → Claude | 已拒绝 |

### 4.3 连接事件

| 类型 | 方向 | 说明 |
|------|------|------|
| CONNECTED | 内部 | 已连接 |
| DISCONNECTED | 内部 | 已断开 |

---

## 五、Payload 结构

### 5.1 TASK_STARTED

```json
{
  "taskId": "task_001",
  "description": "重构用户认证模块"
}
```

### 5.2 TASK_UPDATED

```json
{
  "taskId": "task_001",
  "progress": 0.65,
  "message": "已完成 65%",
  "filesModified": ["auth.swift", "session.swift"]
}
```

### 5.3 TOOL_CALLED

```json
{
  "taskId": "task_001",
  "tool": "Bash",
  "input": {
    "command": "git status"
  },
  "outputPreview": "M src/main.swift",
  "duration": 150
}
```

### 5.4 THINKING

```json
{
  "taskId": "task_001",
  "thinking": "需要先分析现有代码结构...",
  "thinkingType": "reasoning"
}
```

### 5.5 WAITING_APPROVAL

```json
{
  "taskId": "approval_001",
  "description": "删除 node_modules 目录",
  "command": "rm -rf ./node_modules",
  "riskLevel": "HIGH",
  "details": {
    "affectedFiles": ["node_modules/"],
    "impact": "将删除所有依赖包",
    "reversible": false
  },
  "timeoutSeconds": 300,
  "approvalToken": "tok_abc123"
}
```

### 5.6 APPROVED

```json
{
  "taskId": "task_001",
  "approvedTaskId": "approval_001",
  "approvedAt": "2026-06-22T10:05:00.000Z",
  "approvedBy": "Michael's iPhone"
}
```

### 5.7 REJECTED

```json
{
  "taskId": "task_001",
  "rejectedTaskId": "approval_001",
  "reason": "操作风险过高",
  "rejectedAt": "2026-06-22T10:05:00.000Z",
  "rejectedBy": "Michael's iPhone"
}
```

---

## 六、错误处理

### 6.1 连接错误

- WebSocket 断开 → 自动重连
- 重连失败 → 显示错误信息

### 6.2 消息错误

- JSON 解析失败 → 丢弃消息
- 缺少必要字段 → 使用默认值

---

## 七、心跳机制

### 7.1 心跳间隔

- 每 30 秒发送一次心跳
- 超过 60 秒无响应视为断开

### 7.2 心跳消息

```json
{
  "type": "HEARTBEAT",
  "timestamp": "2026-06-22T10:00:30.000Z"
}
```

---

## 八、安全考虑

### 8.1 当前状态

- 无签名验证
- 无加密传输
- 无身份认证

### 8.2 未来增强

- HMAC 签名（见 HMACSigner.swift）
- TLS 加密
- Token 认证

---

## 九、Mock 模式

### 9.1 Mock 服务器

Mock 模式无需真实 WebSocket 服务器：

```swift
func enableMockMode() {
    isConnected = true
    
    Task {
        for eventType in [.thinking, .coding, .waiting, .approvalRequired] {
            try? await Task.sleep(for: .seconds(2))
            handleEvent(ClaudeEvent.sample(type: eventType))
        }
    }
}
```

### 9.2 Mock 事件

使用 `ClaudeEvent.sample()` 生成测试数据：

```swift
static func sample(type: EventType) -> ClaudeEvent {
    // 返回预定义的测试事件
}
```

---

## 十、实现参考

### 10.1 macOS WebSocket 客户端

```swift
// EventStreamManager.swift
func connect() {
    let request = URLRequest(url: serverURL)
    webSocketTask = urlSession.webSocketTask(with: request)
    webSocketTask?.resume()
    receiveMessage()
}
```

### 10.2 iOS WebSocket 客户端

```swift
// WebSocketBridge.swift
func connect() {
    let request = URLRequest(url: relayURL)
    webSocketTask = urlSession.webSocketTask(with: request)
    webSocketTask?.resume()
    receiveMessage()
}
```

---

## 十一、测试建议

1. 使用 Mock 模式验证 UI
2. 检查事件解析正确性
3. 验证审批响应发送
4. 测试断线重连逻辑