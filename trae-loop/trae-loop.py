#!/usr/bin/env python3
"""trae-loop — 路径二：真正的 Agent Loop 编排器。

流程:
    Phase 0 (环境检测)    → 检测 Xcode / Swift / 项目目录
    第零步 (AI 辅助定界)  → 引导用户用 Claude 生成 prompt-scope.md
    执行循环              → 引导用户将 scope 粘贴到 Trae IDE
    验证 + 确认           → PhaseChecker + TraceAnalyzer → y/n/redo → done

支持命令行参数:
    --mock              mock 模式, 自动伪造全部产物 (跳过真实 Trae 执行)
    --input "..."       通过字面字符串作为交互式输入 (换行用 \\n), 用于管道测试
    -h / --help         标准帮助
"""

from __future__ import annotations

import argparse
import io
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from lib import (  # noqa: E402
    STATE_FILE,
    STATE_SCHEMA_FILE,
    PROJECT_DIR,
    PHASES,
    MAX_ATTEMPTS,
    EVENT_TYPES,
    ARTIFACT_DOCS,
    ARTIFACT_MACOS,
    ARTIFACT_IOS,
    MACOS_DIR,
    IOS_DIR,
    VERIFICATION_FILE,
    EXECUTION_DIR,
)
from lib.state_manager import StateManager  # noqa: E402
from lib.phase_checker import PhaseChecker  # noqa: E402
from lib.trae_bridge import TraeBridge  # noqa: E402
from lib.environment_checker import EnvironmentChecker  # noqa: E402
from lib.trace_analyzer import TraceAnalyzer  # noqa: E402


# ---------------------------------------------------------------------------
# 工具
# ---------------------------------------------------------------------------


def build_input_stream(input_str: str | None):
    """把 --input 的字面字符串转为输入流; 未提供时使用 sys.stdin。"""
    if input_str:
        normalized = input_str.replace("\\n", "\n")
        return io.StringIO(normalized)
    return sys.stdin


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="trae-loop: Agent Loop 编排器 —— 驱动 Claude Code Island 开发",
    )
    parser.add_argument(
        "--mock",
        action="store_true",
        help="mock 模式: 自动伪造全部产物, 跳过真实 Trae 执行",
    )
    parser.add_argument(
        "--input",
        default=None,
        help="交互式输入字面字符串, 用 \\n 分割各行",
    )
    return parser.parse_args(argv)


# ---------------------------------------------------------------------------
# Mock 产物生成
# ---------------------------------------------------------------------------


def _write_text(path: str, content: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)


def _mock_produce_all_artifacts(project_dir: str) -> None:
    """为 mock 模式快速构造全部交付物文件。"""
    # 1) docs/
    docs_dir = os.path.join(project_dir, "docs")
    os.makedirs(docs_dir, exist_ok=True)
    for doc in ["requirements.md", "architecture.md", "communication-protocol.md"]:
        _write_text(
            os.path.join(docs_dir, doc),
            f"# {doc.replace('.md', '')}\n\nplaceholder content\n",
        )
    _write_text(
        os.path.join(docs_dir, "event-schema.md"),
        "# Event Schema\n\n" + "\n".join(f"- {et}" for et in EVENT_TYPES) + "\n",
    )

    # 2) macos-island/
    macos_dir = os.path.join(project_dir, MACOS_DIR)
    os.makedirs(macos_dir, exist_ok=True)
    for sf in ARTIFACT_MACOS:
        _write_text(os.path.join(macos_dir, sf), f"// {sf}\nclass {sf.replace('.swift','')} {{}}\n")
    xcodeproj_dir = os.path.join(macos_dir, "Island.xcodeproj")
    os.makedirs(xcodeproj_dir, exist_ok=True)
    _write_text(os.path.join(xcodeproj_dir, "project.pbxproj"), "// proj\n")

    # 3) ios-island/
    ios_dir = os.path.join(project_dir, IOS_DIR)
    os.makedirs(ios_dir, exist_ok=True)
    for sf in ARTIFACT_IOS:
        _write_text(os.path.join(ios_dir, sf), f"// {sf}\nclass {sf.replace('.swift','')} {{}}\n")
    xcodeproj_dir = os.path.join(ios_dir, "iOS.xcodeproj")
    os.makedirs(xcodeproj_dir, exist_ok=True)
    _write_text(os.path.join(xcodeproj_dir, "project.pbxproj"), "// proj\n")

    # 4) verification-report.md
    _write_text(
        os.path.join(project_dir, VERIFICATION_FILE),
        "# Verification Report\n\n## Overview\n\nMock report.\n\n## Test Coverage\n\nMock coverage.\n\n## Results\n\nMock results.\n",
    )

    # 5) mock trace.json
    trace_path = os.path.join(EXECUTION_DIR, "trace.json")
    os.makedirs(EXECUTION_DIR, exist_ok=True)
    import json
    mock_trace = {
        "scope": "Claude Code Island loop scope",
        "prompt": "Build Claude Code Island",
        "execution": [
            {"step": 1, "action": "create", "file": "docs/requirements.md"},
            {"step": 2, "action": "create", "file": "macos-island/ClaudeEvent.swift"},
        ],
        "duration": 120.5,
        "errors": [],
    }
    with open(trace_path, "w", encoding="utf-8") as f:
        json.dump(mock_trace, f, ensure_ascii=False, indent=2)


# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------


def _mock_produce_scope(execution_dir: str) -> None:
    """mock 模式下写一份最小 prompt-scope.md（不依赖模板文件）。"""
    os.makedirs(execution_dir, exist_ok=True)
    _write_text(
        os.path.join(execution_dir, "prompt-scope.md"),
        "# Mock Prompt Scope\n\n## 交付清单\n- ALL artifacts (mock generated)\n",
    )


def main(argv: list[str] | None = None) -> int:
    opts = parse_args(argv)

    state_mgr = StateManager(STATE_FILE, STATE_SCHEMA_FILE)
    state = state_mgr.load()
    current_phase = state["currentPhase"]

    bridge = TraeBridge(
        input_stream=build_input_stream(opts.input),
    )
    checker = PhaseChecker(PROJECT_DIR)
    trace_analyzer = TraceAnalyzer()

    # ------------------------------------------------------------------
    # Phase 0: 环境检测 (非 mock 模式)
    # ------------------------------------------------------------------
    if not opts.mock:
        if current_phase == "init" or state.get("__env_checked") is not True:
            print("[trae-loop] Phase 0: 环境检测 ...")
            env = EnvironmentChecker()
            ok, failures = env.check()
            if not ok:
                state_mgr.pause("environment check failed: " + "; ".join(failures))
                print("[trae-loop] 环境检测失败, 状态 PAUSED。请修复后再运行。")
                return 1
            state_mgr.state["__env_checked"] = True
            if current_phase == "init":
                state_mgr.advance("scoping", output="environment check passed")
                current_phase = state_mgr.state["currentPhase"]
    else:
        # mock: 跳过环境检测
        if current_phase == "init":
            state_mgr.advance("scoping", output="mock: skip env check")
            current_phase = state_mgr.state["currentPhase"]

    # ------------------------------------------------------------------
    # 主循环
    # ------------------------------------------------------------------
    try:
        while current_phase not in ("done",):
            if current_phase == "PAUSED":
                print("[trae-loop] state=PAUSED, 退出。")
                return 1

            # ---- 第零步: AI 辅助定界 ----
            if current_phase == "scoping":
                print()
                print("=" * 60)
                print("  Phase: 第零步 — AI 辅助定界")
                print("=" * 60)

                if opts.mock:
                    _mock_produce_scope(EXECUTION_DIR)
                else:
                    scope_path = os.path.join(EXECUTION_DIR, "prompt-scope.md")
                    if not os.path.isfile(scope_path) or os.path.getsize(scope_path) < 200:
                        try:
                            from lib.prompt_engine import PromptEngine
                            PromptEngine().render_to_file(
                                "scope-template.md", "prompt-scope.md", context={}
                            )
                            size = os.path.getsize(scope_path)
                            print(f"  [第零步] ✅ 已自动生成 prompt-scope.md ({size} 字节)")
                        except Exception as e:
                            print(f"  [第零步] ❌ 自动渲染失败: {e}")
                            bridge.scope_guide()
                            bridge.wait_for_done(prompt="手动生成后输入 done > ")
                    else:
                        size = os.path.getsize(scope_path)
                        print(f"  [第零步] ✅ prompt-scope.md 已存在 ({size} 字节)")

                    print()
                    print(f"  [第零步] scope 文件: {scope_path}")
                    print("  [第零步] 完成 — 进入执行循环")

                state_mgr.advance("executing", output="scoping complete")
                current_phase = state_mgr.state["currentPhase"]
                continue

            # ---- 执行循环 ----
            if current_phase == "executing":
                print()
                print("=" * 60)
                print("  Phase: 执行循环 — 一次给足, Agent 自主执行")
                print("=" * 60)

                if opts.mock:
                    _mock_produce_all_artifacts(PROJECT_DIR)
                else:
                    scope_path = os.path.join(EXECUTION_DIR, "prompt-scope.md")
                    trace_path = os.path.join(EXECUTION_DIR, "trace.json")
                    bridge.run_loop(
                        scope_file=scope_path,
                        trace_file=trace_path,
                        wait_for_done=True,
                    )

                # 产物完整性检查 (PhaseChecker)
                print()
                print("[trae-loop] 正在检查产物完整性 ...")
                ok, missing, details = checker.check_all()

                if not ok:
                    state_mgr.append_error(
                        "Artifact check failed: " + "; ".join(missing)
                    )
                    if state_mgr.state["currentAttempt"] >= MAX_ATTEMPTS:
                        state_mgr.pause("max attempts reached")
                        print(
                            "[trae-loop] 达到最大重试次数, 状态 PAUSED。"
                            "请手动检查后再运行。"
                        )
                        return 1
                    state_mgr.bump_attempt()
                    print(
                        f"[trae-loop] 产物检查失败: {details}"
                        " 将在下一轮重试。"
                    )
                    continue

                # Trace 分析 (可选, 不阻塞完成)
                trace_path = os.path.join(EXECUTION_DIR, "trace.json")
                trace = trace_analyzer.load_trace(trace_path)
                if trace:
                    trace_ok, trace_issues = trace_analyzer.validate_trace(trace)
                    summary = trace_analyzer.summarize(trace)
                    print()
                    print(summary)
                    if not trace_ok:
                        print(f"[trae-loop] Trace 质量告警: {'; '.join(trace_issues)}")
                else:
                    print("[trae-loop] 未找到 trace.json (IDE 粘贴模式, 无 trace 属正常)")

                # 内容质量检查
                print()
                print("[trae-loop] 检查产物文件内容质量 ...")
                all_paths = (
                    ARTIFACT_DOCS
                    + [os.path.join(MACOS_DIR, f) for f in ARTIFACT_MACOS]
                    + [os.path.join(IOS_DIR, f) for f in ARTIFACT_IOS]
                    + [VERIFICATION_FILE]
                )
                content_results = trace_analyzer.check_all_artifact_content(
                    PROJECT_DIR, all_paths, min_size=20
                )
                content_failures = [
                    r for r in content_results if not r[1]
                ]
                for _path, _ok, _msg in content_results:
                    status = "✓" if _ok else "✗"
                    print(f"  [{status}] {_msg}")

                if content_failures:
                    print(
                        f"  内容质量: {len(content_failures)}/{len(content_results)} 文件异常"
                    )
                else:
                    print("  内容质量: 全部正常")

                # y/n/redo 确认
                confirm = bridge.ask_confirm("全部交付物")
                if confirm == "n":
                    print("[trae-loop] 用户拒绝, 保留当前阶段退出。")
                    return 0
                if confirm == "redo":
                    state_mgr.bump_attempt()
                    print("[trae-loop] 用户 redo, 重新执行。")
                    continue

                # 全部完成!
                state_mgr.advance("done", output="all artifacts complete")
                current_phase = "done"
                print()
                print("=" * 60)
                print("  ✅ 全部阶段完成!")
                print("=" * 60)
                print()
                print(f"  产物目录: {PROJECT_DIR}")
                print(f"  docs/      — 需求与架构文档")
                print(f"  macos-island/ — macOS SwiftUI 项目")
                print(f"  ios-island/   — iOS SwiftUI 项目")
                print(f"  verification-report.md — 集成验证报告")
                print()
                break

            # ---- 未知阶段保护 ----
            if current_phase not in PHASES:
                print(f"[trae-loop] 未知阶段: {current_phase}, 重置到 scoping")
                state_mgr.advance("scoping")
                current_phase = state_mgr.state["currentPhase"]
                continue

            # 不应到达这里, 安全兜底
            break

    except KeyboardInterrupt:
        state_mgr.append_error("interrupted")
        print("\n[trae-loop] 已保存, 下次从断点继续。")
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
