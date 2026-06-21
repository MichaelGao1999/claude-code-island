# Claude Code Island — 补丁候选清单

> 生成时间：2026-06-21（主 Loop 完成后记录）
> 状态：待下一个补丁循环评估与处理

---

## 补丁候选 #1：Swift 语法验证

**优先级**：高
**描述**：当前 PhaseChecker 只做文件存在性检查，缺少 Swift 语法验证。本地已有 Swift 6.3.2 CLI，可对 9 个 `.swift` 文件执行 `swift -parse` 词法语法检查，确保无明显语法错误。
**目标文件**：
- `claude-code-island/macos-island/ClaudeEvent.swift`
- `claude-code-island/macos-island/EventStreamManager.swift`
- `claude-code-island/macos-island/IslandView.swift`
- `claude-code-island/macos-island/ApprovalView.swift`
- `claude-code-island/macos-island/main.swift`
- `claude-code-island/ios-island/WebSocketBridge.swift`
- `claude-code-island/ios-island/LiveActivityManager.swift`
- `claude-code-island/ios-island/RemoteApprovalView.swift`
- `claude-code-island/ios-island/main.swift`
**依赖**：Swift 6.3.2 CLI（已就绪，无需 Xcode）
**验证标准**：全部文件 `swift -parse` 退出码 0

---

## 补丁候选 #2：Xcode 项目文件（project.pbxproj）

**优先级**：中
**描述**：当前 `*.xcodeproj/` 是空目录占位符，真正可构建需要 `project.pbxproj` 文件，定义 targets、build settings、info.plist、source files 引用。手写一个最小可用的 PBX 项目文件。
**目标文件**：
- `claude-code-island/macos-island/IslandApp.xcodeproj/project.pbxproj`
- `claude-code-island/ios-island/iOSCompanion.xcodeproj/project.pbxproj`
**依赖**：需要 Xcode 才能验证构建
**验证标准**：Xcode 打开项目后可成功 build（scheme 自动生成）

---

## 补丁候选 #3：项目 README

**优先级**：低
**描述**：`claude-code-island/` 根目录缺少 README。快速写一份项目简介、构建要求、文件结构说明、快速开始、已知限制。
**目标文件**：
- `claude-code-island/README.md`
**依赖**：无
**验证标准**：PhaseChecker 新增检查点：README.md 存在且含 ≥ 3 个标题

---

## 补丁候选 #4：端到端 WebSocket Mock Server

**优先级**：中
**描述**：实现一个最小的 Python WebSocket mock server，在 localhost 模拟 Claude Code 发送事件，让 macOS/iOS App 可以真实跑一圈事件流，验证端到端通信。
**目标文件**：
- `claude-code-island/tools/mock_websocket_server.py`
**依赖**：Python 3.8+（可选第三方库 `websockets`），不强制
**验证标准**：启动 mock server → macOS IslandView 能接收并渲染事件 → CLI 日志确认

---

## 补丁候选 #5：安全性增强（Token Auth / 签名）

**优先级**：低
**描述**：当前 prompt-scope.md 提到安全性考虑，但代码层未实现。加一个轻量的 HMAC 签名模块：事件签名 + 验证，仅允许信任客户端接入 WebSocket。
**目标文件**：
- `claude-code-island/macos-island/EventStreamManager.swift`（新增签名验证方法）
- `claude-code-island/ios-island/WebSocketBridge.swift`（新增签名附加）
**依赖**：需要 Swift CryptoKit（已内置 iOS 13+ / macOS 10.15+）
**验证标准**：无签名的事件被拒绝；正确签名的事件正常通过

---

## 补丁候选 #6：Swift 单元测试

**优先级**：中
**描述**：为纯逻辑部分写 XCTestCase 单元测试：ClaudeEvent 编解码、EventType 状态机、RiskLevel 渲染逻辑。
**目标文件**：
- `claude-code-island/macos-island/Tests/IslandAppTests.swift`
- `claude-code-island/ios-island/Tests/iOSCompanionTests.swift`
**依赖**：Xcode（XCTest 内置）
**验证标准**：`xcodebuild test` 全部通过

---

## 说明

- 以上 6 项均不在 MVP 范围内，不影响当前交付状态
- 待下一个补丁循环（patch loop）启动后按需评估处理
- 当前 Loop 状态：`currentPhase=done, status=done`
