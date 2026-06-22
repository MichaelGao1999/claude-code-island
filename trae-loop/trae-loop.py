#!/usr/bin/env python3
"""trae-loop — 路径三：模式 C 真正的 Agent Loop 编排器。

模式 C (自动): 编排器驱动外部 Agent CLI 自动创建交付物, 零人工介入。
模式 B (手动): 引导用户将 scope 粘贴到 Trae IDE, 等待 done 后检查。

CLI:
    --mock              Mock 模式, 自动伪造全部产物
    --env-check         仅执行环境检测 (Phase 0)
    --scoping           自动生成 prompt-scope.md
    --run               全流程 (Phase 0 → scoping → 执行 → 验证)
    --verify            仅执行产物检查 (Patch 入口)
    --patch             自动修补缺失项 (AgentLoop.patch_mode)
    --agent /path/to/cli  指定外部 Agent CLI
    --max-iter N        自定义最大迭代次数 (默认 20)
    --input "..."       交互式输入字面字符串 (用于管道测试)
    -h / --help         标准帮助
"""

from __future__ import annotations

import argparse
import io
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from lib import (  # noqa: E402
    STATE_FILE,
    PROJECT_DIR,
    EXECUTION_DIR,
    PHASES,
    MAX_ITER,
    PATCH_MAX_ITER,
    COMMAND_TIMEOUT,
    AGENT_TIMEOUT,
    AGENT_MAX_RETRIES,
)
from lib.state_manager import StateManager  # noqa: E402
from lib.phase_checker import PhaseChecker  # noqa: E402
from lib.trae_bridge import TraeBridge  # noqa: E402
from lib.environment_checker import EnvironmentChecker  # noqa: E402
from lib.trace_analyzer import TraceAnalyzer  # noqa: E402
from lib.tool_executor import ToolExecutor  # noqa: E402


# ---------------------------------------------------------------------------
# 工具
# ---------------------------------------------------------------------------


def build_input_stream(input_str: str | None):
    if input_str:
        normalized = input_str.replace("\\n", "\n")
        return io.StringIO(normalized)
    return sys.stdin


def _write_text(path: str, content: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)


# ---------------------------------------------------------------------------
# Mock 产物生成
# ---------------------------------------------------------------------------


def _mock_produce_scope(execution_dir: str) -> None:
    """mock 模式下写一份最小 prompt-scope.md。"""
    from lib import EVENT_TYPES

    os.makedirs(execution_dir, exist_ok=True)
    _write_text(
        os.path.join(execution_dir, "prompt-scope.md"),
        f"# Mock Prompt Scope\n\n## 交付清单\n- ALL artifacts (mock generated)\n"
        f"\n## 事件类型\n" + "\n".join(f"- {et}" for et in EVENT_TYPES) + "\n",
    )


def _mock_produce_all_artifacts(project_dir: str) -> None:
    """为 mock 模式快速构造全部交付物文件。"""
    from lib import (
        EVENT_TYPES, ARTIFACT_DOCS, ARTIFACT_MACOS, ARTIFACT_IOS,
        MACOS_DIR, IOS_DIR, VERIFICATION_FILE,
    )

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
        _write_text(
            os.path.join(macos_dir, sf),
            f"// {sf}\nclass {sf.replace('.swift', '')} {{}}\n",
        )
    xcodeproj_dir = os.path.join(macos_dir, "Island.xcodeproj")
    os.makedirs(xcodeproj_dir, exist_ok=True)
    _write_text(os.path.join(xcodeproj_dir, "project.pbxproj"), "// proj\n")

    # 3) ios-island/
    ios_dir = os.path.join(project_dir, IOS_DIR)
    os.makedirs(ios_dir, exist_ok=True)
    for sf in ARTIFACT_IOS:
        _write_text(
            os.path.join(ios_dir, sf),
            f"// {sf}\nclass {sf.replace('.swift', '')} {{}}\n",
        )
    xcodeproj_dir = os.path.join(ios_dir, "iOS.xcodeproj")
    os.makedirs(xcodeproj_dir, exist_ok=True)
    _write_text(os.path.join(xcodeproj_dir, "project.pbxproj"), "// proj\n")

    # 4) verification-report.md
    _write_text(
        os.path.join(project_dir, VERIFICATION_FILE),
        "# Verification Report\n\n## Overview\n\nMock report.\n\n"
        "## Test Coverage\n\nMock coverage.\n\n## Results\n\nMock results.\n",
    )

    # 5) mock trace.json
    import json
    trace_path = os.path.join(EXECUTION_DIR, "trace.json")
    os.makedirs(EXECUTION_DIR, exist_ok=True)
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
# 自动检测 Agent CLI
# ---------------------------------------------------------------------------


def detect_agent_cli() -> list[str] | None:
    """检测可用的外部 Agent CLI。

    优先级: trae → claude (--tmux? 或 pipe) → 其他。
    """
    trae = shutil.which("trae")
    if trae:
        return [trae, "run", "-"]

    # Claude Code 可通过 stdin/stdout pipe 使用
    claude = shutil.which("claude")
    if claude:
        return [claude, "--stdin"]  # 假设 claude 有 stdin 模式

    return None


# ---------------------------------------------------------------------------
# Trap (来自 StdioDriver 的模块级函数/异常, 避免循环导入)
# ---------------------------------------------------------------------------


def _try_read_scope() -> str | None:
    """读取 prompt-scope.md, 返回内容或 None。"""
    scope_path = os.path.join(EXECUTION_DIR, "prompt-scope.md")
    if not os.path.isfile(scope_path):
        return None
    try:
        with open(scope_path, "r", encoding="utf-8") as f:
            return f.read()
    except OSError:
        return None


# ---------------------------------------------------------------------------
# 解析器
# ---------------------------------------------------------------------------


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="trae-loop: Agent Loop 编排器 —— 模式 C / 模式 B 双模式执行",
    )
    # 原有参数
    parser.add_argument(
        "--mock", action="store_true",
        help="mock 模式: 自动伪造全部产物, 跳过真实执行",
    )
    parser.add_argument(
        "--input", default=None,
        help="交互式输入字面字符串, 用 \\n 分割各行",
    )

    # 新参数 (模式 C)
    parser.add_argument(
        "--env-check", action="store_true",
        help="仅执行环境检测 (Phase 0)",
    )
    parser.add_argument(
        "--scoping", action="store_true",
        help="自动生成 prompt-scope.md (无需外部 Agent)",
    )
    parser.add_argument(
        "--run", action="store_true",
        help="全流程: Phase 0 → scoping → 执行 → 验证",
    )
    parser.add_argument(
        "--verify", action="store_true",
        help="仅执行产物检查 (PhaseChecker.check_all)",
    )
    parser.add_argument(
        "--patch", action="store_true",
        help="Patch 模式: 检查产物, 自动修补缺失项",
    )
    parser.add_argument(
        "--agent", default=None,
        help="指定外部 Agent CLI 路径 (默认自动检测)",
    )
    parser.add_argument(
        "--max-iter", type=int, default=None,
        help="最大迭代次数 (默认: 主循环 20, Patch 循环 10)",
    )

    return parser.parse_args(argv)


# ---------------------------------------------------------------------------
# 子命令执行
# ---------------------------------------------------------------------------


def cmd_env_check(state_mgr: StateManager) -> int:
    """--env-check: 仅执行 Phase 0。"""
    print("[trae-loop] Phase 0: 环境检测 ...")
    env = EnvironmentChecker()
    ok, failures = env.check()
    if not ok:
        state_mgr.pause("environment check failed: " + "; ".join(failures))
        print("[trae-loop] 环境检测失败, 状态 PAUSED。请修复后再运行。")
        print("  失败项:")
        for f in failures:
            print(f"    - {f}")
        return 1
    state_mgr.state["__env_checked"] = True
    state_mgr.advance("scoping", output="environment check passed")
    print("[trae-loop] ✅ 环境检测通过")
    return 0


def cmd_scoping(state_mgr: StateManager) -> int:
    """--scoping: 自动生成 prompt-scope.md。"""
    scope_path = os.path.join(EXECUTION_DIR, "prompt-scope.md")
    state_mgr.set_scope_file(scope_path)

    if os.path.isfile(scope_path) and os.path.getsize(scope_path) > 200:
        size = os.path.getsize(scope_path)
        print(f"[trae-loop] prompt-scope.md 已存在 ({size} 字节), 跳过生成")
        return 0

    try:
        from lib.prompt_engine import PromptEngine
        PromptEngine().render_to_file("scope-template.md", "prompt-scope.md", context={})
        size = os.path.getsize(scope_path)
        print(f"[trae-loop] ✅ 已自动生成 prompt-scope.md ({size} 字节)")
        print(f"  路径: {scope_path}")
        return 0
    except Exception as e:
        print(f"[trae-loop] ❌ 自动渲染失败: {e}")
        print("请手动创建 prompt-scope.md")
        return 1


def cmd_verify(state_mgr: StateManager) -> int:
    """--verify: 仅执行产物检查。"""
    checker = PhaseChecker(PROJECT_DIR)
    ok, missing, details = checker.check_all()

    print()
    print("=" * 60)
    print("  产物检查结果")
    print("=" * 60)

    if ok:
        print(f"  ✅ 全部通过: {details}")
    else:
        print(f"  ⚠️ 缺失 {len(missing)} 项:")
        for m in missing:
            print(f"    - {m}")

    print()
    print(f"  检查路径: {PROJECT_DIR}")
    return 0 if ok else 1


def cmd_run(opts: argparse.Namespace, state_mgr: StateManager) -> int:
    """--run: 全流程执行。"""
    bridge = TraeBridge(input_stream=build_input_stream(opts.input))
    checker = PhaseChecker(PROJECT_DIR)
    trace_analyzer = TraceAnalyzer()
    scope_path = os.path.join(EXECUTION_DIR, "prompt-scope.md")
    state_mgr.set_scope_file(scope_path)

    # ---- 检测模式 C 前提 ----
    agent_cli = None
    if opts.mock:
        pass  # mock 模式用 StubDriver
    elif opts.agent:
        agent_cli = [opts.agent]
    else:
        agent_cli = detect_agent_cli()

    use_mode_c = agent_cli is not None or opts.mock
    mode_name = "模式 C (Auto Agent)" if use_mode_c else "模式 B (IDE Paste Guide)"

    print()
    print("=" * 60)
    print(f"  trae-loop — {mode_name}")
    print("=" * 60)

    if agent_cli:
        print(f"  检测到 Agent CLI: {' '.join(agent_cli)}")
    elif opts.mock:
        print("  Mock 模式: 使用 StubDriver")
    else:
        print("  未检测到 Agent CLI, 降级为 IDE 粘贴模式")
    print()

    # ---- Phase 0 ----
    if not opts.mock:
        print("[trae-loop] Phase 0: 环境检测 ...")
        env = EnvironmentChecker()
        ok, failures = env.check()
        if not ok:
            state_mgr.pause("environment check failed: " + "; ".join(failures))
            print("[trae-loop] 环境检测失败, 状态 PAUSED。")
            return 1
        state_mgr.state["__env_checked"] = True
        if state_mgr.state.get("currentPhase") == "init":
            state_mgr.advance("scoping", output="environment check passed")
        print("[trae-loop] ✅ 环境检测通过")
    else:
        if state_mgr.state.get("currentPhase") == "init":
            state_mgr.advance("scoping", output="mock: skip env check")

    # ---- Scoping ----
    current_phase = state_mgr.state.get("currentPhase")
    if current_phase in ("init", "scoping"):
        if opts.mock:
            _mock_produce_scope(EXECUTION_DIR)
        else:
            if not os.path.isfile(scope_path) or os.path.getsize(scope_path) < 200:
                try:
                    from lib.prompt_engine import PromptEngine
                    PromptEngine().render_to_file(
                        "scope-template.md", "prompt-scope.md", context={}
                    )
                    size = os.path.getsize(scope_path)
                    print(f"[第零步] ✅ 已自动生成 prompt-scope.md ({size} 字节)")
                except Exception as e:
                    print(f"[第零步] ❌ 自动渲染失败: {e}")
                    bridge.scope_guide()
                    bridge.wait_for_done(prompt="手动生成后输入 done > ")
            else:
                size = os.path.getsize(scope_path)
                print(f"[第零步] ✅ prompt-scope.md 已存在 ({size} 字节)")

        state_mgr.advance("executing", output="scoping complete")

    # ---- Execute ----
    current_phase = state_mgr.state.get("currentPhase")
    trace_file = os.path.join(EXECUTION_DIR, "trace.json")
    state_mgr.set_trace_file(trace_file)

    if use_mode_c:
        # 模式 C: AgentLoop
        return _run_mode_c(opts, state_mgr, checker, trace_analyzer, agent_cli, scope_path)
    else:
        # 模式 B: IDE 粘贴 + wait_for_done
        return _run_mode_b(opts, state_mgr, bridge, checker, trace_analyzer, scope_path)


def _run_mode_c(
    opts: argparse.Namespace,
    state_mgr: StateManager,
    checker: PhaseChecker,
    trace_analyzer: TraceAnalyzer,
    agent_cli: list[str] | None,
    scope_path: str,
) -> int:
    """模式 C 执行: AgentLoop 驱动外部 Agent CLI。"""
    from lib.agent_driver import StdioDriver, StubDriver, AgentResponse, ToolCall
    from lib.agent_loop import AgentLoop
    from lib.tool_executor import ToolExecutor

    # 读取 scope
    scope_content = _try_read_scope()
    if not scope_content:
        print("[trae-loop] ❌ 未找到 prompt-scope.md")
        return 1

    if opts.mock:
        # StubDriver: 模拟依次创建每个文件 + end_turn
        from lib import ARTIFACT_DOCS, ARTIFACT_MACOS, ARTIFACT_IOS, EVENT_TYPES

        all_artifacts = []
        for d in ARTIFACT_DOCS:
            path_tail = d.split("/")[-1]
            content = f"# {path_tail.replace('.md','')}\n\nmock content\n"
            if path_tail == "event-schema.md":
                content = "# Event Schema\n\n" + "\n".join(f"- {et}" for et in EVENT_TYPES) + "\n"
            all_artifacts.append((d, content))

        for sf in ARTIFACT_MACOS:
            all_artifacts.append((f"macos-island/{sf}", f"// {sf}\nclass {sf.replace('.swift','')} {{}}\n"))

        for sf in ARTIFACT_IOS:
            all_artifacts.append((f"ios-island/{sf}", f"// {sf}\nclass {sf.replace('.swift','')} {{}}\n"))

        all_artifacts.append(("verification-report.md",
            "# Verification Report\n\n## Overview\n\nMock report.\n\n## Test Coverage\n\nMock coverage.\n\n## Results\n\nMock results.\n"))

        responses = []
        for art, content in all_artifacts:
            responses.append(AgentResponse(
                content=f"Creating {art}...",
                tool_calls=[ToolCall(type="create_file", params={"path": art, "content": content})],
                stop_reason="tool_use",
            ))
        # 额外创建 xcodeproj 目录以满足 PhaseChecker
        responses.append(AgentResponse(
            content="Creating xcodeproj directories...",
            tool_calls=[
                ToolCall(type="run_command", params={"command": "mkdir -p macos-island/Island.xcodeproj"}),
                ToolCall(type="run_command", params={"command": "mkdir -p ios-island/iOS.xcodeproj"}),
            ],
            stop_reason="tool_use",
        ))
        responses.append(AgentResponse(
            content="All deliverables created, including xcodeproj directories.",
            stop_reason="end_turn",
        ))
        driver = StubDriver(responses, repeat_last=False)
    else:
        driver = StdioDriver(
            command=agent_cli or ["trae", "run", "-"],
            cwd=PROJECT_DIR,
            timeout=AGENT_TIMEOUT,
            max_retries=AGENT_MAX_RETRIES,
        )

    executor = ToolExecutor(
        project_dir=PROJECT_DIR,
        command_timeout=COMMAND_TIMEOUT,
    )

    max_iter = opts.max_iter or MAX_ITER
    loop = AgentLoop(
        driver=driver,
        executor=executor,
        checker=checker,
        state_mgr=state_mgr,
        trace_analyzer=trace_analyzer,
        max_iter=max_iter,
        trace_file=os.path.join(EXECUTION_DIR, "trace.json"),
    )

    # 如果是 StdioDriver/StubDriver, 以 close 结束
    if hasattr(driver, "close"):
        try:
            ok, summary = loop.run(scope_content)
        finally:
            driver.close()
    else:
        ok, summary = loop.run(scope_content)

    if ok:
        state_mgr.advance("done", output="all artifacts complete (mode C)")
        _print_completion()
        return 0
    else:
        state_mgr.append_error(f"AgentLoop failed: {summary}")
        print(f"\n[trae-loop] ❌ {summary}")
        print("  状态保留在执行阶段, 可重试或切模式 B 手动修复。")
        return 1


def _run_mode_b(
    opts: argparse.Namespace,
    state_mgr: StateManager,
    bridge: TraeBridge,
    checker: PhaseChecker,
    trace_analyzer: TraceAnalyzer,
    scope_path: str,
) -> int:
    """模式 B 执行: IDE 粘贴 + wait_for_done + y/n/redo。"""
    max_attempts = state_mgr.state.get("maxAttempts", 2)

    while state_mgr.state.get("currentPhase") == "executing":
        print()
        print("=" * 60)
        print("  Phase: 执行循环 — 一次给足, Agent 自主执行")
        print("=" * 60)

        # 模式 B: IDE 粘贴引导
        bridge.run_loop(
            scope_file=scope_path,
            trace_file=os.path.join(EXECUTION_DIR, "trace.json"),
            wait_for_done=True,
        )

        # 产物检查
        print()
        print("[trae-loop] 正在检查产物完整性 ...")
        ok, missing, details = checker.check_all()

        if not ok:
            state_mgr.append_error("Artifact check failed: " + "; ".join(missing))
            if state_mgr.state.get("currentAttempt", 1) >= max_attempts:
                state_mgr.pause("max attempts reached")
                print("[trae-loop] 达到最大重试次数, 状态 PAUSED。请手动检查后再运行。")
                return 1
            state_mgr.bump_attempt()
            print(f"[trae-loop] 产物检查失败: {details} 将在下一轮重试。")
            continue

        # Trace 分析
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

        # 内容质量
        print()
        print("[trae-loop] 检查产物文件内容质量 ...")
        from lib import ARTIFACT_DOCS, ARTIFACT_MACOS, ARTIFACT_IOS, MACOS_DIR, IOS_DIR, VERIFICATION_FILE

        all_paths = (
            ARTIFACT_DOCS
            + [os.path.join(MACOS_DIR, f) for f in ARTIFACT_MACOS]
            + [os.path.join(IOS_DIR, f) for f in ARTIFACT_IOS]
            + [VERIFICATION_FILE]
        )
        content_results = trace_analyzer.check_all_artifact_content(
            PROJECT_DIR, all_paths, min_size=20
        )
        content_failures = [r for r in content_results if not r[1]]
        for _path, _ok, _msg in content_results:
            status = "✓" if _ok else "✗"
            print(f"  [{status}] {_msg}")

        if content_failures:
            print(f"  内容质量: {len(content_failures)}/{len(content_results)} 文件异常")
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

        # 完成
        state_mgr.advance("done", output="all artifacts complete (mode B)")
        _print_completion()
        return 0

    return 0


def cmd_patch(opts: argparse.Namespace, state_mgr: StateManager) -> int:
    """--patch: 检查产物, 自动修补缺失项。"""
    checker = PhaseChecker(PROJECT_DIR)
    ok, missing, details = checker.check_all()

    print()
    print("=" * 60)
    print("  Patch 模式 — 自动修复缺失项")
    print("=" * 60)

    if ok:
        print(f"  ✅ 全部通过, 无需修补: {details}")
        return 0

    print(f"  ⚠️ 发现 {len(missing)} 项缺失:")
    for m in missing:
        print(f"    - {m}")
    print()

    # 读取 scope
    scope_content = _try_read_scope()
    if not scope_content:
        print("[trae-loop] ❌ 未找到 prompt-scope.md, 无法生成 Patch scope")
        return 1

    # 检测 Agent CLI
    agent_cli = None
    if opts.agent:
        agent_cli = [opts.agent]
    else:
        agent_cli = detect_agent_cli()

    if not agent_cli:
        print("[trae-loop] ❌ 未检测到 Agent CLI, Patch 模式需要外部 Agent")
        print("  请通过 --agent 指定外部 CLI, 或手动修复后运行 --verify")
        return 1

    print(f"  使用 Agent CLI: {' '.join(agent_cli)}")
    print()

    from lib.agent_driver import StdioDriver
    from lib.agent_loop import AgentLoop
    from lib.tool_executor import ToolExecutor

    driver = StdioDriver(
        command=agent_cli,
        cwd=PROJECT_DIR,
        timeout=AGENT_TIMEOUT,
        max_retries=AGENT_MAX_RETRIES,
    )
    executor = ToolExecutor(
        project_dir=PROJECT_DIR,
        command_timeout=COMMAND_TIMEOUT,
    )
    trace_analyzer = TraceAnalyzer()

    max_iter = opts.max_iter or PATCH_MAX_ITER
    loop = AgentLoop(
        driver=driver,
        executor=executor,
        checker=checker,
        state_mgr=state_mgr,
        trace_analyzer=trace_analyzer,
        max_iter=max_iter,
        trace_file=os.path.join(EXECUTION_DIR, "trace.json"),
    )

    try:
        patch_ok, summary = loop.patch_mode(scope_content, missing)
    finally:
        driver.close()

    if patch_ok:
        state_mgr.advance("done", output=f"patch complete: {summary}")
        _print_completion()
        return 0
    else:
        state_mgr.append_error(f"Patch failed: {summary}")
        print(f"\n[trae-loop] ❌ Patch 未完全修复: {summary}")
        print("  请手动修复后运行 --verify")
        return 1


# ---------------------------------------------------------------------------
# 完成提示
# ---------------------------------------------------------------------------


def _print_completion() -> None:
    print()
    print("=" * 60)
    print("  ✅ 全部阶段完成!")
    print("=" * 60)
    print()
    print(f"  产物目录: {PROJECT_DIR}")
    print(f"  docs/          — 需求与架构文档")
    print(f"  macos-island/  — macOS SwiftUI 项目")
    print(f"  ios-island/    — iOS SwiftUI 项目")
    print(f"  verification-report.md — 集成验证报告")
    print()


# ---------------------------------------------------------------------------
# 主入口
# ---------------------------------------------------------------------------


def main(argv: list[str] | None = None) -> int:
    opts = parse_args(argv)
    state_mgr = StateManager(STATE_FILE)

    # ---- 子命令分发 ----
    if opts.mock:
        # 保持原有 mock 行为
        return _mock_full_flow(opts, state_mgr)

    if opts.env_check:
        return cmd_env_check(state_mgr)

    if opts.scoping:
        return cmd_scoping(state_mgr)

    if opts.run:
        return cmd_run(opts, state_mgr)

    if opts.verify:
        return cmd_verify(state_mgr)

    if opts.patch:
        return cmd_patch(opts, state_mgr)

    # ---- 零参数: 交互模式 ----
    _print_interactive_help(state_mgr)
    return 0


def _mock_full_flow(opts: argparse.Namespace, state_mgr: StateManager) -> int:
    """原有 --mock 全流程 (保持向后兼容)。"""
    bridge = TraeBridge(input_stream=build_input_stream(opts.input))
    checker = PhaseChecker(PROJECT_DIR)
    trace_analyzer = TraceAnalyzer()

    state = state_mgr.load()
    current_phase = state["currentPhase"]

    # Phase 0
    if current_phase == "init":
        state_mgr.advance("scoping", output="mock: skip env check")
        current_phase = state_mgr.state["currentPhase"]

    try:
        while current_phase not in ("done",):
            if current_phase == "PAUSED":
                print("[trae-loop] state=PAUSED, 退出。")
                return 1

            if current_phase == "scoping":
                _mock_produce_scope(EXECUTION_DIR)
                state_mgr.advance("executing", output="scoping complete")
                current_phase = state_mgr.state["currentPhase"]
                continue

            if current_phase == "executing":
                _mock_produce_all_artifacts(PROJECT_DIR)

                ok, missing, details = checker.check_all()
                if not ok:
                    state_mgr.append_error("Artifact check failed: " + "; ".join(missing))
                    if state_mgr.state["currentAttempt"] >= state_mgr.state.get("maxAttempts", 2):
                        state_mgr.pause("max attempts reached")
                        return 1
                    state_mgr.bump_attempt()
                    continue

                trace_path = os.path.join(EXECUTION_DIR, "trace.json")
                trace = trace_analyzer.load_trace(trace_path)
                if trace:
                    trace_ok, trace_issues = trace_analyzer.validate_trace(trace)
                    summary = trace_analyzer.summarize(trace)
                    print(summary)
                else:
                    print("[trae-loop] 未找到 trace.json")

                confirm = bridge.ask_confirm("Mock 产物")
                if confirm == "n":
                    return 0
                if confirm == "redo":
                    state_mgr.bump_attempt()
                    continue

                state_mgr.advance("done", output="all artifacts complete (mock)")
                _print_completion()
                return 0

            break
    except KeyboardInterrupt:
        state_mgr.append_error("interrupted")
        print("\n[trae-loop] 已保存, 下次从断点继续。")
        return 1

    return 0


def _print_interactive_help(state_mgr: StateManager) -> None:
    """零参数时输出使用指南和当前状态。"""
    state = state_mgr.load()
    phase = state.get("currentPhase", "unknown")
    mode = state.get("mode", "unknown")
    iterations = state.get("iterations", 0)
    errors = state.get("errors", [])

    print()
    print("=" * 60)
    print("  trae-loop — Agent Loop 编排器")
    print("=" * 60)
    print()
    print(f"  当前状态:")
    print(f"    阶段: {phase}")
    print(f"    模式: {mode}")
    print(f"    迭代: {iterations}")
    if errors:
        print(f"    错误: {len(errors)} 条")
        for e in errors[-3:]:
            print(f"      - {e['msg']}")
    print()
    print("  用法:")
    print("    --run          全流程执行 (自动检测模式 C/B)")
    print("    --env-check    仅环境检测")
    print("    --scoping      生成 prompt-scope.md")
    print("    --verify       仅产物检查")
    print("    --patch        自动修补缺失项")
    print("    --agent PATH   指定外部 Agent CLI")
    print("    --mock         Mock 模式")
    print("    --input STR    输入字符串 (管道测试)")
    print()


if __name__ == "__main__":
    sys.exit(main())
