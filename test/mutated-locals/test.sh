#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Per-function mutated-local identity table (#388). Collection visits each
# body node once; a set resolves to the innermost let binding, not a name
# string. The old node_contains_set / node_sets_local whole-body rescans
# must not return.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-mutated-locals-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'mutated-locals: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

if grep -E -n '^\s*\(fn node_contains_set$|^\s*\(fn node_sets_local$' \
    "$ROOT/src/llvm/stmt.weave" "$ROOT/src/llvm/fn.weave"; then
  printf 'mutated-locals: repeated O(n²) walk returned\n' >&2
  exit 1
fi
grep -Fq '(call_i32 ml_collect' "$ROOT/src/llvm/fn.weave" || {
  printf 'mutated-locals: ml_collect call missing from fn.weave\n' >&2
  exit 1
}
grep -Fq '(call_i32 ml_binding_mutated' "$ROOT/src/llvm/stmt.weave" || {
  printf 'mutated-locals: ml_binding_mutated call missing from stmt.weave\n' >&2
  exit 1
}
grep -Fq 'ml_table_new' "$ROOT/src/llvm/ctx.weave" || {
  printf 'mutated-locals: ml_table_new missing from ctx.weave\n' >&2
  exit 1
}

printf 'mutated-locals: compile program runtime + write shims\n' >&2
"${CC:-clang}" -c "$ROOT/runtime/program.c" -o "$TMP/program.o"
cat > "$TMP/write.c" <<'C'
#include <stddef.h>
#include <stdint.h>
#include <unistd.h>

int32_t weave_rt_write(int32_t fd, const void *data, int64_t n) {
    if (n <= 0 || data == 0) {
        return 0;
    }
    return write((int)fd, data, (size_t)n) < 0 ? 1 : 0;
}
int32_t weave_rt_write_u8(int32_t fd, int32_t b) {
    unsigned char byte = (unsigned char)b;
    return weave_rt_write(fd, &byte, 1);
}
int32_t weave_rt_write_finish(int32_t fd) {
    (void)fd;
    return 0;
}
int32_t weave_rt_write_failed(void) {
    return 0;
}
C
"${CC:-clang}" -c "$TMP/write.c" -o "$TMP/write.o"
ld -r -o "$TMP/runtime.o" "$TMP/program.o" "$TMP/write.o"

printf 'mutated-locals: weavec build\n' >&2
"$WEAVEC" build \
    "$ROOT/src/core/extern.weave" \
    "$ROOT/src/parser/tokens.weave" \
    "$ROOT/src/parser/tree.weave" \
    "$ROOT/src/parser/lexer.weave" \
    "$ROOT/src/parser/parser.weave" \
    "$ROOT/src/core/io.weave" \
    "$ROOT/src/core/util.weave" \
    "$ROOT/src/llvm/mutated_locals.weave" \
    "$ROOT/test/mutated-locals/main.weave" \
    --runtime "$TMP/runtime.o" \
    -o "$TMP/mutated-locals-test"

printf 'mutated-locals: run unit program\n' >&2
set +e
"$TMP/mutated-locals-test"
status="$?"
set -e
if [[ "$status" -ne 0 ]]; then
  printf 'mutated-locals: unit program exited %s\n' "$status" >&2
  exit 1
fi

cat > "$TMP/shadow.wir" <<'EOF'
(core-module
  (core-version 3)
  (decls
    (fn main (params) (returns i32)
      (do
        (let x i32 (const_i32 1))
        (do
          (let x i32 (const_i32 2))
          (set x (const_i32 3)))
        (return (local_get x))))))
EOF

"$WEAVEC" --backend "$TMP/shadow.wir" "$TMP/shadow.ll" \
  2>"$TMP/shadow.stderr" || {
  printf 'mutated-locals: shadowed set rejected\n' >&2
  cat "$TMP/shadow.stderr" >&2
  exit 1
}
addr_count="$(grep -c '%x.addr = alloca' "$TMP/shadow.ll" || true)"
if [[ "$addr_count" -ne 1 ]]; then
  printf 'mutated-locals: expected one inner %%x.addr, got %s\n' \
    "$addr_count" >&2
  cat "$TMP/shadow.ll" >&2
  exit 1
fi
grep -Fq 'ret i32 1' "$TMP/shadow.ll"

cat > "$TMP/set-local.wir" <<'EOF'
(core-module
  (core-version 3)
  (decls
    (fn main (params) (returns i32)
      (do
        (let x i32 (const_i32 40))
        (set x (add_i32 (local_get x) (const_i32 2)))
        (return (local_get x))))))
EOF

"$WEAVEC" --backend "$TMP/set-local.wir" "$TMP/set-local.ll" \
  2>"$TMP/set-local.stderr" || {
  printf 'mutated-locals: ordinary set rejected\n' >&2
  cat "$TMP/set-local.stderr" >&2
  exit 1
}
grep -Fq '%x.addr = alloca' "$TMP/set-local.ll"
grep -Fq 'store i32 40, ptr %x.addr' "$TMP/set-local.ll"

printf 'mutated-locals: passed\n'
