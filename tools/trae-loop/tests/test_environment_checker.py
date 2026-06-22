import io
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from lib.environment_checker import EnvironmentChecker


def _capture_stdout(func):
    old_stdout = sys.stdout
    sys.stdout = buf = io.StringIO()
    try:
        result = func()
    finally:
        sys.stdout = old_stdout
    return result, buf.getvalue()


def run(name, func):
    try:
        func()
        print(f"  [PASS] {name}")
        return True
    except AssertionError as e:
        print(f"  [FAIL] {name}: {e}")
        return False


def test_tr61():
    def mock_runner(cmd):
        program = cmd[0] if isinstance(cmd, list) and len(cmd) > 0 else ""
        if program == "xcode-select":
            return (1, "", "not installed")
        return (0, "ok", "")

    with tempfile.TemporaryDirectory() as tmpdir:
        checker = EnvironmentChecker(
            project_dir=tmpdir,
            command_runner=mock_runner,
            print_errors=True,
        )
        (ok, failures), output = _capture_stdout(checker.check)
        assert ok is False, f"expected ok=False, got ok={ok}"
        assert any("xcode-select" in f for f in failures), f"failures={failures}"
        assert "Xcode Command Line Tools" in output, f"output={output}"


def test_tr62():
    def mock_runner(cmd):
        return (0, "ok", "")

    with tempfile.TemporaryDirectory() as tmpdir:
        checker = EnvironmentChecker(
            project_dir=tmpdir,
            command_runner=mock_runner,
            print_errors=True,
        )
        ok, failures = checker.check()
        assert ok is True, f"expected ok=True, got ok={ok}, failures={failures}"
        assert failures == [], f"failures={failures}"


def test_tr63():
    checker = EnvironmentChecker()
    result = checker.check()
    assert isinstance(result, tuple) and len(result) == 2
    ok, failures = result
    assert isinstance(ok, bool)
    assert isinstance(failures, list)


def main():
    tests = [
        ("TR-6.1", test_tr61),
        ("TR-6.2", test_tr62),
        ("TR-6.3", test_tr63),
    ]
    total = len(tests)
    passed = 0
    for name, func in tests:
        if run(name, func):
            passed += 1
    print(f"\nAll 3 tests PASSED" if passed == total else f"\n{passed}/{total} tests passed")
    sys.exit(0 if passed == total else 1)


if __name__ == "__main__":
    main()
