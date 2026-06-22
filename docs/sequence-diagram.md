# Claude Code Island — 序列图

> 版本：1.0 | 更新时间：2026-06-22

---

## 一、正常执行流程

```mermaid
sequenceDiagram
    participant CC as Claude Code
    participant Mac as macOS Island App
    participant iOS as iOS Companion App
    participant LA as Live Activity

    CC->>Mac: TASK_STARTED
    Mac->>iOS: Relay TASK_STARTED
    iOS->>LA: Update Activity
    
    CC->>Mac: THINKING
    Mac->>iOS: Relay THINKING
    iOS->>LA: Update "思考中..."
    
    CC->>Mac: TOOL_CALLED (Bash)
    Mac->>iOS: Relay TOOL_CALLED
    iOS->>LA: Update "执行命令"
    
    CC->>Mac: TASK_UPDATED (progress: 65%)
    Mac->>iOS: Relay TASK_UPDATED
    iOS->>LA: Update Progress Bar
    
    CC->>Mac: TASK_COMPLETED
    Mac->>iOS: Relay TASK_COMPLETED
    iOS->>LA: End Activity
```

---

## 二、审批流程（macOS）

```mermaid
sequenceDiagram
    participant CC as Claude Code
    participant Mac as macOS Island App
    participant AV as ApprovalView

    CC->>Mac: WAITING_APPROVAL
    Mac->>AV: Show Approval Sheet
    
    Note over AV: 用户查看命令详情
    
    alt 批准
        AV->>Mac: approved = true
        Mac->>CC: APPROVED
        CC->>Mac: TASK_COMPLETED
    else 拒绝
        AV->>Mac: approved = false
        Mac->>CC: REJECTED
        CC->>Mac: TASK_FAILED
    end
```

---

## 三、远程审批流程（iOS）

```mermaid
sequenceDiagram
    participant CC as Claude Code
    participant Mac as macOS Island App
    participant iOS as iOS Companion App
    participant RP as RemoteApprovalView
    participant LA as Live Activity

    CC->>Mac: WAITING_APPROVAL
    Mac->>iOS: Relay WAITING_APPROVAL
    iOS->>LA: Update "需要审批"
    iOS->>RP: Show Approval View
    
    Note over RP: 用户在 iPhone 上查看
    
    alt 批准
        RP->>iOS: approved = true
        iOS->>Mac: Relay APPROVED
        Mac->>CC: APPROVED
        CC->>Mac: TASK_COMPLETED
        Mac->>iOS: Relay TASK_COMPLETED
        iOS->>LA: End Activity
    else 拒绝
        RP->>iOS: approved = false
        iOS->>Mac: Relay REJECTED
        Mac->>CC: REJECTED
        CC->>Mac: TASK_FAILED
        Mac->>iOS: Relay TASK_FAILED
        iOS->>LA: End Activity
    end
```

---

## 四、连接流程

```mermaid
sequenceDiagram
    participant Mac as macOS Island App
    participant CC as Claude Code WebSocket
    participant iOS as iOS Companion App
    participant Relay as Mac Relay

    Mac->>CC: WebSocket Connect (ws://localhost:8080)
    CC-->>Mac: Connection Ack
    
    iOS->>Relay: WebSocket Connect (ws://localhost:8081)
    Relay-->>iOS: Connection Ack
    
    Note over Mac,Relay: Relay 转发所有事件到 iOS
    
    CC->>Mac: Event Stream
    Mac->>Relay: Forward Events
    Relay->>iOS: Event Stream
```

---

## 五、断线重连流程

```mermaid
sequenceDiagram
    participant App as macOS/iOS App
    participant WS as WebSocket Server

    WS->>App: Connection Lost
    
    Note over App: 检测到断开
    
    App->>App: reconnectAttempts = 1
    
    loop 重连尝试 (最多5次)
        App->>WS: WebSocket Connect
        alt 成功
            WS-->>App: Connection Ack
            Note over App: 重连成功
        else 失败
            WS-->>App: Connection Failed
            App->>App: reconnectAttempts++
            Note over App: 等待 delay = attempts * 2 秒
        end
    end
    
    alt 达到最大重连次数
        Note over App: 显示错误信息
    end
```

---

## 六、Mock 模式流程

```mermaid
sequenceDiagram
    participant User as 用户
    participant App as macOS/iOS App
    participant Mock as Mock Mode

    User->>App: 点击 "Mock 模式"
    App->>Mock: enableMockMode()
    
    Mock->>App: isConnected = true
    
    loop 模拟事件流
        Mock->>App: ClaudeEvent.sample(thinking)
        Note over App: 显示 "思考中"
        
        Mock->>App: ClaudeEvent.sample(coding)
        Note over App: 显示 "编码中"
        
        Mock->>App: ClaudeEvent.sample(waiting)
        Note over App: 显示 "等待中"
        
        Mock->>App: ClaudeEvent.sample(approvalRequired)
        Note over App: 显示审批弹窗
    end
```

---

## 七、Live Activity 更新流程

```mermaid
sequenceDiagram
    participant iOS as iOS App
    participant LAM as LiveActivityManager
    participant LA as Live Activity
    participant Notif as 本地通知

    iOS->>LAM: startActivity()
    LAM->>LA: Activity.request()
    
    iOS->>LAM: updateActivity(event)
    LAM->>LA: activity.update(state)
    
    alt 审批事件
        LAM->>Notif: 触发本地通知
        Note over Notif: "需要审批"
    end
    
    iOS->>LAM: endActivity()
    LAM->>LA: activity.end()
```

---

## 八、事件处理流程

```mermaid
sequenceDiagram
    participant WS as WebSocket
    participant App as macOS/iOS App
    participant Parser as JSON Parser
    participant Handler as Event Handler
    participant UI as SwiftUI View

    WS->>App: Raw JSON Message
    App->>Parser: JSONDecoder.decode(ClaudeEvent)
    
    alt 解析成功
        Parser-->>App: ClaudeEvent
        App->>Handler: handleEvent(event)
        Handler->>UI: Update @Published properties
        UI->>UI: Re-render View
    else 解析失败
        Parser-->>App: Error
        App->>App: print("无法解析事件")
        Note over App: 丢弃消息
    end
```

---

## 九、审批响应发送流程

```mermaid
sequenceDiagram
    participant User as 用户
    participant View as ApprovalView/RemoteApprovalView
    participant Manager as EventStreamManager/WebSocketBridge
    participant WS as WebSocket

    User->>View: 点击 Approve/Reject
    View->>Manager: sendApprovalResponse(eventId, approved)
    
    Manager->>Manager: 构建响应 JSON
    Manager->>WS: send(.string(jsonString))
    
    alt 发送成功
        WS-->>Manager: Success
        Note over Manager: 关闭审批弹窗
    else 发送失败
        WS-->>Manager: Error
        Manager->>Manager: print("发送失败")
    end
```

---

## 十、完整生命周期

```mermaid
sequenceDiagram
    participant CC as Claude Code
    participant Mac as macOS App
    participant iOS as iOS App
    participant LA as Live Activity

    Note over Mac,iOS: App 启动
    
    Mac->>Mac: connect()
    iOS->>iOS: connect()
    iOS->>LA: startActivity()
    
    Note over Mac,iOS: 等待事件
    
    CC->>Mac: TASK_STARTED
    Mac->>iOS: Relay
    iOS->>LA: Update
    
    CC->>Mac: THINKING
    Mac->>iOS: Relay
    iOS->>LA: Update
    
    CC->>Mac: WAITING_APPROVAL
    Mac->>iOS: Relay
    iOS->>LA: Update
    
    Note over Mac,iOS: 用户审批
    
    Mac->>CC: APPROVED
    
    CC->>Mac: TASK_COMPLETED
    Mac->>iOS: Relay
    iOS->>LA: End
    
    Note over Mac,iOS: App 关闭
    
    Mac->>Mac: disconnect()
    iOS->>iOS: disconnect()
    iOS->>LA: endActivity()
```