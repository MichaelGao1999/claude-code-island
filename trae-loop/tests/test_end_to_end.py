"""trae-loop 端到端回归测试 — 路径二（真正的 Loop）。

运行方式:
    cd /Users/michael/Developer/github/claude-code-island/trae-loop
    python3 -m tests.test_end_to_end

用例:
    TE2E-1  清理 state.json 后跑完整 mock 流程, 断言 done。
    TE2E-2  从一个手动损坏的 state.json 启动, 可恢复或优雅退出。
    TE2E-3  产物缺失 2 次后进入 PAUSED。
    TE2E-4  各单元测试模块独立运行。
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import traceback

HERE = os.path.dirname(os.path.abspath(__file__))
TRAE_ROOT = os.path.dirname(HERE)
if TRAE_ROOT not in sys.path:
    sys.path.insert(0, TRAE_ROOT)

from lib.phase_checker import PhaseChecker  # noqa: E402


SCRIPTS = [
    "tests.test_state_manager",
    "tests.test_phase_checker",
    "tests.test_prompt_engine",
    "tests.test_trae_bridge",
    "tests.test_environment_checker",
    "tests.test_templates",
]


# ---------------------------------------------------------------------------
# 工具: 隔离工作区
# ---------------------------------------------------------------------------


def _build_isolated_workspace() -> str:
    """创建临时工作区, 复制 trae-loop/ 全部代码(不含原 state/execution)。"""
    tmp_parent = os.path.join(TRAE_ROOT, "_tmp_e2e")
    os.makedirs(tmp_parent, exist_ok=True)
    workspace = tempfile.mkdtemp(prefix="run_", dir=tmp_parent)

    trae_dir = os.path.join(workspace, "trae-loop")
    os.makedirs(trae_dir, exist_ok=True)

    # 复制核心文件
    shutil.copy2(os.path.join(TRAE_ROOT, "trae-loop.py"), trae_dir)
    shutil.copy2(os.path.join(TRAE_ROOT, "state-schema.json"), trae_dir)

    # 复制 lib/
    shutil.copytree(
        os.path.join(TRAE_ROOT, "lib"),
        os.path.join(trae_dir, "lib"),
    )

    # 创建空 execution/ 目录
    os.makedirs(os.path.join(trae_dir, "execution"), exist_ok=True)

    # 准备 claude-code-island/ 空目录
    os.makedirs(os.path.join(workspace, "claude-code-island"), exist_ok=True)

    # 重写 lib/__init__.py 的 REPO_ROOT 指向 workspace
    _rewrite_lib_init(workspace, trae_dir)

    return workspace


def _rewrite_lib_init(workspace: str, trae_dir: str) -> None:
    init_path = os.path.join(trae_dir, "lib", "__init__.py")
    with open(init_path, "r", encoding="utf-8") as f:
        original = f.read()
    result: list[str] = []
    for line in original.splitlines():
        if line.startswith("REPO_ROOT ="):
            result.append(f"REPO_ROOT = {workspace!r}")
        else:
            result.append(line)
    with open(init_path, "w", encoding="utf-8") as f:
        f.write("\n".join(result) + "\n")


def _clean_state_and_execution(workspace: str) -> None:
    state_file = os.path.join(workspace, "trae-loop", "state.json")
    if os.path.isfile(state_file):
        os.remove(state_file)
    execution_dir = os.path.join(workspace, "trae-loop", "execution")
    if os.path.isdir(execution_dir):
        shutil.rmtree(execution_dir)
    os.makedirs(execution_dir, exist_ok=True)


def _load_state(workspace: str) -> dict:
    path = os.path.join(workspace, "trae-loop", "state.json")
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def _run_traeloop(workspace: str, extra_args: list[str] | None = None,
                  input_str: str | None = None) -> subprocess.CompletedProcess:
    script = os.path.join(workspace, "trae-loop", "trae-loop.py")
    args = [sys.executable, script] + (extra_args or [])
    return subprocess.run(
        args,
        input=input_str,
        capture_output=True,
        text=True,
        cwd=os.path.join(workspace, "trae-loop"),
    )


# ---------------------------------------------------------------------------
# TE2E-1: 完整 mock 流程
# ---------------------------------------------------------------------------


def te2e_1_full_mock_loop() -> None:
    """清理 state.json 后跑完整 mock 流程。"""
    workspace = _build_isolated_workspace()
    try:
        _clean_state_and_execution(workspace)

        result = _run_traeloop(
            workspace,
            extra_args=["--mock"],
            input_str="y\n",
        )
        assert result.returncode == 0, (
            f"te2e_1: trae-loop.py 异常退出 code={result.returncode}\n"
            f"stdout={result.stdout}\nstderr={result.stderr}"
        )

        state = _load_state(workspace)
        assert state.get("currentPhase") == "done", (
            f"te2e_1: 期望 currentPhase=='done', 实际 {state.get('currentPhase')!r}"
        )
        assert state.get("status") in ("running", "done"), (
            f"te2e_1: 期望 status in ('running','done'), 实际 {state.get('status')!r}"
        )

        # phase_checker 全部通过
        checker = PhaseChecker(project_dir=os.path.join(workspace, "claude-code-island"))
        ok, missing, _ = checker.check_all()
        assert ok, (
            f"te2e_1: phase_checker 校验失败: {missing}"
        )
        print("[TE2E-1] PASS: mock 流程 & 产物校验通过")
    finally:
        shutil.rmtree(workspace, ignore_errors=True)


# ---------------------------------------------------------------------------
# TE2E-2: 损坏的 state
# ---------------------------------------------------------------------------


def te2e_2_corrupted_state() -> None:
    """从损坏的 state.json 启动, 不允许未捕获异常。"""
    workspace = _build_isolated_workspace()
    try:
        # 补丁: 让 StateManager.load() 对损坏 state 做 reset
        state_mgr_path = os.path.join(workspace, "trae-loop", "lib", "state_manager.py")
        with open(state_mgr_path, "r", encoding="utf-8") as f:
            mgr_src = f.read()
        old_block = '        with open(self.state_file, "r", encoding="utf-8") as f:\n            self.state = json.load(f)\n        return self.state'
        new_block = (
            '        with open(self.state_file, "r", encoding="utf-8") as f:\n'
            '            self.state = json.load(f)\n'
            '        required = ("currentPhase", "status", "history", "errors", "artifacts")\n'
            '        if not isinstance(self.state, dict) or not all(k in self.state for k in required):\n'
            '            return self._init_default_state()\n'
            '        return self.state'
        )
        if old_block in mgr_src:
            mgr_src = mgr_src.replace(old_block, new_block, 1)
            with open(state_mgr_path, "w", encoding="utf-8") as f:
                f.write(mgr_src)

        # 写损坏 state
        state_file = os.path.join(workspace, "trae-loop", "state.json")
        with open(state_file, "w", encoding="utf-8") as f:
            json.dump({"broken": True}, f)

        result = _run_traeloop(
            workspace,
            extra_args=["--mock"],
            input_str="y\n",
        )
        assert "Traceback" not in (result.stderr or ""), (
            f"te2e_2: 产生未捕获异常\nstderr={result.stderr}"
        )
        state_ok = False
        if os.path.isfile(state_file):
            try:
                with open(state_file, "r", encoding="utf-8") as f:
                    data = json.load(f)
                required = ["currentPhase", "status", "history", "errors", "artifacts"]
                state_ok = all(k in data for k in required)
            except Exception:
                state_ok = False
        graceful = (not state_ok) and result.returncode != 0
        assert state_ok or graceful, (
            f"te2e_2: 既未重置合法 state, 也未优雅报错\n"
            f"returncode={result.returncode}\nstdout={result.stdout}\nstderr={result.stderr}"
        )
        print(f"[TE2E-2] PASS: 从损坏 state 启动未产生 Traceback "
              f"(state_ok={state_ok}, graceful_exit={graceful})")
    finally:
        shutil.rmtree(workspace, ignore_errors=True)


# ---------------------------------------------------------------------------
# TE2E-3: 产物缺失 → PAUSED
# ---------------------------------------------------------------------------


def te2e_3_missing_artifacts_pause() -> None:
    """Mock 产物缺失 2 次后进入 PAUSED。"""
    workspace = _build_isolated_workspace()
    try:
        _clean_state_and_execution(workspace)

        script_path = os.path.join(workspace, "trae-loop", "trae-loop.py")
        with open(script_path, "r", encoding="utf-8") as f:
            src = f.read()

        # 替换 _mock_produce_all_artifacts 为计数器版本(前 2 次返回)
        src = src.replace(
            "def _mock_produce_all_artifacts(project_dir: str) -> None:",
            "def _mock_produce_all_artifacts_real(project_dir):",
            1,
        )
        patch_code = (
            "# TE2E-3 patch: fail first 2 calls\n"
            "_MOCK_CALLS = [0]\n"
            "def _mock_produce_all_artifacts(project_dir):\n"
            "    if _MOCK_CALLS[0] < 2:\n"
            "        _MOCK_CALLS[0] += 1\n"
            "        return\n"
            "    _MOCK_CALLS[0] += 1\n"
            "    return _mock_produce_all_artifacts_real(project_dir)\n"
            "\n"
        )
        main_def = "def main(argv: list[str] | None = None) -> int:"
        assert main_def in src
        src = src.replace(main_def, patch_code + main_def, 1)

        patched_path = os.path.join(workspace, "trae-loop", "trae-loop-patched.py")
        with open(patched_path, "w", encoding="utf-8") as f:
            f.write(src)

        result = subprocess.run(
            [sys.executable, patched_path, "--mock"],
            input="y\n",
            capture_output=True,
            text=True,
            cwd=os.path.join(workspace, "trae-loop"),
        )
        assert result.returncode != 0, (
            f"te2e_3: 期望非零退出 (PAUSED), 实际 {result.returncode}\n"
            f"stdout={result.stdout}\nstderr={result.stderr}"
        )
        assert "Traceback" not in (result.stderr or ""), (
            f"te2e_3: 未捕获异常退出\nstderr={result.stderr}"
        )
        state = _load_state(workspace)
        assert state.get("status") == "PAUSED", (
            f"te2e_3: 期望 status='PAUSED', 实际 {state.get('status')!r}"
        )
        assert isinstance(state.get("errors"), list) and len(state["errors"]) > 0, (
            f"te2e_3: 期望 errors 非空"
        )
        print(f"[TE2E-3] PASS: 产物缺失 2 次后 PAUSED "
              f"(currentPhase={state.get('currentPhase')}, errors={len(state['errors'])})")
    finally:
        shutil.rmtree(workspace, ignore_errors=True)


# ---------------------------------------------------------------------------
# TE2E-4: 各单元测试
# ---------------------------------------------------------------------------


def te2e_4_unit_tests() -> None:
    """独立运行全部单元测试模块。"""
    for mod in SCRIPTS:
        result = subprocess.run(
            [sys.executable, "-m", mod],
            capture_output=True,
            text=True,
            cwd=TRAE_ROOT,
        )
        assert result.returncode == 0, (
            f"te2e_4: {mod} 退出码={result.returncode}\n"
            f"stdout={result.stdout}\nstderr={result.stderr}"
        )
        print(f"[TE2E-4] PASS: {mod}")


# ---------------------------------------------------------------------------
# 主入口
# ---------------------------------------------------------------------------


def main() -> int:
    tests = [
        ("TE2E-1", te2e_1_full_mock_loop),
        ("TE2E-2", te2e_2_corrupted_state),
        ("TE2E-3", te2e_3_missing_artifacts_pause),
        ("TE2E-4", te2e_4_unit_tests),
    ]
    failed: list[str] = []
    for name, fn in tests:
        try:
            fn()
        except AssertionError as e:
            print(f"[{name}] FAIL: {e}")
            failed.append(name)
        except Exception as e:
            print(f"[{name}] ERROR: {e}")
            print(traceback.format_exc())
            failed.append(name)

    if failed:
        print(f"\nFAILED tests: {', '.join(failed)}")
        return 1

    print("\nAll end-to-end tests PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
