#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
SOURCE="$ROOT/test/correctness/surface/74_call_ptr_missing_callee.weave"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-backend-call-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'backend-call-validation: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

WIR="$TMP/missing-callee.wir"
"$WEAVEC" --frontend "$WIR" "$SOURCE"

for attempt in $(seq 1 32); do
  LLVM="$TMP/missing-callee-$attempt.ll"
  STDERR="$TMP/backend-$attempt.stderr"

  set +e
  "$WEAVEC" --backend "$WIR" "$LLVM" 2>"$STDERR"
  status=$?
  set -e

  if (( status == 0 )); then
    printf 'backend-call-validation: attempt %s unexpectedly succeeded\n' \
      "$attempt" >&2
    exit 1
  fi
  if (( status >= 128 )); then
    printf 'backend-call-validation: attempt %s terminated by signal: %s\n' \
      "$attempt" "$status" >&2
    cat "$STDERR" >&2
    exit 1
  fi
  [[ ! -e "$LLVM" ]] || {
    printf 'backend-call-validation: attempt %s published LLVM output\n' \
      "$attempt" >&2
    exit 1
  }
  grep -Fq 'unknown identifier: <missing>' "$STDERR"
done

printf 'backend-call-validation: malformed calls rejected normally\n'
