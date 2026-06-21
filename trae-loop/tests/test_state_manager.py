"""测试 StateManager 的基本行为。

运行方式:
    cd /Users/michael/Developer/github/claude-code-island/trae-loop
    python3 -m tests.test_state_manager
    # 或
    python3 tests/test_state_manager.py
"""

from __future__ import annotations

import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from lib.state_manager import StateManager  # noqa: E402


def _make_tmp_manager() -> StateManager:
    """创建一个使用临时 state.json 的 StateManager, 便于隔离测试。"""
    tmp_dir = tempfile.mkdtemp(prefix="trae-loop-state-test-")
    state_file = os.path.join(tmp_dir, "state.json")
    return StateManager(state_file=state_file)


def run_test_2_1() -> bool:
    """TR-2.1: 无 state.json -> 初始化后 currentPhase=='init', status=='running'。"""
    sm = _make_tmp_manager()
    if os.path.isfile(sm.state_file):
        os.remove(sm.state_file)
    state = sm.load()
    return state["currentPhase"] == "init" and state["status"] == "running"


def run_test_2_2() -> bool:
    """TR-2.2: advance('requirements-architecture') 后 phase 切换且 history 有记录。"""
    sm = _make_tmp_manager()
    sm.load()
    sm.advance("requirements-architecture", output="some arch output")
    current_ok = sm.state["currentPhase"] == "requirements-architecture"
    history_has_phase = any(
        h.get("phase") == "requirements-architecture" for h in sm.state["history"]
    ) or any(
        h.get("phase") == "init" and h.get("status") == "completed"
        for h in sm.state["history"]
    )
    # spec: advance 记录的是「当前阶段」(init) 到 history, 切换到 requirements-architecture
    init_completed_recorded = any(
        h.get("phase") == "init" and h.get("status") == "completed"
        for h in sm.state["history"]
    )
    return current_ok and history_has_phase and init_completed_recorded


def run_test_2_3() -> bool:
    """TR-2.3: pause('missing deps') 后 status=='PAUSED', errors[-1]['msg']=='missing deps'。"""
    sm = _make_tmp_manager()
    sm.load()
    sm.pause("missing deps")
    return (
        sm.state["status"] == "PAUSED"
        and len(sm.state["errors"]) > 0
        and sm.state["errors"][-1]["msg"] == "missing deps"
    )


def run_test_2_4() -> bool:
    """TR-2.4: 初始 state validate 成功; 缺少 currentPhase 的损坏 state validate 失败。"""
    sm = _make_tmp_manager()
    sm.load()
    ok1, errs1 = sm.validate()
    if not ok1 or errs1:
        return False

    broken = dict(sm.state)
    broken.pop("currentPhase")
    ok2, errs2 = sm.validate(broken)
    return ok2 is False and len(errs2) > 0


def main() -> int:
    # 运行前先清理默认路径下残留的 state.json (若存在)
    from lib import STATE_FILE

    stale_removed = False
    if os.path.isfile(STATE_FILE):
        try:
            os.remove(STATE_FILE)
            stale_removed = True
        except OSError:
            pass

    tests = [
        ("TR-2.1", run_test_2_1),
        ("TR-2.2", run_test_2_2),
        ("TR-2.3", run_test_2_3),
        ("TR-2.4", run_test_2_4),
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
    if stale_removed:
        print(f"  (已清理默认路径残留 state.json: {STATE_FILE})")
    print()
    if ok:
        print(f"All {len(tests)} tests PASSED")
        return 0
    print(f"{sum(1 for _, p in results if not p)} tests FAILED")
    return 1


if __name__ == "__main__":
    sys.exit(main())
