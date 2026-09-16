#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Qualify #379 if/when/while/for/break/continue tree lowering: nested
# control composes child WIR nodes, generated loop identities are atoms,
# diagnostics stay on stderr, a mixed program runs to a known exit, and
# representative forms match frozen pre-migration WIR goldens.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-surface-control-tree-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'surface-control-tree: compiler not found: %s\n' "$WEAVEC" >&2
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
    printf 'surface-control-tree: %s was accepted\n' "$name" >&2
    exit 1
  }
  grep -Fq "$expected" "$TMP/$name.err" || {
    printf 'surface-control-tree: %s diagnostic changed\n' "$name" >&2
    cat "$TMP/$name.err" >&2
    exit 1
  }
}

run_expect() {
  local name="$1"
  local expected="$2"
  local src="${3:-$TMP/$name.weave}"

  "$WEAVEC" build "$src" -o "$TMP/$name.bin" \
    2>"$TMP/$name.build.stderr" || {
    printf 'surface-control-tree: %s failed to build\n' "$name" >&2
    cat "$TMP/$name.build.stderr" >&2
    exit 1
  }
  set +e
  "$TMP/$name.bin"
  local status="$?"
  set -e
  [[ "$status" -eq "$expected" ]] || {
    printf 'surface-control-tree: %s exited %s, expected %s\n' \
      "$name" "$status" "$expected" >&2
    exit 1
  }
}

expect_wir_equivalent() {
  local name="$1"
  local src="$ROOT/test/surface-control-tree/$name.weave"
  local expected="$ROOT/test/surface-control-tree/$name.expected.wir"
  "$WEAVEC" --frontend "$TMP/$name.wir" "$src"
  local got
  got="$(normalize_wir "$TMP/$name.wir")"
  local want
  want="$(normalize_wir "$expected")"
  [[ "$got" == "$want" ]] || {
    printf 'surface-control-tree: %s WIR diverged from pre-migration golden\n' \
      "$name" >&2
    printf 'got:  %s\n' "$got" >&2
    printf 'want: %s\n' "$want" >&2
    exit 1
  }
}

cat > "$TMP/nested.weave" <<'WEAVE'
(program
  (name "surface-control-tree-nested")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (let acc 0)
      (when true
        (set acc 1))
      (if (condition true)
        (then (do
          (set acc (op add acc 10))))
        (else (do
          (set acc 0))))
      (let i 0)
      (while (condition (op less-than i 3))
        (do
          (set acc (op add acc 1))
          (set i (op add i 1))))
      (for (range j 0 4)
        (do
          (if (condition (op equal j 1))
            (then (do (continue))))
          (if (condition (op equal j 3))
            (then (do (break))))
          (set acc (op add acc j))))
      (return acc))))
WEAVE

"$WEAVEC" --frontend "$TMP/nested.wir" "$TMP/nested.weave"
got="$(normalize_wir "$TMP/nested.wir")"
grep -Fq 'raw_text' "$TMP/nested.wir" && {
  printf 'surface-control-tree: raw_text node present\n%s\n' "$got" >&2
  exit 1
}
printf '%s\n' "$got" | grep -Fq '(when' && {
  printf 'surface-control-tree: when was not lowered to if\n%s\n' "$got" >&2
  exit 1
}
printf '%s\n' "$got" | grep -Fq '(then (do (if (condition' || {
  printf 'surface-control-tree: nested if was not a child node\n%s\n' "$got" >&2
  exit 1
}
printf '%s\n' "$got" | grep -Fq '(set l0_skip (const_i32 1))' || {
  printf 'surface-control-tree: continue flag missing\n%s\n' "$got" >&2
  exit 1
}
printf '%s\n' "$got" | grep -Fq '(set l0_run (const_i32 0))' || {
  printf 'surface-control-tree: break flag missing\n%s\n' "$got" >&2
  exit 1
}
printf '%s\n' "$got" | grep -Eq '"[^"]*\(if \(condition' && {
  printf 'surface-control-tree: nested if serialized inside a string\n%s\n' "$got" >&2
  exit 1
}

run_expect nested 16

cat > "$TMP/expr-if.weave" <<'WEAVE'
(program
  (name "surface-control-tree-expr-if")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (let pick (if (condition true) (then 40) (else 0)))
      (return (if (condition false) (then 1) (else (op add pick 2)))))))
WEAVE

"$WEAVEC" --frontend "$TMP/expr-if.wir" "$TMP/expr-if.weave"
got="$(normalize_wir "$TMP/expr-if.wir")"
printf '%s\n' "$got" | grep -Fq '(set pick (const_i32 40))' || {
  printf 'surface-control-tree: expression-if let mismatch\n%s\n' "$got" >&2
  exit 1
}
printf '%s\n' "$got" | grep -Fq '(return (add_i32 pick (const_i32 2)))' || {
  printf 'surface-control-tree: expression-if return mismatch\n%s\n' "$got" >&2
  exit 1
}
run_expect expr-if 42

cat > "$TMP/optional-else.weave" <<'WEAVE'
(program
  (name "surface-control-tree-optional-else")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (let n 1)
      (if (condition false)
        (then (do (set n 0))))
      (return n))))
WEAVE

"$WEAVEC" --frontend "$TMP/optional-else.wir" "$TMP/optional-else.weave"
got="$(normalize_wir "$TMP/optional-else.wir")"
printf '%s\n' "$got" | grep -Fq '(else (do))' || {
  printf 'surface-control-tree: optional else was not normalized\n%s\n' "$got" >&2
  exit 1
}
run_expect optional-else 1

cat > "$TMP/nested-loops.weave" <<'WEAVE'
(program
  (name "surface-control-tree-nested-loops")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (let total 0)
      (for (range i 0 3)
        (do
          (let j 0)
          (while (condition (op less-than j 3))
            (do
              (if (condition (op equal j 2))
                (then (do (break))))
              (set total (op add total 1))
              (set j (op add j 1))))))
      (return total))))
WEAVE

"$WEAVEC" --frontend "$TMP/nested-loops.wir" "$TMP/nested-loops.weave"
got="$(normalize_wir "$TMP/nested-loops.wir")"
printf '%s\n' "$got" | grep -Fq '(set l1_run (const_i32 0))' || {
  printf 'surface-control-tree: nested break target mismatch\n%s\n' "$got" >&2
  exit 1
}
run_expect nested-loops 6

cat > "$TMP/break-out.weave" <<'WEAVE'
(program
  (name "surface-control-tree-break-out")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (break)
      (return 0))))
WEAVE
expect_frontend_failure break-out 'break outside a loop'

cat > "$TMP/continue-out.weave" <<'WEAVE'
(program
  (name "surface-control-tree-continue-out")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (continue)
      (return 0))))
WEAVE
expect_frontend_failure continue-out 'continue outside a loop'

cat > "$TMP/expr-if-else.weave" <<'WEAVE'
(program
  (name "surface-control-tree-expr-if-else")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (let n i32 (if (condition true) (then 1)))
      (return n))))
WEAVE
expect_frontend_failure expr-if-else 'expression if requires an else'

cat > "$TMP/unknown-bound.weave" <<'WEAVE'
(program
  (name "surface-control-tree-unknown-bound")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (for (range i missing 4)
        (do (return 0)))
      (return 1))))
WEAVE
expect_frontend_failure unknown-bound 'range bounds must be i32'

cat > "$TMP/bool-bound.weave" <<'WEAVE'
(program
  (name "surface-control-tree-bool-bound")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (for (range i true 4)
        (do (return 0)))
      (return 1))))
WEAVE
expect_frontend_failure bool-bound 'range bounds must be i32'

# Frozen goldens were captured from the pre-#379 text renderer so this
# suite is a before/after structural-equivalence oracle, not greps.
expect_wir_equivalent if-when
expect_wir_equivalent while
expect_wir_equivalent for-break-continue
expect_wir_equivalent nested-loops
expect_wir_equivalent expr-if
expect_wir_equivalent optional-else
run_expect if-when 11 "$ROOT/test/surface-control-tree/if-when.weave"
run_expect while 3 "$ROOT/test/surface-control-tree/while.weave"
run_expect for-break-continue 2 \
  "$ROOT/test/surface-control-tree/for-break-continue.weave"
run_expect nested-loops-golden 6 \
  "$ROOT/test/surface-control-tree/nested-loops.weave"
run_expect expr-if-golden 42 "$ROOT/test/surface-control-tree/expr-if.weave"
run_expect optional-else-golden 1 \
  "$ROOT/test/surface-control-tree/optional-else.weave"

printf 'surface-control-tree: nested control, expression-if, diagnostics, and WIR equivalence passed\n'
