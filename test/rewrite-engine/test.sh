#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Generic rewrite engine and circuit-IR library (#456/#457 modules).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-rewrite-engine-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'rewrite-engine: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

BIN="$TMP/rewrite-engine"
WIR="$TMP/rewrite-engine.wir"

"$WEAVEC" build \
  "$ROOT/stdlib/memory.weave" \
  "$ROOT/stdlib/option.weave" \
  "$ROOT/stdlib/vec.weave" \
  "$ROOT/stdlib/io.weave" \
  "$ROOT/src/rewrite/engine.weave" \
  "$ROOT/src/rewrite/circuit.weave" \
  "$ROOT/src/rewrite/targets.weave" \
  "$ROOT/test/rewrite-engine/main.weave" \
  -o "$BIN" \
  --emit-wir "$WIR" \
  2>"$TMP/build.stderr" || {
  printf 'rewrite-engine: build failed\n' >&2
  cat "$TMP/build.stderr" >&2
  exit 1
}

set +e
LC_ALL=C "$BIN" >"$TMP/run.stdout" 2>"$TMP/run.stderr"
status="$?"
set -e
if [[ "$status" -ne 0 ]]; then
  printf 'rewrite-engine: program exited %s\n' "$status" >&2
  cat "$TMP/run.stdout" >&2 || true
  cat "$TMP/run.stderr" >&2 || true
  exit 1
fi
printf '%s' $'engine ok\n' > "$TMP/expected.stdout"
cmp "$TMP/expected.stdout" "$TMP/run.stdout" || {
  printf 'rewrite-engine: stdout mismatch\n' >&2
  diff -u "$TMP/expected.stdout" "$TMP/run.stdout" >&2 || true
  exit 1
}
[[ ! -s "$TMP/run.stderr" ]] || {
  printf 'rewrite-engine: unexpected stderr\n' >&2
  cat "$TMP/run.stderr" >&2
  exit 1
}
if grep -Eq '\(q?rewrite\b' "$ROOT/src/rewrite/engine.weave" \
    "$ROOT/src/rewrite/circuit.weave" \
    "$ROOT/test/rewrite-engine/main.weave"; then
  printf 'rewrite-engine: leaked rewrite syntax\n' >&2
  exit 1
fi
grep -Fq '(core-version 3)' "$WIR"
printf 'rewrite-engine: passed\n'
