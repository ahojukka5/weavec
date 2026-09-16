#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Qualify #381 struct helper and field-op tree lowering: generated
# NAME_new/get/set helpers, new/field-get/field-set calls, and nested
# helper composition must be complete WIR subtrees. Diagnostics stay on
# stderr. Flat and nested programs must run. Frozen pre-migration WIR
# goldens are the before/after structural-equivalence oracle.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUITE="$ROOT/test/surface-struct-tree"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-surface-struct-tree-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'surface-struct-tree: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

normalize_wir() {
  tr '\n\t\r' ' ' < "$1" |
    sed -E 's/[[:space:]]+/ /g; s/\( /(/g; s/ \)/)/g; s/^ //; s/ $//'
}

expect_frontend_failure() {
  local name="$1"
  local expected="$2"
  set +e
  "$WEAVEC" --frontend "$TMP/$name.wir" "$TMP/$name.weave" 2>"$TMP/$name.err"
  local status=$?
  set -e
  [[ "$status" -ne 0 ]] || {
    printf 'surface-struct-tree: %s was accepted\n' "$name" >&2
    exit 1
  }
  grep -Fq "$expected" "$TMP/$name.err" || {
    printf 'surface-struct-tree: %s diagnostic changed\n' "$name" >&2
    cat "$TMP/$name.err" >&2
    exit 1
  }
}

expect_wir_equivalent() {
  local name="$1"
  local src="$SUITE/$name.weave"
  local expected="$SUITE/$name.expected.wir"
  "$WEAVEC" --frontend "$TMP/$name.wir" "$src"
  local got want
  got="$(normalize_wir "$TMP/$name.wir")"
  want="$(normalize_wir "$expected")"
  [[ "$got" == "$want" ]] || {
    printf 'surface-struct-tree: %s WIR diverged from pre-migration golden\n' \
      "$name" >&2
    printf 'got:  %s\n' "$got" >&2
    printf 'want: %s\n' "$want" >&2
    exit 1
  }
}

run_expect() {
  local name="$1"
  local expected="$2"
  local src="$3"
  "$WEAVEC" build "$src" -o "$TMP/$name.bin" \
    2>"$TMP/$name.build.stderr" || {
    printf 'surface-struct-tree: %s failed to build\n' "$name" >&2
    cat "$TMP/$name.build.stderr" >&2
    exit 1
  }
  set +e
  "$TMP/$name.bin"
  local status="$?"
  set -e
  [[ "$status" -eq "$expected" ]] || {
    printf 'surface-struct-tree: %s exited %s, expected %s\n' \
      "$name" "$status" "$expected" >&2
    exit 1
  }
}

expect_wir_equivalent flat
got="$(normalize_wir "$TMP/flat.wir")"
printf '%s\n' "$got" | grep -Fq '(core-version 3)' || {
  printf 'surface-struct-tree: flat WIR is not core version 3\n%s\n' "$got" >&2
  exit 1
}
if grep -Eq 'ptr_add|const_i64 (4|8)\)' "$TMP/flat.wir"; then
  printf 'surface-struct-tree: a layout number survived into WIR\n' >&2
  exit 1
fi
run_expect flat 40 "$SUITE/flat.weave"

expect_wir_equivalent nested
run_expect nested 42 "$SUITE/nested.weave"

WEAVEC_INTERNAL_SOURCE_LOCATIONS=1 "$WEAVEC" --frontend \
  "$TMP/flat-span.wir" "$SUITE/flat.weave"
python3 - "$SUITE/flat.weave" "$TMP/flat-span.wir" <<'PY'
import re
import sys
from pathlib import Path

src_path = Path(sys.argv[1])
wir_path = Path(sys.argv[2])
src = src_path.read_bytes()
wir = wir_path.read_text()


def form_span(needle: bytes) -> tuple[int, int]:
    start = src.find(needle)
    if start < 0:
        raise SystemExit(f'surface-struct-tree: missing {needle!r} in source')
    depth = 0
    for index, byte in enumerate(src[start:], start):
        if byte == ord('('):
            depth += 1
        elif byte == ord(')'):
            depth -= 1
            if depth == 0:
                return start, index + 1
    raise SystemExit(f'surface-struct-tree: unclosed {needle!r}')


def span_before(marker: str) -> tuple[int, int]:
    lines = wir.splitlines()
    for index, line in enumerate(lines):
        if marker not in line:
            continue
        if index == 0 or 'weavec-source-span-v1' not in lines[index - 1]:
            raise SystemExit(
                f'surface-struct-tree: no span before {marker!r}'
            )
        match = re.search(
            r'weavec-source-span-v1 (\d+) (\d+) (\d+)',
            lines[index - 1],
        )
        if match is None:
            raise SystemExit(
                f'surface-struct-tree: unparsable span before {marker!r}'
            )
        return int(match.group(2)), int(match.group(3))
    raise SystemExit(f'surface-struct-tree: missing {marker!r} in WIR')


struct_span = form_span(b'(struct Point')
x_span = form_span(b'(field x i32)')
y_span = form_span(b'(field y i32)')

if span_before('(struct Point') != struct_span:
    raise SystemExit('surface-struct-tree: struct declaration span drifted')
if span_before('(fn Point_new') != struct_span:
    raise SystemExit('surface-struct-tree: Point_new is not the struct node')
if span_before('(fn Point_get_x') != x_span:
    raise SystemExit('surface-struct-tree: Point_get_x is not field x')
if span_before('(fn Point_set_x') != x_span:
    raise SystemExit('surface-struct-tree: Point_set_x is not field x')
if span_before('(fn Point_get_y') != y_span:
    raise SystemExit('surface-struct-tree: Point_get_y is not field y')
if span_before('(fn Point_set_y') != y_span:
    raise SystemExit('surface-struct-tree: Point_set_y is not field y')
print('surface-struct-tree: generated helper spans match source nodes')
PY

cat > "$TMP/unknown-field.weave" <<'WEAVE'
(program
  (name "surface-struct-tree-unknown-field")
  (version "0.1")
  (extern malloc (params (size i64)) (returns ptr))
  (struct Point
    (field x i32))
  (entry main
    (params)
    (returns i32)
    (do
      (let p Point (new Point (x 1)))
      (return (field-get p y)))))
WEAVE
expect_frontend_failure unknown-field 'unknown field y for Point'

cat > "$TMP/missing-field.weave" <<'WEAVE'
(program
  (name "surface-struct-tree-missing-field")
  (version "0.1")
  (extern malloc (params (size i64)) (returns ptr))
  (struct Point
    (field x i32)
    (field y i32))
  (entry main
    (params)
    (returns i32)
    (do
      (let p Point (new Point (x 1)))
      (return 0))))
WEAVE
expect_frontend_failure missing-field 'missing field y for Point'

printf 'surface-struct-tree: flat, nested, provenance, goldens, and diagnostics passed\n'
