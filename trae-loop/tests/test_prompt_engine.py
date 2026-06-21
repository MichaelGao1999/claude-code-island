"""测试 PromptEngine 的基本行为。

运行方式:
    cd /Users/michael/Developer/github/claude-code-island/trae-loop
    python3 -m tests.test_prompt_engine
"""

from __future__ import annotations

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from lib import (  # noqa: E402
    EXECUTION_DIR,
    PROJECT_DIR,
    PROJECT_NAME,
    TEMPLATES_DIR,
)
from lib.prompt_engine import PromptEngine  # noqa: E402


def _ensure_template(name: str, content: str) -> str:
    """确保模板目录存在, 并写入指定内容的模板文件。返回模板文件绝对路径。"""
    os.makedirs(TEMPLATES_DIR, exist_ok=True)
    path = os.path.join(TEMPLATES_DIR, name)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    return path


def _remove_template(name: str) -> None:
    path = os.path.join(TEMPLATES_DIR, name)
    if os.path.isfile(path):
        try:
            os.remove(path)
        except OSError:
            pass


def run_test_3_1() -> bool:
    """TR-3.1: 最小模板渲染; 未提供占位符保留原样不抛异常。"""
    template_name = "_test_minimal.md"
    content = "Hello ${project_name}, attempt=${attempt}, dir=${project_dir}. Undefined=${undefined_key}."
    _ensure_template(template_name, content)
    try:
        engine = PromptEngine()

        rendered_default = engine.render(template_name)
        if PROJECT_NAME not in rendered_default:
            return False
        if PROJECT_DIR not in rendered_default:
            return False
        if "attempt=1" not in rendered_default:
            return False
        if "${undefined_key}" not in rendered_default:
            return False

        rendered_custom = engine.render(template_name, {"attempt": 3})
        if "attempt=3" not in rendered_custom:
            return False
        return True
    finally:
        _remove_template(template_name)


def run_test_3_2() -> bool:
    """TR-3.2: 失败上下文注入 — last_error + list 形式的 missing_files。"""
    template_name = "_test_err.md"
    content = "Last error: ${last_error}. Missing: ${missing_files}."
    _ensure_template(template_name, content)
    try:
        engine = PromptEngine()
        rendered = engine.render(
            template_name,
            {
                "last_error": "missing file",
                "missing_files": ["x.swift", "y.swift"],
            },
        )
        if "missing file" not in rendered:
            return False
        if "x.swift" not in rendered or "y.swift" not in rendered:
            return False
        return True
    finally:
        _remove_template(template_name)


def run_test_3_3() -> bool:
    """TR-3.3: render_to_file 输出文件存在且非空。"""
    template_name = "_test_render_to_file.md"
    content = "project=${project_name}"
    output_filename = "_test_output.md"
    _ensure_template(template_name, content)
    try:
        engine = PromptEngine()
        output_path = engine.render_to_file(template_name, output_filename)
        expected = os.path.join(EXECUTION_DIR, output_filename)
        if output_path != expected:
            return False
        if not os.path.isfile(output_path):
            return False
        with open(output_path, "r", encoding="utf-8") as f:
            body = f.read()
        if not body:
            return False
        if PROJECT_NAME not in body:
            return False
        return True
    finally:
        _remove_template(template_name)
        # 清理测试输出文件, 但保留可能存在的 EXECUTION_DIR 目录
        output_path = os.path.join(EXECUTION_DIR, output_filename)
        if os.path.isfile(output_path):
            try:
                os.remove(output_path)
            except OSError:
                pass


def main() -> int:
    tests = [
        ("TR-3.1", run_test_3_1),
        ("TR-3.2", run_test_3_2),
        ("TR-3.3", run_test_3_3),
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
