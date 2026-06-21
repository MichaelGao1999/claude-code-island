"""测试 PhaseChecker.check_all() 的统一产物检查逻辑。

运行方式:
    cd /Users/michael/Developer/github/claude-code-island/trae-loop
    python3 -m tests.test_phase_checker
"""

from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from lib.phase_checker import PhaseChecker
from lib import (
    EVENT_TYPES,
    ARTIFACT_DOCS,
    ARTIFACT_MACOS,
    ARTIFACT_IOS,
    MACOS_DIR,
    IOS_DIR,
    VERIFICATION_FILE,
)


def _write_file(path: str, content: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)


def _setup_all(tmpdir: str, complete: bool = True) -> None:
    """构建完整的 mock 产物目录结构。"""
    # docs/
    for doc in ARTIFACT_DOCS:
        if doc == "docs/event-schema.md":
            content = "\n".join(EVENT_TYPES[:9]) + "\n"
        else:
            content = f"# {doc}\nplaceholder\n"
        _write_file(os.path.join(tmpdir, doc), content)

    # macos-island/
    for sf in ARTIFACT_MACOS:
        if sf == "EventStreamManager.swift":
            content = "class EventStreamManager {\n}\n"
        elif sf == "IslandView.swift":
            content = "struct IslandView: View {\n}\n"
        elif sf == "ApprovalView.swift":
            content = "class ApprovalView {\n}\n"
        elif sf == "ClaudeEvent.swift":
            content = "struct ClaudeEvent {\n}\n"
        else:
            content = "// main\n"
        _write_file(os.path.join(tmpdir, MACOS_DIR, sf), content)
    os.makedirs(os.path.join(tmpdir, MACOS_DIR, "Island.xcodeproj"), exist_ok=True)
    _write_file(os.path.join(tmpdir, MACOS_DIR, "Island.xcodeproj", "project.pbxproj"), "// proj\n")

    # ios-island/
    for sf in ARTIFACT_IOS:
        if sf == "WebSocketBridge.swift":
            content = "class WebSocketBridge {\n}\n"
        elif sf == "LiveActivityManager.swift":
            content = "class LiveActivityManager {\n}\n"
        elif sf == "RemoteApprovalView.swift":
            content = "struct RemoteApprovalView: View {\n}\n"
        else:
            content = "// main\n"
        _write_file(os.path.join(tmpdir, IOS_DIR, sf), content)
    os.makedirs(os.path.join(tmpdir, IOS_DIR, "iOS.xcodeproj"), exist_ok=True)
    _write_file(os.path.join(tmpdir, IOS_DIR, "iOS.xcodeproj", "project.pbxproj"), "// proj\n")

    # verification-report.md
    _write_file(os.path.join(tmpdir, VERIFICATION_FILE),
                "# Report\n\nbody\n\n## Coverage\n\nbody\n\n## Results\n\nbody\n")


def run_test_all_complete() -> bool:
    """完整产物: check_all() 返回 ok=True。"""
    import tempfile
    with tempfile.TemporaryDirectory() as tmpdir:
        _setup_all(tmpdir, complete=True)
        checker = PhaseChecker(project_dir=tmpdir)
        ok, missing, details = checker.check_all()
        if not ok:
            print(f"  期望 ok=True, 实际 ok={ok}, missing={missing}")
            return False
        if missing:
            print(f"  期望 missing=[], 实际 {missing}")
            return False
        return True


def run_test_all_missing_one_doc() -> bool:
    """缺失 1 个 docs 文件: check_all() 返回 ok=False。"""
    import tempfile
    with tempfile.TemporaryDirectory() as tmpdir:
        _setup_all(tmpdir, complete=True)
        # 删除一个文件
        os.remove(os.path.join(tmpdir, ARTIFACT_DOCS[1]))
        checker = PhaseChecker(project_dir=tmpdir)
        ok, missing, details = checker.check_all()
        if ok:
            print("  期望 ok=False (缺失文件), 实际 ok=True")
            return False
        if not any(ARTIFACT_DOCS[1] in m for m in missing):
            print(f"  期望 missing 包含 {ARTIFACT_DOCS[1]}, 实际 {missing}")
            return False
        return True


def run_test_all_insufficient_events() -> bool:
    """事件类型不足: check_all() 返回 ok=False。"""
    import tempfile
    with tempfile.TemporaryDirectory() as tmpdir:
        _setup_all(tmpdir, complete=True)
        # 用不足 7 种事件类型的文件覆盖 event-schema.md
        _write_file(os.path.join(tmpdir, "docs", "event-schema.md"),
                    "Only TASK_STARTED mentioned here.\n")
        checker = PhaseChecker(project_dir=tmpdir)
        ok, missing, details = checker.check_all()
        if ok:
            print("  期望 ok=False (事件类型不足), 实际 ok=True")
            return False
        if not any("事件类型" in m for m in missing):
            print(f"  期望 missing 包含事件类型不足提示, 实际 {missing}")
            return False
        return True


def run_test_all_missing_xcodeproj() -> bool:
    """缺少 .xcodeproj: check_all() 返回 ok=False。"""
    import tempfile
    import shutil
    with tempfile.TemporaryDirectory() as tmpdir:
        _setup_all(tmpdir, complete=True)
        shutil.rmtree(os.path.join(tmpdir, MACOS_DIR, "Island.xcodeproj"), ignore_errors=True)
        checker = PhaseChecker(project_dir=tmpdir)
        ok, missing, details = checker.check_all()
        if ok:
            print("  期望 ok=False (缺少 .xcodeproj), 实际 ok=True")
            return False
        return True


def run_test_all_empty_project() -> bool:
    """空项目目录: check_all() 返回 ok=False。"""
    import tempfile
    with tempfile.TemporaryDirectory() as tmpdir:
        checker = PhaseChecker(project_dir=tmpdir)
        ok, missing, details = checker.check_all()
        if ok:
            print("  期望 ok=False (空目录), 实际 ok=True")
            return False
        return True


def main() -> int:
    tests = [
        ("check_all (完整产物)", run_test_all_complete),
        ("check_all (缺失 1 个文件)", run_test_all_missing_one_doc),
        ("check_all (事件类型不足)", run_test_all_insufficient_events),
        ("check_all (缺少 .xcodeproj)", run_test_all_missing_xcodeproj),
        ("check_all (空目录)", run_test_all_empty_project),
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
        print("All phase_checker tests PASSED")
        return 0
    print(f"{passed}/{len(tests)} tests PASSED")
    return 1


if __name__ == "__main__":
    sys.exit(main())
