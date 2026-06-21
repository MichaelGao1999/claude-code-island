# Claude Code Island - 事件 Schema 文档

## 1. 概述

本文档定义 Claude Code Island 项目中所有事件的 JSON Schema。所有事件均为 JSON 格式，通过 WebSocket 传输。

**设计原则**：
- 强类型字段命名（camelCase）
- payload 使用 tagged union（通过 `type` 字段区分）
- 时间戳统一使用 ISO 8601 UTC 格式
- 事件 ID 使用 UUID v4 格式

---

## 2. 完整 JSON Schema

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "ClaudeEvent",
  "description": "Claude Code Island 事件总线上的所有事件类型",
  "type": "object",
  "required": ["id", "timestamp", "type", "payload"],
  "properties": {
    "id": {
      "type": "string",
      "format": "uuid",
      "description": "事件的唯一标识符，UUID v4 格式",
      "example": "550e8400-e29b-41d4-a716-446655440000"
    },
    "timestamp": {
      "type": "string",
      "format": "date-time",
      "description": "事件发生时间，ISO 8601 UTC 格式",
      "example": "2024-01-15T10:30:00.000Z"
    },
    "type": {
      "type": "string",
      "enum": [
        "TASK_STARTED",
        "TASK_UPDATED",
        "TOOL_CALLED",
        "THINKING",
        "WAITING_APPROVAL",
        "APPROVED",
        "REJECTED",
        "TASK_COMPLETED",
        "TASK_FAILED"
      ],
      "description": "事件类型，决定 payload 的结构"
    },
    "payload": {
      "description": "事件负载，根据 type 字段的内容有不同的结构",
      "oneOf": [
        { "$ref": "#/definitions/TASK_STARTED" },
        { "$ref": "#/definitions/TASK_UPDATED" },
        { "$ref": "#/definitions/TOOL_CALLED" },
        { "$ref": "#/definitions/THINKING" },
        { "$ref": "#/definitions/WAITING_APPROVAL" },
        { "$ref": "#/definitions/APPROVED" },
        { "$ref": "#/definitions/REJECTED" },
        { "$ref": "#/definitions/TASK_COMPLETED" },
        { "$ref": "#/definitions/TASK_FAILED" }
      ]
    }
  },
  "definitions": {
    "TASK_STARTED": {
      "type": "object",
      "description": "任务开始事件",
      "required": ["taskId", "description"],
      "properties": {
        "taskId": {
          "type": "string",
          "description": "任务的唯一标识符",
          "example": "task_abc123"
        },
        "description": {
          "type": "string",
          "description": "任务的简要描述",
          "example": "Refactoring user authentication module"
        },
        "parentTaskId": {
          "type": ["string", "null"],
          "description": "父任务 ID（如果有），用于任务嵌套关系",
          "example": null
        }
      }
    },
    "TASK_UPDATED": {
      "type": "object",
      "description": "任务进度更新事件",
      "required": ["taskId", "progress"],
      "properties": {
        "taskId": {
          "type": "string",
          "description": "任务的唯一标识符"
        },
        "progress": {
          "type": "number",
          "minimum": 0,
          "maximum": 100,
          "description": "任务完成百分比",
          "example": 45
        },
        "message": {
          "type": ["string", "null"],
          "description": "进度说明",
          "example": "Completed file deletion"
        },
        "filesModified": {
          "type": "array",
          "items": { "type": "string" },
          "description": "本次更新修改的文件列表",
          "example": ["src/auth/login.swift", "src/auth/session.swift"]
        }
      }
    },
    "TOOL_CALLED": {
      "type": "object",
      "description": "工具调用事件",
      "required": ["taskId", "tool", "input"],
      "properties": {
        "taskId": {
          "type": "string",
          "description": "关联的任务 ID"
        },
        "tool": {
          "type": "string",
          "description": "工具名称",
          "enum": ["Bash", "Read", "Write", "Edit", "Grep", "Glob", "WebFetch", "TodoWrite", "NotebookEdit"],
          "example": "Bash"
        },
        "input": {
          "type": "object",
          "description": "工具输入参数（不包含敏感信息）",
          "example": {
            "command": "git status",
            "workingDirectory": "/Users/project"
          }
        },
        "outputPreview": {
          "type": ["string", "null"],
          "description": "输出预览（截断至 200 字符）",
          "example": "M src/main.swift\n?? build/"
        },
        "duration": {
          "type": ["number", "null"],
          "description": "执行时长（毫秒）",
          "example": 150
        }
      }
    },
    "THINKING": {
      "type": "object",
      "description": "AI 思考过程事件",
      "required": ["taskId", "thinking"],
      "properties": {
        "taskId": {
          "type": "string",
          "description": "关联的任务 ID"
        },
        "thinking": {
          "type": "string",
          "description": "AI 当前的思考内容",
          "example": "The user wants me to refactor the authentication module. I need to first understand the current structure by reading the existing files."
        },
        "thinkingType": {
          "type": "string",
          "enum": ["reasoning", "planning", "critiquing", "summarizing"],
          "description": "思考类型",
          "default": "reasoning"
        }
      }
    },
    "WAITING_APPROVAL": {
      "type": "object",
      "description": "等待用户审批事件（需要用户确认才能继续执行）",
      "required": ["taskId", "description", "command", "riskLevel"],
      "properties": {
        "taskId": {
          "type": "string",
          "description": "关联的任务 ID"
        },
        "description": {
          "type": "string",
          "description": "操作的简要描述",
          "example": "Delete 3 files in project"
        },
        "command": {
          "type": "string",
          "description": "将要执行的具体命令（不包含参数注入风险）",
          "example": "rm -rf src/old_module/"
        },
        "riskLevel": {
          "type": "string",
          "enum": ["LOW", "MEDIUM", "HIGH", "CRITICAL"],
          "description": "风险等级",
          "example": "HIGH"
        },
        "details": {
          "type": "object",
          "description": "风险的详细说明",
          "properties": {
            "affectedFiles": {
              "type": "array",
              "items": { "type": "string" },
              "description": "将受影响文件列表"
            },
            "impact": {
              "type": "string",
              "description": "操作影响说明",
              "example": "This will permanently delete 3 files and cannot be undone"
            },
            "reversible": {
              "type": "boolean",
              "description": "操作是否可逆"
            }
          }
        },
        "timeoutSeconds": {
          "type": "integer",
          "description": "审批超时时间（秒），默认 300 秒",
          "default": 300,
          "minimum": 30,
          "maximum": 3600
        },
        "approvalToken": {
          "type": "string",
          "description": "审批令牌，用于唯一确认审批操作"
        }
      }
    },
    "APPROVED": {
      "type": "object",
      "description": "用户批准事件",
      "required": ["taskId", "approvedTaskId", "approvedAt"],
      "properties": {
        "taskId": {
          "type": "string",
          "description": "关联的原始任务 ID"
        },
        "approvedTaskId": {
          "type": "string",
          "description": "被批准的 WAITING_APPROVAL 事件中的 taskId",
          "example": "approval_xyz789"
        },
        "approvedAt": {
          "type": "string",
          "format": "date-time",
          "description": "审批时间"
        },
        "approvedBy": {
          "type": ["string", "null"],
          "description": "审批者标识（设备名称或用户名称）",
          "example": "Michael's iPhone"
        }
      }
    },
    "REJECTED": {
      "type": "object",
      "description": "用户拒绝事件",
      "required": ["taskId", "rejectedTaskId", "reason"],
      "properties": {
        "taskId": {
          "type": "string",
          "description": "关联的原始任务 ID"
        },
        "rejectedTaskId": {
          "type": "string",
          "description": "被拒绝的 WAITING_APPROVAL 事件中的 taskId"
        },
        "reason": {
          "type": ["string", "null"],
          "description": "拒绝原因（可选）",
          "example": "This operation is too risky, please do it manually"
        },
        "rejectedAt": {
          "type": "string",
          "format": "date-time",
          "description": "拒绝时间"
        },
        "rejectedBy": {
          "type": ["string", "null"],
          "description": "拒绝者标识"
        }
      }
    },
    "TASK_COMPLETED": {
      "type": "object",
      "description": "任务完成事件",
      "required": ["taskId", "completedAt", "summary"],
      "properties": {
        "taskId": {
          "type": "string",
          "description": "任务的唯一标识符"
        },
        "completedAt": {
          "type": "string",
          "format": "date-time",
          "description": "任务完成时间"
        },
        "summary": {
          "type": "string",
          "description": "任务完成摘要",
          "example": "Successfully refactored 5 files in authentication module"
        },
        "duration": {
          "type": "integer",
          "description": "任务总耗时（毫秒）"
        },
        "filesModified": {
          "type": "array",
          "items": { "type": "string" },
          "description": "修改的文件列表"
        },
        "toolsUsed": {
          "type": "array",
          "items": { "type": "string" },
          "description": "使用的工具列表",
          "example": ["Bash", "Read", "Edit", "Edit"]
        }
      }
    },
    "TASK_FAILED": {
      "type": "object",
      "description": "任务失败事件",
      "required": ["taskId", "failedAt", "error"],
      "properties": {
        "taskId": {
          "type": "string",
          "description": "任务的唯一标识符"
        },
        "failedAt": {
          "type": "string",
          "format": "date-time",
          "description": "失败时间"
        },
        "error": {
          "type": "object",
          "required": ["code", "message"],
          "properties": {
            "code": {
              "type": "string",
              "description": "错误代码",
              "example": "COMMAND_FAILED"
            },
            "message": {
              "type": "string",
              "description": "错误消息",
              "example": "rm: cannot remove '/protected': Operation not permitted"
            },
            "recoverable": {
              "type": "boolean",
              "description": "是否可恢复"
            }
          }
        },
        "lastSuccessfulStep": {
          "type": ["string", "null"],
          "description": "最后一个成功步骤的描述",
          "example": "Completed file read of config.yaml"
        }
      }
    }
  }
}
```

---

## 3. 事件类型详解

### 3.1 TASK_STARTED

**触发时机**：Claude Code 开始执行一个任务时

**iOS Dynamic Island 展示**：
- Compact：显示 "Running" 图标
- Expanded：显示任务描述

**示例**：
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440001",
  "timestamp": "2024-01-15T10:30:00.000Z",
  "type": "TASK_STARTED",
  "payload": {
    "taskId": "task_abc123",
    "description": "Refactoring user authentication module",
    "parentTaskId": null
  }
}
```

### 3.2 TASK_UPDATED

**触发时机**：任务进度有变化时（文件修改、完成百分比更新）

**iOS Dynamic Island 展示**：
- Expanded：显示进度条和修改的文件数

**示例**：
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440002",
  "timestamp": "2024-01-15T10:31:00.000Z",
  "type": "TASK_UPDATED",
  "payload": {
    "taskId": "task_abc123",
    "progress": 45,
    "message": "Completed file deletion",
    "filesModified": ["src/auth/login.swift", "src/auth/session.swift"]
  }
}
```

### 3.3 TOOL_CALLED

**触发时机**：Claude Code 调用任何工具时（Bash/Read/Write/Edit 等）

**iOS Dynamic Island 展示**：
- Minimal：显示工具图标闪烁
- 不主动通知，仅记录

**示例**：
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440003",
  "timestamp": "2024-01-15T10:31:30.000Z",
  "type": "TOOL_CALLED",
  "payload": {
    "taskId": "task_abc123",
    "tool": "Bash",
    "input": {
      "command": "git status",
      "workingDirectory": "/Users/project"
    },
    "outputPreview": "M src/main.swift\n?? build/",
    "duration": 150
  }
}
```

### 3.4 THINKING

**触发时机**：Claude Code 正在推理/规划时（通常在 TOOL_CALLED 之前）

**iOS Dynamic Island 展示**：
- Expanded：显示思考内容摘要（截断至 50 字符）
- 思考内容更新时自动刷新

**示例**：
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440004",
  "timestamp": "2024-01-15T10:30:05.000Z",
  "type": "THINKING",
  "payload": {
    "taskId": "task_abc123",
    "thinking": "The user wants me to refactor the authentication module. I need to first understand the current structure by reading the existing files.",
    "thinkingType": "reasoning"
  }
}
```

### 3.5 WAITING_APPROVAL

**触发时机**：Claude Code 执行高风险操作前需要用户确认

**iOS Dynamic Island 展示**：
- Expanded：显示操作描述、风险等级、详情
- 显示 Approve/Reject 按钮
- 显示倒计时

**示例**：
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440005",
  "timestamp": "2024-01-15T10:32:00.000Z",
  "type": "WAITING_APPROVAL",
  "payload": {
    "taskId": "approval_xyz789",
    "description": "Delete 3 files in project",
    "command": "rm -rf src/old_module/",
    "riskLevel": "HIGH",
    "details": {
      "affectedFiles": [
        "src/old_module/file1.swift",
        "src/old_module/file2.swift",
        "src/old_module/file3.swift"
      ],
      "impact": "This will permanently delete 3 files and cannot be undone",
      "reversible": false
    },
    "timeoutSeconds": 300,
    "approvalToken": "tok_abc123def456"
  }
}
```

### 3.6 APPROVED

**触发时机**：用户在 iOS 端点击 Approve 后

**iOS Dynamic Island 展示**：
- 显示 "Approved ✓" 状态
- 3 秒后消失

**示例**：
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440006",
  "timestamp": "2024-01-15T10:32:30.000Z",
  "type": "APPROVED",
  "payload": {
    "taskId": "task_abc123",
    "approvedTaskId": "approval_xyz789",
    "approvedAt": "2024-01-15T10:32:30.000Z",
    "approvedBy": "Michael's iPhone"
  }
}
```

### 3.7 REJECTED

**触发时机**：用户在 iOS 端点击 Reject 或审批超时

**iOS Dynamic Island 展示**：
- 显示 "Rejected ✗" 状态和原因
- 3 秒后消失

**示例**：
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440007",
  "timestamp": "2024-01-15T10:37:00.000Z",
  "type": "REJECTED",
  "payload": {
    "taskId": "task_abc123",
    "rejectedTaskId": "approval_xyz789",
    "reason": "This operation is too risky, please do it manually",
    "rejectedAt": "2024-01-15T10:37:00.000Z",
    "rejectedBy": "Michael's iPhone"
  }
}
```

### 3.8 TASK_COMPLETED

**触发时机**：任务成功完成时

**iOS Dynamic Island 展示**：
- Expanded：显示完成摘要
- 自动消失

**示例**：
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440008",
  "timestamp": "2024-01-15T10:35:00.000Z",
  "type": "TASK_COMPLETED",
  "payload": {
    "taskId": "task_abc123",
    "completedAt": "2024-01-15T10:35:00.000Z",
    "summary": "Successfully refactored 5 files in authentication module",
    "duration": 300000,
    "filesModified": [
      "src/auth/login.swift",
      "src/auth/session.swift",
      "src/auth/token.swift",
      "src/auth/logout.swift",
      "src/auth/middleware.swift"
    ],
    "toolsUsed": ["Bash", "Read", "Edit", "Edit", "Edit", "Edit", "Edit"]
  }
}
```

### 3.9 TASK_FAILED

**触发时机**：任务执行失败时（命令错误、权限问题等）

**iOS Dynamic Island 展示**：
- Expanded：显示错误信息
- 显示 "Tap for details"

**示例**：
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440009",
  "timestamp": "2024-01-15T10:33:00.000Z",
  "type": "TASK_FAILED",
  "payload": {
    "taskId": "task_abc123",
    "failedAt": "2024-01-15T10:33:00.000Z",
    "error": {
      "code": "COMMAND_FAILED",
      "message": "rm: cannot remove '/protected': Operation not permitted",
      "recoverable": false
    },
    "lastSuccessfulStep": "Completed file read of config.yaml"
  }
}
```

---

## 4. Swift 类型映射

```swift
enum ClaudeEventType: String, Codable {
    case taskStarted = "TASK_STARTED"
    case taskUpdated = "TASK_UPDATED"
    case toolCalled = "TOOL_CALLED"
    case thinking = "THINKING"
    case waitingApproval = "WAITING_APPROVAL"
    case approved = "APPROVED"
    case rejected = "REJECTED"
    case taskCompleted = "TASK_COMPLETED"
    case taskFailed = "TASK_FAILED"
}

struct ClaudeEvent: Codable {
    let id: UUID
    let timestamp: Date
    let type: ClaudeEventType
    let payload: ClaudeEventPayload
}

enum ClaudeEventPayload: Codable {
    case taskStarted(TaskStartedPayload)
    case taskUpdated(TaskUpdatedPayload)
    case toolCalled(ToolCalledPayload)
    case thinking(ThinkingPayload)
    case waitingApproval(WaitingApprovalPayload)
    case approved(ApprovedPayload)
    case rejected(RejectedPayload)
    case taskCompleted(TaskCompletedPayload)
    case taskFailed(TaskFailedPayload)
}
```

---

## 5. 事件流转状态机

```
                    TASK_STARTED
                        │
                        ▼
                   THINKING ──→ TOOL_CALLED
                        │           │
                        │           ▼
                        │      TASK_UPDATED
                        │           │
                        ▼           ▼
                  WAITING_APPROVAL ◄──┘
                   │         │
          APPROVED │         │ REJECTED / TIMEOUT
                   │         │
                   ▼         ▼
              TASK_COMPLETED / TASK_FAILED
```

---

## 6. 版本兼容性

| Schema 版本 | 支持的事件类型 | iOS 要求 | macOS 要求 |
|------------|--------------|---------|-----------|
| 1.0 (Phase A) | 全部 9 种 | iOS 17.0+ | macOS 14.0+ |
