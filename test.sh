#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
WIR_TEST_DIR="$ROOT/test/correctness/wir"
SURFACE_TEST_DIR="$ROOT/test/correctness/surface"
BUILD_DIR="${WEAVEC_TEST_BUILD_DIR:-$ROOT/build/test/correctness}"
LL_DIR="$BUILD_DIR/ll"
BC_DIR="$BUILD_DIR/bc"
BIN_DIR="$BUILD_DIR/bin"
WIR_FROM_SURFACE_DIR="$BUILD_DIR/wir"
RUNTIME_C="$ROOT/runtime/program.c"

pass_count=0
fail_count=0

log() {
  printf '[weavec-test] %s\n' "$*"
}

fail() {
  printf '[weavec-test] error: %s\n' "$*" >&2
  fail_count=$((fail_count + 1))
}

normalize_wir() {
  tr '\n\t\r' ' ' < "$1" |
    sed -E 's/[[:space:]]+/ /g; s/\( /(/g; s/ \)/)/g; s/^ //; s/ $//'
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    printf '[weavec-test] missing required tool: %s\n' "$1" >&2
    exit 1
  }
}

needs_contract_runtime() {
  case "$1" in
    *_contract_*|contract_* ) return 0 ;;
    * ) return 1 ;;
  esac
}

link_surface_bin() {
  local ll="$1"
  local bin="$2"
  local name="$3"
  if needs_contract_runtime "$name"; then
    clang "$ll" "$RUNTIME_C" -o "$bin"
  else
    clang "$ll" -o "$bin"
  fi
}

expected_exit() {
  case "$1" in
    01_return_constant) echo 0 ;;
    02_return_42) echo 42 ;;
    03_add) echo 42 ;;
    04_one_arg_function) echo 42 ;;
    05_let_local) echo 42 ;;
    06_set_local) echo 42 ;;
    07_if) echo 42 ;;
    08_while) echo 42 ;;
    09_two_arg_function) echo 42 ;;
    10_string_literal) echo 42 ;;
    11_const_i64) echo 42 ;;
    12_i64_arithmetic) echo 42 ;;
    13_i64_comparisons) echo 42 ;;
    14_bool_ops) echo 42 ;;
    15_ptr_null) echo 42 ;;
    16_extern_malloc_free) echo 42 ;;
    17_ptr_add_store_load_i64) echo 42 ;;
    18_store_load_i8) echo 42 ;;
    19_call_void) echo 42 ;;
    20_call_i64) echo 42 ;;
    21_call_ptr) echo 42 ;;
    22_return_void) echo 42 ;;
    23_mod_i32) echo 2 ;;
    24_buffer_like_smoke) echo 42 ;;
    25_ptr_params_call_i32) echo 42 ;;
    26_bool_return) echo 42 ;;
    27_three_arg_function) echo 42 ;;
    28_i32_memory_and_cast) echo 42 ;;
    29_const_string_ptr) echo 42 ;;
    30_i64_sub_eq) echo 42 ;;
    31_not_bool) echo 42 ;;
    32_codegen_join_and_i64_arg) echo 42 ;;
    33_store_i8_temp) echo 42 ;;
    34_ge_i32) echo 42 ;;
    35_sub_i32) echo 42 ;;
    36_mul_i32) echo 42 ;;
    37_div_i32) echo 42 ;;
    38_i32_comparisons_full) echo 42 ;;
    39_i64_ge_gt) echo 42 ;;
    40_call_bool_direct) echo 42 ;;
    41_load_store_ptr) echo 42 ;;
    42_empty_do) echo 42 ;;
    43_if_fallthrough_join) echo 42 ;;
    44_while_zero_iterations) echo 42 ;;
    45_nested_while) echo 42 ;;
    46_forward_function_call) echo 42 ;;
    47_multiple_externs_used_subset) echo 42 ;;
    48_string_escape) echo 42 ;;
    49_negative_i32_literal) echo 42 ;;
    54_debug_marker) echo 42 ;;
    55_integration_nested_control_flow) echo 75 ;;
    56_integration_multi_function_chain) echo 35 ;;
    57_integration_memory_flow) echo 100 ;;
    60_discard_call_i32) echo 42 ;;
    66_typed_array_at) echo 42 ;;
    *) return 1 ;;
  esac
}

is_positive_wir_test() {
  expected_exit "$1" >/dev/null
}

expected_backend_error() {
  case "$1" in
    51_unknown_operator) echo "unknown expression operator: banana_i32" ;;
    52_wrong_arity_add_i32_too_few) echo "wrong arity for add_i32: expected 2, got 1" ;;
    53_wrong_arity_add_i32_too_many) echo "wrong arity for add_i32: expected 2, got 3" ;;
    61_wrong_arity_let_too_few) echo "wrong arity for let: expected 3, got 2" ;;
    62_wrong_arity_return_too_few) echo "wrong arity for return: expected 1, got 0" ;;
    63_wrong_arity_if_too_few) echo "wrong arity for if: expected 3, got 2" ;;
    64_wrong_arity_fn_too_few) echo "wrong arity for fn: expected 4, got 3" ;;
    65_unknown_statement) echo "unknown expression operator: mystery_stmt" ;;
    67_core_version_1_rejected) echo "expected exactly one (core-version 2), got 1" ;;
    68_core_version_missing) echo "expected exactly one (core-version 2), found 0 declarations" ;;
    69_core_version_duplicate) echo "expected exactly one (core-version 2), found 2 declarations" ;;
    70_wrong_root) echo "expected WIR core-module root" ;;
    71_core_version_missing_value) echo "expected exactly one (core-version 2), missing version value" ;;
    72_core_version_string_rejected) echo "expected exactly one (core-version 2), got" ;;
    *) return 1 ;;
  esac
}

is_backend_fail_wir_test() {
  expected_backend_error "$1" >/dev/null
}

[[ -x "$WEAVEC" ]] || {
  printf '[weavec-test] build/weavec not found; run ./build.sh first\n' >&2
  exit 1
}

require_tool llvm-as
require_tool clang

mkdir -p "$LL_DIR" "$BC_DIR" "$BIN_DIR" "$WIR_FROM_SURFACE_DIR"


log "reject implicit backend syntax"
legacy_weavec="$WEAVEC"
legacy_ll="$LL_DIR/implicit_backend_should_fail.ll"
rm -f "$legacy_ll"
set +e
"$legacy_weavec" "$WIR_TEST_DIR/01_return_constant.wir" "$legacy_ll" \
  >/dev/null 2>&1
legacy_status="$?"
set -e
if [[ "$legacy_status" -eq 0 ]]; then
  fail "implicit backend syntax unexpectedly succeeded"
elif [[ -e "$legacy_ll" ]]; then
  fail "implicit backend syntax created output"
else
  log "ok explicit backend CLI required"
  pass_count=$((pass_count + 1))
fi

for src in "$WIR_TEST_DIR"/*.wir; do
  name="$(basename "$src" .wir)"

  if ! is_positive_wir_test "$name"; then
    log "skip $name"
    continue
  fi

  ll="$LL_DIR/$name.ll"
  bc="$BC_DIR/$name.bc"
  bin="$BIN_DIR/$name"
  expected="$(expected_exit "$name")"

  log "compile $name"

  if ! "$WEAVEC" --backend "$src" "$ll"; then
    fail "$name: weavec failed"
    continue
  fi

  if ! llvm-as "$ll" -o "$bc"; then
    fail "$name: llvm-as failed"
    continue
  fi

  if ! link_surface_bin "$ll" "$bin" "$name"; then
    fail "$name: clang failed"
    continue
  fi

  set +e
  "$bin"
  actual="$?"
  set -e

  if [[ "$actual" != "$expected" ]]; then
    fail "$name: expected exit $expected, got $actual"
    continue
  fi

  log "ok $name"
  pass_count=$((pass_count + 1))
done

for src in "$WIR_TEST_DIR"/*.wir; do
  name="$(basename "$src" .wir)"

  if ! is_backend_fail_wir_test "$name"; then
    continue
  fi

  ll="$LL_DIR/$name.ll"
  err="$BUILD_DIR/$name.err"
  expected_error="$(expected_backend_error "$name")"

  log "backend-fail $name"
  rm -f "$ll" "$err"

  set +e
  "$WEAVEC" --backend "$src" "$ll" 2>"$err"
  status="$?"
  set -e

  if [[ "$status" -eq 0 ]]; then
    fail "$name: expected backend failure"
    continue
  fi

  if [[ -e "$ll" ]]; then
    fail "$name: backend failure created output"
    continue
  fi

  if ! grep -F "$expected_error" "$err" >/dev/null 2>&1; then
    fail "$name: expected diagnostic '$expected_error'"
    continue
  fi

  log "ok backend-fail $name"
  pass_count=$((pass_count + 1))
done

surface_smoke_tests=(
  01_return_42
  02_return_constant
  03_return_42
  04_add_i32
  05_one_arg_function
  06_let_local
  07_set_local
  08_if
  09_while
  10_two_arg_function
  11_string_literal
  12_const_i64
  13_i64_arithmetic
  14_i64_comparisons
  15_bool_ops
  16_ptr_null
  17_extern_malloc_free
  18_ptr_add_store_load_i64
  19_store_load_i8
  20_call_void
  21_call_i64
  22_call_ptr
  23_return_void
  24_mod_i32
  25_buffer_like_smoke
  26_ptr_params_call_i32
  27_bool_return
  28_three_arg_function
  29_i32_memory_and_cast
  30_const_string_ptr
  31_i64_sub_eq
  32_not_bool
  33_codegen_join_and_i64_arg
  34_store_i8_temp
  35_ge_i32
  36_sub_i32
  37_mul_i32
  38_div_i32
  39_i32_comparisons_full
  40_i64_ge_gt
  41_call_bool_direct
  42_load_store_ptr
  43_empty_do
  44_if_fallthrough_join
  45_while_zero_iterations
  46_nested_while
  47_forward_function_call
  48_multiple_externs_used_subset
  49_string_escape
  50_negative_i32_literal
  51_debug_marker
  52_integration_nested_control_flow
  53_integration_multi_function_chain
  54_integration_memory_flow
  55_new_operators
  56_extern_decl
  57_struct_basic
  58_const_decl
  59_bare_identifier_operands
  60_let_literal_sugar
  61_contract_requires_ok
  63_contract_ensures_ok
  64_contract_ensures_multi_return
  67_contract_pure_ok
  69_contract_no_alloc_ok
  73_contract_pure_cycle_ok
)

contract_compile_fail_tests=(
  68_contract_pure_fail
  70_contract_no_alloc_fail
  71_contract_pure_indirect_fail
  72_contract_no_alloc_indirect_fail
  audit_effect_malformed
)

contract_fail_tests=(
  62_contract_requires_fail
  65_contract_ensures_fail
  66_contract_clamp_requires_fail
)

for name in "${surface_smoke_tests[@]}"; do
  src="$SURFACE_TEST_DIR/$name.weave"
  expected_wir="$SURFACE_TEST_DIR/$name.expected.wir"
  wir="$WIR_FROM_SURFACE_DIR/$name.wir"
  ll="$LL_DIR/surface_$name.ll"
  bc="$BC_DIR/surface_$name.bc"
  bin="$BIN_DIR/surface_$name"
  expected=42
  case "$name" in
    02_return_constant) expected=0 ;;
    04_add_i32) expected=42 ;;
    05_one_arg_function) expected=43 ;;
    24_mod_i32) expected=2 ;;
    39_i32_comparisons_full) expected=42 ;;
    52_integration_nested_control_flow) expected=75 ;;
    53_integration_multi_function_chain) expected=35 ;;
    54_integration_memory_flow) expected=100 ;;
    55_new_operators) expected=40 ;;
    58_const_decl) expected=42 ;;
    61_contract_requires_ok) expected=42 ;;
    63_contract_ensures_ok) expected=42 ;;
    64_contract_ensures_multi_return) expected=10 ;;
    67_contract_pure_ok) expected=42 ;;
    69_contract_no_alloc_ok) expected=42 ;;
    73_contract_pure_cycle_ok) expected=42 ;;
  esac

  log "frontend $name"

  if ! "$WEAVEC" --frontend "$wir" "$src"; then
    fail "$name: frontend failed"
    continue
  fi

  if ! diff -u <(normalize_wir "$expected_wir") <(normalize_wir "$wir"); then
    fail "$name: frontend WIR golden mismatch"
    continue
  fi

  if ! "$WEAVEC" --backend "$wir" "$ll"; then
    fail "$name: backend failed"
    continue
  fi

  if ! llvm-as "$ll" -o "$bc"; then
    fail "$name: llvm-as failed"
    continue
  fi

  if ! link_surface_bin "$ll" "$bin" "$name"; then
    fail "$name: clang failed"
    continue
  fi

  set +e
  "$bin"
  actual="$?"
  set -e

  if [[ "$actual" != "$expected" ]]; then
    fail "$name: expected exit $expected, got $actual"
    continue
  fi

  log "ok frontend $name"
  pass_count=$((pass_count + 1))
done

for name in "${contract_fail_tests[@]}"; do
  src="$SURFACE_TEST_DIR/$name.weave"
  wir="$WIR_FROM_SURFACE_DIR/$name.wir"
  ll="$LL_DIR/surface_$name.ll"
  bc="$BC_DIR/surface_$name.bc"
  bin="$BIN_DIR/surface_$name"

  log "contract-fail $name"

  if ! "$WEAVEC" --frontend "$wir" "$src"; then
    fail "$name: frontend failed"
    continue
  fi

  if ! "$WEAVEC" --backend "$wir" "$ll"; then
    fail "$name: backend failed"
    continue
  fi

  if ! llvm-as "$ll" -o "$bc"; then
    fail "$name: llvm-as failed"
    continue
  fi

  if ! link_surface_bin "$ll" "$bin" "$name"; then
    fail "$name: clang failed"
    continue
  fi

  set +e
  "$bin" 2>"$BUILD_DIR/$name.stderr"
  actual="$?"
  set -e

  if [[ "$actual" != "1" ]]; then
    fail "$name: expected exit 1, got $actual"
    continue
  fi

  if ! grep -F "contract failed:" "$BUILD_DIR/$name.stderr" >/dev/null 2>&1; then
    fail "$name: expected contract failed message on stderr"
    continue
  fi

  log "ok contract-fail $name"
  pass_count=$((pass_count + 1))
done

for name in "${contract_compile_fail_tests[@]}"; do
  case "$name" in
    audit_effect_malformed)
      src="$ROOT/test/correctness/contracts/$name.weave"
      ;;
    *)
      src="$SURFACE_TEST_DIR/$name.weave"
      ;;
  esac
  wir="$WIR_FROM_SURFACE_DIR/$name.wir"

  log "contract-compile-fail $name"

  set +e
  "$WEAVEC" --frontend --strict-contracts "$wir" "$src" 2>"$BUILD_DIR/$name.stderr"
  actual="$?"
  set -e

  if [[ "$actual" == "0" ]]; then
    fail "$name: expected frontend failure, got success"
    continue
  fi

  case "$name" in
    68_contract_pure_fail)
      if ! grep -F "contract failed: pure" "$BUILD_DIR/$name.stderr" >/dev/null 2>&1; then
        fail "$name: expected contract failed: pure on stderr"
        continue
      fi
      ;;
    70_contract_no_alloc_fail)
      if ! grep -F "contract failed: no_alloc" "$BUILD_DIR/$name.stderr" >/dev/null 2>&1; then
        fail "$name: expected contract failed: no_alloc on stderr"
        continue
      fi
      ;;
    71_contract_pure_indirect_fail)
      if ! grep -F "contract failed: pure" "$BUILD_DIR/$name.stderr" >/dev/null 2>&1; then
        fail "$name: expected contract failed: pure on stderr"
        continue
      fi
      ;;
    72_contract_no_alloc_indirect_fail)
      if ! grep -F "contract failed: no_alloc" "$BUILD_DIR/$name.stderr" >/dev/null 2>&1; then
        fail "$name: expected contract failed: no_alloc on stderr"
        continue
      fi
      ;;
    audit_effect_malformed)
      if ! grep -F "malformed effect clause: pure" "$BUILD_DIR/$name.stderr" >/dev/null 2>&1; then
        fail "$name: expected malformed effect clause on stderr"
        continue
      fi
      ;;
  esac

  log "ok contract-compile-fail $name"
  pass_count=$((pass_count + 1))
done

if [[ -x "$ROOT/test/correctness/contracts/test-explain.sh" ]]; then
  log "explain"
  if "$ROOT/test/correctness/contracts/test-explain.sh"; then
    pass_count=$((pass_count + 1))
  else
    fail "explain output test"
  fi
fi

if [[ -x "$ROOT/test/correctness/contracts/test-explain-audit.sh" ]]; then
  log "explain-audit"
  if "$ROOT/test/correctness/contracts/test-explain-audit.sh"; then
    pass_count=$((pass_count + 1))
  else
    fail "explain audit output test"
  fi
fi

if [[ -x "$ROOT/test/correctness/contracts/test-audit.sh" ]]; then
  log "audit-report"
  if "$ROOT/test/correctness/contracts/test-audit.sh"; then
    pass_count=$((pass_count + 1))
  else
    fail "audit report output test"
  fi
fi

if [[ -x "$ROOT/test/correctness/contracts/test-audit-json.sh" ]]; then
  log "audit-json"
  if "$ROOT/test/correctness/contracts/test-audit-json.sh"; then
    pass_count=$((pass_count + 1))
  else
    fail "audit-json output test"
  fi
fi

log "effect allocation walk guards missing call_ptr callee"
effect_src="$SURFACE_TEST_DIR/74_call_ptr_missing_callee.weave"
effect_wir="$WIR_FROM_SURFACE_DIR/74_call_ptr_missing_callee.wir"
effect_ll="$LL_DIR/surface_74_call_ptr_missing_callee.ll"
effect_err="$BUILD_DIR/74_call_ptr_missing_callee.stderr"
rm -f "$effect_wir" "$effect_ll" "$effect_err"
if ! "$WEAVEC" --frontend "$effect_wir" "$effect_src"; then
  fail "74_call_ptr_missing_callee: frontend failed"
else
  set +e
  "$WEAVEC" --backend "$effect_wir" "$effect_ll" 2>"$effect_err"
  effect_status="$?"
  set -e
  if [[ "$effect_status" -eq 0 ]]; then
    fail "74_call_ptr_missing_callee: expected backend rejection"
  elif [[ -e "$effect_ll" ]]; then
    fail "74_call_ptr_missing_callee: backend failure created output"
  else
    log "ok effect allocation walk guard"
    pass_count=$((pass_count + 1))
  fi
fi

log "frontend multifile"
if ! "$WEAVEC" --frontend "$WIR_FROM_SURFACE_DIR/multifile.wir" \
  "$SURFACE_TEST_DIR/multifile_a.weave" \
  "$SURFACE_TEST_DIR/multifile_b.weave"; then
  fail "multifile: frontend failed"
else
  if ! "$WEAVEC" --backend "$WIR_FROM_SURFACE_DIR/multifile.wir" "$LL_DIR/surface_multifile.ll"; then
    fail "multifile: backend failed"
  elif ! llvm-as "$LL_DIR/surface_multifile.ll" -o "$BC_DIR/surface_multifile.bc"; then
    fail "multifile: llvm-as failed"
  elif ! clang "$LL_DIR/surface_multifile.ll" -o "$BIN_DIR/surface_multifile"; then
    fail "multifile: clang failed"
  else
    set +e
    "$BIN_DIR/surface_multifile"
    actual="$?"
    set -e
    if [[ "$actual" != "42" ]]; then
      fail "multifile: expected exit 42, got $actual"
    else
      log "ok frontend multifile"
      pass_count=$((pass_count + 1))
    fi
  fi
fi

log "$pass_count passed, $fail_count failed"

if [[ "$fail_count" -ne 0 ]]; then
  exit 1
fi
