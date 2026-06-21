"""trae-loop 主流程集成测试 — 路径二（真正的 Loop）。

包含:
  - TR-loop-1: --mock 跑完整个流程, 断言 currentPhase == "done"
  - TR-loop-2: 模拟产物缺失 → bump_attempt → retry → PAUSED
  - TR-loop-3: 模拟产物缺失 → bump_attempt → retry → 成功

运行方式:
    cd /Users/michael/Developer/github/claude-code-island/trae-loop
    python3 -m tests.test_mock_loop
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

SCRIPT = os.path.join(ROOT, "trae-loop.py")

from lib import STATE_FILE, PROJECT_DIR  # noqa: E402
from lib.phase_checker import PhaseChecker  # noqa: E402


# ---------------------------------------------------------------------------
# 工具: 生成临时 runner
# ---------------------------------------------------------------------------


def _make_runner(tmp_root: str, alt_project: str, alt_state: str,
                 extra_patch: str = "", script_override: str | None = None) -> str:
    """生成 wrapper runner.py, 将 lib.PROJECT_DIR / STATE_FILE 指向临时路径。"""
    path = tempfile.mktemp(suffix="_runner.py", dir=tmp_root)
    script_to_run = script_override if script_override else SCRIPT
    with open(path, "w", encoding="utf-8") as f:
        f.write(
            "import sys, os\n"
            "sys.path.insert(0, " + repr(ROOT) + ")\n"
            "import lib\n"
            "lib.PROJECT_DIR = " + repr(alt_project) + "\n"
            "lib.STATE_FILE = " + repr(alt_state) + "\n"
            + extra_patch +
            "with open(" + repr(script_to_run) + ", 'r', encoding='utf-8') as _f:\n"
            "    _code = compile(_f.read(), " + repr(script_to_run) + ", 'exec')\n"
            "    exec(_code, {'__name__': '__main__', '__file__': " + repr(script_to_run) + "})\n"
        )
    return path


def _read_state(path: str) -> dict:
    if not os.path.isfile(path):
        return {}
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except json.JSONDecodeError:
        return {}


# ---------------------------------------------------------------------------
# TR-loop-1: 完整 mock 循环
# ---------------------------------------------------------------------------


def run_test_mock_full_loop() -> bool:
    """完整跑一次 mock 流程, 验证 currentPhase == 'done'。"""
    tmp_root = tempfile.mkdtemp(prefix="trae-loop-loop-test-1-")
    try:
        alt_project = os.path.join(tmp_root, "claude-code-island")
        alt_state = os.path.join(tmp_root, "state.json")
        os.makedirs(alt_project, exist_ok=True)

        runner = _make_runner(tmp_root, alt_project, alt_state)
        completed = subprocess.run(
            [sys.executable, runner, "--mock", "--input", "y\n"],
            cwd=tmp_root,
            capture_output=True,
            text=True,
            timeout=30,
        )
        if completed.returncode != 0:
            print("  returncode=", completed.returncode)
            print("  stdout:", completed.stdout[-500:])
            print("  stderr:", completed.stderr[-500:])
            return False

        state = _read_state(alt_state)
        if state.get("currentPhase") != "done":
            print("  state.currentPhase != 'done':", state.get("currentPhase"))
            return False

        # 产物检查: PhaseChecker.check_all() 全部通过
        checker = PhaseChecker(project_dir=alt_project)
        ok, missing, _ = checker.check_all()
        if not ok:
            print(f"  产物校验失败: {missing}")
            return False

        return True
    finally:
        shutil.rmtree(tmp_root, ignore_errors=True)


# ---------------------------------------------------------------------------
# TR-loop-2: 缺失产物 → bump_attempt → PAUSED
# ---------------------------------------------------------------------------


def run_test_mock_retry_then_pause() -> bool:
    """模拟产物缺失 2 次后进入 PAUSED。"""
    tmp_root = tempfile.mkdtemp(prefix="trae-loop-loop-test-2-")
    try:
        alt_project = os.path.join(tmp_root, "claude-code-island")
        alt_state = os.path.join(tmp_root, "state.json")
        os.makedirs(alt_project, exist_ok=True)

        # 注入补丁: 让 _mock_produce_all_artifacts 前 2 次调用什么都不做
        patched_script_path = os.path.join(tmp_root, "trae-loop-patched.py")
        with open(SCRIPT, "r", encoding="utf-8") as f:
            original_code = f.read()

        # 重命名原函数, 在 def main() 前注入 wrapper
        src = original_code.replace(
            "def _mock_produce_all_artifacts(project_dir: str) -> None:",
            "def _mock_produce_all_artifacts_real(project_dir):",
            1,
        )
        inject_code = (
            "# <injected by test: fail first 2 calls>\n"
            "_MOCK_PAUSE_COUNT = [0]\n"
            "def _mock_produce_all_artifacts(project_dir):\n"
            "    if _MOCK_PAUSE_COUNT[0] < 2:\n"
            "        _MOCK_PAUSE_COUNT[0] += 1\n"
            "        return\n"
            "    return _mock_produce_all_artifacts_real(project_dir)\n"
            "\n"
        )
        main_def = "def main(argv: list[str] | None = None) -> int:"
        assert main_def in src, "Cannot find main() in source"
        src = src.replace(main_def, inject_code + main_def, 1)
        with open(patched_script_path, "w", encoding="utf-8") as f:
            f.write(src)

        runner = _make_runner(
            tmp_root, alt_project, alt_state,
            script_override=patched_script_path,
        )
        completed = subprocess.run(
            [sys.executable, runner, "--mock", "--input", "y\n"],
            cwd=tmp_root,
            capture_output=True,
            text=True,
            timeout=30,
        )

        state = _read_state(alt_state)

        # 期望 PAUSED (returncode != 0)
        if completed.returncode == 0:
            print("  期望非零退出码 (PAUSED), 实际 returncode=0")
            print("  stdout:", completed.stdout[-400:])
            print("  stderr:", completed.stderr[-400:])
            return False

        if state.get("status") != "PAUSED":
            print("  期望 status=PAUSED, 实际", state.get("status"))
            print("  errors:", state.get("errors", []))
            return False

        if not state.get("errors"):
            print("  期望 errors 非空, 实际为空")
            return False

        return True
    finally:
        shutil.rmtree(tmp_root, ignore_errors=True)


# ---------------------------------------------------------------------------
# TR-loop-3: 缺失产物 → bump_attempt → retry 成功
# ---------------------------------------------------------------------------


def run_test_mock_retry_then_success() -> bool:
    """模拟产物缺失 1 次, 第二次成功, 验证 bump_attempt + 最终 done。"""
    tmp_root = tempfile.mkdtemp(prefix="trae-loop-loop-test-3-")
    try:
        alt_project = os.path.join(tmp_root, "claude-code-island")
        alt_state = os.path.join(tmp_root, "state.json")
        os.makedirs(alt_project, exist_ok=True)

        patched_script_path = os.path.join(tmp_root, "trae-loop-patched.py")
        with open(SCRIPT, "r", encoding="utf-8") as f:
            original_code = f.read()

        # 重命名原函数, 在 def main() 前注入只失败一次的 wrapper
        src = original_code.replace(
            "def _mock_produce_all_artifacts(project_dir: str) -> None:",
            "def _mock_produce_all_artifacts_real(project_dir):",
            1,
        )
        inject_code = (
            "# <injected by test: fail once, succeed on retry>\n"
            "_MOCK_FAIL_COUNT = [0]\n"
            "def _mock_produce_all_artifacts(project_dir):\n"
            "    if _MOCK_FAIL_COUNT[0] == 0:\n"
            "        _MOCK_FAIL_COUNT[0] += 1\n"
            "        return\n"
            "    return _mock_produce_all_artifacts_real(project_dir)\n"
            "\n"
        )
        main_def = "def main(argv: list[str] | None = None) -> int:"
        assert main_def in src, "Cannot find main() in source"
        src = src.replace(main_def, inject_code + main_def, 1)
        with open(patched_script_path, "w", encoding="utf-8") as f:
            f.write(src)

        runner = _make_runner(
            tmp_root, alt_project, alt_state,
            script_override=patched_script_path,
        )
        completed = subprocess.run(
            [sys.executable, runner, "--mock", "--input", "y\n"],
            cwd=tmp_root,
            capture_output=True,
            text=True,
            timeout=30,
        )

        state = _read_state(alt_state)

        if completed.returncode != 0:
            print("  期望 returncode=0 (成功), 实际", completed.returncode)
            print("  stdout:", completed.stdout[-400:])
            print("  stderr:", completed.stderr[-400:])
            return False

        if state.get("currentPhase") != "done":
            print("  期望 currentPhase=done, 实际", state.get("currentPhase"))
            return False

        # 验证 bump_attempt: history 中 executing 应该有 attempt≥2
        history = state.get("history", [])
        exec_entries = [h for h in history if isinstance(h, dict) and h.get("phase") == "executing"]
        attempts = [h.get("attempt", 0) for h in exec_entries]
        if not attempts or max(attempts) < 2:
            print(f"  期望 executing phase 有 attempt≥2 的记录, 实际 attempts={attempts}")
            return False

        return True
    finally:
        shutil.rmtree(tmp_root, ignore_errors=True)


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------


def main() -> int:
    tests = [
        ("TR-loop-1 (full mock loop -> done)", run_test_mock_full_loop),
        ("TR-loop-2 (missing -> retry -> PAUSED)", run_test_mock_retry_then_pause),
        ("TR-loop-3 (missing -> retry -> success)", run_test_mock_retry_then_success),
    ]
    passed = 0
    for name, fn in tests:
        print("  running", name, "...")
        try:
            ok = bool(fn())
        except Exception as exc:  # noqa: BLE001
            print("  抛出异常:", exc)
            ok = False
        print("  ", name, "->", "PASS" if ok else "FAIL")
        if ok:
            passed += 1

    print()
    if passed == len(tests):
        print("All mock-loop tests PASSED")
        return 0
    print(f"{passed}/{len(tests)} tests PASSED")
    return 1


if __name__ == "__main__":
    sys.exit(main())
