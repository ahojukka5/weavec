#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-backend-call-validation-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'backend-call-validation: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

SOURCE="$ROOT/test/correctness/surface/74_call_ptr_missing_callee.weave"
WIR="$TMP/missing-callee.wir"
LLVM="$TMP/missing-callee.ll"
STDERR="$TMP/missing-callee.stderr"

"$WEAVEC" --frontend "$WIR" "$SOURCE"

set +e
"$WEAVEC" --backend "$WIR" "$LLVM" 2>"$STDERR"
status="$?"
set -e

[[ "$status" -ne 0 ]] || {
  printf 'backend-call-validation: malformed call was accepted\n' >&2
  exit 1
}
[[ "$status" -lt 128 ]] || {
  printf 'backend-call-validation: backend terminated by signal: %s\n' \
    "$status" >&2
  exit 1
}
[[ ! -e "$LLVM" ]] || {
  printf 'backend-call-validation: failure published LLVM output\n' >&2
  exit 1
}
grep -Fq 'unknown identifier: <missing>' "$STDERR" || {
  printf 'backend-call-validation: missing-callee diagnostic not found\n' >&2
  cat "$STDERR" >&2
  exit 1
}

printf 'backend-call-validation: missing callees reject without signals\n'
