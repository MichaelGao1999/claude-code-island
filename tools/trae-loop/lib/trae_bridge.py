"""TraeBridge — 精简为仅人机交互桥接。

职责：
  1. 引导用户在「第零步」用 Claude 生成 prompt-scope.md
  2. 自动检测 trae run CLI 是否存在，执行或降级为 IDE 粘贴模式
  3. 通过 stdin 等待用户确认（done / y / n / redo）
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys

from lib import EXECUTION_DIR, REPO_ROOT


class TraeBridge:
    """执行阶段的人工交互桥接器。"""

    def __init__(
        self,
        input_stream=None,
        output_stream=None,
    ) -> None:
        self.input_stream = input_stream if input_stream is not None else sys.stdin
        self.output_stream = output_stream if output_stream is not None else sys.stdout

    # ------------------------------------------------------------------
    # 第零步引导
    # ------------------------------------------------------------------

    def scope_guide(self) -> None:
        """输出 第零步（AI 辅助定界）操作指引。

        注意：
        1. 输出使用角色标记，防止 AI 编排器（Claude Code）误执行。
        2. 「用户操作」标记的内容应由人类完成，AI 编排器仅引导。
        3. 生成的 prompt-scope.md 必须包含「交付后行为」节，
           明确告诉 Agent 完成交付清单后停止、不要问用户"下一步"。
        """
        dest = os.path.join(EXECUTION_DIR, "prompt-scope.md")
        self.output_stream.write("\n")
        self.output_stream.write("=" * 60 + "\n")
        self.output_stream.write("  Phase: 第零步 — AI 辅助定界\n")
        self.output_stream.write("=" * 60 + "\n")
        self.output_stream.write("\n")
        self.output_stream.write("  ◆ 编排器状态: 等待第零步完成          \n")
        self.output_stream.write("  ◆ 当前编排器: Claude Code（引导 + 验证）\n")
        self.output_stream.write("  ◆ 执行器:     Trae IDE（代码执行）     \n")
        self.output_stream.write("  ◆ 用户角色:   完成下方人工操作后输入 done\n")
        self.output_stream.write("\n")
        self.output_stream.write("  ── 用户操作 ──\n")
        self.output_stream.write("\n")
        self.output_stream.write("    1. 打开 Trae IDE, 新建一个对话\n")
        self.output_stream.write("    2. 将 spec.md 的全部内容粘贴到该对话\n")
        self.output_stream.write("    3. 要求 Trae IDE 的 Claude\n")
        self.output_stream.write("      按 agent-loop-workflow.md 标准格式\n")
        self.output_stream.write("      输出 prompt-scope.md\n")
        self.output_stream.write("      （注意：scope 必须包含「交付后行为」节，\n")
        self.output_stream.write("       告诉 Agent 完成即停、不推荐外任务）\n")
        self.output_stream.write("    4. 将输出的 scope 保存到:\n")
        self.output_stream.write(f"       {dest}\n")
        self.output_stream.write("    5. 在此终端输入 done 继续\n")
        self.output_stream.write("\n")
        self.output_stream.write(f"  scope 保存路径: {dest}\n")
        self.output_stream.write("=" * 60 + "\n")
        self.output_stream.write("> ")
        self.output_stream.flush()

    # ------------------------------------------------------------------
    # 执行引导
    # ------------------------------------------------------------------

    def execution_guide(self) -> None:
        """输出执行阶段操作指引；若 prompt-scope.md 不存在则自动生成。

        注意：输出使用角色标记，防止 AI 编排器误执行。
        "用户操作"标记的内容应由人类完成。
        """
        scope_path = os.path.join(EXECUTION_DIR, "prompt-scope.md")
        self.output_stream.write("\n")
        self.output_stream.write("=" * 60 + "\n")
        self.output_stream.write("  Phase: 执行阶段\n")
        self.output_stream.write("=" * 60 + "\n")
        self.output_stream.write("\n")
        self.output_stream.write("  ◆ 编排器状态: 等待执行完成              \n")
        self.output_stream.write("  ◆ 执行器: Trae IDE（粘贴后自主执行）     \n")
        self.output_stream.write("\n")

        # 自动从模板渲染 scope（若不存在）
        if not os.path.isfile(scope_path):
            self.output_stream.write(
                "  [TraeBridge] prompt-scope.md 不存在，"
                "自动从模板生成 ...\n"
            )
            self.output_stream.flush()
            try:
                from lib.prompt_engine import PromptEngine
                PromptEngine().render_to_file(
                    "scope-template.md", "prompt-scope.md", context={}
                )
                self.output_stream.write(
                    f"  [TraeBridge] 已生成: {scope_path}\n"
                )
            except Exception as e:
                self.output_stream.write(
                    f"  [TraeBridge] 渲染失败: {e}\n"
                )
            self.output_stream.write("\n")

        self.output_stream.write("  ── 用户操作 ──\n")
        self.output_stream.write("\n")
        self.output_stream.write(
            f"    1. 将 {scope_path} 的全部内容粘贴到 Trae IDE\n"
        )
        self.output_stream.write("    2. Trae 会在单次循环内自主完成全部交付物\n")
        self.output_stream.write("    3. 在此终端输入 done 继续\n")
        self.output_stream.write("=" * 60 + "\n")
        self.output_stream.write("> ")
        self.output_stream.flush()

    # ------------------------------------------------------------------
    # 等待 done
    # ------------------------------------------------------------------

    def wait_for_done(
        self,
        prompt: str = "Trae 执行完成后输入 done 并回车 > ",
    ) -> None:
        """阻塞等待用户输入包含 `done` 的行。"""
        self.output_stream.write(prompt)
        self.output_stream.flush()

        while True:
            line = self.input_stream.readline()
            if line == "":
                return
            stripped = line.strip().lower()
            if "done" in stripped:
                return

    # ------------------------------------------------------------------
    # y/n/redo 确认
    # ------------------------------------------------------------------

    def ask_confirm(
        self,
        phase: str = "全部产物",
        prompt: str | None = None,
    ) -> str:
        """询问是否通过，返回 'y' / 'n' / 'redo'。

        Args:
            phase: 阶段描述文字。
            prompt: 自定义提示文字，默认使用标准 y / n / redo 格式。

        Returns:
            "y" | "n" | "redo"
        """
        valid = {"y", "n", "redo"}
        if prompt is None:
            prompt = f"阶段 [{phase}] 全部交付物检查通过。确认通过？[y/n/redo] > "
        while True:
            self.output_stream.write(prompt)
            self.output_stream.flush()

            line = self.input_stream.readline()
            if line == "":
                return "y"
            stripped = line.strip().lower()
            if stripped in valid:
                return stripped

    # ------------------------------------------------------------------
    # trae run CLI 执行
    # ------------------------------------------------------------------

    def run_loop(
        self,
        scope_file: str,
        trace_file: str,
        wait_for_done: bool = True,
    ) -> None:
        """自动检测 trae CLI 是否存在，执行或降级为 IDE 粘贴模式。

        Args:
            scope_file: prompt-scope.md 的绝对路径
            trace_file: 输出 trace.json 的绝对路径
            wait_for_done: 是否在 IDE 粘贴模式下等待 done 输入
        """
        trae_cmd = shutil.which("trae")
        if trae_cmd:
            self.output_stream.write(
                f"\n[TraeBridge] 检测到 trae CLI，正在执行 ...\n"
            )
            self.output_stream.write(
                f"  trae run -f {scope_file} -t {trace_file} -w {REPO_ROOT}\n"
            )
            self.output_stream.flush()
            try:
                subprocess.run(
                    ["trae", "run",
                     "-f", scope_file,
                     "-t", trace_file,
                     "-w", REPO_ROOT],
                    check=True,
                )
            except subprocess.CalledProcessError as e:
                self.output_stream.write(
                    f"\n[TraeBridge] trae run 退出码 {e.returncode}，"
                    "请检查后重试。\n"
                )
                self.output_stream.flush()
        else:
            self.output_stream.write(
                "\n[TraeBridge] 未检测到 trae CLI，降级为 IDE 粘贴模式。\n"
            )
            self.output_stream.write(
                f"  请将以下文件内容粘贴到 Trae IDE：\n"
                f"    {scope_file}\n\n"
                "  Trae 会在单次循环内自主完成全部交付物。\n"
            )
            self.output_stream.flush()
            if wait_for_done:
                self.wait_for_done(
                    prompt="Trae 执行完成后输入 done 并回车 > "
                )
