"""
StateManager - 管理 trae-loop 运行时 state.json 的零依赖工具类。

职责:
- 从磁盘加载 / 保存 state.json
- 提供简化的结构校验 (不依赖 jsonschema)
- 记录 phase 推进、尝试记录、错误、暂停
"""

from __future__ import annotations

import datetime
import json
import os
from typing import Optional, Tuple

from lib import (
    PHASES,
    MAX_ATTEMPTS,
    MAX_ITER,
    STATE_FILE,
    STATE_SCHEMA_FILE,
    PROJECT_NAME,
)


class StateManager:
    """管理 trae-loop 运行状态 state.json 的轻量管理器。"""

    def __init__(self, state_file: str = STATE_FILE, schema_file: str | None = STATE_SCHEMA_FILE):
        """
        构造函数。

        :param state_file: state.json 的绝对路径, 默认取 lib.STATE_FILE
        :param schema_file: JSON Schema 文件路径, 默认 STATE_SCHEMA_FILE (可选, 不强制)
        """
        self.state_file = state_file
        self.schema_file = schema_file
        self.state: dict = {}

        # 确保目录存在, 避免第一次写入失败
        os.makedirs(os.path.dirname(self.state_file), exist_ok=True)

    # ------------------------------------------------------------------ #
    # 工具函数
    # ------------------------------------------------------------------ #
    def _iso_now(self) -> str:
        """返回 UTC ISO 8601 字符串, 形如 2026-06-21T10:00:00Z。"""
        return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    def _init_default_state(self) -> dict:
        """构建初始 state, 并落盘一次。"""
        now = self._iso_now()
        self.state = {
            "projectName": PROJECT_NAME,
            "version": "1.0",
            "currentPhase": "init",
            "status": "running",
            "history": [
                {
                    "phase": "init",
                    "attempt": 1,
                    "status": "completed",
                    "output": None,
                    "confirmed": True,
                    "confirmedAt": now,
                }
            ],
            "currentAttempt": 1,
            "maxAttempts": MAX_ATTEMPTS,
            "artifacts": {
                "scoping": None,
                "executing": None,
            },
            "errors": [],
            "startedAt": now,
            "updatedAt": now,
            # AgentLoop 模式 C 字段
            "iterations": 0,
            "messages": [],
            "mode": "manual",           # "auto" (模式 C) | "manual" (模式 B)
            "scope_file": None,
            "trace_file": None,
        }
        self.save()
        return self.state

    # ------------------------------------------------------------------ #
    # 读写
    # ------------------------------------------------------------------ #
    def load(self) -> dict:
        """
        从 self.state_file 加载 state。
        若文件不存在, 先调用 _init_default_state() 写入初始 state 再返回。
        """
        if not os.path.isfile(self.state_file):
            return self._init_default_state()

        with open(self.state_file, "r", encoding="utf-8") as f:
            self.state = json.load(f)
        return self.state

    def save(self, data: dict | None = None) -> None:
        """
        保存当前 self.state (或传入的 data) 到 state_file。
        写入前会更新 updatedAt 字段。
        """
        if data is not None:
            self.state = data
        self.state["updatedAt"] = self._iso_now()
        with open(self.state_file, "w", encoding="utf-8") as f:
            json.dump(self.state, f, ensure_ascii=False, indent=2)

    # ------------------------------------------------------------------ #
    # 校验
    # ------------------------------------------------------------------ #
    def validate(self, data: dict | None = None) -> tuple[bool, list[str]]:
        """
        简化校验: 检查必需顶层字段与基本类型 / 约束。

        返回 (ok, errors)。
        """
        target = data if data is not None else self.state
        errors: list[str] = []

        required_fields = [
            "projectName", "version", "currentPhase", "status",
            "history", "currentAttempt", "maxAttempts",
            "artifacts", "errors", "startedAt", "updatedAt",
        ]
        for field in required_fields:
            if field not in target:
                errors.append(f"missing required field: {field}")

        if "currentPhase" in target:
            if target["currentPhase"] not in PHASES:
                errors.append(
                    f"invalid currentPhase: {target['currentPhase']} not in {PHASES}"
                )

        if "status" in target:
            if target["status"] not in ("running", "PAUSED", "done"):
                errors.append(f"invalid status: {target['status']}")

        for int_field, name in (("currentAttempt", "currentAttempt"),
                                ("maxAttempts", "maxAttempts")):
            if int_field in target:
                val = target[int_field]
                if not isinstance(val, int) or isinstance(val, bool) or val < 1:
                    errors.append(f"{name} must be a positive integer, got {val!r}")

        if "history" in target and not isinstance(target["history"], list):
            errors.append("history must be a list")

        if "errors" in target and not isinstance(target["errors"], list):
            errors.append("errors must be a list")

        if "artifacts" in target and not isinstance(target["artifacts"], dict):
            errors.append("artifacts must be a dict")

        return (len(errors) == 0, errors)

    # ------------------------------------------------------------------ #
    # 模式 C 扩展方法
    # ------------------------------------------------------------------ #

    def set_mode(self, mode: str) -> None:
        """设置运行模式: "auto" (模式 C) 或 "manual" (模式 B)。"""
        self.state["mode"] = mode
        self.save()

    def set_iterations(self, n: int) -> None:
        """设置已执行迭代数。"""
        self.state["iterations"] = n
        self.save()

    def increment_iterations(self) -> int:
        """iterations += 1, 保存, 返回新值。"""
        self.state["iterations"] = self.state.get("iterations", 0) + 1
        self.save()
        return self.state["iterations"]

    def save_messages(self, messages: list[dict]) -> None:
        """持久化 messages (最多保留最近 100 条)。"""
        self.state["messages"] = messages[-100:]  # 保留最近 100 条
        self.save()

    def restore_messages(self) -> list[dict]:
        """从 state.json 恢复 messages (用于断点继续)。"""
        return self.state.get("messages", [])

    def set_scope_file(self, path: str | None) -> None:
        self.state["scope_file"] = path
        self.save()

    def set_trace_file(self, path: str | None) -> None:
        self.state["trace_file"] = path
        self.save()

    def is_mode_c(self) -> bool:
        return self.state.get("mode") == "auto"

    # ------------------------------------------------------------------ #
    # 状态变更业务方法
    # ------------------------------------------------------------------ #
    def advance(self, next_phase: str, output: str | None = None, confirmed: bool = True) -> None:
        """
        推进阶段: 记录当前阶段到 history (status=completed), 切换 currentPhase,
        重置 currentAttempt=1, 写入 artifacts[prev_phase]=output, 保存。
        """
        prev_phase = self.state.get("currentPhase")
        self.state.setdefault("history", []).append({
            "phase": prev_phase,
            "attempt": self.state.get("currentAttempt", 1),
            "status": "completed",
            "output": output,
            "confirmed": confirmed,
            "confirmedAt": self._iso_now(),
        })
        self.state["currentPhase"] = next_phase
        self.state["currentAttempt"] = 1
        artifacts = self.state.setdefault("artifacts", {})
        if prev_phase is not None:
            artifacts[prev_phase] = output
        self.save()

    def record_attempt(self, phase: str, status: str,
                       output: str | None = None, confirmed: bool = False) -> None:
        """往 history 追加一条尝试记录, 含 confirmedAt (ISO UTC), 不自动 save。"""
        self.state.setdefault("history", []).append({
            "phase": phase,
            "attempt": self.state.get("currentAttempt", 1),
            "status": status,
            "output": output,
            "confirmed": confirmed,
            "confirmedAt": self._iso_now(),
        })

    def append_error(self, msg: str) -> None:
        """追加一条带时间戳的错误, 并保存。"""
        self.state.setdefault("errors", []).append({"ts": self._iso_now(), "msg": msg})
        self.save()

    def pause(self, reason: str) -> None:
        """设置 status=PAUSED, append_error(reason), 保存。"""
        self.state["status"] = "PAUSED"
        self.append_error(reason)

    def bump_attempt(self) -> int:
        """currentAttempt += 1, 保存, 返回新值。"""
        self.state["currentAttempt"] = self.state.get("currentAttempt", 0) + 1
        self.save()
        return self.state["currentAttempt"]
