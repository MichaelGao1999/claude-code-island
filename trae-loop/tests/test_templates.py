"""测试 TraceAnalyzer 的加载、校验、摘要功能。

运行方式:
    cd /Users/michael/Developer/github/claude-code-island/trae-loop
    python3 -m tests.test_templates
"""

from __future__ import annotations

import json
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from lib.trace_analyzer import TraceAnalyzer  # noqa: E402


def _make_valid_trace() -> dict:
    return {
        "prompt": "Build the project",
        "scope": "Claude Code Island full spec",
        "execution": [
            {"step": 1, "action": "create file", "file": "docs/requirements.md"},
            {"step": 2, "action": "create file", "file": "macos-island/ClaudeEvent.swift"},
        ],
        "duration": 42.5,
        "errors": [],
    }


def test_load_valid() -> bool:
    """加载合法 JSON trace 应返回 dict。"""
    ta = TraceAnalyzer()
    with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False, encoding="utf-8") as f:
        json.dump(_make_valid_trace(), f)
        path = f.name
    try:
        result = ta.load_trace(path)
        if not isinstance(result, dict):
            print("  期望 dict, 实际", type(result))
            return False
        return True
    finally:
        os.unlink(path)


def test_load_missing() -> bool:
    """加载不存在的文件应返回 None。"""
    ta = TraceAnalyzer()
    result = ta.load_trace("/nonexistent/trace.json")
    if result is not None:
        print("  期望 None, 实际返回 dict")
        return False
    return True


def test_validate_ok() -> bool:
    """合法 trace 应通过校验。"""
    ta = TraceAnalyzer()
    ok, issues = ta.validate_trace(_make_valid_trace())
    if not ok:
        print(f"  期望 ok=True, 实际 ok={ok}, issues={issues}")
        return False
    return True


def test_validate_missing_keys() -> bool:
    """缺少必需字段应返回 issue。"""
    ta = TraceAnalyzer()
    ok, issues = ta.validate_trace({"prompt": "only"})
    if ok:
        print("  期望 ok=False (缺少字段), 实际 ok=True")
        return False
    if not any("execution" in i for i in issues):
        print(f"  期望 issue 包含 execution, 实际 {issues}")
        return False
    return True


def test_validate_empty_execution() -> bool:
    """空 execution 列表应返回 issue。"""
    ta = TraceAnalyzer()
    trace = _make_valid_trace()
    trace["execution"] = []
    ok, issues = ta.validate_trace(trace)
    if ok:
        print("  期望 ok=False (空 execution), 实际 ok=True")
        return False
    return True


def test_summarize() -> bool:
    """摘要应包含关键信息。"""
    ta = TraceAnalyzer()
    summary = ta.summarize(_make_valid_trace())
    if "操作步数: 2" not in summary:
        print(f"  摘要不包含步数信息: {summary}")
        return False
    if "执行耗时" not in summary:
        print(f"  摘要不包含耗时信息: {summary}")
        return False
    return True


def test_check_artifact_content() -> bool:
    """文件大小检查。"""
    ta = TraceAnalyzer()
    with tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False, encoding="utf-8") as f:
        f.write("x" * 100)
        path = f.name
    try:
        ok, msg = ta.check_artifact_content(path, min_size=50)
        if not ok:
            print(f"  期望 ok=True, 实际 {msg}")
            return False
        ok, msg = ta.check_artifact_content(path, min_size=200)
        if ok:
            print(f"  期望 ok=False (大小不足), 实际 {msg}")
            return False
        return True
    finally:
        os.unlink(path)


def main() -> int:
    tests = [
        ("加载合法 trace", test_load_valid),
        ("加载不存在的文件", test_load_missing),
        ("校验合法 trace", test_validate_ok),
        ("校验缺失字段", test_validate_missing_keys),
        ("校验空 execution", test_validate_empty_execution),
        ("生成摘要", test_summarize),
        ("检查文件内容", test_check_artifact_content),
    ]
    passed = 0
    for name, fn in tests:
        try:
            ok = bool(fn())
        except Exception as exc:
            print(f"  抛出异常: {exc}")
            ok = False
        print(f"  [{ 'PASS' if ok else 'FAIL' }] {name}")
        if ok:
            passed += 1

    print()
    if passed == len(tests):
        print("All templates/trace_analyzer tests PASSED")
        return 0
    print(f"{passed}/{len(tests)} tests PASSED")
    return 1


if __name__ == "__main__":
    sys.exit(main())
