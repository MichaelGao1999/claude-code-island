# Claude Code Island - 阶段 4: 集成验证

## 项目背景

项目 **${project_name}** 是一个跨设备 Agent HUD 系统，让 Claude Code 的运行状态在 Mac 和 iPhone 上可见且可控。前三个阶段已经分别产出了 docs/、macos-island/、ios-island/ 目录下的架构文档与源码。本阶段对整体产物进行完整性与可构建性的验证，并产出验证报告。

项目根目录：`${project_dir}`

## 本阶段目标

在 `${project_dir}/verification-report.md` 下生成一份结构化验证报告，报告中至少包含 3 条 `#` 标题：关键功能路径验证、文件完整性、构建命令说明。报告以事实性描述为主，方便人工二次确认。

## 输入

本阶段需要检查以下文件/目录是否存在与合法：

- `${project_dir}/docs/requirements.md`
- `${project_dir}/docs/architecture.md`
- `${project_dir}/docs/event-schema.md`
- `${project_dir}/docs/communication-protocol.md`
- `${project_dir}/macos-island/ClaudeCodeIsland.xcodeproj`
- `${project_dir}/macos-island/ClaudeCodeIsland/*.swift`
- `${project_dir}/ios-island/ClaudeCodeIsland.xcodeproj`
- `${project_dir}/ios-island/ClaudeCodeIsland/*.swift`

## 执行要求

1. 列出 `${project_dir}/docs/`、`${project_dir}/macos-island/`、`${project_dir}/ios-island/` 下的文件清单，按文件存在性打分。
2. 对关键功能路径进行文字化验证：Claude Code 事件 → macOS Island 解码 → 菜单栏/刘海展示 → Approval 弹窗 → iOS Live Activity → 远程审批回传。
3. 给出 `xcodebuild` 命令示例，说明如何构建 `macos-island/` 与 `ios-island/` 项目。
4. 在 `${project_dir}/verification-report.md` 中以 Markdown 形式写入：
   - 至少 3 个 `#` 一级标题（即 `# 标题` 形式）
   - 文件完整性表格
   - 关键功能路径说明
   - `xcodebuild` 构建命令说明
   - 可能的风险与后续改进建议
5. 完成后**立即落盘** `verification-report.md`。

## 产出清单

- `${project_dir}/verification-report.md`

## 质量标准

由 PhaseChecker（Phase D）在执行完毕后自动验证：

- [ ] `${project_dir}/verification-report.md` 文件存在
- [ ] `verification-report.md` 中至少包含 3 条 `#` 一级标题
- [ ] 报告中包含关键字 "xcodebuild"
- [ ] 报告中包含 "关键功能路径验证" 或等价描述

【重试上下文】
本阶段第 ${attempt} 次尝试执行。
上一次错误信息：${last_error}
上一次缺失文件：${missing_files}

如果本次是第 2 次及以后的尝试，请优先补齐上述缺失文件，并修正上一次的错误。

## 事件样例

Claude Code 通过 WebSocket 实时广播 `ClaudeEvent` 事件，作为全项目事件总线的事实标准。

9 种事件类型：
- TASK_STARTED
- TASK_UPDATED
- TOOL_CALLED
- THINKING
- WAITING_APPROVAL
- APPROVED
- REJECTED
- TASK_COMPLETED
- TASK_FAILED

示例 `WAITING_APPROVAL` 事件：

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
