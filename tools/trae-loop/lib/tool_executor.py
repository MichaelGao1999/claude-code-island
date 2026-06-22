"""ToolExecutor — 编排器的工具执行器。

Agent 通过 StdioDriver 发出 `<tool>` 调用决策,
ToolExecutor 实际执行 create_file / edit_file / run_command / verify。

安全约束:
    - 所有文件路径必须解析到 project_dir 以内 (路径逃逸防御)
    - run_command 使用白名单模式, 拒绝危险操作
    - 文件内容有长度保护 (create_file max 100k, edit_file max 50k)
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
import time
from typing import Any


class ToolExecutor:
    """执行 Agent 决策的具体工具操作。"""

    def __init__(
        self,
        project_dir: str,
        command_timeout: int = 30,
    ) -> None:
        self.project_dir = os.path.abspath(project_dir)
        self.command_timeout = command_timeout

    # ------------------------------------------------------------------
    # 安全校验
    # ------------------------------------------------------------------

    def _safe_path(self, path: str) -> str | None:
        """解析并验证路径是否在 project_dir 内。

        Returns:
            规范化绝对路径 (如果安全), None 如果路径越界。
        """
        abs_path = os.path.abspath(os.path.join(self.project_dir, path))
        if not abs_path.startswith(self.project_dir + os.sep) and abs_path != self.project_dir:
            # 允许精确等于 project_dir (如验证工具在根目录)
            # 但不在根目录内时拒绝
            if not abs_path.startswith(self.project_dir):
                return None
        return abs_path

    def _deny_path(self, path: str, reason: str) -> str:
        return f"[ToolExecutor] DENIED: path '{path}' {reason}"

    # ------------------------------------------------------------------
    # 工具实现
    # ------------------------------------------------------------------

    def create_file(self, path: str, content: str = "", **kwargs: Any) -> str:
        """创建新文件 (如果存在则覆盖)。

        Args:
            path: 相对于 project_dir 的文件路径。
            content: 文件内容。
            **kwargs: 额外参数 (忽略)。

        Returns:
            结果文本 (用于追加到 messages 的 tool 消息)。
        """
        safe = self._safe_path(path)
        if safe is None:
            return self._deny_path(path, "escapes project directory")

        # 内容长度保护
        if len(content) > 100_000:
            content = content[:100_000] + "\n<!-- content truncated at 100k chars -->\n"

        try:
            os.makedirs(os.path.dirname(safe), exist_ok=True)
            with open(safe, "w", encoding="utf-8") as f:
                f.write(content)
            size = len(content.encode("utf-8"))
            return f"[ToolExecutor] created {path} ({size} bytes)"
        except OSError as e:
            return f"[ToolExecutor] ERROR creating {path}: {e}"

    def edit_file(self, path: str, old_string: str = "", new_string: str = "", **kwargs: Any) -> str:
        """在已有文件中精确替换文本。

        要求 old_string 必须唯一匹配 (恰好出现一次), 防止误替换。

        Args:
            path: 相对于 project_dir 的文件路径。
            old_string: 被替换的精确文本 (必须完全匹配)。
            new_string: 替换后的文本。
            **kwargs: 额外参数 (忽略)。

        Returns:
            结果文本。
        """
        safe = self._safe_path(path)
        if safe is None:
            return self._deny_path(path, "escapes project directory")

        if not os.path.isfile(safe):
            return f"[ToolExecutor] ERROR: {path} does not exist"
        if not old_string:
            return f"[ToolExecutor] ERROR: old_string is empty — refusing to replace blindly"

        try:
            with open(safe, "r", encoding="utf-8") as f:
                content = f.read()
        except (OSError, UnicodeDecodeError) as e:
            return f"[ToolExecutor] ERROR reading {path}: {e}"

        count = content.count(old_string)
        if count == 0:
            return f"[ToolExecutor] ERROR: old_string not found in {path}"
        if count > 1:
            return (
                f"[ToolExecutor] ERROR: old_string appears {count} times in {path}, "
                "refusing ambiguous edit. Use create_file to rewrite instead."
            )

        new_content = content.replace(old_string, new_string, 1)

        # 新内容长度保护
        if len(new_content) > 100_000:
            return f"[ToolExecutor] ERROR: edited file would exceed 100k chars"

        try:
            with open(safe, "w", encoding="utf-8") as f:
                f.write(new_content)
            delta = len(new_content) - len(content)
            sign = "+" if delta >= 0 else ""
            return f"[ToolExecutor] edited {path}: {sign}{delta} chars, 1 replacement"
        except OSError as e:
            return f"[ToolExecutor] ERROR writing {path}: {e}"

    def run_command(self, command: str = "", **kwargs: Any) -> str:
        """在 project_dir 下执行命令。

        安全: 使用白名单模式, 拒绝危险命令。

        Args:
            command: 要执行的 shell 命令。
            **kwargs: 额外参数 (忽略)。

        Returns:
            命令输出 (stdout + stderr, 截断到 5000 字符)。
        """
        from .agent_driver import _is_safe_command

        if not command:
            return "[ToolExecutor] ERROR: empty command"

        safe, reason = _is_safe_command(command)
        if not safe:
            return f"[ToolExecutor] DENIED: {reason}"

        try:
            result = subprocess.run(
                command,
                shell=True,
                capture_output=True,
                text=True,
                encoding="utf-8",
                cwd=self.project_dir,
                timeout=self.command_timeout,
            )
            output = result.stdout.strip()
            if result.stderr:
                output += "\n" + result.stderr.strip()
            # 截断长输出
            max_len = 5000
            if len(output) > max_len:
                output = output[:max_len] + f"\n... (output truncated at {max_len} chars)"

            if result.returncode == 0:
                return f"[ToolExecutor] command exited 0:\n{output}"
            else:
                return (
                    f"[ToolExecutor] command exited {result.returncode}:\n{output}"
                )
        except subprocess.TimeoutExpired:
            return f"[ToolExecutor] TIMEOUT after {self.command_timeout}s"
        except OSError as e:
            return f"[ToolExecutor] ERROR: {e}"

    def verify(self, **kwargs: Any) -> str:
        """调用 PhaseChecker 执行全部产物检查。

        Returns:
            检查结果文本 (用于注入 messages)。
        """
        from .phase_checker import PhaseChecker

        checker = PhaseChecker(self.project_dir)
        ok, missing, details = checker.check_all()

        if ok:
            lines = [
                "## Verify Results: ✅ ALL PASS",
                f"  Status: {details}",
                f"  Missing: 0 items",
            ]
        else:
            lines = [
                "## Verify Results: ⚠️ ISSUES FOUND",
                f"  Status: {details}",
                f"  Missing: {len(missing)} items",
            ]
            for item in missing:
                lines.append(f"    - {item}")

        return "\n".join(lines)

    # ------------------------------------------------------------------
    # 分发入口
    # ------------------------------------------------------------------

    def execute(self, tool_call: Any) -> str:
        """根据 ToolCall 类型分发到具体方法。

        Args:
            tool_call: 具有 `type` 和 `params` (dict) 属性的对象。
                       ToolCall 或任何有相同协议的对象均可。

        Returns:
            执行结果文本。
        """
        ttype = tool_call.type if hasattr(tool_call, "type") else tool_call.get("type", "")
        params = tool_call.params if hasattr(tool_call, "params") else tool_call.get("params", {})

        if ttype == "create_file":
            return self.create_file(**params)
        elif ttype == "edit_file":
            return self.edit_file(**params)
        elif ttype == "run_command":
            return self.run_command(**params)
        elif ttype == "verify":
            return self.verify(**params)
        else:
            return f"[ToolExecutor] unknown tool type: {ttype}"
