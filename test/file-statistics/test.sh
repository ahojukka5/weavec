#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-file-statistics-XXXXXX")"
trap 'chmod -R u+rwX "$TMP" 2>/dev/null || true; rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'file-statistics: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

BIN="$TMP/file-statistics"
WIR="$TMP/file-statistics.wir"

"$WEAVEC" build \
  "$ROOT/stdlib/memory.weave" \
  "$ROOT/stdlib/process.weave" \
  "$ROOT/stdlib/parse.weave" \
  "$ROOT/stdlib/math.weave" \
  "$ROOT/stdlib/io.weave" \
  "$ROOT/stdlib/statistics.weave" \
  "$ROOT/stdlib/result.weave" \
  "$ROOT/stdlib/file.weave" \
  "$ROOT/examples/file-statistics/main.weave" \
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
    printf 'file-statistics: %s exited %s, expected %s\n' \
      "$name" "$status" "$expected_status" >&2
    cat "$stdout" >&2 || true
    cat "$stderr" >&2 || true
    exit 1
  fi
  cmp "$want_stdout" "$stdout" || {
    printf 'file-statistics: %s stdout mismatch\n' "$name" >&2
    diff -u "$want_stdout" "$stdout" >&2 || true
    exit 1
  }
  cmp "$want_stderr" "$stderr" || {
    printf 'file-statistics: %s stderr mismatch\n' "$name" >&2
    diff -u "$want_stderr" "$stderr" >&2 || true
    exit 1
  }
}

# The documented case from the issue.
printf '1\n2\n3\n4\n' > "$TMP/values.txt"
run_case documented 0 \
  $'count = 4\nmean = 2.5\nvariance = 1.25\nstddev = 1.118034\n' '' \
  "$TMP/values.txt"

# A single value has no spread.
printf '2.5\n' > "$TMP/one.txt"
run_case single 0 \
  $'count = 1\nmean = 2.5\nvariance = 0.0\nstddev = 0.0\n' '' \
  "$TMP/one.txt"

# A final line without a trailing newline still counts.
printf '5\n6' > "$TMP/no-trailing-newline.txt"
run_case no-trailing-newline 0 \
  $'count = 2\nmean = 5.5\nvariance = 0.25\nstddev = 0.5\n' '' \
  "$TMP/no-trailing-newline.txt"

printf -- '-1\n-2\n-3\n' > "$TMP/negative.txt"
run_case negative 0 \
  $'count = 3\nmean = -2.0\nvariance = 0.666667\nstddev = 0.816497\n' '' \
  "$TMP/negative.txt"

# The same values as the command-line statistics example, which shares this
# implementation, must produce the same summary.
printf '1\n2\n3\n4\n' > "$TMP/shared.txt"
run_case shared-with-argument-example 0 \
  $'count = 4\nmean = 2.5\nvariance = 1.25\nstddev = 1.118034\n' '' \
  "$TMP/shared.txt"

# Malformed lines are reported with their line number, counted from one.
printf '1\n2\nx\n4\n' > "$TMP/malformed.txt"
run_case malformed 2 '' $'error: line 3: not a number: x\n' "$TMP/malformed.txt"
printf 'oops\n2\n' > "$TMP/malformed-first.txt"
run_case malformed-first 2 '' \
  $'error: line 1: not a number: oops\n' "$TMP/malformed-first.txt"
# A blank line is not a number either, and is reported as its own line.
printf '1\n\n3\n' > "$TMP/blank.txt"
run_case blank-line 2 '' $'error: line 2: not a number: \n' "$TMP/blank.txt"

: > "$TMP/empty.txt"
run_case empty 2 '' $'error: file contains no values\n' "$TMP/empty.txt"

run_case missing 2 '' \
  "error: cannot read file: $TMP/absent.txt"$'\n' "$TMP/absent.txt"

run_case arity 2 '' $'usage: file-statistics <path>\n'

# An unreadable file reports the same failure as a missing one. Skipped when
# running as root, which ignores permission bits.
if [[ "$(id -u)" -ne 0 ]]; then
  printf '1\n2\n' > "$TMP/unreadable.txt"
  chmod 000 "$TMP/unreadable.txt"
  run_case unreadable 2 '' \
    "error: cannot read file: $TMP/unreadable.txt"$'\n' "$TMP/unreadable.txt"
  chmod 644 "$TMP/unreadable.txt"
else
  printf 'file-statistics: skipping the unreadable case as root\n'
fi

# The program must not depend on the source tree: run it from elsewhere with a
# relative path.
mkdir -p "$TMP/elsewhere"
printf '10\n20\n' > "$TMP/elsewhere/rel.txt"
(
  cd "$TMP/elsewhere"
  LC_ALL=C "$BIN" rel.txt > "$TMP/relative.stdout" 2> "$TMP/relative.stderr"
)
printf 'count = 2\nmean = 15.0\nvariance = 25.0\nstddev = 5.0\n' \
  > "$TMP/relative.expected"
cmp "$TMP/relative.expected" "$TMP/relative.stdout" || {
  printf 'file-statistics: relative path invocation mismatch\n' >&2
  diff -u "$TMP/relative.expected" "$TMP/relative.stdout" >&2 || true
  exit 1
}

# Application source stays on the ordinary surface: no descriptors, buffers, or
# user-declared libc.
if grep -Eq '\bptr\b|\bextern\b|call_(i32|i64|f32|f64|ptr|void)|const_[a-z0-9_]+|ptr_add|load_|store_|weave_rt_|fopen|fread|fclose' \
    "$ROOT/examples/file-statistics/main.weave"; then
  printf 'file-statistics: application source leaked low-level forms\n' >&2
  exit 1
fi
# The statistics formulas are reused, not copied into this example.
if grep -Eq 'sub .*mean|deviation|/ *count|total_squares' \
    "$ROOT/examples/file-statistics/main.weave"; then
  printf 'file-statistics: example recomputed the statistics formulas\n' >&2
  exit 1
fi
if ! grep -Fq 'samples_population_variance' \
    "$ROOT/examples/file-statistics/main.weave"; then
  printf 'file-statistics: example did not reuse the statistics module\n' >&2
  exit 1
fi

grep -Fq '(fn samples_population_variance' "$WIR"
grep -Fq '(fn file_open_text' "$WIR"
grep -Fq '(fn sqrt_f64' "$WIR"

printf 'file-statistics: passed\n'
