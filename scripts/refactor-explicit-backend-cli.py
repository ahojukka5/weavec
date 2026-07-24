#!/usr/bin/env python3
"""Remove the implicit `weavec input.wir output.ll` compatibility path."""

from __future__ import annotations

import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def tracked_shell_files() -> list[Path]:
    raw = subprocess.check_output(["git", "ls-files", "-z", "*.sh"], cwd=ROOT)
    return [ROOT / item.decode() for item in raw.split(b"\0") if item]


updated: list[Path] = []
for path in tracked_shell_files():
    lines = path.read_text().splitlines(keepends=True)
    changed = False
    result: list[str] = []
    for line in lines:
        if (
            '"$WEAVEC" ' in line
            and '"$WEAVEC" --' not in line
            and '[[ ' not in line
        ):
            line = line.replace('"$WEAVEC" ', '"$WEAVEC" --backend ', 1)
            changed = True
        result.append(line)
    if changed:
        path.write_text("".join(result))
        updated.append(path)

main = ROOT / "src/main.weave"
text = main.read_text()
legacy = """      ; Keep the historical backend spelling for current tests and scripts.
      (let input_path_legacy ptr (local_get arg1))
      (let output_path_legacy ptr (load_ptr (ptr_add (param_get argv) (const_i64 16))))
      (return (call_i32 compile_file (local_get input_path_legacy) (local_get output_path_legacy)))))
"""
replacement = """      ; Unknown or incomplete command.
      (return (const_i32 1))))
"""
if legacy not in text:
    raise SystemExit("legacy backend fallback block not found in src/main.weave")
main.write_text(text.replace(legacy, replacement, 1))
updated.append(main)

test = ROOT / "test.sh"
text = test.read_text()
anchor = 'mkdir -p "$LL_DIR" "$BC_DIR" "$BIN_DIR" "$WIR_FROM_SURFACE_DIR"\n'
check = r'''

log "reject implicit backend syntax"
legacy_ll="$LL_DIR/implicit_backend_should_fail.ll"
rm -f "$legacy_ll"
set +e
"$WEAVEC" "$WIR_TEST_DIR/01_return_constant.wir" "$legacy_ll" \
  >/dev/null 2>&1
legacy_status="$?"
set -e
if [[ "$legacy_status" -eq 0 ]]; then
  fail "implicit backend syntax unexpectedly succeeded"
elif [[ -e "$legacy_ll" ]]; then
  fail "implicit backend syntax created output"
else
  log "ok explicit backend CLI required"
  pass_count=$((pass_count + 1))
fi
'''
if check.strip() not in text:
    if anchor not in text:
        raise SystemExit("test insertion anchor not found")
    text = text.replace(anchor, anchor + check, 1)
test.write_text(text)

# Ensure every direct shell invocation is explicit after the migration.
remaining: list[str] = []
for path in tracked_shell_files():
    for number, line in enumerate(path.read_text().splitlines(), 1):
        if (
            '"$WEAVEC" ' in line
            and '"$WEAVEC" --' not in line
            and '[[ ' not in line
        ):
            remaining.append(f"{path.relative_to(ROOT)}:{number}:{line}")
if remaining:
    raise SystemExit("implicit WEAVEC invocation(s) remain:\n" + "\n".join(remaining))

changelog = ROOT / "CHANGELOG.md"
text = changelog.read_text()
needle = "- Expanded CI to require SDK mode on Linux glibc and musl and source mode on\n  macOS.\n"
entry = (
    needle
    + "- Removed the implicit `weavec input.wir output.ll` backend compatibility "
      "syntax; callers must use `weavec --backend input.wir output.ll`.\n"
)
if "Removed the implicit `weavec input.wir output.ll`" not in text:
    if needle not in text:
        raise SystemExit("changelog insertion anchor not found")
    text = text.replace(needle, entry, 1)
changelog.write_text(text)

Path(__file__).unlink()
print("updated:")
for path in updated:
    print(path.relative_to(ROOT))
