"""PhaseChecker — 单次全部产物完整性检查。

路径二（真正的 Loop）下，所有 4 阶段产物一次性完成，不再区分 A/B/C/D。
"""

from __future__ import annotations

import os
import re

from . import (
    PROJECT_DIR,
    ARTIFACT_DOCS,
    ARTIFACT_MACOS,
    ARTIFACT_IOS,
    MACOS_DIR,
    IOS_DIR,
    VERIFICATION_FILE,
    EVENT_TYPES,
)


class PhaseChecker:
    """统一检查全部 deliverables 是否存在且内容合规。"""

    def __init__(self, project_dir: str | None = None) -> None:
        self.project_dir = project_dir if project_dir is not None else PROJECT_DIR

    def _full_path(self, relpath: str) -> str:
        return os.path.join(self.project_dir, relpath)

    def _file_exists(self, relpath: str) -> bool:
        return os.path.isfile(self._full_path(relpath))

    def _read_text(self, relpath: str) -> str:
        path = self._full_path(relpath)
        try:
            with open(path, "r", encoding="utf-8") as f:
                return f.read()
        except (OSError, UnicodeDecodeError):
            return ""

    def _contains_keyword(self, text: str, keyword: str) -> bool:
        if keyword in text:
            return True
        token = keyword.strip()
        m = re.match(r"^(?:class|struct)\s+(\S+)$", token)
        if m:
            name = m.group(2)
            patterns = [
                r"(?:^|\s)(?:class|struct)\s+" + re.escape(name) + r"\s*[:{\(]",
                r"(?:^|\s)(?:class|struct)\s+" + re.escape(name) + r"\s*$",
            ]
            for pat in patterns:
                if re.search(pat, text, re.MULTILINE):
                    return True
            if re.search(
                r"(?:^|\s)" + re.escape(name) + r"(?:\s|:|\(|\{|\.|,|$)", text
            ):
                return True
        return False

    def _has_xcodeproj(self, base_dir: str, depth: int = 2) -> bool:
        base = self._full_path(base_dir)
        if not os.path.isdir(base):
            return False
        for root, dirs, _files in os.walk(base):
            rel = os.path.relpath(root, base)
            level = 0 if rel == "." else rel.count(os.sep) + 1
            if level > depth:
                dirs[:] = []
                continue
            if any(d.endswith(".xcodeproj") for d in dirs):
                return True
        return False

    def _count_heading_lines(self, text: str) -> int:
        count = 0
        for line in text.splitlines():
            stripped = line.lstrip()
            if re.match(r"^#+\s", stripped) or re.match(r"^#+$", stripped):
                count += 1
        return count

    def _count_event_types(self, text: str) -> int:
        found = 0
        for et in EVENT_TYPES:
            if re.search(r"(?:^|\W)" + re.escape(et) + r"(?:\W|$)", text):
                found += 1
        return found

    # ------------------------------------------------------------------
    # 统一检查（路径二主入口）
    # ------------------------------------------------------------------

    def check_all(self) -> tuple[bool, list[str], str]:
        """一次性检查全部 4 阶段交付物。

        Returns:
            (ok: bool, missing: list[str], details: str)
        """
        missing: list[str] = []

        # 1) docs/*
        for doc in ARTIFACT_DOCS:
            if not self._file_exists(doc):
                missing.append(doc)

        if "docs/event-schema.md" not in missing:
            text = self._read_text("docs/event-schema.md")
            count_et = self._count_event_types(text)
            if count_et < 7:
                missing.append(f"event-schema: 事件类型 {count_et} 种，期望 ≥7")

        # 2) macos-island/*
        for sf in ARTIFACT_MACOS:
            rel = os.path.join(MACOS_DIR, sf)
            if not self._file_exists(rel):
                missing.append(rel)

        if not self._has_xcodeproj(MACOS_DIR):
            missing.append(f"{MACOS_DIR}/*.xcodeproj 不存在")

        # 3) ios-island/*
        for sf in ARTIFACT_IOS:
            rel = os.path.join(IOS_DIR, sf)
            if not self._file_exists(rel):
                missing.append(rel)

        if not self._has_xcodeproj(IOS_DIR):
            missing.append(f"{IOS_DIR}/*.xcodeproj 不存在")

        # 4) verification-report.md
        if not self._file_exists(VERIFICATION_FILE):
            missing.append(VERIFICATION_FILE)
        else:
            text = self._read_text(VERIFICATION_FILE)
            hl = self._count_heading_lines(text)
            if hl < 3:
                missing.append(f"verification-report: 标题行 {hl}，期望 ≥3")

        ok = len(missing) == 0
        details = "全部交付物检查通过" if ok else "; ".join(missing)
        return ok, missing, details
