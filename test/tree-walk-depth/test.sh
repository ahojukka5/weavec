#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Tree-walk depth budget (#386). Nested sources just at the limit parse;
# one level past it fails with a stable diagnostic instead of crashing.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-tree-walk-depth-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'tree-walk-depth: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

HEADER="$ROOT/runtime/tree_walk_depth.h"
PARSER="$ROOT/src/parser/parser.weave"
MAX_DEPTH="$(sed -n 's/^#define WEAVEC_TREE_WALK_MAX_DEPTH //p' "$HEADER")"
[[ -n "$MAX_DEPTH" ]]
grep -Fq "#define WEAVEC_TREE_WALK_MAX_DEPTH ${MAX_DEPTH}" "$HEADER"
grep -Fq "(const_i64 ${MAX_DEPTH})" "$PARSER"
NESTING_MSG="nesting exceeds the compiler depth budget of ${MAX_DEPTH}"

python3 - "$TMP" "$MAX_DEPTH" <<'PY'
from pathlib import Path
import sys

out = Path(sys.argv[1])
max_depth = int(sys.argv[2])

def wrap_expr(inner, wraps, form):
    expr = inner
    for _ in range(wraps):
        expr = form % expr
    return expr

# program/entry/do/return contribute 4 lists. The admitted compile is a
# shallow program: a 64-deep add_i32 spine overflows remaining recursive
# lowering on an 8 MiB Linux stack even after parse admits it.
inner_ok = '(const_i32 0)'
inner_over = wrap_expr('(const_i32 0)', max_depth - 4, '(add_i32 (const_i32 0) %s)')

def program(inner):
    return (
        '(program\n'
        '  (name "tree-walk-depth")\n'
        '  (version "0.1")\n'
        '  (entry main\n'
        '    (params)\n'
        '    (returns i32)\n'
        '    (do (return %s))))\n' % inner
    )

(out / 'ok.weave').write_text(program(inner_ok), encoding='utf-8')
(out / 'over.weave').write_text(program(inner_over), encoding='utf-8')
(out / 'parens-over.weave').write_text(
    '(' * (max_depth + 1) + 'x' + ')' * (max_depth + 1) + '\n',
    encoding='utf-8',
)

wir_inner_ok = '(const_i32 0)'
wir_inner_over = wrap_expr('(const_i32 0)', max_depth - 4, '(add_i32 (const_i32 0) %s)')

def wir(inner):
    return (
        '(core-module\n'
        '  (core-version 3)\n'
        '  (decls\n'
        '    (fn main (params) (returns i32)\n'
        '      (do (return %s)))))\n' % inner
    )

(out / 'ok.wir').write_text(wir(wir_inner_ok), encoding='utf-8')
(out / 'over.wir').write_text(wir(wir_inner_over), encoding='utf-8')
PY

expect_fail() {
  local name="$1"
  local expected="$2"
  shift 2
  set +e
  "$@" >"$TMP/$name.stdout" 2>"$TMP/$name.stderr"
  local status="$?"
  set -e
  if [[ "$status" -eq 0 ]]; then
    printf 'tree-walk-depth: %s unexpectedly succeeded\n' "$name" >&2
    exit 1
  fi
  if [[ -s "$TMP/$name.stdout" ]]; then
    printf 'tree-walk-depth: %s wrote stdout\n' "$name" >&2
    cat "$TMP/$name.stdout" >&2
    exit 1
  fi
  if ! grep -Fq "$expected" "$TMP/$name.stderr"; then
    printf 'tree-walk-depth: %s missing diagnostic\n' "$name" >&2
    cat "$TMP/$name.stderr" >&2
    exit 1
  fi
  if grep -Eq 'Segmentation fault|SIGSEGV|SIGBUS|Bus error' "$TMP/$name.stderr"; then
    printf 'tree-walk-depth: %s crashed\n' "$name" >&2
    exit 1
  fi
}

printf 'tree-walk-depth: admitted compile covered by correctness/surface/01_return_42\n'

expect_fail over-build \
  "$NESTING_MSG" \
  "$WEAVEC" build "$TMP/over.weave" -o "$TMP/over-program" \
  --diagnostics-json "$TMP/over.json" \
  --emit-wir "$TMP/over.wir.out"
[[ ! -e "$TMP/over-program" ]]
[[ ! -e "$TMP/over.wir.out" ]]
python3 - "$TMP/over.json" "$MAX_DEPTH" <<'PY'
import json
import sys

document = json.load(open(sys.argv[1]))
assert document["status"] == "failed"
assert document["phase"] == "frontend"
assert document["exit_code"] == 10
entry = document["diagnostics"][0]
assert entry["code"] == "frontend.parse.nesting-too-deep"
assert f"depth budget of {sys.argv[2]}" in entry["message"]
assert entry["span"] is not None
PY

expect_fail over-frontend \
  'frontend.parse.nesting-too-deep' \
  "$WEAVEC" --frontend "$TMP/over.front.wir" "$TMP/over.weave"
[[ ! -e "$TMP/over.front.wir" ]]

"$WEAVEC" --frontend "$TMP/ok.front.wir" "$TMP/ok.weave" \
  || { printf 'tree-walk-depth: --frontend of admitted source failed\n' >&2; exit 1; }
[[ -s "$TMP/ok.front.wir" ]] \
  || { printf 'tree-walk-depth: empty frontend WIR\n' >&2; exit 1; }

"$WEAVEC" --backend "$TMP/ok.wir" "$TMP/ok.ll" \
  || { printf 'tree-walk-depth: --backend of admitted WIR failed\n' >&2; exit 1; }
[[ -s "$TMP/ok.ll" ]] \
  || { printf 'tree-walk-depth: empty backend LLVM\n' >&2; exit 1; }

expect_fail over-backend \
  'backend.parse.nesting-too-deep' \
  "$WEAVEC" --backend "$TMP/over.wir" "$TMP/over.ll"
[[ ! -e "$TMP/over.ll" ]]

"$WEAVEC" fmt "$TMP/ok.weave" >"$TMP/ok.fmt" \
  || { printf 'tree-walk-depth: fmt of admitted source failed\n' >&2; exit 1; }

expect_fail over-fmt \
  'frontend.parse.nesting-too-deep' \
  "$WEAVEC" fmt "$TMP/parens-over.weave"

if ulimit -s 2048 >/dev/null 2>&1; then
  set +e
  (
    ulimit -s 2048
    "$WEAVEC" build "$TMP/over.weave" -o "$TMP/over-ulimit" \
      >"$TMP/ulimit.stdout" 2>"$TMP/ulimit.stderr"
  )
  ulimit_status="$?"
  set -e
  if [[ "$ulimit_status" -eq 0 ]]; then
    printf 'tree-walk-depth: reduced-stack over-limit build succeeded\n' >&2
    exit 1
  fi
  if ! grep -Fq "$NESTING_MSG" \
      "$TMP/ulimit.stderr"; then
    printf 'tree-walk-depth: reduced-stack missing diagnostic\n' >&2
    cat "$TMP/ulimit.stderr" >&2
    exit 1
  fi
  if grep -Eq 'Segmentation fault|SIGSEGV|SIGBUS|Bus error' \
      "$TMP/ulimit.stderr"; then
    printf 'tree-walk-depth: reduced-stack crashed\n' >&2
    exit 1
  fi
else
  printf 'tree-walk-depth: ulimit -s not available; skipped reduced-stack\n'
fi

printf 'tree-walk-depth: passed\n'
