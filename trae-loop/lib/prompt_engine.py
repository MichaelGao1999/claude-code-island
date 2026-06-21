"""PromptEngine: 基于 string.Template + safe_substitute 的零依赖模板渲染引擎。

渲染约定: 模板占位符采用 ${name} 形式 (例如 ${project_name}), 未提供的占位符
会被 safe_substitute 原样保留而不抛出异常。
"""

from __future__ import annotations

import os
import string

from lib import (
    EXECUTION_DIR,
    PROJECT_DIR,
    PROJECT_NAME,
    TEMPLATES_DIR,
)


class PromptEngine:
    """读取指定目录下的模板文件, 合并默认上下文后使用 string.Template 渲染。"""

    def __init__(
        self,
        templates_dir: str | None = None,
        execution_dir: str | None = None,
    ) -> None:
        """初始化 PromptEngine。

        Args:
            templates_dir: 模板文件所在目录, 默认使用 lib.TEMPLATES_DIR。
            execution_dir: render_to_file 输出文件的目录, 默认使用 lib.EXECUTION_DIR。
        """
        self.templates_dir = templates_dir if templates_dir is not None else TEMPLATES_DIR
        self.execution_dir = execution_dir if execution_dir is not None else EXECUTION_DIR

    def render(self, template_name: str, context: dict | None = None) -> str:
        """读取模板文件并渲染为字符串。

        合并的默认上下文包括:
            project_name = PROJECT_NAME
            project_dir  = PROJECT_DIR
            attempt      = context.get("attempt", 1)
            last_error   = context.get("last_error", "")
            missing_files= context.get("missing_files", "")  (list 会被转为 ", ".join(...))

        Args:
            template_name: 模板文件名, 会在 self.templates_dir 下查找。
            context: 额外提供的上下文字典, 可覆盖默认值。

        Returns:
            渲染后的字符串。未提供的占位符会保留原始 ${name} 形式。
        """
        if context is None:
            context = {}

        template_path = os.path.join(self.templates_dir, template_name)
        with open(template_path, "r", encoding="utf-8") as f:
            template_content = f.read()

        mf = context.get("missing_files", "")
        if isinstance(mf, list):
            mf = ", ".join(str(item) for item in mf)

        merged: dict = {
            "project_name": PROJECT_NAME,
            "project_dir": PROJECT_DIR,
            "attempt": context.get("attempt", 1),
            "last_error": context.get("last_error", ""),
            "missing_files": mf,
        }
        for key, value in context.items():
            if key == "missing_files":
                merged[key] = mf
            else:
                merged[key] = value

        template = string.Template(template_content)
        return template.safe_substitute(**merged)

    def render_to_file(
        self,
        template_name: str,
        output_filename: str,
        context: dict | None = None,
    ) -> str:
        """渲染模板并写入到 self.execution_dir 下的文件中。

        若 self.execution_dir 不存在, 会自动创建。

        Args:
            template_name: 模板文件名。
            output_filename: 输出文件名 (不含目录)。
            context: 额外提供的上下文字典。

        Returns:
            写入文件的绝对路径。
        """
        rendered = self.render(template_name, context)
        os.makedirs(self.execution_dir, exist_ok=True)
        output_path = os.path.join(self.execution_dir, output_filename)
        with open(output_path, "w", encoding="utf-8") as f:
            f.write(rendered)
        return output_path
