PROJECT_NAME = "claude-code-island"

REPO_ROOT = "/Users/michael/Developer/github/claude-code-island"
PROJECT_DIR = REPO_ROOT + "/claude-code-island"

TRAPE_ROOT = REPO_ROOT + "/trae-loop"
STATE_FILE = TRAPE_ROOT + "/state.json"
STATE_SCHEMA_FILE = TRAPE_ROOT + "/state-schema.json"
TEMPLATES_DIR = TRAPE_ROOT + "/execution-templates"
EXECUTION_DIR = TRAPE_ROOT + "/execution"

# --- Simplified phase model (路径二: 真正的 Loop) ---
PHASES = [
    "init",
    "scoping",
    "executing",
    "done",
]

MAX_ATTEMPTS = 2

# --- 9 种 ClaudeEvent 事件类型 ---
EVENT_TYPES = [
    "TASK_STARTED",
    "TASK_UPDATED",
    "TOOL_CALLED",
    "THINKING",
    "WAITING_APPROVAL",
    "APPROVED",
    "REJECTED",
    "TASK_COMPLETED",
    "TASK_FAILED",
]

# --- 全部交付物清单（合并原 4 个阶段）---
ARTIFACT_DOCS = [
    "docs/requirements.md",
    "docs/architecture.md",
    "docs/event-schema.md",
    "docs/communication-protocol.md",
]

ARTIFACT_MACOS = [
    "ClaudeEvent.swift",
    "EventStreamManager.swift",
    "IslandView.swift",
    "ApprovalView.swift",
    "main.swift",
]

ARTIFACT_IOS = [
    "WebSocketBridge.swift",
    "LiveActivityManager.swift",
    "RemoteApprovalView.swift",
    "main.swift",
]

MACOS_DIR = "macos-island"
IOS_DIR = "ios-island"
VERIFICATION_FILE = "verification-report.md"

# --- AgentLoop 配置常量 (模式 C) ---
MAX_ITER = 20               # 主循环最大迭代次数
CHECKPOINT_EVERY = 5        # 每 N 轮自动 check_all
PATCH_MAX_ITER = 10         # Patch 循环最大迭代次数 (比主循环少)
COMMAND_TIMEOUT = 30        # 命令执行超时 (秒)
AGENT_TIMEOUT = 120         # Agent CLI step 超时 (秒, 含思考时间)
AGENT_MAX_RETRIES = 2       # Agent CLI 非零退出重试次数
