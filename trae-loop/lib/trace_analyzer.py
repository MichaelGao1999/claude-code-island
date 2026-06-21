"""TraceAnalyzer — Execution Trace 分析与质量检查。

当 Trae CLI 输出 trajectory.json（或 IDE 粘贴模式下人工填写 trace），
TraceAnalyzer 验证其完整性并生成 human-readable 摘要。
"""

from __future__ import annotations

import json
import os
from typing import Any


class TraceAnalyzer:
    """分析 execution trace 的质量并生成摘要。"""

    REQUIRED_KEYS = {"execution", "prompt", "scope", "duration", "errors"}

    def load_trace(self, trace_path: str) -> dict | None:
        """从 JSON 文件加载 trace，若不存在或解析失败返回 None。"""
        if not os.path.isfile(trace_path):
            return None
        try:
            with open(trace_path, "r", encoding="utf-8") as f:
                return json.load(f)
        except (json.JSONDecodeError, OSError):
            return None

    def validate_trace(self, trace: dict) -> tuple[bool, list[str]]:
        """检查 trace 结构完整性。

        Returns:
            (ok: bool, issues: list[str])
        """
        issues: list[str] = []

        # 1) 必需顶层键
        missing_keys = self.REQUIRED_KEYS - set(trace.keys())
        if missing_keys:
            issues.append(f"缺少必需字段: {', '.join(sorted(missing_keys))}")

        # 2) execution 非空
        execution = trace.get("execution", [])
        if isinstance(execution, list):
            if len(execution) == 0:
                issues.append("execution 为空列表（无操作记录）")
        elif not execution:
            issues.append("execution 字段不存在或无内容")

        # 3) errors 字段不应抛异常（允许空列表）
        errs = trace.get("errors")
        if errs and isinstance(errs, list):
            serious = [e for e in errs if isinstance(e, str) and "error" in e.lower()]
            if serious:
                issues.append(f"trace 中包含 {len(serious)} 个严重错误标记")

        # 4) 最小 content 检查：有 scope 或 prompt
        if not trace.get("scope") and not trace.get("prompt"):
            issues.append("trace 缺少 scope 和 prompt 字段（无法追溯输入）")

        ok = len(issues) == 0
        return ok, issues

    def summarize(self, trace: dict) -> str:
        """生成 human-readable 执行摘要。"""
        lines: list[str] = []
        lines.append("=== Execution Trace 摘要 ===")

        execution = trace.get("execution", [])
        if isinstance(execution, list):
            lines.append(f"操作步数: {len(execution)}")
            # 提取唯一文件操作
            files_touched: set[str] = set()
            for step in execution:
                if isinstance(step, dict):
                    for val in step.values():
                        if isinstance(val, str) and "/" in val:
                            files_touched.add(val)
            if files_touched:
                lines.append(f"操作文件数: {len(files_touched)}")
        else:
            lines.append("操作步数: (格式不支持)")

        duration = trace.get("duration")
        if duration:
            if isinstance(duration, (int, float)):
                lines.append(f"执行耗时: {duration:.1f}s")
            else:
                lines.append(f"执行耗时: {duration}")

        errs = trace.get("errors", [])
        if isinstance(errs, list) and errs:
            lines.append(f"错误/警告: {len(errs)} 条")

        scope = trace.get("scope", "")
        if isinstance(scope, str) and scope:
            lines.append(f"Scope 长度: {len(scope)} 字符")

        return "\n".join(lines)

    def check_artifact_content(
        self, file_path: str, min_size: int = 50
    ) -> tuple[bool, str]:
        """检查单文件内容质量：存在且大小 ≥ min_size 字节。"""
        if not os.path.isfile(file_path):
            return False, f"文件不存在: {file_path}"
        size = os.path.getsize(file_path)
        if size < min_size:
            return False, f"文件过小 ({size}B < {min_size}B)"
        return True, f"{os.path.basename(file_path)} ({size}B)"

    def check_all_artifact_content(
        self, project_dir: str, artifact_paths: list[str], min_size: int = 50
    ) -> list[tuple[str, bool, str]]:
        """批量检查全部产物文件内容质量。"""
        results: list[tuple[str, bool, str]] = []
        for rel_path in artifact_paths:
            full = os.path.join(project_dir, rel_path)
            ok, msg = self.check_artifact_content(full, min_size)
            results.append((rel_path, ok, msg))
        return results
