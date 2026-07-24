#!/usr/bin/env python3
"""Apply the final weavec/weavec-bootstrap naming across tracked text files."""

from __future__ import annotations

import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CI_PATH = ROOT / ".github/workflows/ci.yml"


def tracked_text_files() -> list[Path]:
    raw = subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT)
    result: list[Path] = []
    for item in raw.split(b"\0"):
        if not item:
            continue
        path = ROOT / item.decode()
        if not path.is_file() or path == CI_PATH:
            continue
        if path.name in {"CHANGELOG.md", "NOTICE", "LICENSE"}:
            continue
        try:
            path.read_text()
        except UnicodeDecodeError:
            continue
        result.append(path)
    return result


REPLACEMENTS = (
    ("WEAVEC2_BACKEND", "WEAVEC_BACKEND"),
    ("WEAVEC2_DIR", "WEAVEC_DIR"),
    ("WEAVEFRONT_TAG", "WEAVEC_BOOTSTRAP_REF"),
    ("WEAVEFRONT_REPO", "WEAVEC_BOOTSTRAP_REPO"),
    ("WEAVEFRONT_DIR", "WEAVEC_BOOTSTRAP_DIR"),
    ("WEAVEFRONT_BIN", "WEAVEC_BOOTSTRAP_BIN"),
    ("WEAVEFRONT_BUILD", "WEAVEC_BOOTSTRAP_BUILD"),
    ("WEAVEFRONT", "WEAVEC_BOOTSTRAP"),
    ("weavefront-cat.sh", "weavec-bootstrap-cat.sh"),
    ("weavefront", "weavec-bootstrap"),
    ("build/weavec2", "build/weavec"),
)

for path in tracked_text_files():
    text = path.read_text()
    original = text
    for old, new in REPLACEMENTS:
        text = text.replace(old, new)
    text = re.sub(r"\bweavec2\b", "weavec", text)
    text = re.sub(r"\bWeavec2\b", "Weavec", text)
    if text != original:
        path.write_text(text)

readme = ROOT / "README.md"
text = readme.read_text()
text = text.replace(
    "The repository was renamed from `weavec` to `weavec`.",
    "This repository is the final user-facing compiler product.",
)
text = text.replace("formerly `weavec`", "the final compiler")
readme.write_text(text)

changelog = ROOT / "CHANGELOG.md"
text = changelog.read_text()
marker = "## [Unreleased]\n"
entry = (
    "\n### Changed\n"
    "- Renamed all current compiler artifacts from `weavec2` to `weavec`: "
    "`build/weavec.{wir,ll,bc}` and `build/weavec`.\n"
    "- Renamed the bootstrap dependency and environment contract from "
    "`weavefront`/`WEAVEFRONT_*` to `weavec-bootstrap`/"
    "`WEAVEC_BOOTSTRAP_*`.\n"
    "- Replaced four raw parser-module links with the single versioned boundary "
    "`build/libweave-sexpr.bc`.\n"
    "- Renamed the self-host backend override to `WEAVEC_BACKEND` and all "
    "stage outputs to `weavec`.\n"
    "- Removed the remaining compatibility paths and former stack-helper names.\n"
)
if entry not in text:
    text = text.replace(marker, marker + entry, 1)
changelog.write_text(text)

# The helper itself is one-shot. CI is updated separately through the GitHub API.
Path(__file__).unlink()
