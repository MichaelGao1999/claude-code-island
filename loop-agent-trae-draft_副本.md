# Trae 自主全流程 Loop — 实验方案（草稿）

> **执行状态**: 📝 活跃 | 2026-06-21
>
> 实验性方案：用 Python 状态机编排器产出执行文档（MD），由人为桥接送入 **Trae IDE Agent** 执行，人仅在关键阶段节点确认。
>
> **目标项目**: [Claude Code Island] — 跨设备 Agent HUD 系统（macOS + iOS），让 Claude Code 的状态可见且可控

---

## 背景

AI Workbench 现有 5 阶段 SOP 是严格 human-in-the-loop：阶段边界 = 会话边界，每阶段结束必须人工介入。本方案探索一种新范式——**自主 Loop 模式**：

- **编排器**（Python 状态机）驱动流程前进，产出分阶段的执行文档(MD)
- **你作为桥接人**：把执行文档送入 Trae IDE Agent 执行
- **Trae IDE Agent** 作为执行者完成具体开发工作（写代码、创建文件、跑命令）
- 你只需在 3-4 个大阶段边界做 yes/no 确认
- 实验目标：用 **Claude Code Island** 项目验证这种模式的可行性

### Claude Code Island 项目简介

一个跨设备 Agent HUD 系统，让 Claude Code 的运行状态在 Mac 和 iPhone 上可见可控：

| 组件 | 描述 |
|------|------|
| macOS 主运行环境 | Claude Code 运行任务，通过 WebSocket 实时广播事件 |
| macOS 灵动岛 UI | SwiftUI 原生 macOS 应用，在菜单栏/刘海区显示 Agent 状态 |
| 审批系统 | 当 Claude Code 需要高危操作确认时（删文件、git push 等），岛展开显示确认界面 |
| iOS 伴侣 App | SwiftUI iOS 应用，锁屏 Live Activity + 远程审批 |
| 事件协议 | 统一的 JSON 事件模型，定义 `ClaudeEvent` 六种状态 |

详见用户提供的 `/goal` 完整规格。

---

## 总体架构

```
┌──────────────────────────────────────────────────────────┐
│                  trae-loop.py（编排器）                    │
│                                                          │
│  循环:                                                    │
│    1. 读 state.json ← 当前阶段/重试次数/产物路径           │
│    2. 按阶段执行文档模板 → 写入 execution/{phase}.md       │
│       ← 你收到通知：去把 execution/*.md 送入 Trae          │
│    3. 你手动/半自动把 execution/*.md 喂给 Trae IDE Agent   │
│    4. Trae 执行 → 产生产出文件                             │
│    5. 你确认 Trae 执行完毕 → 编排器继续                    │
│    6. 编排器检查产出文件是否存在/内容完整性                  │
│    7. 通过 → 推进状态                                     │
│    8. 失败 → 重试（最多 N 次）→ 仍失败则挂起等人             │
│    9. 到达确认节点 → 输出摘要 → 等待人工 yes/no             │
│   10. 全部完成 → 输出总结报告                              │
└──────────────────────────────────────────────────────────┘
           │                ▲
           ▼                │
    ┌──────────────┐   ┌──────────────┐
    │   state.json  │   │ execution/*  │
    │  (状态持久化)  │   │ (要喂给Trae的)│
    └──────────────┘   └──────────────┘
           │
           ▼  (你作为桥接人)
    ┌──────────────────────────────────────┐
    │     Trae IDE Agent                   │
    │  你打开 Trae → 把 execution/*.md 作为 │
    │  对话内容粘贴/拖入 → Trae 开始执行    │
    └──────────────────────────────────────┘
           │
           ▼
    ┌──────────────────────────────────────┐
    │  产物目录 (Claude Code Island 项目)    │
    │  docs/requirements.md                │
    │  docs/architecture.md                │
    │  docs/event-schema.md                │
    │  macos-island/   (SwiftUI macOS App) │
    │  ios-island/     (SwiftUI iOS App)   │
    │  shared/         (共享协议/模型)      │
    │  verification-report.md              │
    └──────────────────────────────────────┘
```

### 组件说明

| 组件 | 角色 | 关键技术 |
|------|------|----------|
| `trae-loop.py` | 编排器主入口 | 状态机循环 |
| `lib/state_manager.py` | 状态读写、校验、推进 | JSON 持久化 |
| `lib/phase_checker.py` | 各阶段产出文件检查 | 文件存在性 + 内容完整性 |
| `lib/trae_bridge.py` | 写 execution doc + 通知你喂给 Trae | 文件写入 + 终端提示 |
| `lib/prompt_engine.py` | 模板渲染 + 上下文注入 | 变量替换 + 失败上下文 |
| `prompt-templates/*.md` | 各阶段给 Trae 的指令模板 | Markdown |
| `state.json` | 运行时持久化状态 | JSON，人可读可编辑 |

---

## 阶段划分（Claude Code Island 专用）

| 阶段 | 名称 | 编排器产出的执行文档 | Trae 执行的交付物 | 确认点 |
|------|------|----------------------|-------------------|--------|
| A | 需求与架构定稿 | `execution/01-requirements-architecture.md` | `docs/requirements.md`, `docs/architecture.md`, `docs/event-schema.md` | ✅ 架构可行？ |
| B | macOS Island 实现 | `execution/02-macos-island.md` | `macos-island/` SwiftUI App 源码 | ✅ 实现无误？ |
| C | iOS Companion 实现 | `execution/03-ios-companion.md` | `ios-island/` SwiftUI App 源码 | ✅ 实现无误？ |
| D | 集成验证 | `execution/04-integration-verification.md` | 运行测试 + `verification-report.md` | ✅ 整体满意？ |

### 阶段 A 产出物详解

| 文档 | 内容 |
|------|------|
| `docs/requirements.md` | 从 /goal 细化：功能列表、MVP 范围、用户故事 |
| `docs/architecture.md` | 系统架构图（文字描述）、组件交互、数据流 |
| `docs/event-schema.md` | `ClaudeEvent` JSON Schema、事件类型定义（TASK_STARTED 等 9 种）|
| `docs/communication-protocol.md` | WebSocket 协议、macOS→iOS 桥接方案 |

### 阶段 B 产出物详解

| 产物 | 内容 |
|------|------|
| `macos-island/ClaudeCodeIsland.xcodeproj` | Xcode 项目 |
| `macos-island/ClaudeCodeIsland/` | SwiftUI 源码 |
| | - EventStreamManager.swift（WebSocket 客户端） |
| | - IslandView.swift（灵动岛 UI） |
| | - ApprovalView.swift（审批界面） |
| | - ClaudeEvent.swift（事件模型） |
| | - main.swift（App 入口） |

### 阶段 C 产出物详解

| 产物 | 内容 |
|------|------|
| `ios-island/ClaudeCodeIsland.xcodeproj` | Xcode 项目 |
| `ios-island/ClaudeCodeIsland/` | SwiftUI 源码 |
| | - LiveActivityManager.swift |
| | - RemoteApprovalView.swift |
| | - WebSocketBridge.swift |
| | - main.swift |

### Phase 0: 环境检测（新增前置阶段）

在进入任何开发阶段之前，编排器先检测环境是否就绪。

| 检查项 | 检查方式 | 通过条件 |
|--------|---------|---------|
| Xcode CLI | `xcode-select -p` | 返回非空路径 |
| Xcode App | `xcodebuild -version` | 返回版本号 |
| Swift 编译器 | `swift --version` | 返回版本号 |
| 本地 GitHub 路径 | `ls {PROJECT_DIR}` | 目录存在且可写入 |

**不通过时**：编排器输出缺失项的安装指南，暂停（PAUSED），等你装好后继续。

### 确认流程（每个阶段边界触发）

```
编排器:
  1. 检查产出物是否完整
  2. 输出阶段摘要（产出文件列表 + 状态）
  3. 打印: "阶段 [X] 已完成。确认通过？[y/n/redo]"

你:
  y    → 编排器生成下一阶段执行文档，你去喂给 Trae
  n    → 编排器输出原因后退出，你修改后再跑
  redo → 编排器重新生成执行文档（附加上次失败上下文），重试当前阶段

---

## 状态机设计

### 状态定义

```
PHASES = [
    "init",                        # 初始，等待项目描述
    "requirements-architecture",   # A: 需求与架构定稿
    "macos-island",                # B: macOS Island 实现
    "ios-companion",               # C: iOS Companion 实现
    "integration-verification",    # D: 集成验证
    "done"                         # 完成
]

SPECIAL_STATES: PAUSED  # 重试耗尽后挂起
```

### 状态转换

```
init  ──[有项目描述]──→  requirements-architecture
req-arch ──[通过 + 确认]──→  macos-island
req-arch ──[重试耗尽]────→  PAUSED
macos  ──[通过 + 确认]──→  ios-companion
macos  ──[重试耗尽]────→  PAUSED
ios    ──[通过 + 确认]──→  integration-verification
ios    ──[重试耗尽]────→  PAUSED
verify ──[确认通过]────→  done
verify ──[失败/重试耗尽]──→  PAUSED
```

### 错误处理

| 场景 | 编排器行为 |
|------|-----------|
| 产出文件缺失 | 自动重试，新 prompt 附带上轮上下文 + 失败原因 |
| 重试 2 次仍失败 | 写入 PAUSED，退出，输出原因 |
| 你通知 Trae 已执行但编排器检测无产出 | 提示检查，等待确认后重试 |
| state.json 损坏 | 输出错误，要求人修复后重跑 |
| 人中途终止 | 当前状态保留在 state.json，下次重跑从断点继续 |

---

## State File 格式

```json
{
  "projectName": "claude-code-island",
  "version": "1.0",
  "currentPhase": "requirements-architecture",
  "status": "running",
  "history": [
    {
      "phase": "requirements-architecture",
      "attempt": 1,
      "status": "completed",
      "output": "docs/requirements.md",
      "confirmed": true,
      "confirmedAt": "2026-06-21T10:00:00Z"
    }
  ],
  "currentAttempt": 1,
  "maxAttempts": 2,
  "artifacts": {
    "requirements-architecture": "docs/ architecture.md + event-schema.md",
    "macos-island": null,
    "ios-companion": null,
    "integration-verification": null
  },
  "errors": [],
  "startedAt": "2026-06-21T09:00:00Z",
  "updatedAt": "2026-06-21T10:00:00Z"
}
```

---

## 执行文档（Execution Doc）模板

### 喂给 Trae 的方式

1. 编排器将渲染好的执行文档写入 `execution/{phase}.md`
2. 你打开 Trae IDE
3. 把 `execution/*.md` 的**全部内容**粘贴到 Trae 的对话输入框
4. Trae 读取后开始执行
5. 执行完毕后，你回到终端告诉编排器："完成了"（或编排器通过文件变化自动检测）

> **项目路径**：`{LOCAL_GITHUB_PATH}/claude-code-island/` — 所有产物放在这个目录下。

### 事件样例（所有执行文档通用的参考信息）

由于 Trae 需要理解 Claude Code 的事件协议，每个执行文档尾部统一附带以下参考信息：

```json
// Claude Code WebSocket 事件样例
// ClaudeEvent 结构
{
  "id": "evt_abc123",
  "timestamp": "2026-06-21T10:00:00.000Z",
  "type": "WAITING_APPROVAL",  // 事件类型之一
  "payload": {
    "taskId": "task_001",
    "description": "准备执行 git push",
    "command": "git push origin main",
    "riskLevel": "high",
    "details": "将推送 3 个 commit 到 main 分支"
  }
}

// 完整事件类型列表（9 种）
// TASK_STARTED  |  TASK_UPDATED  |  TOOL_CALLED  |  THINKING
// WAITING_APPROVAL  |  APPROVED  |  REJECTED  |  TASK_COMPLETED  |  TASK_FAILED
```

### 执行文档通用结构

```markdown
# Claude Code Island - 阶段 [X]: [名称]

## 项目背景
（简要描述项目定位和 MVP 范围）

## 本阶段目标
（本阶段要完成什么，产出什么）

## 输入
（列出需要先读取的文件/参考）
- docs/requirements.md（如果已存在）
- docs/architecture.md（如果已存在）

## 执行要求
（具体要做什么，逐条列出）

## 产出清单
（必须产生的文件路径列表）

## 质量标准
（自动检查条件，Trae 执行后可自查）
```

### 各阶段特化模板

#### Phase A: 需求与架构定稿

写入 `execution/01-requirements-architecture.md`，核心指令包括：

1. 精炼 `/goal` 为结构化需求文档 `docs/requirements.md`
2. 设计系统架构 `docs/architecture.md`（组件图文字描述、数据流、macOS→iOS 通信路径）
3. 定义 `ClaudeEvent` 事件模型 JSON Schema → `docs/event-schema.md`
   - 事件类型：TASK_STARTED, TASK_UPDATED, TOOL_CALLED, THINKING, WAITING_APPROVAL, APPROVED, REJECTED, TASK_COMPLETED, TASK_FAILED
4. 设计通信协议 `docs/communication-protocol.md`（WebSocket 消息格式、macOS→iOS 桥接）

#### Phase B: macOS Island 实现

写入 `execution/02-macos-island.md`，核心指令包括：

1. 用 SwiftUI 创建 macOS 项目 `macos-island/`
2. 实现 `ClaudeEvent.swift` — JSON 事件模型解码
3. 实现 `EventStreamManager.swift` — WebSocket 客户端连接 Claude Code 的 localhost WebSocket
4. 实现 `IslandView.swift` — 刘海区 Dynamic Island 式 UI，显示：当前任务、状态（thinking/coding/waiting）、进度
5. 实现 `ApprovalView.swift` — 审批弹窗 UI：命令摘要、风险等级、Approve/Reject/Inspect 按钮
6. 实现自动展开逻辑：approval 需要时展开、错误时展开、任务完成时展开
7. 支持键盘 + 点击两种审批方式
8. App 入口：MenuBarExtra + SwiftUI Window

#### Phase C: iOS Companion 实现

写入 `execution/03-ios-companion.md`，核心指令包括：

1. 用 SwiftUI 创建 iOS 项目 `ios-island/`
2. 实现 `WebSocketBridge.swift` — 通过 Mac 作为 WebSocket relay 接收事件
3. 实现 `LiveActivityManager.swift` — 锁屏 Live Activity：当前任务、状态、进度
4. 实现 `RemoteApprovalView.swift` — 远程审批界面：命令摘要、风险等级、Approve/Reject 按钮
5. 实现推送通知机制：当 approval 需要时推送通知
6. 可选：Detail View 查看完整事件历史

#### Phase D: 集成验证

写入 `execution/04-integration-verification.md`，核心指令包括：

1. 检查所有文件是否完整
2. 尝试构建 macOS 和 iOS 项目（`xcodebuild`）
3. 验证关键功能路径
4. 产出 `verification-report.md`

---

## 文件清单

```
trae-loop/
├── trae-loop.py              # 主入口
├── state.json                # 运行时状态（人可编辑做断点恢复）
├── state-schema.json         # state.json 的 JSON Schema
├── execution-templates/      # 分阶段 Trae 执行文档模板
│   ├── 01-requirements-architecture.md
│   ├── 02-macos-island.md
│   ├── 03-ios-companion.md
│   └── 04-integration-verification.md
├── execution/                # 运行时渲染后的执行文档（你要喂给Trae的）
├── lib/
│   ├── __init__.py
│   ├── state_manager.py      # 状态机核心
│   ├── phase_checker.py      # 产出检查（检查产物完整性）
│   ├── trae_bridge.py        # Trae 桥接逻辑（写 execution doc + 通知你）
│   └── prompt_engine.py      # 模板引擎（变量替换 + 失败上下文注入）
└── README.md                 # 使用说明

# Claude Code Island 项目产物（Trae 执行后生成）
claude-code-island/
├── docs/
│   ├── requirements.md
│   ├── architecture.md
│   ├── event-schema.md
│   └── communication-protocol.md
├── macos-island/
│   └── ClaudeCodeIsland/
│       ├── ClaudeCodeIsland.xcodeproj
│       └── ClaudeCodeIsland/
│           ├── main.swift
│           ├── ClaudeEvent.swift
│           ├── EventStreamManager.swift
│           ├── IslandView.swift
│           └── ApprovalView.swift
├── ios-island/
│   └── ClaudeCodeIsland/
│       ├── ClaudeCodeIsland.xcodeproj
│       └── ClaudeCodeIsland/
│           ├── main.swift
│           ├── WebSocketBridge.swift
│           ├── LiveActivityManager.swift
│           └── RemoteApprovalView.swift
└── verification-report.md
```

---

## 验证方案

### 验证目标：Claude Code Island MVP

成功标准：
> 用户在 Mac 上运行 Claude Code 时，可以：
> 1. 在 Dynamic Island UI 中实时看到 Agent 状态
> 2. 在 Mac 或 iPhone 上批准/拒绝操作
> 3. 在不打开终端的情况下在 iPhone 上实时监控 Claude Code 执行

### 自动检查清单（由 phase_checker.py 执行）

| # | 检查项 | 阶段 | 检查方式 |
|---|--------|------|---------|
| 1 | `docs/requirements.md` 存在且包含功能列表 | A | 文件存在性 |
| 2 | `docs/architecture.md` 存在且包含组件描述 | A | 文件存在性 |
| 3 | `docs/event-schema.md` 存在且定义 >=6 种事件 | A | 内容检查 |
| 4 | `docs/communication-protocol.md` 存在 | A | 文件存在性 |
| 5 | `macos-island/` 下有 Swift 源码文件 | B | 文件存在性 |
| 6 | `macos-island/` 包含 IslandView、ApprovalView | B | 关键字检查 |
| 7 | `ios-island/` 下有 Swift 源码文件 | C | 文件存在性 |
| 8 | `ios-island/` 包含 LiveActivity、RemoteApproval | C | 关键字检查 |
| 9 | 项目可构建（xcodebuild） | D | 命令执行 |
| 10 | 关键文件路径完整 | D | 比对产出清单 |
| 11 | `verification-report.md` 存在 | D | 文件存在性 |

### 手动确认清单

| # | 确认内容 | 出现时机 |
|---|---------|---------|
| 1 | 架构设计是否合理？事件模型是否覆盖所有状态？ | A→B |
| 2 | macOS Island UI 是否符合预期？审批流程是否顺手？ | B→C |
| 3 | iOS App 的功能是否完整？远程控制是否流畅？ | C→D |
| 4 | 整体交付是否达到 MVP 要求？ | D→done |

---

## 实施步骤（按优先级）

- [x] **Step 1**: 方案讨论定稿（本文档）
- [ ] **Step 2**: 实现核心状态机（`lib/state_manager.py`）—— 不依赖 Trae，纯状态读写推进
- [ ] **Step 3**: 编写各阶段执行文档模板（`execution-templates/*.md`）
- [ ] **Step 4**: 实现模板引擎（`lib/prompt_engine.py`）—— 变量替换 + 失败上下文注入
- [ ] **Step 5**: 实现产出检查逻辑（`lib/phase_checker.py`）
- [ ] **Step 6**: 实现 Trae 桥接（`lib/trae_bridge.py`）—— 写 execution doc + 通知你
- [ ] **Step 7**: 串联主循环（`trae-loop.py`）—— 先 Mock 方式调试状态机流转
- [ ] **Step 8**: Mock 调试验证：四阶段是否正常流转、重试/PAUSED 是否生效
- [ ] **Step 9**: 真实实验：运行编排器，你手动喂 execution doc 给 Trae，观察流转
- [ ] **Step 10**: 根据实验结果迭代（调整 template 质量、重试策略、确认频率）

---

## 已确认

- ✅ **Trae 交互方式**：你直接把 execution doc MD 粘贴到 Trae IDE 对话窗口
- ✅ **项目存放位置**：`{LOCAL_GITHUB_PATH}/claude-code-island/`（独立子目录）
- ✅ **环境**：不确定是否有 Xcode —— 已增加 Phase 0 环境检测阶段
- ✅ **Claude Code 事件样例**：放在 execution doc 尾部，供 Trae 参考
- ✅ **模板引擎**：f-string（零依赖，先简单再升级）

## 待确认问题

- [ ] **Trae 是否支持 xcodebuild？**—— 如果环境没有 Xcode，Phase 0 检测后会暂停指导安装。但如果 Trae 能自动检测并提示安装，编排器可以设计得更智能

---

## 关联文档

- [5 阶段 SOP](starter/agent-coding-workflow.md) — 对比参考
- [轻量级开发流程](docs/lightweight-dev.md) — 现有轻量模式的对比
