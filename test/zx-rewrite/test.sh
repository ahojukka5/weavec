#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# ZX graph IR, compiled graph rewrites, and deterministic extraction (#458).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-zx-rewrite-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'zx-rewrite: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

BIN="$TMP/zx-rewrite"
WIR="$TMP/zx-rewrite.wir"

"$WEAVEC" build \
  "$ROOT/stdlib/memory.weave" \
  "$ROOT/stdlib/option.weave" \
  "$ROOT/stdlib/vec.weave" \
  "$ROOT/stdlib/io.weave" \
  "$ROOT/src/rewrite/engine.weave" \
  "$ROOT/src/rewrite/circuit.weave" \
  "$ROOT/src/rewrite/zx.weave" \
  "$ROOT/test/zx-rewrite/main.weave" \
  -o "$BIN" \
  --emit-wir "$WIR" \
  2>"$TMP/build.stderr" || {
  printf 'zx-rewrite: build failed\n' >&2
  cat "$TMP/build.stderr" >&2
  exit 1
}

set +e
LC_ALL=C "$BIN" >"$TMP/run.stdout" 2>"$TMP/run.stderr"
status="$?"
set -e
if [[ "$status" -ne 0 ]]; then
  printf 'zx-rewrite: program exited %s\n' "$status" >&2
  cat "$TMP/run.stdout" >&2 || true
  cat "$TMP/run.stderr" >&2 || true
  exit 1
fi
[[ ! -s "$TMP/run.stderr" ]] || {
  printf 'zx-rewrite: unexpected stderr\n' >&2
  cat "$TMP/run.stderr" >&2
  exit 1
}
grep -Fq 'zx ok' "$TMP/run.stdout"
grep -Fq '(core-version 3)' "$WIR"
python3 "$ROOT/test/zx-rewrite/check_unitary.py" "$TMP/run.stdout"
if grep -Eq '\(q?rewrite\b' "$ROOT/src/rewrite/zx.weave" \
    "$ROOT/test/zx-rewrite/main.weave"; then
  printf 'zx-rewrite: leaked rewrite syntax\n' >&2
  exit 1
fi
printf 'zx-rewrite: passed\n'
