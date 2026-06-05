#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Patch vendored weavefront to link with a larger main-thread stack.
set -euo pipefail

WEAVEFRONT_BUILD_SH="${1:?usage: patch-weavefront-stack.sh <weavefront/build.sh>}"

if grep -q 'stack_size' "$WEAVEFRONT_BUILD_SH"; then
  exit 0
fi

python3 - "$WEAVEFRONT_BUILD_SH" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
old = '''  log "compiling to executable"
  clang "$BUILD_DIR/weavefront.bc" "$RUNTIME_C" -o "$BUILD_DIR/weavefront" \\
    || fail "clang link failed"
'''
new = '''  log "compiling to executable"
  # Large combined surface programs recurse deeply during lowering; default
  # main-thread stack (~8 MiB on macOS) overflows without an explicit limit.
  local stack_size="0x1000000"
  if [[ "$(uname -s)" == "Darwin" ]]; then
    clang "$BUILD_DIR/weavefront.bc" "$RUNTIME_C" -o "$BUILD_DIR/weavefront" \\
      -Wl,-stack_size,"$stack_size" \\
      || fail "clang link failed"
  else
    clang "$BUILD_DIR/weavefront.bc" "$RUNTIME_C" -o "$BUILD_DIR/weavefront" \\
      -Wl,-z,stack-size="$stack_size" \\
      || fail "clang link failed"
  fi
'''
if old not in text:
    raise SystemExit(f"weavefront build.sh layout changed; cannot patch: {path}")
path.write_text(text.replace(old, new, 1))
PY
