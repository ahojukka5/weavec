#!/usr/bin/env python3
from __future__ import annotations

import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
ci = root / ".github/workflows/ci.yml"
raw = subprocess.check_output(["git", "ls-files", "-z"], cwd=root)
for item in raw.split(b"\0"):
    if not item:
        continue
    path = root / item.decode()
    if not path.is_file() or path == ci or path.name in {"CHANGELOG.md", "NOTICE", "LICENSE"}:
        continue
    try:
        text = path.read_text()
    except UnicodeDecodeError:
        continue
    updated = text.replace("WEAVEC2", "WEAVEC")
    if updated != text:
        path.write_text(updated)

Path(__file__).unlink()
