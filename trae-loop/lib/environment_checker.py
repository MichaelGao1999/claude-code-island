import os
import subprocess

from typing import Callable, Optional

from lib import PROJECT_DIR


class EnvironmentChecker:
    def __init__(
        self,
        project_dir: Optional[str] = None,
        command_runner: Optional[Callable[[str], tuple[int, str, str]]] = None,
        print_errors: bool = True,
    ):
        self.project_dir = project_dir if project_dir is not None else PROJECT_DIR
        self.command_runner = command_runner if command_runner is not None else self._default_runner
        self.print_errors = print_errors

    def _default_runner(self, cmd) -> tuple[int, str, str]:
        try:
            result = subprocess.run(
                cmd,
                shell=False,
                capture_output=True,
                text=True,
            )
            return (result.returncode, result.stdout or "", result.stderr or "")
        except FileNotFoundError:
            return (1, "", "")
        except Exception:
            return (1, "", "")

    def _run(self, cmd) -> tuple[int, str, str]:
        return self.command_runner(cmd)

    def check(self) -> tuple[bool, list[str]]:
        """检查环境。

        硬要求（失败则 PAUSED）：
          - xcode-select -p 可用（Xcode CLI 工具）
          - swift --version 可用（Swift 工具链）
          - 项目目录存在且可写

        软要求（仅警告，不阻塞）：
          - xcodebuild -version —— 用于 Phase D 构建验证，缺失时降级为 swift -parse
        """
        failures: list[str] = []
        warnings: list[str] = []

        # 硬要求 1: xcode-select (CLI 工具)
        returncode, _, _ = self._run(["xcode-select", "-p"])
        if returncode != 0:
            failures.append("xcode-select: Xcode Command Line Tools not detected")

        # 软要求: xcodebuild (Xcode App) —— 缺失只警告，不阻塞
        returncode, _, _ = self._run(["xcodebuild", "-version"])
        if returncode != 0:
            warnings.append(
                "xcodebuild: Xcode App not available "
                "(swift -parse 将在 Phase D 作为降级验证)"
            )

        # 硬要求 2: swift toolchain
        returncode, stdout, _ = self._run(["swift", "--version"])
        if returncode != 0:
            failures.append("swift: Swift toolchain not available")
        elif self.print_errors and stdout:
            # 非错误场景也顺便打印版本
            first_line = stdout.strip().splitlines()[0] if stdout.strip() else ""
            if first_line:
                print(f"  Swift 版本: {first_line}")

        # 硬要求 3: 项目目录
        try:
            if not os.path.isdir(self.project_dir):
                os.makedirs(self.project_dir, exist_ok=True)
            dir_ok = os.path.isdir(self.project_dir) and os.access(
                self.project_dir, os.W_OK
            )
        except Exception:
            dir_ok = False

        if not dir_ok:
            failures.append(f"project_dir: 项目目录不可写：{self.project_dir}")

        ok = len(failures) == 0

        if self.print_errors:
            # 打印警告
            for w in warnings:
                print(f"  ⚠️  {w}")
            # 打印错误
            for f in failures:
                if "xcode-select" in f:
                    print(
                        "请安装 Xcode Command Line Tools：xcode-select --install"
                    )
                elif "xcodebuild" in f:
                    print(
                        "请在 App Store 安装 Xcode，并在 Xcode → Preferences → "
                        "Locations → Command Line Tools 中选择"
                    )
                elif "swift" in f:
                    print("请确保 Swift 工具链可用")
                elif "project_dir" in f:
                    print(f"项目目录不可写：{self.project_dir}")

        # 将 warning 附加到 failures 以便在 state.json 中留下记录
        # 但 ok 仍按 hard failures 判断
        if self.print_errors:
            self._last_warnings = warnings

        return (ok, failures + warnings)
