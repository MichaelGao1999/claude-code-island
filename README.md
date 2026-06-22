# Claude Code Island

> 跨设备 Agent HUD 系统 — 让 Claude Code 的运行状态在 Mac 和 iPhone 上可见可控

---

## 项目简介

Claude Code Island 是一个跨设备的 Agent HUD（Heads-Up Display）系统，为 Claude Code 提供实时状态监控和远程审批功能。

**核心功能：**

- 🖥️ **macOS 灵动岛 UI** — 在菜单栏/刘海区实时显示 Agent 状态
- 📱 **iOS 伴侣 App** — 锁屏 Live Activity + 远程审批
- 🔔 **审批系统** — 高危操作前暂停，等待用户确认
- 📡 **WebSocket 通信** — macOS → iOS 实时事件流

---

## 系统架构

```
┌─────────────────┐     WebSocket      ┌─────────────────┐
│   Claude Code   │ ─────────────────► │  macOS Island   │
│   (localhost)   │     (events)       │     App         │
└─────────────────┘                    └─────────────────┘
                                              │
                                              │ Relay
                                              ▼
                                       ┌─────────────────┐
                                       │  iOS Companion  │
                                       │     App         │
                                       └─────────────────┘
                                              │
                                              ▼
                                       ┌─────────────────┐
                                       │  Live Activity  │
                                       │  (锁屏显示)     │
                                       └─────────────────┘
```

---

## 项目结构

```
claude-code-island/
├── docs/                           # 文档
│   ├── requirements.md             # 功能需求
│   ├── architecture.md             # 系统架构
│   ├── event-schema.md             # 事件 JSON Schema
│   ├── communication-protocol.md   # WebSocket 协议
│   └── sequence-diagram.md         # 序列图（Mermaid）
│
├── macos-island/                   # macOS App
│   ├── ClaudeEvent.swift           # 事件模型
│   ├── EventStreamManager.swift    # WebSocket 客户端
│   ├── IslandView.swift            # 菜单栏 UI
│   ├── ApprovalView.swift          # 审批弹窗
│   ├── main.swift                  # App 入口
│   └── IslandApp.xcodeproj/        # Xcode 项目
│
├── ios-island/                     # iOS App
│   ├── WebSocketBridge.swift       # WebSocket relay 客户端
│   ├── LiveActivityManager.swift   # Live Activity 管理
│   ├── RemoteApprovalView.swift    # 远程审批界面
│   ├── main.swift                  # App 入口
│   └── iOSCompanion.xcodeproj/     # Xcode 项目
│
├── tests/                          # 单元测试
│   ├── IslandAppTests.swift        # macOS 测试
│   └── iOSCompanionTests.swift     # iOS 测试
│
├── WebSocketMockServer.swift       # Mock 服务器（测试）
│
├── HMACSigner.swift                # 安全签名模块
│
├── README.md                       # 本文件
├── verification-report.md          # 验证报告
└── PATCH-CANDIDATES.md             # 补丁候选清单
```

---

## 快速开始

### 系统要求

| 平台 | 最低版本 | 说明 |
|------|---------|------|
| macOS | 13.0+ | MenuBarExtra 需要 macOS 13 |
| iOS | 16.1+ | Live Activity 需要 iOS 16.1 |
| Xcode | 15.0+ | SwiftUI + ActivityKit |
| Swift | 5.9+ | Sendable + Codable |

### 构建步骤

**1. macOS App**

```bash
cd macos-island
xcodebuild -project IslandApp.xcodeproj \
  -scheme IslandApp \
  -configuration Debug \
  build
```

**2. iOS App**

```bash
cd ios-island
xcodebuild -project iOSCompanion.xcodeproj \
  -scheme iOSCompanion \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  build
```

### Mock 模式测试

两个 App 都内置 Mock 模式，无需真实 WebSocket 服务器：

- macOS App：点击菜单栏 → "Mock 模式"
- iOS App：点击 "Mock" 按钮

---

## 事件类型

系统定义 9 种事件类型：

| 类型 | 说明 | UI 显示 |
|------|------|---------|
| `TASK_STARTED` | 任务开始 | "Running" 图标 |
| `TASK_UPDATED` | 进度更新 | 进度条 |
| `TOOL_CALLED` | 工具调用 | 工具图标闪烁 |
| `THINKING` | AI 思考 | 思考内容摘要 |
| `WAITING_APPROVAL` | 等待审批 | 审批弹窗 |
| `APPROVED` | 已批准 | "Approved ✓" |
| `REJECTED` | 已拒绝 | "Rejected ✗" |
| `TASK_COMPLETED` | 任务完成 | 完成摘要 |
| `TASK_FAILED` | 任务失败 | 错误信息 |

完整 JSON Schema 见 [docs/event-schema.md](docs/event-schema.md)。

---

## 风险等级

审批操作按风险等级分类：

| 等级 | 颜色 | 说明 |
|------|------|------|
| LOW | 🟢 绿色 | 低风险，通常安全 |
| MEDIUM | 🟠 橙色 | 中等风险，建议检查 |
| HIGH | 🔴 红色 | 高风险，可能导致数据丢失 |
| CRITICAL | 🟣 紫色 | 严重风险，不可逆后果 |

---

## 键盘快捷键

**审批弹窗（macOS）：**

| 按键 | 操作 |
|------|------|
| `Enter` | 批准 |
| `Esc` | 拒绝 |
| `I` | 检查详情 |

---

## 已知限制

1. **WebSocket Server** — Claude Code 尚未内置 WebSocket 服务器，通信层预留接口
2. **Live Activity** — iOS 16.1+ 才支持，更早版本不显示
3. **Dynamic Island** — macOS 灵动岛仅支持硬件刘海 Mac，MenuBarExtra 是通用替代方案
4. **代码签名** — 未处理 iOS 真机部署签名

---

## 测试覆盖

- ✅ Swift 语法验证（`swiftc -parse`）
- ✅ Mock 模式功能测试
- ⏳ XCTest 单元测试（待补充）

---

## 后续改进

见 [PATCH-CANDIDATES.md](PATCH-CANDIDATES.md)：

1. Swift 语法验证自动化
2. Xcode 项目完善
3. WebSocket Mock Server
4. 安全性增强（HMAC 签名）
5. 单元测试

---

## 许可证

MIT License

---

## 贡献

欢迎提交 Issue 和 Pull Request！

**仓库地址：** https://github.com/MichaelGao1999/claude-code-island