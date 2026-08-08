#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-float-arithmetic-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'float-arithmetic: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

BIN="$TMP/float-arithmetic"
WIR="$TMP/float-arithmetic.wir"
OUT="$TMP/stdout.txt"
ERR="$TMP/stderr.txt"
BUILD_OUT="$TMP/build.stdout"
BUILD_ERR="$TMP/build.stderr"
EXPECTED="$TMP/expected.txt"

cat > "$EXPECTED" <<'EOF'
1.5 + 2.25 = 3.75
7.0 / 2.0 = 3.5
2.5 * 4.0 - 1.0 = 9.0
EOF

if ! LC_ALL=C "$WEAVEC" build \
    "$ROOT/stdlib/io.weave" \
    "$ROOT/examples/float-arithmetic/main.weave" \
    -o "$BIN" \
    --emit-wir "$WIR" >"$BUILD_OUT" 2>"$BUILD_ERR"; then
  printf 'float-arithmetic: build failed\n' >&2
  cat "$BUILD_OUT" >&2
  cat "$BUILD_ERR" >&2
  exit 1
fi

set +e
LC_ALL=C "$BIN" >"$OUT" 2>"$ERR"
status="$?"
set -e
if [[ "$status" -ne 0 ]]; then
  printf 'float-arithmetic: program exited with status %s\n' "$status" >&2
  cat "$OUT" >&2
  cat "$ERR" >&2
  exit 1
fi

if ! cmp "$EXPECTED" "$OUT"; then
  printf '%s\n' 'float-arithmetic: stdout mismatch' >&2
  printf '%s\n' '--- expected ---' >&2
  cat "$EXPECTED" >&2
  printf '%s\n' '--- actual ---' >&2
  cat "$OUT" >&2
  exit 1
fi
if [[ -s "$ERR" ]]; then
  printf '%s\n' 'float-arithmetic: unexpected stderr' >&2
  cat "$ERR" >&2
  exit 1
fi

grep -Fq '(const_f64 1.5)' "$WIR"
grep -Fq '(const_f64 2.25)' "$WIR"
grep -Fq '(op add' "$ROOT/examples/float-arithmetic/main.weave"
grep -Fq '(op sub' "$ROOT/examples/float-arithmetic/main.weave"
grep -Fq '(op mul' "$ROOT/examples/float-arithmetic/main.weave"
grep -Fq '(op div' "$ROOT/examples/float-arithmetic/main.weave"
if grep -Eq '\(op (subtract|multiply|divide|remainder)([[:space:]]|\))' \
    "$ROOT/examples/float-arithmetic/main.weave"; then
  printf 'float-arithmetic: example used obsolete long arithmetic names\n' >&2
  exit 1
fi
if grep -Eq 'call_(void|f64)|const_f64|extern|ptr_add|load_|store_' \
    "$ROOT/examples/float-arithmetic/main.weave"; then
  printf 'float-arithmetic: example leaked low-level compiler forms\n' >&2
  exit 1
fi
if grep -Eq 'snprintf|printf|weave_rt_print_f64|basic_io' \
    "$ROOT/runtime/program.c" "$ROOT/stdlib/io.weave"; then
  printf 'float-arithmetic: numeric formatting leaked into the C runtime\n' >&2
  exit 1
fi
[[ ! -e "$ROOT/runtime/basic_io.c" ]]
grep -Fq '(fn print_f64' "$ROOT/stdlib/io.weave"
grep -Fq '(fn write_fraction6' "$ROOT/stdlib/io.weave"

printf 'float-arithmetic: passed\n'
