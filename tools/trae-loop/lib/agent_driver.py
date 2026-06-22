"""AgentDriver — 编排器与外部 Agent CLI 的通信抽象层。

协议:
    编排器将 messages (list[dict]) 格式化为纯文本通过 stdin 送入外部 Agent,
    从 stdout 读取 `<tool>` 标记提取 tool_use 决策。

角色:
    AgentDriver (ABC) — 接口定义
    StdioDriver     — 通过 subprocess stdin/stdout 与外部 CLI 通信
    StubDriver      — 测试用, 固定响应序列
"""

from __future__ import annotations

import re
import subprocess
import sys
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Any


# ---------------------------------------------------------------------------
# 数据类型
# ---------------------------------------------------------------------------


@dataclass
class ToolCall:
    """单个工具调用的描述。"""

    type: str  # "create_file" | "edit_file" | "run_command" | "verify"
    params: dict[str, Any] = field(default_factory=dict)


@dataclass
class AgentResponse:
    """Agent 单次 step 的返回。"""

    content: str
    """Agent 回复的纯文本内容（不含工具标记）。"""

    tool_calls: list[ToolCall] = field(default_factory=list)
    """Agent 在本轮调用的工具列表。"""

    stop_reason: str = "end_turn"
    """停止原因: "tool_use" (还有工具要调用) | "end_turn" (本轮完成)。"""


# ---------------------------------------------------------------------------
# ABC
# ---------------------------------------------------------------------------


class AgentDriver(ABC):
    """编排器与外部 Agent CLI 的通信接口。"""

    @abstractmethod
    def step(self, messages: list[dict]) -> AgentResponse:
        """向 Agent 送入一条带上下文的消息, 返回其响应。

        Args:
            messages: OpenAI/Anthropic 风格消息列表,
                      每项含 {"role": str, "content": str}。

        Returns:
            AgentResponse, 包含文本回复和/或工具调用。
        """
        ...


# ---------------------------------------------------------------------------
# StdioDriver — 通过 stdin/stdout 与外部 CLI 通信
# ---------------------------------------------------------------------------

# 被拒绝的危险命令前缀（白名单反面）
_DENIED_PREFIXES = (
    "rm -rf /", "rm -rf --no-preserve-root",
    "sudo ", "dd if=", "mkfs.", "fdisk",
    "> /dev/", "| shutdown", "| reboot",
    ":(){ :|:& };:",  # fork bomb
)

# 工具标记正则 —— 支持跨行
_TOOL_TAG_RE = re.compile(
    r"<tool>\s*\n"
    r"(.*?)"
    r"\n</tool>",
    re.DOTALL,
)

_RESULT_TAG_RE = re.compile(
    r"<result>(.*?)</result>",
    re.DOTALL,
)

_STOP_RE = re.compile(
    r"<stop_reason>\s*(\S+)\s*</stop_reason>",
    re.DOTALL,
)


def _format_messages(messages: list[dict]) -> str:
    """将 messages 列表格式化为纯文本, 供 StdioDriver 写入 stdin。"""
    parts: list[str] = []
    for msg in messages:
        role = msg.get("role", "unknown")
        content = msg.get("content", "")
        if role == "system":
            parts.append(f"## System Instructions\n{content}\n")
        elif role == "user":
            parts.append(f"## User Message\n{content}\n")
        elif role == "assistant":
            parts.append(f"## Assistant Response\n{content}\n")
        elif role == "tool":
            parts.append(f"## Tool Result\n{content}\n")
        else:
            parts.append(f"## {role.title()} Message\n{content}\n")
    return "\n".join(parts)


def _parse_agent_output(text: str) -> tuple[str, list[ToolCall], str]:
    """从 Agent stdout 解析工具标记和停止原因。

    Returns:
        (content: str, tool_calls: list[ToolCall], stop_reason: str)
    """
    # 1) 提取停止原因
    stop_reason = "end_turn"
    stp = _STOP_RE.search(text)
    if stp:
        stop_reason = stp.group(1).strip()

    # 2) 提取工具调用
    tool_calls: list[ToolCall] = []
    for match in _TOOL_TAG_RE.finditer(text):
        block = match.group(1).strip()
        tc = _parse_tool_block(block)
        if tc is not None:
            tool_calls.append(tc)

    # 3) 移除标记后剩纯文本
    clean = _TOOL_TAG_RE.sub("", text)
    clean = _RESULT_TAG_RE.sub("", clean)
    clean = _STOP_RE.sub("", clean)
    clean = clean.strip()

    return clean, tool_calls, stop_reason


def _parse_tool_block(block: str) -> ToolCall | None:
    """从 <tool>...</tool> 块内部解析单条工具调用。"""
    lines = block.splitlines()
    if not lines:
        return None

    first = lines[0].strip()
    if first.startswith("type:"):
        ttype = first.split(":", 1)[1].strip()
    else:
        # 没有 type 头, 第一行可能是 type 值
        return None

    params: dict[str, Any] = {}
    current_key: str | None = None
    current_value: list[str] = []

    for line in lines[1:]:
        # YAML-style switch: "key:" starts new param, "|" starts multiline
        if re.match(r"^\w[\w_-]*:\s*$", line):
            # Save previous
            if current_key is not None:
                params[current_key] = "\n".join(current_value).strip()
            current_key = line.split(":", 1)[0].strip()
            current_value = []
            # Check if next line has | style
            continue
        elif re.match(r"^\w[\w_-]*:\s*\|", line):
            if current_key is not None:
                params[current_key] = "\n".join(current_value).strip()
            current_key = line.split(":", 1)[0].strip()
            # literal block scalar — content follows on subsequent lines
            current_value = []
            continue
        elif re.match(r"^\w[\w_-]*:\s", line):
            # key: value on same line
            key, _, val = line.partition(":")
            if current_key is not None:
                params[current_key] = "\n".join(current_value).strip()
            params[key.strip()] = val.strip()
            current_key = None
            current_value = []
            continue

        if current_key is not None:
            current_value.append(line)

    # flush last
    if current_key is not None:
        params[current_key] = "\n".join(current_value).strip()

    # 对 create_file 做 content 长度保护
    if ttype == "create_file" and "content" in params:
        if len(params["content"]) > 50_000:
            params["content"] = params["content"][:50_000] + "\n<!-- content truncated at 50k chars -->"

    return ToolCall(type=ttype, params=params)


def _is_safe_command(command: str) -> tuple[bool, str]:
    """检查命令是否在安全白名单内。"""
    stripped = command.strip()
    if not stripped:
        return False, "empty command"

    # 拒绝危险前缀
    for prefix in _DENIED_PREFIXES:
        if stripped.startswith(prefix):
            return False, f"denied: command starts with '{prefix}'"

    # 白名单: 允许的命令前缀
    allowed_prefixes = (
        "swift", "xcodebuild", "ls", "mkdir", "touch", "echo",
        "cat", "cp", "mv", "python3", "python", "swiftc",
        "plutil", "file", "head", "tail", "wc", "find",
        "grep", "sed", "awk", "sort", "uniq", "diff",
        "chmod", "chown",
    )
    cmd_word = stripped.split()[0] if stripped.split() else ""
    if cmd_word in allowed_prefixes:
        return True, ""

    # 绝对路径允许（通常是 swiftc/xcodebuild 等）
    if cmd_word.startswith("/"):
        return True, ""

    return False, f"command '{cmd_word}' not in allowed list"


# ---------------------------------------------------------------------------
# StdioDriver
# ---------------------------------------------------------------------------


class StdioDriver(AgentDriver):
    """通过 subprocess 的 stdin/stdout 与外部 Agent CLI 通信。

    启动一个长期运行的子进程, 每次 step() 写入格式化消息并读取响应。
    """

    def __init__(
        self,
        command: list[str],
        cwd: str | None = None,
        timeout: int = 60,
        max_retries: int = 2,
    ) -> None:
        self.command = command
        self.cwd = cwd
        self.timeout = timeout
        self.max_retries = max_retries
        self._process: subprocess.Popen | None = None

    def _ensure_process(self) -> subprocess.Popen:
        if self._process is None or self._process.poll() is not None:
            self._process = subprocess.Popen(
                self.command,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                cwd=self.cwd,
                text=True,
                encoding="utf-8",
            )
        return self._process

    def step(self, messages: list[dict]) -> AgentResponse:
        """向 Agent 写入消息并读取响应。

        重试逻辑: 非零退出码或解析失败最多重试 max_retries 次。
        """
        last_error = ""
        for attempt in range(1 + self.max_retries):
            try:
                proc = self._ensure_process()
                text = _format_messages(messages)
                stdout_data, stderr_data = proc.communicate(
                    input=text,
                    timeout=self.timeout,
                )
                if proc.returncode != 0:
                    last_error = (
                        f"CLI exited with code {proc.returncode}\n"
                        f"stderr: {stderr_data.strip()}"
                    )
                    self._process = None  # 进程已退出, 下次重建
                    if attempt < self.max_retries:
                        continue
                    return AgentResponse(
                        content=f"[StdioDriver] {last_error}",
                        stop_reason="end_turn",
                    )

                content, tool_calls, stop_reason = _parse_agent_output(stdout_data)
                return AgentResponse(
                    content=content,
                    tool_calls=tool_calls,
                    stop_reason=stop_reason,
                )

            except subprocess.TimeoutExpired:
                if self._process:
                    self._process.kill()
                    self._process = None
                last_error = f"timeout after {self.timeout}s"
                if attempt < self.max_retries:
                    continue
                return AgentResponse(
                    content=f"[StdioDriver] {last_error}",
                    stop_reason="end_turn",
                )

            except Exception as e:
                self._process = None
                last_error = str(e)
                if attempt < self.max_retries:
                    continue
                return AgentResponse(
                    content=f"[StdioDriver] error: {last_error}",
                    stop_reason="end_turn",
                )

        # Unreachable, but satisfy type checker
        return AgentResponse(
            content=f"[StdioDriver] max retries exceeded: {last_error}",
            stop_reason="end_turn",
        )

    def close(self) -> None:
        """关闭子进程。"""
        if self._process and self._process.poll() is None:
            self._process.terminate()
            try:
                self._process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self._process.kill()
            self._process = None


# ---------------------------------------------------------------------------
# StubDriver — 固定响应序列（测试用）
# ---------------------------------------------------------------------------


class StubDriver(AgentDriver):
    """固定响应序列的桩驱动, 用于测试 AgentLoop 流程。"""

    def __init__(
        self,
        responses: list[AgentResponse] | None = None,
        repeat_last: bool = True,
    ) -> None:
        self.responses = responses or []
        self._index = 0
        self.repeat_last = repeat_last

    def step(self, messages: list[dict]) -> AgentResponse:
        if self._index < len(self.responses):
            resp = self.responses[self._index]
            self._index += 1
            return resp
        if self.repeat_last and self.responses:
            return self.responses[-1]
        return AgentResponse(content="", stop_reason="end_turn")
