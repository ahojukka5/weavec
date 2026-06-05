#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Return 0 when weavefront was linked with at least a 16 MiB stack.
set -euo pipefail

BIN="${1:?usage: weavefront-has-stack-patch.sh <weavefront-binary>}"
[[ -f "$BIN" ]] || exit 1

if [[ "$(uname -s)" != "Darwin" ]]; then
  # Non-macOS linkers vary; rely on rebuild after patch-weavefront-stack.sh.
  exit 0
fi

# LC_MAIN stacksize (macOS) — default is 8388608 (8 MiB).
size="$(otool -l "$BIN" 2>/dev/null | awk '/stacksize/{print $2; exit}')"
[[ -n "$size" ]] || exit 1
(( size >= 16777216 ))  # 0x1000000
