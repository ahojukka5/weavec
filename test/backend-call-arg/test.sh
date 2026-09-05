#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Failed call-argument expressions must not become %t-1 (#265).
# The structured diagnostic stays, and no LLVM file is published.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-backend-call-arg-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'backend-call-arg: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

cat > "$TMP/bad-arg.wir" <<'EOF'
(core-module
  (core-version 3)
  (decls
    (fn add2 (params (x i32) (y i32)) (returns i32)
      (do (return (add_i32 (param_get x) (param_get y)))))
    (fn sink (params (x i32)) (returns void)
      (do (return_void)))
    (fn main (params) (returns i32)
      (do
        (call_void sink (unknown_op 1))
        (return (call_i32 add2 (unknown_op 2) (const_i32 3)))))))
EOF

set +e
"$WEAVEC" --backend "$TMP/bad-arg.wir" "$TMP/bad-arg.ll" 2>"$TMP/bad-arg.stderr"
status="$?"
set -e

if [[ "$status" -eq 0 ]]; then
  printf 'backend-call-arg: backend accepted a failed call argument\n' >&2
  exit 1
fi
if [[ "$status" -ge 128 ]]; then
  printf 'backend-call-arg: backend terminated by signal %s\n' "$status" >&2
  cat "$TMP/bad-arg.stderr" >&2
  exit 1
fi
[[ ! -e "$TMP/bad-arg.ll" ]] || {
  printf 'backend-call-arg: published LLVM after a failed argument\n' >&2
  cat "$TMP/bad-arg.ll" >&2
  exit 1
}
if grep -Fq '%t-1' "$TMP/bad-arg.stderr"; then
  printf 'backend-call-arg: diagnostic mentioned %%t-1\n' >&2
  cat "$TMP/bad-arg.stderr" >&2
  exit 1
fi
grep -Fq 'unknown expression operator: unknown_op' "$TMP/bad-arg.stderr"

# A cast in call-argument position types the call site from the cast's target
# type, not from the operand it converts (#431). Getting this wrong emitted
# `call i32 @take_i32(double %.t)`, which the assembler rejects, so the user
# saw a raw LLVM parse error against <stdin> with no span and no code.
cat > "$TMP/cast-arg.wir" <<'EOF'
(core-module
  (core-version 3)
  (decls
    (fn take_i32 (params (v i32)) (returns i32)
      (do (return (param_get v))))
    (fn take_i64 (params (v i64)) (returns i64)
      (do (return (param_get v))))
    (fn take_f64 (params (v f64)) (returns f64)
      (do (return (param_get v))))
    (fn take_f32 (params (v f32)) (returns f32)
      (do (return (param_get v))))
    (fn main (params) (returns i32)
      (do
        (let a f64 (const_f64 2.5))
        (let b f32 (const_f32 3.5))
        (let c i32 (const_i32 4))
        (let d i64 (const_i64 5))
        (let r1 i32 (call_i32 take_i32 (cast_f64_to_i32 (local_get a))))
        (let r2 i32 (call_i32 take_i32 (cast_f32_to_i32 (local_get b))))
        (let r3 i32 (call_i32 take_i32 (cast_i64_to_i32 (local_get d))))
        (let r4 i64 (call_i64 take_i64 (cast_i32_to_i64 (local_get c))))
        (let r5 f64 (call_f64 take_f64 (cast_i32_to_f64 (local_get c))))
        (let r6 f64 (call_f64 take_f64 (cast_f32_to_f64 (local_get b))))
        (let r7 f32 (call_f32 take_f32 (cast_i32_to_f32 (local_get c))))
        (let r8 f32 (call_f32 take_f32 (cast_f64_to_f32 (local_get a))))
        (return (local_get r1))))))
EOF
"$WEAVEC" --backend "$TMP/cast-arg.wir" "$TMP/cast-arg.ll" \
  2>"$TMP/cast-arg.stderr" || {
  printf 'backend-call-arg: cast-in-argument module was rejected\n' >&2
  cat "$TMP/cast-arg.stderr" >&2
  exit 1
}
# Every call site must name the cast's target type, never the source type.
while read -r expected; do
  if ! grep -Fq "$expected" "$TMP/cast-arg.ll"; then
    printf 'backend-call-arg: missing call site: %s\n' "$expected" >&2
    grep -F 'call ' "$TMP/cast-arg.ll" >&2 || true
    exit 1
  fi
done <<'EOF'
call i32 @take_i32(i32
call i64 @take_i64(i64
call double @take_f64(double
call float @take_f32(float
EOF
if grep -E 'call i32 @take_i32\((double|float|i64) ' "$TMP/cast-arg.ll"; then
  printf 'backend-call-arg: a call site was typed from the pre-cast operand\n' >&2
  exit 1
fi
if grep -E 'call (double|float) @take_f(64|32)\(i(32|64) ' "$TMP/cast-arg.ll"; then
  printf 'backend-call-arg: a float call site kept an integer operand type\n' >&2
  exit 1
fi
printf 'backend-call-arg: cast argument typing passed\n'

printf 'backend-call-arg: passed\n'
