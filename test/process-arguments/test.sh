#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-process-args-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.weave" <<'EOF'
(program
  (name "process-arguments-test")
  (version "0.1")
  (fn program_main
    (params)
    (returns i32)
    (do
      (if
        (condition (op not-equal (call args_count) 2))
        (then (do (return 10)))
        (else (do)))
      (if
        (condition (op equal (call arg 0) null))
        (then (do (return 11)))
        (else (do)))
      (if
        (condition (op equal (call arg 1) null))
        (then (do (return 12)))
        (else (do)))
      (if
        (condition (op not-equal (call arg 2) null))
        (then (do (return 13)))
        (else (do)))
      (if
        (condition (op not-equal (call arg -1) null))
        (then (do (return 14)))
        (else (do)))
      (return 0))))
EOF

"$WEAVEC" build \
  "$ROOT/stdlib/process.weave" \
  "$TMP/main.weave" \
  -o "$TMP/process-arguments"

set +e
"$TMP/process-arguments" alpha beta
status_two="$?"
"$TMP/process-arguments" alpha
status_one="$?"
set -e

[[ "$status_two" -eq 0 ]] || {
  printf 'process-arguments: two-argument case exited %s\n' "$status_two" >&2
  exit 1
}
[[ "$status_one" -eq 10 ]] || {
  printf 'process-arguments: arity case exited %s, expected 10\n' "$status_one" >&2
  exit 1
}

printf 'process-arguments: passed\n'
