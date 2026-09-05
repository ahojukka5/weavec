#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# for, break, and continue (#237). Range is half-open i32. break/continue
# lower to flags around ordinary WIR while.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-loop-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'loop-control: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

expect_rejected() {
  local name="$1"
  local needle="$2"
  set +e
  "$WEAVEC" --frontend "$TMP/$name.wir" "$TMP/$name.weave" \
    >"$TMP/$name.stdout" 2>"$TMP/$name.stderr"
  local status="$?"
  set -e
  if [[ "$status" -eq 0 ]]; then
    printf 'loop-control: %s was accepted\n' "$name" >&2
    exit 1
  fi
  if ! grep -Fq "$needle" "$TMP/$name.stderr"; then
    printf 'loop-control: %s missing diagnostic\n' "$name" >&2
    printf 'expected: %s\n' "$needle" >&2
    cat "$TMP/$name.stderr" >&2
    exit 1
  fi
}

cat > "$TMP/sum.weave" <<'EOF'
(program
  (name "sum")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (let total 0)
      (for (range i 0 4)
        (do
          (set total (op add total i))))
      (return total))))
EOF
"$WEAVEC" --frontend "$TMP/sum.wir" "$TMP/sum.weave" \
  2>"$TMP/sum.stderr" || {
  printf 'loop-control: sum rejected\n' >&2
  cat "$TMP/sum.stderr" >&2
  exit 1
}
grep -Fq '(let i i32 (const_i32 0))' "$TMP/sum.wir"
grep -Fq '(lt_i32 (local_get i)' "$TMP/sum.wir"
grep -Fq '(add_i32 (local_get i) (const_i32 1))' "$TMP/sum.wir"

cat > "$TMP/break.weave" <<'EOF'
(program
  (name "break")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (let total 0)
      (for (range i 0 10)
        (do
          (if (condition (op equal i 3))
            (then (do (break))))
          (set total (op add total i))))
      (return total))))
EOF
"$WEAVEC" --frontend "$TMP/break.wir" "$TMP/break.weave" \
  2>"$TMP/break.stderr" || {
  printf 'loop-control: break rejected\n' >&2
  cat "$TMP/break.stderr" >&2
  exit 1
}
grep -Fq '(set l0_run (const_i32 0))' "$TMP/break.wir"

cat > "$TMP/continue.weave" <<'EOF'
(program
  (name "continue")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (let total 0)
      (for (range i 0 4)
        (do
          (if (condition (op equal i 1))
            (then (do (continue))))
          (set total (op add total i))))
      (return total))))
EOF
"$WEAVEC" --frontend "$TMP/continue.wir" "$TMP/continue.weave" \
  2>"$TMP/continue.stderr" || {
  printf 'loop-control: continue rejected\n' >&2
  cat "$TMP/continue.stderr" >&2
  exit 1
}
grep -Fq '(set l0_skip (const_i32 1))' "$TMP/continue.wir"

cat > "$TMP/while-plain.weave" <<'EOF'
(program
  (name "while-plain")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (let i 0)
      (while
        (condition (op less-than i 3))
        (do
          (set i (op add i 1))))
      (return i))))
EOF
"$WEAVEC" --frontend "$TMP/while-plain.wir" "$TMP/while-plain.weave" \
  2>"$TMP/while-plain.stderr" || {
  printf 'loop-control: plain while rejected\n' >&2
  cat "$TMP/while-plain.stderr" >&2
  exit 1
}
if grep -Fq 'l0_run' "$TMP/while-plain.wir"; then
  printf 'loop-control: plain while was rewritten\n' >&2
  exit 1
fi
grep -Fq '(while' "$TMP/while-plain.wir"

cat > "$TMP/while-break.weave" <<'EOF'
(program
  (name "while-break")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (let i 0)
      (while
        (condition (op less-than i 10))
        (do
          (if (condition (op equal i 2))
            (then (do (break))))
          (set i (op add i 1))))
      (return i))))
EOF
"$WEAVEC" --frontend "$TMP/while-break.wir" "$TMP/while-break.weave" \
  2>"$TMP/while-break.stderr" || {
  printf 'loop-control: while-break rejected\n' >&2
  cat "$TMP/while-break.stderr" >&2
  exit 1
}
grep -Fq '(set l0_run (const_i32 0))' "$TMP/while-break.wir"

cat > "$TMP/outside.weave" <<'EOF'
(program
  (name "outside")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (break)
      (return 0))))
EOF
expect_rejected outside 'break outside a loop'

cat > "$TMP/cont-out.weave" <<'EOF'
(program
  (name "cont-out")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (continue)
      (return 0))))
EOF
expect_rejected cont-out 'continue outside a loop'

cat > "$TMP/bad-range.weave" <<'EOF'
(program
  (name "bad-range")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (for (range i 0)
        (do (return 0)))
      (return 0))))
EOF
expect_rejected bad-range 'range needs a name, start, and end'

"$WEAVEC" analyze "$TMP/sum.weave" \
  --semantic-index-json "$TMP/sum.index.json"
python3 - "$TMP/sum.index.json" <<'PY'
import json
import pathlib
import sys

doc = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert doc["analysis"]["status"] == "complete"
assert doc["analysis"]["complete"] is True
print("loop-control: semantic index passed")
PY

# Grepping emitted WIR proves nothing about whether a loop program links and
# runs. The mis-nested lowering fixed in #427 satisfied every substring
# assertion above while emitting WIR the backend rejected, and `for`, `break`,
# and `continue` never produced a runnable program. Build and execute each
# shape, and assert its exit value.
run_expect() {
  local name="$1"
  local expected="$2"

  "$WEAVEC" build "$TMP/$name.weave" -o "$TMP/$name.bin" \
    2>"$TMP/$name.build.stderr" || {
    printf 'loop-control: %s failed to build\n' "$name" >&2
    cat "$TMP/$name.build.stderr" >&2
    exit 1
  }
  set +e
  "$TMP/$name.bin"
  local status="$?"
  set -e
  [[ "$status" -eq "$expected" ]] || {
    printf 'loop-control: %s exited %s, expected %s\n' \
      "$name" "$status" "$expected" >&2
    exit 1
  }
}

run_expect sum 6            # 0+1+2+3 over the half-open range [0,4)
run_expect break 3          # break at i == 3: 0+1+2
run_expect continue 5       # continue at i == 1: 0+2+3
run_expect while-plain 3    # hand-written while must keep working
run_expect while-break 2    # break out of a hand-written while
printf 'loop-control: execution passed\n'

printf 'loop-control: passed\n'
