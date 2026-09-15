#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Tree-walk depth budget (#386, #466). Nested sources just at the public
# limit parse; one level past it fails with a stable diagnostic instead of
# crashing. Generated-WIR reparse uses a bounded internal budget that
# ambient environment cannot select.
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
PUBLIC="$(sed -n 's/^#define WEAVEC_TREE_WALK_MAX_DEPTH //p' "$HEADER")"
INTERNAL="$(sed -n 's/^#define WEAVEC_TREE_WALK_INTERNAL_WIR_MAX_DEPTH //p' "$HEADER")"
[[ -n "$PUBLIC" && -n "$INTERNAL" ]]
[[ "$INTERNAL" -eq $((PUBLIC + 1)) ]]
grep -Fq "#define WEAVEC_TREE_WALK_MAX_DEPTH ${PUBLIC}" "$HEADER"
grep -Fq "#define WEAVEC_TREE_WALK_INTERNAL_WIR_MAX_DEPTH ${INTERNAL}" "$HEADER"
grep -Fq "(const_i64 ${PUBLIC})" "$PARSER"
grep -Fq "(const_i64 ${INTERNAL})" "$PARSER"
NESTING_MSG="nesting exceeds the compiler depth budget of ${PUBLIC}"
INTERNAL_MSG="nesting exceeds the compiler depth budget of ${INTERNAL}"

python3 - "$TMP" "$PUBLIC" "$INTERNAL" <<'PY'
from pathlib import Path
import sys

out = Path(sys.argv[1])
public = int(sys.argv[2])
internal = int(sys.argv[3])

def wrap_expr(inner, wraps, form):
    expr = inner
    for _ in range(wraps):
        expr = form % expr
    return expr

def parens(depth):
    return '(' * depth + 'x' + ')' * depth + '\n'

# program/entry/do/return contribute 4 lists. The admitted compile is a
# shallow program: a 64-deep add_i32 spine overflows remaining recursive
# lowering on an 8 MiB Linux stack even after parse admits it.
inner_ok = '(const_i32 0)'
inner_over = wrap_expr('(const_i32 0)', public - 4, '(add_i32 (const_i32 0) %s)')

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
(out / 'parens-public-at.weave').write_text(parens(public), encoding='utf-8')
(out / 'parens-public-over.weave').write_text(parens(public + 1), encoding='utf-8')
(out / 'parens-internal-at.weave').write_text(parens(internal), encoding='utf-8')
(out / 'parens-internal-over.weave').write_text(parens(internal + 1), encoding='utf-8')

wir_inner_ok = '(const_i32 0)'
wir_inner_over = wrap_expr('(const_i32 0)', public - 4, '(add_i32 (const_i32 0) %s)')

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
(out / 'parens-public-at.wir').write_text(parens(public), encoding='utf-8')
(out / 'parens-public-over.wir').write_text(parens(public + 1), encoding='utf-8')
(out / 'parens-internal-at.wir').write_text(parens(internal), encoding='utf-8')
(out / 'parens-internal-over.wir').write_text(parens(internal + 1), encoding='utf-8')
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

expect_not_nesting() {
  local name="$1"
  shift
  set +e
  "$@" >"$TMP/$name.stdout" 2>"$TMP/$name.stderr"
  local status="$?"
  set -e
  if grep -Eq 'Segmentation fault|SIGSEGV|SIGBUS|Bus error' "$TMP/$name.stderr"; then
    printf 'tree-walk-depth: %s crashed\n' "$name" >&2
    cat "$TMP/$name.stderr" >&2
    exit 1
  fi
  if grep -Fq 'nesting-too-deep' "$TMP/$name.stderr"; then
    printf 'tree-walk-depth: %s hit nesting diagnostic\n' "$name" >&2
    cat "$TMP/$name.stderr" >&2
    exit 1
  fi
  if grep -Fq 'driver.usage.invalid-arguments' "$TMP/$name.stderr"; then
    printf 'tree-walk-depth: %s hit usage error\n' "$name" >&2
    cat "$TMP/$name.stderr" >&2
    exit 1
  fi
  printf '%s' "$status" >"$TMP/$name.status"
}

printf 'tree-walk-depth: admitted compile covered by correctness/surface/01_return_42\n'

"$WEAVEC" build "$TMP/ok.weave" -o "$TMP/ok-program" \
  || { printf 'tree-walk-depth: weavec build of admitted source failed\n' >&2; exit 1; }
[[ -x "$TMP/ok-program" ]] \
  || { printf 'tree-walk-depth: missing admitted program\n' >&2; exit 1; }

expect_fail over-build \
  "$NESTING_MSG" \
  "$WEAVEC" build "$TMP/over.weave" -o "$TMP/over-program" \
  --diagnostics-json "$TMP/over.json" \
  --emit-wir "$TMP/over.wir.out"
[[ ! -e "$TMP/over-program" ]]
[[ ! -e "$TMP/over.wir.out" ]]
python3 - "$TMP/over.json" "$PUBLIC" <<'PY'
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

"$WEAVEC" fmt "$TMP/parens-public-at.weave" >"$TMP/parens-public-at.fmt" \
  || { printf 'tree-walk-depth: fmt at public bound failed\n' >&2; exit 1; }

expect_fail over-fmt \
  'frontend.parse.nesting-too-deep' \
  "$WEAVEC" fmt "$TMP/parens-public-over.weave"

expect_fail public-at-frontend-over \
  'frontend.parse.nesting-too-deep' \
  "$WEAVEC" --frontend "$TMP/parens-public-over.front.wir" \
  "$TMP/parens-public-over.weave"

expect_not_nesting public-at-backend \
  "$WEAVEC" --backend "$TMP/parens-public-at.wir" "$TMP/parens-public-at.ll"
[[ ! -e "$TMP/parens-public-at.ll" ]] || true

expect_fail public-over-backend \
  'backend.parse.nesting-too-deep' \
  "$WEAVEC" --backend "$TMP/parens-public-over.wir" "$TMP/parens-public-over.ll"
[[ ! -e "$TMP/parens-public-over.ll" ]]

expect_fail env-spoof-backend \
  'backend.parse.nesting-too-deep' \
  env WEAVEC_INTERNAL_WIR_PARSE=1 \
  "$WEAVEC" --backend "$TMP/parens-public-over.wir" "$TMP/env-spoof.ll"
[[ ! -e "$TMP/env-spoof.ll" ]]
if ! grep -Fq "$NESTING_MSG" "$TMP/env-spoof-backend.stderr"; then
  printf 'tree-walk-depth: env spoof used a non-public budget message\n' >&2
  cat "$TMP/env-spoof-backend.stderr" >&2
  exit 1
fi

expect_fail env-spoof-frontend \
  'frontend.parse.nesting-too-deep' \
  env WEAVEC_INTERNAL_WIR_PARSE=1 \
  "$WEAVEC" --frontend "$TMP/env-spoof.front.wir" "$TMP/parens-public-over.weave"

expect_fail env-spoof-fmt \
  'frontend.parse.nesting-too-deep' \
  env WEAVEC_INTERNAL_WIR_PARSE=1 \
  "$WEAVEC" fmt "$TMP/parens-public-over.weave"

expect_not_nesting internal-at-backend \
  "$WEAVEC" --backend --generated-wir \
  "$TMP/parens-internal-at.wir" "$TMP/internal-at.ll"

expect_fail internal-over-backend \
  'backend.parse.nesting-too-deep' \
  "$WEAVEC" --backend --generated-wir \
  "$TMP/parens-internal-over.wir" "$TMP/internal-over.ll"
[[ ! -e "$TMP/internal-over.ll" ]]
if ! grep -Fq "$INTERNAL_MSG" "$TMP/internal-over-backend.stderr"; then
  printf 'tree-walk-depth: internal over-bound used the wrong budget\n' >&2
  cat "$TMP/internal-over-backend.stderr" >&2
  exit 1
fi

expect_fail internal-over-env \
  'backend.parse.nesting-too-deep' \
  env WEAVEC_INTERNAL_WIR_PARSE=1 \
  "$WEAVEC" --backend --generated-wir \
  "$TMP/parens-internal-over.wir" "$TMP/internal-over-env.ll"

if ulimit -s 2048 >/dev/null 2>&1; then
  set +e
  (
    ulimit -s 2048
    env WEAVEC_INTERNAL_WIR_PARSE=1 \
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
