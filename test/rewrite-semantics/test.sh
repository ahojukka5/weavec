#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Typed deterministic rewrite semantics (#456). Builds the ordinary-Weave
# witness and runs it. The program applies two trusted sequence rules, an
# independent normal-form oracle, provenance filtering, and two graph rules.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-rewrite-semantics-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'rewrite-semantics: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

SRC="$ROOT/test/rewrite-semantics/main.weave"
BIN="$TMP/rewrite-semantics"
WIR="$TMP/rewrite-semantics.wir"

"$WEAVEC" build \
  "$ROOT/stdlib/memory.weave" \
  "$ROOT/stdlib/option.weave" \
  "$ROOT/stdlib/vec.weave" \
  "$ROOT/stdlib/io.weave" \
  "$SRC" \
  -o "$BIN" \
  --emit-wir "$WIR" \
  2>"$TMP/build.stderr" || {
  printf 'rewrite-semantics: build failed\n' >&2
  cat "$TMP/build.stderr" >&2
  exit 1
}

stdout="$TMP/run.stdout"
stderr="$TMP/run.stderr"
set +e
LC_ALL=C "$BIN" >"$stdout" 2>"$stderr"
status="$?"
set -e

if [[ "$status" -ne 0 ]]; then
  printf 'rewrite-semantics: program exited %s\n' "$status" >&2
  cat "$stdout" >&2 || true
  cat "$stderr" >&2 || true
  exit 1
fi

printf '%s' $'seq 1\ngraph 1 2\n' > "$TMP/expected.stdout"
cmp "$TMP/expected.stdout" "$stdout" || {
  printf 'rewrite-semantics: stdout mismatch\n' >&2
  diff -u "$TMP/expected.stdout" "$stdout" >&2 || true
  exit 1
}
[[ ! -s "$stderr" ]] || {
  printf 'rewrite-semantics: unexpected stderr\n' >&2
  cat "$stderr" >&2
  exit 1
}

# The witness stays on the ordinary surface. No rewrite syntax, WIR dialect,
# or compiler-internal forms belong in the prototype.
if grep -Eq '\(q?rewrite\b|\bextern\b|call_(i32|i64|f32|f64|ptr|void)|const_[a-z0-9_]+|ptr_add|load_|store_|weave_rt_' \
    "$SRC"; then
  printf 'rewrite-semantics: witness leaked low-level or rewrite-syntax forms\n' >&2
  exit 1
fi
grep -Fq '(enum Soundness' "$SRC"
grep -Fq '(struct RewriteMatch' "$SRC"
grep -Fq '(core-version 3)' "$WIR"

printf 'rewrite-semantics: passed\n'
