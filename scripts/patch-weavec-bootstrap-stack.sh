#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Patch a vendored weavec-bootstrap source build to request a 16 MiB main stack.
set -euo pipefail

BUILD_SH="${1:?usage: patch-weavec-bootstrap-stack.sh <weavec-bootstrap/build.sh>}"

if grep -q 'stack_size="0x1000000"' "$BUILD_SH"; then
  exit 0
fi

python3 - "$BUILD_SH" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
old = '''link_with_source() {
  log "linking weavec-bootstrap with source runtime fallback"
  clang "$BUILD_DIR/weavec-bootstrap.bc" "$RUNTIME_C" \
    -o "$BUILD_DIR/weavec-bootstrap"
}
'''
new = '''link_with_source() {
  log "linking weavec-bootstrap with source runtime fallback"
  local stack_size="0x1000000"
  if [[ "$(uname -s)" == Darwin ]]; then
    clang "$BUILD_DIR/weavec-bootstrap.bc" "$RUNTIME_C" \
      -o "$BUILD_DIR/weavec-bootstrap" \
      -Wl,-stack_size,"$stack_size"
  else
    clang "$BUILD_DIR/weavec-bootstrap.bc" "$RUNTIME_C" \
      -o "$BUILD_DIR/weavec-bootstrap" \
      -Wl,-z,stack-size="$stack_size"
  fi
}
'''
if old not in text:
    raise SystemExit(f"weavec-bootstrap build.sh layout changed; cannot patch: {path}")
path.write_text(text.replace(old, new, 1))
PY
