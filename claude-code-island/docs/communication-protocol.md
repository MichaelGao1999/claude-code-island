# Claude Code Island - 通信协议文档

## 1. 协议概述

Claude Code Island 采用 **WebSocket** 作为 macOS 和 iOS 之间的实时通信协议。Phase A 使用明文 WebSocket（ws://），Phase B 将升级为加密 WebSocket（wss://）。

**协议设计原则**：
- 基于文本的 JSON 消息
- 单向消息推送（macOS → iOS）和双向命令（iOS → macOS）
- 心跳保活
- 自动重连

---

## 2. WebSocket 连接建立

### 2.1 连接地址

| 环境 | 地址 |
|-----|------|
| Phase A (局域网) | `ws://<macos-ip>:9090/claude-code-island` |
| Phase A (本机测试) | `ws://127.0.0.1:9090/claude-code-island` |
| Phase B (Relay) | `wss://relay.claude-code-island.example.com` |

### 2.2 连接流程图

```
[iOS Companion App]
       │
       │ 1. 获取服务器地址
       │    - Phase A: 用户手动输入 macOS IP
       │    - Phase B: 通过 mDNS 发现服务
       │
       ▼
       │ 2. 创建 WebSocket 连接
       │    URLSession.webSocketTask(with: url)
       │
       ▼
[macOS Island App - NWListener]
       │
       │ 3. 接收新连接
       │    listener.state == .ready
       │
       ▼
       │ 4. 验证客户端（Phase B 实现）
       │    - 检查 Token
       │    - 验证设备标识
       │
       ▼
       │ 5. 接受连接
       │    connection.accept()
       │
       ▼
[iOS] ◄────► [macOS]
       │
       │ 6. 握手完成
       │    iOS 发送: {"type": "SUBSCRIBE", "payload": {"events": ["*"]}}
       │    macOS 确认: {"type": "SUBSCRIBED", "payload": {"count": 0}}
       │
       ▼
[开始事件传输]
```

### 2.3 macOS WebSocket Server 实现

```swift
// 使用 NWListener 创建 WebSocket Server
import Network

class WebSocketServer {
    private let listener: NWListener
    private var connections: [NWConnection] = []
    
    init(port: UInt16 = 9090) {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        
        // 配置 WebSocket
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)
        
        listener = try! NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
    }
    
    func start() {
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("WebSocket Server ready on port 9090")
            case .failed(let error):
                print("Server failed: \(error)")
            default:
                break
            }
        }
        
        listener.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }
        
        listener.start(queue: .main)
    }
}
```

### 2.4 iOS WebSocket Client 实现

```swift
// 使用 URLSession WebSocket
class WebSocketClient: NSObject {
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession!
    private var isConnected = false
    
    func connect(to url: URL) {
        urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        webSocketTask = urlSession.webSocketTask(with: url)
        webSocketTask?.resume()
        receiveMessage()
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handleMessage(message)
                self?.receiveMessage() // 递归接收下一条
            case .failure(let error):
                print("Receive error: \(error)")
                self?.handleDisconnect()
            }
        }
    }
}
```

---

## 3. macOS 作为 WebSocket Relay 的角色

### 3.1 Relay 架构

```
┌──────────────────────────────────────────────────────────────┐
│                      macOS Island App                         │
│                                                               │
│  ┌─────────────┐    ┌──────────────┐    ┌───────────────┐   │
│  │ ClaudeEvent │───▶│  EventStore  │───▶│ WebSocket     │   │
│  │   Parser    │    │  (内存队列)   │    │ 广播          │   │
│  └─────────────┘    └──────────────┘    └───────────────┘   │
│         ▲                                       │             │
│         │                                       │             │
│  ┌─────────────┐                               │             │
│  │  ClaudeCode │                               │             │
│  │   stdout    │                               │             │
│  └─────────────┘                               │             │
└──────────────────────────────────────────────────────────────┘
              │                                    │
              │ 广播所有事件                         │ relay
              ▼                                    ▼
    ┌─────────────────┐              ┌─────────────────┐
    │  已连接的 iOS    │              │  已连接的 iOS    │
    │   设备 A         │              │   设备 B         │
    └─────────────────┘              └─────────────────┘
```

### 3.2 macOS 职责

| 职责 | 说明 |
|-----|------|
| 事件聚合 | 接收 Claude Code 所有输出事件 |
| 事件存储 | 维护最近 100 条事件（内存队列） |
| 连接管理 | 管理所有 iOS 客户端连接 |
| 广播分发 | 将事件广播到所有连接客户端 |
| 命令转发 | 将 iOS 的审批命令转发给 Claude Code |
| 心跳保活 | 定时发送 ping，保持连接活跃 |

### 3.3 iOS 职责

| 职责 | 说明 |
|-----|------|
| 连接建立 | 主动连接 macOS WebSocket Server |
| 事件订阅 | 订阅感兴趣的事件类型 |
| 状态渲染 | 根据事件更新 Dynamic Island UI |
| 命令发送 | 发送 APPROVED/REJECTED 命令 |
| 重连处理 | 连接断开时自动重连 |

---

## 4. 事件订阅机制

### 4.1 订阅消息格式

iOS 连接成功后，需要发送订阅消息：

```json
// 订阅所有事件
{
  "type": "SUBSCRIBE",
  "payload": {
    "events": ["*"]
  }
}

// 订阅特定事件
{
  "type": "SUBSCRIBE",
  "payload": {
    "events": ["TASK_STARTED", "WAITING_APPROVAL", "TASK_COMPLETED"]
  }
}
```

### 4.2 订阅确认

```json
{
  "type": "SUBSCRIBED",
  "payload": {
    "subscriptionId": "sub_123456",
    "events": ["*"],
    "queuedEvents": 0
  }
}
```

### 4.3 取消订阅

```json
{
  "type": "UNSUBSCRIBE",
  "payload": {
    "subscriptionId": "sub_123456"
  }
}
```

---

## 5. 心跳/保活机制

### 5.1 WebSocket Ping/Pong

macOS 作为 server，会自动回复 WebSocket 标准的 ping/pong 帧：

```swift
// NWListener 自动处理 ping/pong
// 配置 autoReplyPing = true
let wsOptions = NWProtocolWebSocket.Options()
wsOptions.autoReplyPing = true
```

### 5.2 应用层心跳（推荐实现）

```swift
// macOS 端：每 30 秒发送一次心跳
class HeartbeatManager {
    private var timer: Timer?
    private let interval: TimeInterval = 30
    
    func start(on connection: NWConnection) {
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.sendHeartbeat(to: connection)
        }
    }
    
    private func sendHeartbeat(to connection: NWConnection) {
        let heartbeat = """
        {"type":"PING","timestamp":"\(ISO8601DateFormatter().string(from: Date()))"}
        """
        
        let data = heartbeat.data(using: .utf8)!
        connection.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                print("Heartbeat failed: \(error)")
            }
        })
    }
}

// iOS 端：收到心跳后回复
case "PING":
    let pong = """
    {"type":"PONG","timestamp":"\(ISO8601DateFormatter().string(from: Date()))"}
    """
    webSocketTask?.send(.string(pong)) { error in
        if let error = error {
            print("Pong failed: \(error)")
        }
    }
```

### 5.3 连接健康检测

```swift
// iOS 端：检测连接状态
class ConnectionHealthMonitor {
    private var lastPongTime: Date?
    private var checkTimer: Timer?
    
    func start() {
        checkTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.checkHealth()
        }
    }
    
    private func checkHealth() {
        guard let lastPong = lastPongTime else {
            // 还未收到任何 pong，连接可能有问题
            triggerReconnect()
            return
        }
        
        if Date().timeIntervalSince(lastPong) > 45 {
            // 超过 45 秒没有收到 pong，认为连接已断开
            triggerReconnect()
        }
    }
    
    private func triggerReconnect() {
        // 触发重连逻辑
    }
}
```

---

## 6. 重连策略

### 6.1 指数退避重连

iOS 端实现自动重连，采用指数退避策略：

```swift
class ReconnectManager {
    private var reconnectAttempt = 0
    private let maxAttempts = 10
    private let baseDelay: TimeInterval = 1.0
    private let maxDelay: TimeInterval = 30.0
    
    func scheduleReconnect() {
        guard reconnectAttempt < maxAttempts else {
            print("Max reconnect attempts reached")
            return
        }
        
        let delay = min(baseDelay * pow(2.0, Double(reconnectAttempt)), maxDelay)
        reconnectAttempt += 1
        
        print("Scheduling reconnect attempt \(reconnectAttempt) in \(delay)s")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.attemptReconnect()
        }
    }
    
    private func attemptReconnect() {
        // 尝试建立新的 WebSocket 连接
        webSocketClient.connect(to: serverURL)
    }
    
    func reset() {
        reconnectAttempt = 0
    }
}
```

### 6.2 重连触发条件

| 触发条件 | 处理 |
|---------|------|
| WebSocket 断开 | 立即触发重连 |
| 收到 PONG 超时 | 45 秒无响应则重连 |
| 网络状态变化 | 联网时立即重连 |
| App 进入前台 | 检查连接状态，断开则重连 |
| App 从后台返回 | 立即重连 |

### 6.3 重连消息同步

重连后，macOS 会发送重连后的最新状态：

```json
{
  "type": "SYNC_STATE",
  "payload": {
    "currentTask": {
      "taskId": "task_abc123",
      "status": "RUNNING",
      "description": "Refactoring authentication"
    },
    "queuedEvents": [
      // 重连后补发的未处理事件
    ]
  }
}
```

---

## 7. iOS 通过 Relay 接收事件的协议

### 7.1 完整协议流程

```
[iOS] ──(SUBSCRIBE)──▶ [macOS]
[iOS] ◀──(SUBSCRIBED)── [macOS]
                          │
                          │ Claude Code 触发事件
                          ▼
[iOS] ◀──(TASK_STARTED)── [macOS]
[iOS] ◀──(THINKING)────── [macOS]
[iOS] ◀──(TOOL_CALLED)──── [macOS]
[iOS] ◀──(WAITING_APPROVAL) [macOS]
                          │
                          │ 用户点击 Approve
                          ▼
[iOS] ──(APPROVED)──▶ [macOS] ──▶ [Claude Code]
[iOS] ◀──(TASK_UPDATED)── [macOS]
[iOS] ◀──(TASK_COMPLETED)── [macOS]
```

### 7.2 事件接收处理

```swift
// iOS 端事件处理
func handleEvent(_ json: [String: Any]) {
    guard let typeString = json["type"] as? String,
          let eventType = ClaudeEventType(rawValue: typeString) else {
        print("Unknown event type: \(json["type"])")
        return
    }
    
    switch eventType {
    case .taskStarted:
        handleTaskStarted(json["payload"] as? [String: Any])
    case .taskUpdated:
        handleTaskUpdated(json["payload"] as? [String: Any])
    case .toolCalled:
        handleToolCalled(json["payload"] as? [String: Any])
    case .thinking:
        handleThinking(json["payload"] as? [String: Any])
    case .waitingApproval:
        handleWaitingApproval(json["payload"] as? [String: Any])
    case .approved:
        handleApproved(json["payload"] as? [String: Any])
    case .rejected:
        handleRejected(json["payload"] as? [String: Any])
    case .taskCompleted:
        handleTaskCompleted(json["payload"] as? [String: Any])
    case .taskFailed:
        handleTaskFailed(json["payload"] as? [String: Any])
    }
}
```

### 7.3 审批命令发送

```swift
// iOS 端发送审批命令
func sendApproval(taskId: String, approvalToken: String) {
    let command: [String: Any] = [
        "type": "APPROVED",
        "id": UUID().uuidString,
        "timestamp": ISO8601DateFormatter().string(from: Date()),
        "payload": [
            "taskId": taskId,
            "approvalToken": approvalToken,
            "approvedAt": ISO8601DateFormatter().string(from: Date()),
            "approvedBy": UIDevice.current.name
        ]
    ]
    
    if let data = try? JSONSerialization.data(withJSONObject: command),
       let jsonString = String(data: data, encoding: .utf8) {
        webSocketTask?.send(.string(jsonString)) { error in
            if let error = error {
                print("Send approval failed: \(error)")
            }
        }
    }
}
```

---

## 8. 安全性考虑

### 8.1 Phase A 安全措施

| 措施 | 说明 | 状态 |
|-----|------|------|
| Localhost Only | macOS WebSocket 仅监听 127.0.0.1 | ✅ 已实现 |
| 防火墙隔离 | 阻止外部访问 9090 端口 | ⚠️ 用户配置 |
| 无 Token 验证 | Phase A 无认证 | ❌ 待 Phase B |

### 8.2 Phase B 安全升级

```json
// 设备配对流程
{
  "type": "AUTH_REQUEST",
  "payload": {
    "deviceId": "iPhone-XXXX",
    "deviceName": "Michael's iPhone",
    "pairingToken": "预共享的配对 Token"
  }
}

// 认证响应
{
  "type": "AUTH_RESPONSE",
  "payload": {
    "success": true,
    "sessionToken": "会话 Token（有效期 24 小时）"
  }
}
```

### 8.3 Token 验证预留

macOS 端预留 Token 验证接口：

```swift
// Token 验证（Phase B 实现）
class TokenValidator {
    static let shared = TokenValidator()
    
    private init() {}
    
    func validate(token: String, for deviceId: String) -> Bool {
        // 验证逻辑：
        // 1. 检查 token 是否在有效期内
        // 2. 检查 token 是否与 deviceId 匹配
        // 3. 检查 token 是否已被撤销
        return true
    }
}
```

### 8.4 数据安全

| 数据类型 | 安全处理 |
|---------|---------|
| 命令内容 | 仅传输 WAITING_APPROVAL 事件的 command 字段 |
| 敏感信息 | 不在 payload 中传输密码、密钥等内容 |
| 日志记录 | 仅记录事件类型和描述，不记录完整命令 |
| 存储 | Token 存储在 Keychain 中 |

### 8.5 网络安全建议

**用户应采取的措施**：
1. 仅在同一局域网内使用 Phase A
2. 在路由器/防火墙配置中阻止外部访问 macOS 的 9090 端口
3. Phase B 启用时使用 WSS 加密连接
4. 不要在公共 Wi-Fi 环境下使用

---

## 9. 错误码定义

| 错误码 | 含义 | 处理建议 |
|-------|------|---------|
| `CONNECTION_REFUSED` | 连接被拒绝 | 检查 macOS App 是否运行，端口是否正确 |
| `CONNECTION_TIMEOUT` | 连接超时 | 检查网络环境，尝试重新连接 |
| `INVALID_TOKEN` | Token 无效 | 重新配对设备 |
| `TOKEN_EXPIRED` | Token 过期 | 刷新会话 Token |
| `SUBSCRIPTION_FAILED` | 订阅失败 | 重新发送 SUBSCRIBE |
| `MESSAGE_TOO_LARGE` | 消息过大 | 减少批量事件 |
| `SERVER_ERROR` | 服务器错误 | macOS App 异常，检查日志 |

---

## 10. 协议版本管理

| 版本 | 状态 | 变化 |
|-----|------|------|
| 1.0 | Phase A | 初始版本，9 种事件类型 |
| 1.1 | 规划中 | 添加 AUTH 消息类型 |
| 2.0 | 规划中 | Relay Server 支持 |
