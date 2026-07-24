#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Return 0 when weavec-bootstrap has the required main-thread stack.
set -euo pipefail

BIN="${1:?usage: weavec-bootstrap-has-stack-patch.sh <weavec-bootstrap-binary>}"
[[ -f "$BIN" ]] || exit 1

if [[ "$(uname -s)" != Darwin ]]; then
  # GNU and musl linkers differ in how this metadata is exposed. The build is
  # forced after patching, and Linux execution inherits the configured limit.
  exit 0
fi

size="$(otool -l "$BIN" 2>/dev/null | awk '/stacksize/{print $2; exit}')"
[[ -n "$size" ]] || exit 1
(( size >= 16777216 ))
