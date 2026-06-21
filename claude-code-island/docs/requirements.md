# Claude Code Island - 项目需求文档

## 1. 项目概述

Claude Code Island 是一个跨设备 Agent HUD（Head-Up Display）系统，旨在将 Claude Code CLI 的实时执行状态通过 Dynamic Island（灵动岛）呈现给用户。项目采用"macOS 作为中心节点 + iOS 作为展示终端"的架构，实现跨设备的实时状态同步与交互。

**核心定位**：为开发者提供一种非侵入式的 Claude Code 监控方式，在不打断工作流的前提下，随时随地通过 iOS 设备的 Dynamic Island 查看 AI Agent 的执行状态、审批危险操作。

---

## 2. MVP 范围（Phase A）

Phase A 聚焦于核心链路打通，实现最小可用功能集：

1. **实时状态推送**：Claude Code 执行任务时，macOS App 接收事件并转发至 iOS Companion
2. **Dynamic Island 展示**：iOS 端在 Dynamic Island 上显示当前任务状态（思考中、执行中、等待审批）
3. **审批交互**：iOS 用户可在灵动岛展开视图中对 WAITING_APPROVAL 事件进行 Approve/Reject 操作
4. **跨设备通信**：通过 WebSocket Bridge 实现 macOS → iOS 的实时事件 relay
5. **事件持久化（内存级）**：App 存活期间维护事件队列，支持事件回溯

---

## 3. 用户故事

### 用户故事 1：开发者远程监控长时间任务

> 身为开发者，我在使用 Claude Code 执行数据库迁移等长时间任务时，需要离开工位处理其他事务。
> 我希望能够在 iPhone 的 Dynamic Island 上看到任务执行进度，而不必一直盯着 Mac。
> 当任务完成或遇到问题时，我希望能立即收到通知。

**验收标准**：
- [ ] 任务启动后 500ms 内，Dynamic Island 显示 "Running" 状态
- [ ] 任务状态变更后，iOS 端在 1s 内同步更新
- [ ] 任务完成后，Dynamic Island 显示完成状态并保持 3 秒后消失

### 用户故事 2：危险操作审批

> 身为开发者，我在让 Claude Code 执行删除文件、安装包等高风险操作时。
> 我希望能够在 iPhone 上快速审批，而不必回到 Mac 前。
> 我需要看到操作的描述和风险等级，以便做出正确判断。

**验收标准**：
- [ ] WAITING_APPROVAL 事件触发 Dynamic Island 展开
- [ ] 显示操作描述、具体命令、风险等级（LOW/MEDIUM/HIGH/CRITICAL）
- [ ] Approve/Reject 操作在 200ms 内生效
- [ ] 审批超时（默认 5 分钟）自动视为 Reject

### 用户故事 3：思考过程可视化

> 身为开发者，我希望了解 Claude Code 当前的思考过程。
> 我希望能够在灵动岛上看到 AI 正在思考的简要内容。
> 这帮助我判断 AI 的方向是否符合预期。

**验收标准**：
- [ ] THINKING 事件在 Dynamic Island 上显示思考内容摘要
- [ ] 思考内容截断至 50 字符，超长内容以 "..." 省略
- [ ] 新思考内容自动替换旧内容

---

## 4. 功能列表

| 功能模块 | 功能点 | 优先级 | 状态 |
|---------|-------|--------|------|
| 事件接收 | 监听 Claude Code 输出解析 | P0 | Phase A |
| 事件接收 | ClaudeEvent JSON 解析 | P0 | Phase A |
| WebSocket Bridge | macOS WebSocket Server | P0 | Phase A |
| WebSocket Bridge | iOS WebSocket Client | P0 | Phase A |
| Dynamic Island | Compact/Expanded/Minimal 视图 | P0 | Phase A |
| Dynamic Island | 审批操作按钮 | P0 | Phase A |
| 状态管理 | 事件状态机 | P1 | Phase A |
| 配置管理 | 设备配对 Token 管理 | P1 | Phase B |
| 通知 | 本地通知 fallback | P2 | Phase B |

---

## 5. 非功能需求

### 5.1 性能要求

| 指标 | 要求 | 说明 |
|-----|------|-----|
| 端到端延迟 | < 100ms | Claude Code 事件触发到 iOS 展示的 P99 延迟 |
| WebSocket 吞吐量 | > 1000 events/s | 单连接峰值处理能力 |
| iOS 电池影响 | < 5% / 小时 | Active 使用时额外消耗 |
| macOS CPU 占用 | < 2% idle | Island App 后台运行时 |

### 5.2 可靠性要求

- WebSocket 连接断开后自动重连，重试间隔 1s/2s/4s/8s/16s（指数退避）
- macOS App 退出时，iOS 端显示 "Disconnected" 状态
- 事件传递至少一次语义（at-least-once），内存队列缓冲

### 5.3 安全性要求

- WebSocket 仅监听 localhost（127.0.0.1），不接受外部连接
- 设备配对采用预共享 Token 验证（Phase B 实现）
- 不存储敏感命令内容，仅保留描述和风险等级
- 日志不包含完整命令内容

### 5.4 兼容性要求

- **macOS**: 14.0+ (Sonoma) -Island App 运行平台
- **iOS**: 17.0+ -Dynamic Island 支持
- **Claude Code**: 1.0+ -通过 --output-format json 解析事件

### 5.5 依赖约束

**Phase A 零第三方依赖原则**：
- 网络通信：URLSession WebSocket（系统框架）
- UI 渲染：SwiftUI（系统框架）
- JSON 解析：Codable（系统框架）
- 无 Alamofire/SwiftyJSON/SocketIO 等任何第三方库

---

## 6. 成功标准

Phase A 完成的定义：
- [ ] Claude Code 执行 `ls` 命令，iOS Dynamic Island 在 100ms 内显示 TASK_STARTED
- [ ] Claude Code 执行危险命令，iOS 端可审批通过
- [ ] macOS 和 iOS 在同一局域网下可建立 WebSocket 连接
- [ ] 所有代码通过 `swift build` 编译，无警告
