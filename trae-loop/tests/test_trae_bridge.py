"""测试 TraeBridge 的核心交互方法。

路径二: 测试 scope_guide / execution_guide / wait_for_done / ask_confirm / detect_trae_cli。

运行方式:
    cd /Users/michael/Developer/github/claude-code-island/trae-loop
    python3 -m tests.test_trae_bridge
"""

from __future__ import annotations

import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from lib.trae_bridge import TraeBridge  # noqa: E402


def run_test_guide_output() -> bool:
    """scope_guide() 和 execution_guide() 应输出指引文字。"""
    output_stream = io.StringIO()
    input_stream = io.StringIO("")
    bridge = TraeBridge(input_stream=input_stream, output_stream=output_stream)

    bridge.scope_guide()
    output_text = output_stream.getvalue()
    if "Phase: 第零步" not in output_text:
        print(f"  scope_guide 未包含「第零步」: {output_text[:100]!r}")
        return False
    if "Trae IDE" not in output_text:
        print(f"  scope_guide 未提到执行器: {output_text[:100]!r}")
        return False

    output_stream = io.StringIO()
    bridge2 = TraeBridge(input_stream=input_stream, output_stream=output_stream)
    bridge2.execution_guide()
    output_text2 = output_stream.getvalue()
    if "Phase: 执行阶段" not in output_text2:
        print(f"  execution_guide 未包含「执行阶段」: {output_text2[:100]!r}")
        return False

    return True


def run_test_wait_for_done() -> bool:
    """wait_for_done 接受 `  DONE  ` 行, 不抛异常。"""
    input_stream = io.StringIO("other\n  DONE  \n")
    output_stream = io.StringIO()
    bridge = TraeBridge(input_stream=input_stream, output_stream=output_stream)
    try:
        bridge.wait_for_done()
    except Exception as exc:  # noqa: BLE001
        print(f"  抛出异常: {exc}")
        return False
    return True


def run_test_ask_confirm() -> bool:
    """ask_confirm 三种输入分别返回 y / n / redo。"""
    cases = [
        ("Y", io.StringIO("maybe\nyes\nY\n"), "y"),
        ("N", io.StringIO("N\n"), "n"),
        ("redo", io.StringIO("xx\nRED0\nredo\n"), "redo"),
    ]
    for label, stream, expected in cases:
        output_stream = io.StringIO()
        bridge = TraeBridge(input_stream=stream, output_stream=output_stream)
        try:
            result = bridge.ask_confirm("init")
        except Exception as exc:  # noqa: BLE001
            print(f"  [{label}] 抛出异常: {exc}")
            return False
        if result != expected:
            print(f"  [{label}] 返回值不匹配: 期望 {expected!r}, 实际 {result!r}")
            return False
    return True


def run_test_run_loop() -> bool:
    """run_loop 在 CLI 不存在时应输出降级提示（不抛异常）。"""
    output_stream = io.StringIO()
    input_stream = io.StringIO("done\n")
    bridge = TraeBridge(input_stream=input_stream, output_stream=output_stream)
    try:
        bridge.run_loop("/tmp/mock-scope.md", "/tmp/trace.json", wait_for_done=True)
    except Exception as exc:  # noqa: BLE001
        print(f"  run_loop 抛出异常: {exc}")
        return False
    output_text = output_stream.getvalue()
    if "粘贴" not in output_text:
        print(f"  降级输出未包含粘贴指引: {output_text[:200]!r}")
        return False
    return True


def main() -> int:
    tests = [
        ("引导输出文本", run_test_guide_output),
        ("wait_for_done", run_test_wait_for_done),
        ("ask_confirm", run_test_ask_confirm),
        ("run_loop 降级", run_test_run_loop),
    ]
    results = []
    for name, fn in tests:
        try:
            passed = bool(fn())
        except Exception as exc:  # noqa: BLE001
            print(f"  {name} 抛出异常: {exc}")
            passed = False
        results.append((name, passed))
        print(f"  {name}: {'PASS' if passed else 'FAIL'}")

    ok = all(p for _, p in results)
    print()
    if ok:
        print(f"All {len(tests)} tests PASSED")
        return 0
    print(f"{sum(1 for _, p in results if not p)} tests FAILED")
    return 1


if __name__ == "__main__":
    sys.exit(main())
