"""AgentLoop — 编排器的真正 Agent 循环 (模式 C)。

流程:
    1. 构建初始 messages (system + user 消息)
    2. while not done (最多 max_iter 次):
        a. driver.step(messages) → AgentResponse
        b. if stop_reason == "end_turn":
               check_all() → 若 ok 则 done
               (若 !ok 且 iterations 足够多 → 注入缺失项继续)
        c. for tc in tool_calls:
               result = executor.execute(tc)
               messages += assistant + tool
        d. 每 checkpoint_every 轮: 注入 check_all 中间检查
        e. 持久化 messages 到 state.json (断点恢复)
    3. 生成 trace 记录
    4. 返回 (ok, summary)

Patch 模式:
    - 精简版 run, 只修复 check_all 标记的缺失项
    - max_iter 减半
    - system prompt 强调"只修复缺失项, 不修改已正确的文件"
"""

from __future__ import annotations

import json
import os
import sys
import time
from typing import Any

from . import (
    EXECUTION_DIR,
    PROJECT_DIR,
    MAX_ITER,
    PATCH_MAX_ITER,
    CHECKPOINT_EVERY,
    AGENT_TIMEOUT,
)
from .agent_driver import AgentDriver, AgentResponse, ToolCall
from .tool_executor import ToolExecutor
from .phase_checker import PhaseChecker
from .state_manager import StateManager
from .trace_analyzer import TraceAnalyzer


# ---------------------------------------------------------------------------
# Prompt 片段
# ---------------------------------------------------------------------------

_SYSTEM_PROMPT_TPL = """你是一个代码生成代理, 职责是按照范围文档创建交付物。

## 范围

{scope}

## 行为规则

1. **一次只做一件事**——每次调用一个工具, 创建或修改一个文件。
2. 完成一个文件后再做下一个。
3. 如果工具调用失败, 阅读错误信息并修正后重试。
4. 不要在单个响应中并行调用多个工具——每次只调用一个。
5. 每个文件创建后确认文件存在 (可选, 通过运行 ls / file 命令)。
6. 在所有交付物完成后调用 `<stop_reason>end_turn</stop_reason>` 标记来结束。
7. **不要问问题**——直接执行范围中指定的内容。无需求证。
8. 文件内容必须完整、正确, 不要留占位符或 TODO 注释 (除非范围明确要求)。
"""

_PATCH_SYSTEM_PROMPT_TPL = """你是一个代码修补代理, 职责是修复以下缺失的交付物。

## 范围

{scope}

## 需要修复的缺失项

{issues}

## 行为规则

1. **只修复列出的缺失项**——不要修改已正确的文件。
2. 每次调用一个工具, 修复一个文件。
3. 全部修复后, 调用 `<stop_reason>end_turn</stop_reason>`。
4. 不要问问题——直接修复。
"""

_USER_PROMPT = "请逐步创建交付物。每次只做一件事, 创建完成后用 end_turn 标记结束。"

_RETRY_PROMPT_TPL = """以下交付物尚未满足要求, 请继续:

{missing_text}

每个缺失项都需创建或修复。完成全部后调用 end_turn。"""

_CHECKPOINT_PROMPT_TPL = """## 中间检查 — 当前交付状态

{check_result}

如果还有缺失项, 请继续创建/修复。如果全部已满足, 调用 end_turn。"""


def _format_check_result(ok: bool, missing: list[str], details: str) -> str:
    """格式化 check_all 结果供注入 messages。"""
    if ok:
        return f"✅ 全部 {details}"
    items = "\n".join(f"  - {m}" for m in missing)
    return f"⚠️ 缺 {len(missing)} 项:\n{items}"


def _build_missing_text(missing: list[str]) -> str:
    """格式化缺失项列表。"""
    return "\n".join(f"- {m}" for m in missing)


# ---------------------------------------------------------------------------
# AgentLoop
# ---------------------------------------------------------------------------


class AgentLoop:
    """编排器的自动 Agent 循环 (模式 C)。"""

    def __init__(
        self,
        driver: AgentDriver,
        executor: ToolExecutor,
        checker: PhaseChecker,
        state_mgr: StateManager,
        trace_analyzer: TraceAnalyzer | None = None,
        max_iter: int = MAX_ITER,
        checkpoint_every: int = CHECKPOINT_EVERY,
        trace_file: str | None = None,
    ) -> None:
        self.driver = driver
        self.executor = executor
        self.checker = checker
        self.state_mgr = state_mgr
        self.trace_analyzer = trace_analyzer or TraceAnalyzer()
        self.max_iter = max_iter
        self.checkpoint_every = checkpoint_every
        self.trace_file = trace_file

    # ------------------------------------------------------------------
    # 主循环
    # ------------------------------------------------------------------

    def run(self, scope: str) -> tuple[bool, str]:
        """执行完整的 Agent 循环。

        Args:
            scope: prompt-scope.md 的完整内容。

        Returns:
            (ok: bool, summary: str)
        """
        # 1) 检查是否有断点 messages
        saved_messages = self.state_mgr.restore_messages()
        if saved_messages:
            messages = saved_messages
            start_iter = self.state_mgr.state.get("iterations", 0)
            print(f"[AgentLoop] 恢复断点: 从 iteration {start_iter} 继续")
        else:
            messages = [
                {"role": "system", "content": _SYSTEM_PROMPT_TPL.format(scope=scope)},
                {"role": "user", "content": _USER_PROMPT},
            ]
            start_iter = 0
            self.state_mgr.set_iterations(0)

        # 2) 标记模式 C
        self.state_mgr.set_mode("auto")

        # 3) Trace 记录
        trace_entries: list[dict] = []
        loop_start = time.time()

        print(f"[AgentLoop] 开始执行 (max_iter={self.max_iter})")
        print()

        for iteration in range(start_iter, self.max_iter):
            current_iter = iteration + 1
            print(f"  ── Iteration {current_iter}/{self.max_iter} ──")

            # a) Agent step
            iter_start = time.time()
            response = self.driver.step(messages)
            iter_elapsed = time.time() - iter_start

            # b) 处理响应
            if response.content:
                lines = response.content.splitlines()
                # 只打印前几行
                preview = "\n".join(lines[:5])
                if len(lines) > 5:
                    preview += "\n    ..."
                print(f"  Agent: {preview}")

            tc_count = len(response.tool_calls)
            if tc_count > 0:
                for tc in response.tool_calls:
                    print(f"  → tool: {tc.type} {_tc_preview(tc)}")
            else:
                print(f"  → no tool calls (stop_reason={response.stop_reason})")

            # c) 如果 Agent 说 end_turn → 最终检查
            if response.stop_reason == "end_turn":
                print()
                print("  [AgentLoop] Agent end_turn, 运行最终检查 ...")

                # 注入 assistant 消息
                if response.content:
                    messages.append({"role": "assistant", "content": response.content})

                ok, missing, details = self.checker.check_all()
                if ok:
                    summary = f"全部交付物检查通过 ({details})"
                    print(f"  ✅ {summary}")
                    self.state_mgr.set_iterations(current_iter)
                    self.state_mgr.save_messages(messages)
                    self._save_trace(trace_entries, loop_start, scope)
                    return True, summary
                else:
                    # 缺项: 如果还有迭代额度, 继续循环
                    if current_iter < self.max_iter:
                        missing_text = _build_missing_text(missing)
                        retry_msg = _RETRY_PROMPT_TPL.format(missing_text=missing_text)
                        messages.append({"role": "user", "content": retry_msg})
                        print(f"  ⚠️ 缺 {len(missing)} 项, 继续修复 ...")
                        for m in missing:
                            print(f"    - {m}")
                        # 记录这次 end_turn 到 trace
                        trace_entries.append({
                            "iteration": current_iter,
                            "action": "end_turn_check",
                            "result": "missing",
                            "missing": missing,
                            "elapsed": round(iter_elapsed, 1),
                        })
                        continue
                    else:
                        msg = f"达到 max_iter={self.max_iter}, 仍有 {len(missing)} 项缺失"
                        print(f"  ❌ {msg}")
                        self.state_mgr.set_iterations(current_iter)
                        self.state_mgr.save_messages(messages)
                        self._save_trace(trace_entries, loop_start, scope)
                        return False, msg

            # d) 执行工具调用
            if tc_count > 0:
                # 先追加 assistant 消息 (含工具标记的文本)
                assistant_content = response.content or ""
                if assistant_content:
                    messages.append({"role": "assistant", "content": assistant_content})

                for tc in response.tool_calls:
                    trace_entry = {
                        "iteration": current_iter,
                        "action": tc.type,
                        "params": tc.params,
                        "elapsed": 0,
                    }
                    tool_start = time.time()
                    result = self.executor.execute(tc)
                    tool_elapsed = time.time() - tool_start
                    trace_entry["elapsed"] = round(tool_elapsed, 1)
                    trace_entry["result"] = result[:200]  # 截断
                    trace_entries.append(trace_entry)

                    # 追加 tool result 消息
                    messages.append({"role": "tool", "content": result})
                    print(f"  ✓ {tc.type} 完成 ({tool_elapsed:.1f}s)")

            else:
                # 既无工具调用也无 end_turn → 把文本当 message 继续
                if response.content:
                    messages.append({"role": "assistant", "content": response.content})
                # 追加一个用户提示驱动继续
                messages.append({"role": "user", "content": "请继续下一步。"})

            # e) 每 checkpoint_every 轮执行中间检查
            if current_iter % self.checkpoint_every == 0:
                ok, missing, details = self.checker.check_all()
                check_text = _format_check_result(ok, missing, details)
                checkpoint_msg = _CHECKPOINT_PROMPT_TPL.format(check_result=check_text)
                messages.append({"role": "user", "content": checkpoint_msg})
                if ok:
                    # 全部满足, 可请求 Agent 发 end_turn
                    pass  # 继续循环等待 Agent 的 end_turn
                else:
                    print(f"  [检查点] 缺 {len(missing)} 项")
                    for m in missing:
                        print(f"    - {m}")

            # f) 持久化
            self.state_mgr.set_iterations(current_iter)
            self.state_mgr.save_messages(messages)

            print()

        # 达到 max_iter
        ok, missing, details = self.checker.check_all()
        summary = f"达到 max_iter({self.max_iter}), 仍有 {len(missing)} 项缺失"
        if ok:
            summary = f"在最后一步通过 ({details})"
        print(f"\n[AgentLoop] {summary}")
        self._save_trace(trace_entries, loop_start, scope)
        return ok, summary

    # ------------------------------------------------------------------
    # Patch 模式
    # ------------------------------------------------------------------

    def patch_mode(self, scope: str, issues: list[str]) -> tuple[bool, str]:
        """基于已知缺失项的精简运行。

        Args:
            scope: prompt-scope.md 的完整内容。
            issues: 缺失项列表 (来自 PhaseChecker.check_all())。

        Returns:
            (ok: bool, summary: str)
        """
        issues_text = "\n".join(f"- {m}" for m in issues)

        messages = [
            {
                "role": "system",
                "content": _PATCH_SYSTEM_PROMPT_TPL.format(
                    scope=scope, issues=issues_text
                ),
            },
            {"role": "user", "content": f"请修复以下缺失项:\n{issues_text}"},
        ]

        self.state_mgr.set_mode("auto")
        trace_entries: list[dict] = []
        loop_start = time.time()

        print(f"[AgentLoop] Patch 模式开始 (max_iter={PATCH_MAX_ITER})")
        print()

        for iteration in range(PATCH_MAX_ITER):
            current_iter = iteration + 1
            print(f"  ── Patch Iteration {current_iter}/{PATCH_MAX_ITER} ──")

            response = self.driver.step(messages)
            tc_count = len(response.tool_calls)

            if response.stop_reason == "end_turn":
                print("  [AgentLoop] Agent end_turn, 验证修复 ...")
                if response.content:
                    messages.append({"role": "assistant", "content": response.content})

                ok, missing, details = self.checker.check_all()
                if ok:
                    summary = f"Patch 修复全部通过 ({details})"
                    print(f"  ✅ {summary}")
                    self.state_mgr.save_messages(messages)
                    self._save_trace(trace_entries, loop_start, scope)
                    return True, summary
                else:
                    if current_iter < PATCH_MAX_ITER:
                        new_issues = _build_missing_text(missing)
                        messages.append({
                            "role": "user",
                            "content": f"仍有缺失项:\n{new_issues}\n请继续修复。",
                        })
                        print(f"  ⚠️ 仍有 {len(missing)} 项未修复")
                        continue
                    else:
                        msg = f"Patch 达到 max_iter, 仍有 {len(missing)} 项缺失"
                        print(f"  ❌ {msg}")
                        self._save_trace(trace_entries, loop_start, scope)
                        return False, msg

            if tc_count > 0:
                if response.content:
                    messages.append({"role": "assistant", "content": response.content})
                for tc in response.tool_calls:
                    tool_start = time.time()
                    result = self.executor.execute(tc)
                    tool_elapsed = time.time() - tool_start
                    messages.append({"role": "tool", "content": result})
                    trace_entries.append({
                        "patch_iteration": current_iter,
                        "action": tc.type,
                        "params": tc.params,
                        "elapsed": round(tool_elapsed, 1),
                        "result": result[:200],
                    })
                    print(f"  ✓ {tc.type} ({tool_elapsed:.1f}s)")
            else:
                if response.content:
                    messages.append({"role": "assistant", "content": response.content})
                messages.append({"role": "user", "content": "请继续修复。"})

            self.state_mgr.save_messages(messages)
            print()

        ok, missing, details = self.checker.check_all()
        summary = f"Patch 达到 max_iter({PATCH_MAX_ITER})"
        if ok:
            summary = f"Patch 最后一步通过 ({details})"
        print(f"\n[AgentLoop] {summary}")
        self._save_trace(trace_entries, loop_start, scope)
        return ok, summary

    # ------------------------------------------------------------------
    # Trace 生成
    # ------------------------------------------------------------------

    def _save_trace(self, entries: list[dict], start: float, scope_prompt: str) -> None:
        """保存 trace.json。"""
        duration = round(time.time() - start, 1)
        trace = {
            "scope": "Claude Code Island loop scope",
            "prompt": scope_prompt[:200],
            "execution": entries,
            "duration": duration,
            "errors": [],
            "mode": "auto",
        }
        trace_path = os.path.join(EXECUTION_DIR, "trace.json")
        try:
            with open(trace_path, "w", encoding="utf-8") as f:
                json.dump(trace, f, ensure_ascii=False, indent=2)
        except OSError as e:
            print(f"[AgentLoop] 无法写入 trace.json: {e}")


def _tc_preview(tc: ToolCall) -> str:
    """为工具调用生成简短预览。"""
    path = tc.params.get("path", tc.params.get("command", ""))
    if path:
        return path[:80]
    return ""
