#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-vector-dot-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'vector-dot: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

BIN="$TMP/vector-dot"
WIR="$TMP/vector-dot.wir"

"$WEAVEC" build \
  "$ROOT/stdlib/process.weave" \
  "$ROOT/stdlib/parse.weave" \
  "$ROOT/stdlib/io.weave" \
  "$ROOT/stdlib/vector.weave" \
  "$ROOT/examples/vector-dot/main.weave" \
  -o "$BIN" \
  --emit-wir "$WIR"

run_case() {
  local name="$1"
  local expected_status="$2"
  local expected_stdout="$3"
  local expected_stderr="$4"
  shift 4

  local stdout="$TMP/$name.stdout"
  local stderr="$TMP/$name.stderr"
  local want_stdout="$TMP/$name.expected.stdout"
  local want_stderr="$TMP/$name.expected.stderr"
  printf '%s' "$expected_stdout" > "$want_stdout"
  printf '%s' "$expected_stderr" > "$want_stderr"

  set +e
  LC_ALL=C "$BIN" "$@" >"$stdout" 2>"$stderr"
  local status="$?"
  set -e

  if [[ "$status" -ne "$expected_status" ]]; then
    printf 'vector-dot: %s exited %s, expected %s\n' \
      "$name" "$status" "$expected_status" >&2
    cat "$stdout" >&2 || true
    cat "$stderr" >&2 || true
    exit 1
  fi
  cmp "$want_stdout" "$stdout" || {
    printf 'vector-dot: %s stdout mismatch\n' "$name" >&2
    diff -u "$want_stdout" "$stdout" >&2 || true
    exit 1
  }
  cmp "$want_stderr" "$stderr" || {
    printf 'vector-dot: %s stderr mismatch\n' "$name" >&2
    diff -u "$want_stderr" "$stderr" >&2 || true
    exit 1
  }
}

run_case general 0 $'32.0\n' '' 1 2 3 4 5 6
run_case orthogonal 0 $'0.0\n' '' 1 0 0 0 1 0
run_case parallel 0 $'28.0\n' '' 1 2 3 2 4 6
run_case negative 0 $'-14.0\n' '' 1 2 3 -1 -2 -3
run_case fractional 0 $'4.5\n' '' 0.5 1.5 2.5 1 1 1
run_case zero 0 $'0.0\n' '' 0 0 0 1 2 3
run_case arity 2 '' \
  $'usage: vector-dot <ax> <ay> <az> <bx> <by> <bz>\n' 1 2 3
run_case malformed 2 '' \
  $'error: components must be numbers\n' 1 2 3 4 5 nope

# Application source stays on the ordinary surface. Allocation, field layout,
# and host mechanics are confined to the reusable standard modules.
if grep -Eq '\bptr\b|\bextern\b|call_(i32|i64|f32|f64|ptr|void)|const_[a-z0-9_]+|ptr_add|load_|store_|weave_rt_' \
    "$ROOT/examples/vector-dot/main.weave"; then
  printf 'vector-dot: application source leaked low-level forms\n' >&2
  exit 1
fi

# Vec3 is nominal: an untyped pointer must not satisfy a Vec3 parameter, so two
# vectors cannot be confused through a raw alias in user code.
cat > "$TMP/alias.weave" <<'EOF'
(program
  (name "vector-dot-alias")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (let loose ptr null)
      (let product f64 (call vec3_dot loose loose))
      (return (cast i32 product)))))
EOF
set +e
"$WEAVEC" build \
  "$ROOT/stdlib/vector.weave" \
  "$TMP/alias.weave" \
  -o "$TMP/alias" 2>"$TMP/alias.stderr"
alias_status="$?"
set -e
if [[ "$alias_status" -eq 0 ]]; then
  printf 'vector-dot: a raw pointer satisfied a Vec3 parameter\n' >&2
  exit 1
fi
if [[ -e "$TMP/alias" ]]; then
  printf 'vector-dot: rejected alias program published an executable\n' >&2
  exit 1
fi

grep -Fq '(fn vec3_dot' "$WIR"
grep -Fq '(fn program_main' "$WIR"
grep -Fq '(fn parse_f64' "$WIR"

printf 'vector-dot: passed\n'
