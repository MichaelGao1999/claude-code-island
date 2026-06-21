# Claude Code Island - 系统架构文档

## 1. 架构概述

Claude Code Island 采用 **Hub-and-Spoke** 架构，macOS Island App 作为中心节点（Hub），负责事件聚合与转发；iOS Companion App 作为展示终端（Spoke），负责 Dynamic Island UI 渲染与用户交互。两设备通过 WebSocket 长连接通信，实现实时事件推送。

```
┌─────────────────────────────────────────────────────────────────┐
│                         Claude Code CLI                          │
│                    (--output-format json mode)                  │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               │ stdout / JSON events
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                     macOS Island App                             │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────────────┐   │
│  │ ClaudeEvent  │  │   WebSocket  │  │     Event Store       │   │
│  │   Parser     │→ │    Bridge    │→ │   (In-Memory Queue)   │   │
│  └──────────────┘  └──────────────┘  └───────────────────────┘   │
│                            │                                     │
└────────────────────────────┼────────────────────────────────────┘
                             │ WebSocket (localhost:9090)
                             │ LAN / USB Relay
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                    iOS Companion App                             │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────────────┐   │
│  │ WebSocket   │  │  Event       │  │   Dynamic Island      │   │
│  │   Client    │→ │  Processor   │→ │   UI (SwiftUI)        │   │
│  └──────────────┘  └──────────────┘  └───────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. 核心组件

### 2.1 macOS Island App

**职责**：
- 接收并解析 Claude Code CLI 的 JSON 事件输出
- 维护 WebSocket Server，监听 localhost:9090
- 管理客户端连接（iOS 设备配对）
- 事件 relay 到所有已连接的 iOS 客户端
- 本地通知 fallback（当 iOS 连接断开时）

**技术选型**：
- SwiftUI App（生命周期管理）
- URLSession WebSocket Server（NWListener）
- Codable（JSON 解析）
- 零第三方依赖

**关键文件**：
- `IslandApp.swift` - 主入口
- `ClaudeEventParser.swift` - Claude Code 输出解析
- `WebSocketServer.swift` - WebSocket 服务端
- `EventStore.swift` - 内存事件队列

### 2.2 iOS Companion App

**职责**：
- 连接 macOS WebSocket Server
- 接收并处理 ClaudeEvent
- 渲染 Dynamic Island UI
- 处理用户交互（审批操作）
- 发送 Approve/Reject 命令回 macOS

**技术选型**：
- SwiftUI + WidgetKit（Dynamic Island 支持）
- URLSession WebSocket Client
- App Intents（审批交互）
- 零第三方依赖

**关键文件**：
- `CompanionApp.swift` - 主入口
- `DynamicIslandLiveActivity.swift` - Live Activity 配置
- `WebSocketClient.swift` - WebSocket 客户端
- `EventProcessor.swift` - 事件处理与状态机

### 2.3 ClaudeEvent 事件协议

**设计原则**：
- JSON 格式，易于解析和调试
- 强类型字段，payload 使用 tagged union 模式
- 时间戳使用 ISO 8601 格式
- 事件 ID 使用 UUID v4

**完整 Schema 定义**：参见 `event-schema.md`

### 2.4 WebSocket Bridge

**macOS 端（Server）**：
- 使用 `NWListener` 创建 WebSocket Server
- 监听 `ws://127.0.0.1:9090/claude-code-island`
- 支持文本帧传输 JSON 事件
- 心跳 ping/pong 间隔：30 秒

**iOS 端（Client）**：
- 使用 `URLSessionWebSocketTask` 连接
- 自动重连：指数退避 1s → 2s → 4s → 8s → 16s → 30s（最大）
- 连接超时：10 秒

---

## 3. 数据流详解

### 3.1 完整数据流

```
[Claude Code]
    │
    │ 1. 执行命令，输出 JSON 事件到 stdout
    │    格式：{"type": "TASK_STARTED", "payload": {...}}
    │
    ▼
[macOS Island App]
    │
    │ 2. ClaudeEventParser 监听 stdout / 文件监控
    │ 3. 解析为 ClaudeEvent 结构体
    │ 4. 存入 EventStore（内存队列，保留最近 100 条）
    │ 5. WebSocketServer 广播到所有连接客户端
    │
    ▼
[WebSocket Connection (ws://localhost:9090)]
    │
    │ 6. NAT hole punching / USB 隧道（Phase B）
    │    Phase A: 同一设备或同一局域网
    │
    ▼
[iOS Companion App]
    │
    │ 7. WebSocketClient 接收 JSON
    │ 8. EventProcessor 解析并更新状态
    │ 9. SwiftUI 视图更新 → Dynamic Island 刷新
    │
    ▼
[Dynamic Island]
    │
    │ 10. 显示当前状态：TaskRunning / WaitingApproval / Thinking
    │
    ▼
[User]
```

### 3.2 审批操作反向数据流

```
[User on iOS] --tap Approve--> [Dynamic Island] 
                                        │
                                        │ 11. App Intent 触发
                                        ▼
                               [CompanionApp] 
                                        │
                                        │ 12. WebSocket 发送 ACK 事件
                                        │    {"type": "APPROVED", "payload": {"taskId": "xxx"}}
                                        ▼
                               [WebSocket Server]
                                        │
                                        │ 13. 写入本地 named pipe / 文件
                                        ▼
                               [Claude Code]
                                        │
                                        │ 14. 读取审批结果，继续执行
                                        ▼
                               [macOS Island App]
                                        │
                                        │ 15. 广播 TASK_UPDATED 事件
                                        ▼
                               [iOS Companion] --> Dynamic Island 更新
```

---

## 4. macOS → iOS 通信路径

### 4.1 Phase A：局域网直连

**限制**：macOS 和 iOS 必须在同一局域网下（Wi-Fi）

**连接建立**：
1. iOS App 启动时，获取当前局域网 IP 地址
2. 尝试连接 `ws://<macos-ip>:9090/claude-code-island`
3. macOS 通过 `NWListener` 接收外部连接（需在防火墙放行 9090 端口）

**问题**：
- NAT 环境下可能无法连接
- 跨网络环境无法使用
- 安全性低（局域网内任意设备可连接）

### 4.2 Phase B：Relay Server（规划）

**架构**：
```
[iOS] <-- HTTPS/WSS --> [Relay Server] <-- WSS --> [macOS]
```

- Relay Server 负责设备发现与消息 relay
- 双方均无需暴露公网 IP
- 支持跨网络场景

### 4.3 Phase C：USB 隧道（备选）

通过 iTunes/USB 实现端到端加密隧道：
- 低延迟
- 无需网络
- 仅支持边充边用场景

---

## 5. 技术选型理由

### 5.1 SwiftUI vs UIKit

**选择 SwiftUI 的理由**：
- Dynamic Island 和 Live Activity 仅支持 SwiftUI
- 声明式 UI 更适合状态驱动的展示逻辑
- 减少 50% 代码量（相比 UIKit）
- Apple 主推方向，未来支持更好

### 5.2 URLSession WebSocket vs 第三方库

**选择 URLSession WebSocket 的理由**：
- 系统框架，零依赖
- 苹果官方维护，高度兼容 Apple 平台
- 内存占用低（相比 Starscream/SwiftWebSocket）
- 支持 WSS 加密（Phase B）
- 足以满足 Phase A 性能需求

**不选第三方的理由**：
- Starscream: API 复杂，不支持 watchOS
- SwiftWebSocket: 社区维护，更新不稳定
- SocketIO: 过于重量，与我们的协议不匹配

### 5.3 零依赖原则

**收益**：
- 编译速度快（无 CocoaPods/SPM 解析）
- 包体积小（< 1MB vs 含依赖 10MB+）
- 安全风险低（无第三方代码审计）
- 维护成本低（无依赖版本冲突）

**风险**：
- 部分功能需要自己实现（如心跳定时器）
- 错误处理需要更完善
- **可接受风险**：我们的功能集足够小，自研成本可控

---

## 6. 错误处理策略

| 错误场景 | macOS 处理 | iOS 处理 |
|---------|-----------|---------|
| Claude Code 输出解析失败 | 记录日志，丢弃该事件 | N/A |
| WebSocket 连接断开 | 继续监听新连接 | 显示 Disconnected，尝试重连 |
| iOS 审批超时 | 视为 Reject，写入超时状态 | 倒计时结束自动 Dismiss |
| 事件队列满 | 丢弃最旧事件 | N/A |
| macOS App 退出 | 通知所有客户端 | 显示 Disconnected |

---

## 7. 扩展性考虑

### 7.1 事件类型扩展

未来可添加的事件类型：
- `FILE_CHANGED` - 文件变更通知
- `TERMINAL_OUTPUT` - 终端输出截断
- `RESOURCE_USAGE` - 资源使用率
- `ERROR` - 错误信息

### 7.2 多设备支持

Phase B 规划支持：
- 多台 iOS 设备同时连接同一 macOS
- 审批可在任意设备完成
- 事件同步到所有设备

### 7.3 事件持久化

未来可添加 SQLite/Realm 持久化：
- 历史事件查询
- 审批记录审计
- 统计报表
