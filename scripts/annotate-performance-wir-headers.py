#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Rewrite leading comment blocks on performance WIR fixtures.

Standard header (all lines are ';' comments before (core-module)):

  ; Performance: <stem>
  ; tags = smoke, i32, loop
  ; Why hard: ... (wrapped at 80 columns)
  ; Reveals: ...
  ; Expected: ...
  ; If LLVM regresses: ...

Golden LLVM text is unchanged; only WIR comments are updated.
"""

from __future__ import annotations

import re
import sys
import textwrap
from pathlib import Path

WIR_DIR = Path(__file__).resolve().parents[1] / "test" / "performance" / "wir"

LINE_WIDTH = 80

# stem -> (why_hard, reveals, failure_llvm)
META: dict[str, tuple[str, str, str]] = {}

# Optional per-fixture overrides (merged with inferred tags / expected).
TAGS_OVERRIDE: dict[str, list[str]] = {}
EXPECTED_OVERRIDE: dict[str, str] = {}

PHI_FAIL = (
    "Broken loop header phis or missing .merge blocks: carried locals reload "
    "from stack every iteration, wrong backedge operands, or SSA violations "
    "after llvm-as."
)
MEM_FAIL = (
    "Redundant alloca traffic: repeated load/store of the same slot each "
    "iteration instead of keeping values in registers after mem2reg."
)
LOOP_FAIL = (
    "Loop shape wrong: extra blocks per iteration, incorrect branch on exit "
    "condition, or off-by-one trip count."
)


def reg(
    stem: str,
    why: str,
    reveals: str,
    failure: str,
    *,
    expected: str | None = None,
    tags: list[str] | None = None,
) -> None:
    META[stem] = (why, reveals, failure)
    if expected is not None:
        EXPECTED_OVERRIDE[stem] = expected
    if tags is not None:
        TAGS_OVERRIDE[stem] = tags


def reg_smoke(stem: str, topic: str, reveals: str, failure: str) -> None:
    reg(
        stem,
        f"Smoke baseline for {topic}. Failures here usually indicate broken "
        "lowering shared by every later fixture.",
        reveals,
        failure,
    )


# --- 0001-0049 smoke ---
reg_smoke("0001_return_constant", "minimal return", "const_i32 return, empty prologue", "Wrong return type or extra unreachable blocks after ret.")
reg_smoke("0002_return_42", "constant 42", "named literal return", "Returns wrong constant or emits dead allocas before ret.")
reg_smoke("0003_add", "binary add", "add_i32 of two constants", "Uses sub/mul or leaves add in wrong width (i64 vs i32).")
reg_smoke("0004_one_arg_function", "single-parameter call", "param_get, call_i32, small function", "Argument passed in wrong register/stack slot; broken calling convention.")
reg_smoke("0005_let_local", "local binding", "let + local_get without control flow", "Local name maps to wrong SSA name or duplicate alloca for one binding.")
reg_smoke("0007_if", "conditional branch", "if with then/else joining", "Missing join block, wrong branch condition polarity, or divergent types at merge.")
reg_smoke("0008_while", "while loop", "condition block, backedge, carried i", "No backedge to header, phi missing for i, or body executed one extra time.")
reg_smoke("0009_two_arg_function", "two-parameter call", "two param_get values into call", "Second argument clobbers first or uses wrong attribute/sign.")
reg_smoke("0010_string_literal", "string symbol", "const_string_ptr in IR", "Missing private constant or bad pointer type for string data.")
reg_smoke("0011_const_i64", "i64 constant", "const_i64 materialization", "Truncation/extension errors; i64 value wrong in IR.")
reg_smoke("0012_i64_arithmetic", "i64 add/sub", "add_i64/sub_i64", "32-bit ops used where i64 required; nsw flags inconsistent.")
reg_smoke("0013_i64_comparisons", "i64 compares", "eq/ne/lt i64 predicates", "Signed vs unsigned icmp wrong; compare operands swapped.")
reg_smoke("0014_bool_ops", "boolean logic", "and_bool/or_bool/not_bool", "i1 values widened to i32 incorrectly; short-circuit broken.")
reg_smoke("0015_ptr_null", "null pointer", "const_null, eq_ptr", "null not typed as pointer; comparison lowered to integer eq.")
reg_smoke("0016_extern_malloc_free", "extern calls", "declare malloc/free, call_ptr/call_void", "Missing declare; wrong signature; call not marked correctly.")
reg_smoke("0017_ptr_add_store_load_i64", "pointer arithmetic", "ptr add, store_i64, load_i64", "GEP off-by-element-size; load width mismatch.")
reg_smoke("0018_store_load_i8", "i8 memory", "store_i8/load_i8", "Extends/truncates wrong around i8 access.")
reg_smoke("0019_call_void", "void return call", "call_void side effect only", "Treats void call as value-producing; dead ret of undefined.")
reg_smoke("0020_call_i64", "i64 return call", "call_i64 across function", "Return value in wrong register; caller uses i32 ops.")
reg_smoke("0021_call_ptr", "ptr return call", "call_ptr", "Pointer return not marked noalias where needed; typed as i64.")
reg_smoke("0022_return_void", "void function", "return_void in helper", "Inserts i32 ret in void function.")
reg_smoke("0023_mod_i32", "signed remainder", "mod_i32 lowering to srem", "Uses urem or div without rem; wrong sign on negative inputs.")
reg_smoke("0024_buffer_like_smoke", "GEP chain", "nested pointer offsets", "Collapses distinct object accesses into one base incorrectly.")
reg_smoke("0025_ptr_params_call_i32", "ptr param + load", "ptr param, load_i32, call", "By-value vs by-pointer confusion for array param.")
reg_smoke("0026_bool_return", "bool as i1", "returns boolean from helper", "Returns i32 0/1 with wrong width at callsite.")
reg_smoke("0027_three_arg_function", "three-arg call", "three param_get + call", "Register/stack misalignment from third argument onward.")
reg_smoke("0028_i32_memory_and_cast", "casts + memory", "cast_i32_to_i64, load/store mix", "Extension/truncation on wrong edge of load.")
reg_smoke("0029_const_string_ptr", "string in expr", "const_string_ptr as value", "Double indirection or string not merged as constant.")
reg_smoke("0030_i64_sub_eq", "i64 compare chain", "sub_i64 then eq_i64", "Compare uses truncated subresult.")
reg_smoke("0031_not_bool", "boolean not", "not_bool on predicate", "Emits xor i32 1 instead of xor i1.")
reg_smoke("0032_codegen_join_and_i64_arg", "malloc size i64", "mul_i64 in call arg position", "Size computation widened/narrowed wrong; malloc gets i32.")
reg_smoke("0033_store_i8_temp", "byte temp", "store_i8 to alloca", "Zext/sext missing before i32 use of byte.")
reg_smoke("0034_ge_i32", "signed compare ge", "ge_i32 predicate", "Uses uge or swaps operands silently.")
reg_smoke("0035_sub_i32", "subtraction", "sub_i32", "Becomes add with negative wrong; nsw missing where expected.")
reg_smoke("0036_mul_i32", "multiplication", "mul_i32", "mul lowered to shifts incorrectly for non-power-of-two.")
reg_smoke("0037_div_i32", "signed division", "div_i32 -> sdiv", "Uses udiv or divides before sign extension.")
reg_smoke("0038_i32_comparisons_full", "full icmp set", "eq/ne/lt/le/gt/ge i32", "Any one icmp kind wrong breaks all later branchy code.")
reg_smoke("0039_i64_ge_gt", "i64 ordered compares", "ge_i64/gt_i64", "Treats i64 compares as unsigned incorrectly.")
reg_smoke("0040_call_bool_direct", "bool call", "call_bool + branch", "Caller compares i32 instead of i1.")
reg_smoke("0041_load_store_ptr", "ptr load/store", "load_i32 through ptr", "Missing align on load; TBAA broken for heap slot.")
reg_smoke("0042_empty_do", "empty block", "do with no statements", "Empty block eliminated incorrectly breaking join.")
reg_smoke("0043_if_fallthrough_join", "if join", "then/else paths merge", "Phi missing at join; one arm falls through wrong block.")
reg_smoke("0044_while_zero_iterations", "zero-trip loop", "while with false initial condition", "Header executes body once anyway.")
reg_smoke("0045_nested_while", "nested loops", "outer/inner while", "Inner backedge wired to outer header; induction vars swapped.")
reg_smoke("0046_forward_function_call", "forward ref call", "call before callee in module", "Callee not emitted or wrong linkage order.")
reg_smoke("0047_multiple_externs_used_subset", "multiple extern", "subset of externs used", "Unused declare removed but wrong one kept.")
reg_smoke("0048_string_escape", "escaped string", "special chars in literal", "Broken escape in .ll string constant.")
reg_smoke("0049_negative_i32_literal", "negative literal", "const_i32 negative", "Parsed as large unsigned or missing minus.")

# --- 0054-0060 integration ---
reg(
    "0054_debug_marker",
    "Ensures debug/provenance metadata does not perturb codegen shape.",
    "Minimal body with marker-friendly structure.",
    "Extra instructions inserted in every block; metadata becomes semantic by accident.",
)
reg(
    "0055_integration_nested_control_flow",
    "Combines nested if/while; easy to mis-wire merge edges.",
    "Nested if inside while, multiple join points.",
    PHI_FAIL,
)
reg(
    "0056_integration_multi_function_chain",
    "Several small functions inlined by hand; call chain must preserve ABI.",
    "call_i32 across three functions, args and returns threaded.",
    "Broken tail call or wrong return value register at end of chain.",
)
reg(
    "0057_integration_memory_flow",
    "Malloc, stores, loads, free in one flow; alias mistakes show up quickly.",
    "Heap alloc, multiple stores, reloads, free.",
    "Load before store visible; free before last load; redundant reload of same slot.",
)
reg(
    "0060_discard_call_i32",
    "Return value intentionally unused; must not keep bogus uses alive.",
    "call_i32 result discarded.",
    "Dead code keeps alloca for unused return; extra stores to dead slots.",
)

# --- 0061-0080 classical ---
reg(
    "0061_fibonacci_iterative",
    "Two carried locals swap each iteration; classic phi stress.",
    "while with add, two i32 carried (a,b), i32 index.",
    PHI_FAIL,
)
reg(
    "0062_insertion_sort_i32",
    "Small in-memory sort; inner shift loop with stores.",
    "Nested loops, compare, store through array index.",
    MEM_FAIL,
)
reg(
    "0063_dot_product_i32",
    "Multiply-add reduction over array elements.",
    "Indexed load, mul_i32, add_i32 in loop.",
    "Products computed but not accumulated; reloads array each k.",
)
reg(
    "0064_matrix2_trace_i32",
    "2x2 indexing on heap; diagonal sum.",
    "array_i32_at, load_i32, add.",
    "Row-major index formula wrong; trace sums off-diagonal.",
)
reg(
    "0065_mandelbrot_escape_i32",
    "Iterative complex escape; many mul/add in inner loop.",
    "Nested loops, div/mul on i32 iterates.",
    "Inner loop never exits; escape count wrong due to div rounding.",
)
reg(
    "0066_typed_array_at",
    "Typed array element address computation.",
    "array_i32_at GEP lowering.",
    "GEP uses wrong element size; pointers not i64-scaled.",
)
reg(
    "0067_euclid_gcd_i32",
    "Euclidean GCD; mod in tight while.",
    "mod_i32, carried x/y until y==0.",
    "Uses subtraction loop wrong; mod with div by zero guard missing.",
)
reg(
    "0068_binary_search_i32",
    "Binary search on sorted array; nested compares.",
    "low/high/mid carried, load at mid.",
    "Infinite loop on bounds; mid computed with div rounding error.",
)
reg(
    "0069_sieve_count_i32",
    "Sieve variant; boolean flags on heap.",
    "Store i32 flags, nested marking loop.",
    "Flags not cleared; inner loop reads stale composite.",
)
reg(
    "0070_horner_polynomial_i32",
    "Horner scheme; mul-add chain per coefficient.",
    "mul_i32/add_i32 recurrence in loop.",
    "Polynomial evaluated in wrong order; acc not updated.",
)
reg(
    "0071_collatz_i32",
    "Collatz step; branch on parity with div/mul.",
    "if on mod 2, div and 3n+1 paths.",
    "Odd branch uses wrong formula; infinite loop on 1.",
)
reg(
    "0072_pow_square_i32",
    "Repeated squaring; overflow not goal but mul recurrence matters.",
    "mul_i32 in loop on carried base.",
    "Square done once; exponent counter does not advance.",
)
reg(
    "0073_factorial_iter_i32",
    "Factorial product loop; classic benchmark shape.",
    "mul_i32 on carried fact, i32 index.",
    "Product resets each iteration; off-by-one on range.",
)
reg(
    "0074_sum_array8_i32",
    "Eight-element heap sum.",
    "load_i32 through array_i32_at in loop.",
    MEM_FAIL,
)
reg(
    "0075_bubble_sort4_i32",
    "O(n^2) compare-swap on four elements.",
    "Nested loops, load/compare/store swap.",
    "Swap stores to wrong indices; inner loop bound wrong.",
)
reg(
    "0076_trial_division_prime_i32",
    "Primality by trial division up to sqrt.",
    "Loop with mod, early exit flag.",
    "sqrt bound too large/small; flag never set on composite.",
)
reg(
    "0077_selection_sort4_i32",
    "Selection sort with argmin scan.",
    "Nested loops, min index, swap stores.",
    "Min index not updated; swap uses stale min.",
)
reg(
    "0078_reverse_array4_i32",
    "In-place reverse with two pointers.",
    "Two indices, load/store swap on heap.",
    "Pointers cross without stopping; reads after free if paired wrong.",
)
reg(
    "0079_loop_if_else_passthrough_i32",
    "Loop with if/else that must merge before next iteration.",
    "if inside while on carried acc.",
    PHI_FAIL,
)
reg(
    "0080_loop_twin_if_i32",
    "Two sibling ifs updating same carried local in one iteration.",
    "Twin if merges, loop-carried x, merge suffix allocation.",
    "Missing .merge block or wrong backedge to phi; second if clobbers first update.",
)

# --- 0081-0130 algorithm demos (helper) ---
def reg_alg(
    stem: str,
    algo: str,
    hard: str,
    reveals: str,
    failure: str,
) -> None:
    reg(
        stem,
        f"{algo} {hard}",
        reveals,
        failure,
    )


ALG = reg_alg
ALG("0081_sum_range_i32", "Sum 1..n (triangular number).", "Simple but canonical loop-carried accumulator.", "while, add_i32 on sum, i32 index.", PHI_FAIL)
ALG("0082_sum_squares_range_i32", "Sum of squares 1^2+..+n^2.", "Mul inside add recurrence stresses licm/prevent hoisting bugs.", "mul_i32 then add_i32 each step.", "Square not squared (add instead of mul); sum uses stale i.")
ALG("0083_lcm_i32", "LCM via GCD.", "Combines two algorithms and reuse of mod state.", "GCD loop then div/mul combine.", "LCM formula uses wrong GCD; division by zero.")
ALG("0084_count_divisors_i32", "Count divisors by trial.", "Many mod operations on growing trial.", "mod_i32 in loop with increment.", "Counts wrong divisor; includes n twice.")
ALG("0085_is_prime_i32", "Primality test.", "Early exit branch must preserve flag phi.", "Trial division to sqrt.", "Composite reported prime; loop does not exit at sqrt.")
ALG("0086_max_of_three_i32", "Max of three without loop.", "Nested compares only—joins must be clean.", "Chained if/compare, no loop.", "Wrong compare polarity picks min instead of max.")
ALG("0087_popcount_i32", "Population count by halving.", "Repeated div/mod 2 until zero.", "shr or div by 2, add to count.", "Counts one extra; uses arithmetic shift on negative.")
ALG("0088_digital_sum_i32", "Sum of decimal digits.", "Mod/div loop until n=0.", "mod 10, div 10, accumulate.", "Loses high digits; infinite loop if div wrong.")
ALG("0089_tribonacci_iter_i32", "Three-term recurrence.", "Three carried locals—phi arity 3.", "Three updates per iteration.", "Terms rotate wrong; T(n) drift.")
ALG("0090_floor_sqrt_i32", "Integer sqrt by trial.", "Compare i*i <= n each step.", "mul_i32 for square, carried root.", "Off-by-one sqrt; square overflows silently in i32.")
ALG("0091_linear_search5_i32", "Linear search five elements.", "Early-exit index pattern.", "load, compare, break index.", "Always returns last index; never finds match.")
ALG("0092_array_max5_i32", "Max of five heap values.", "Conditional update on carried max.", "load, gt, set max in if.", PHI_FAIL)
ALG("0093_count_evens5_i32", "Count evens in five elements.", "Mod 2 on loaded values.", "load, mod, branch, add count.", "Counts odds; mod lowered to and wrong.")
ALG("0094_min_of_three_i32", "Min of three.", "Branch-only like max_of_three.", "Nested compares.", "Returns middle value always.")
ALG("0095_abs_i32", "Absolute value.", "Sign test without overflow edge (MIN).", "compare + select pattern via if.", "Negates MIN incorrectly or always negative path.")
ALG("0096_gcd_subtraction_i32", "GCD by subtraction.", "Many iterations vs modulo GCD.", "sub in loop until equal.", "Infinite loop when equal case not handled.")
ALG("0097_product_range_i32", "Factorial-shaped product.", "mul recurrence like 0073.", "mul_i32 carried product.", "Product zeroed each trip; starts at 0.")
ALG("0098_sum_cubes_range_i32", "Sum of cubes.", "Two muls per iteration.", "cube via mul twice, add.", "Cube computed as i*i+i wrong.")
ALG("0099_is_perfect_i32", "Perfect number test.", "Divisor sum loop then compare.", "Inner divisor loop + outer compare.", "Sum includes n itself; wrong equality.")
ALG("0100_reverse_digits_i32", "Reverse decimal digits.", "Build reversed with mod/div.", "mod 10, div 10, accumulate rev.", "Digits appended wrong order.")
ALG("0101_palindrome_number_i32", "Palindrome check.", "Depends on reverse_digits correctness.", "reverse then compare.", "Always true; compares n to partial reverse.")
ALG("0102_count_primes_to_n_i32", "Count primes <= n.", "Nested primality loops.", "Outer candidate, inner trial division.", "Overcounts 1 or composites.")
ALG("0103_mod_pow_i32", "Modular exponentiation.", "Square-and-multiply with mod each step.", "mul+mod in loop on bits of exp.", "Forgot mod; overflow changes semantic mod result.")
ALG("0104_array_min5_i32", "Min reduction five elements.", "Mirror of max5.", "load, lt, conditional update.", PHI_FAIL)
ALG("0105_array_sum5_i32", "Sum five heap elements.", "Baseline heap reduction.", "indexed load, add.", MEM_FAIL)
ALG("0106_clamp_i32", "Clamp to interval.", "Two compares without loop.", "le/ge compares, if chain.", "Returns lo when should return hi.")
ALG("0107_sign_i32", "Sign function -1/0/1.", "Three-way branch.", "nested compares.", "Sign always 0; compares swapped.")
ALG("0108_hailstone_peak_i32", "Collatz peak tracking.", "Inner while + max on carried peak.", "div/mod branch, gt update.", PHI_FAIL)
ALG("0109_insertion_sort5_i32", "Insertion sort five elements.", "Inner while shift with stores.", "nested loops, array stores.", MEM_FAIL)
ALG("0110_nested_sum_ij_i32", "Double sum i*j.", "Triply nested induction if extended—here O(n^2).", "outer/inner loops, mul add.", "Inner bound uses outer wrong; sum formula off.")
ALG("0111_sum_odds_to_n_i32", "Sum odd numbers.", "Stride-2 style loop.", "add with i+=2 or equivalent.", "Includes evens; starts at wrong parity.")
ALG("0112_sum_evens_to_n_i32", "Sum even numbers.", "Pair to odds test.", "even accumulation loop.", "Starts at 1; double-counts.")
ALG("0113_median_of_three_i32", "Median of three.", "Multiple calls/min-max logic.", "function calls + compares.", "Returns mean not median.")
ALG("0114_power_of_two_i32", "Power-of-two test.", "Shift loop until bit pattern.", "shl/shr style loop.", "Always false; uses popcount wrong.")
ALG("0115_sum_powers_of_two_i32", "Sum 2^k.", "Doubling add recurrence.", "shl/add loop.", "Doubles wrong register; sum not geometric.")
ALG("0116_trailing_zeros_i32", "Count trailing zeros.", "Tight div/mod 2 loop like popcount.", "mod 2, div 2, increment count.", "Counts leading not trailing; extra urem per step.")
ALG("0117_multiples_sum_i32", "Sum multiples of 3 or 5.", "Mod in conditional add.", "mod, branch, add acc.", "Double-counts lcm(3,5); mod wrong sign.")
ALG("0118_bubble_sort5_i32", "Bubble sort five.", "O(n^2) swaps.", "nested compare swap.", MEM_FAIL)
ALG("0119_array_product5_i32", "Product reduction.", "mul instead of add.", "mul_i32 chain with loads.", "Product stuck at 1; overflow not relevant to shape.")
ALG("0120_count_positive5_i32", "Count positives.", "Compare load > 0.", "load, gt, add count.", "Counts zero as positive.")
ALG("0121_second_max5_i32", "Second largest of five.", "Two-pass reduction.", "two linear scans.", "Returns max not second; first pass wrong.")
ALG("0122_kadane5_i32", "Kadane max subarray (n=5).", "Running cur/best with negatives.", "max of cur+best pattern.", "Best not updated; cur resets wrongly.")
ALG("0123_selection_sort5_i32", "Selection sort five.", "Argmin inner loop.", "nested loops, swaps.", MEM_FAIL)
ALG("0124_sum_pairs5_i32", "Sum adjacent pairs.", "Index i and i+1 loads.", "two loads per iteration.", "Reads past end; pairs overlap wrong.")
ALG("0125_all_equal5_i32", "All equal test.", "Early false on mismatch.", "compare chain in loop.", "Returns true on different array.")
ALG("0126_xor_reduce5_i32", "XOR reduction.", "xor_i32 in loop.", "xor recurrence with loads.", "Uses or instead of xor.")
ALG("0127_count_less_than5_i32", "Count below threshold.", "Compare load < T.", "lt, add count.", "Uses le vs lt wrong.")
ALG("0128_binary_search6_i32", "Binary search six elements.", "Classic bisection.", "low/high/mid, load mid.", "Infinite loop; off-by-one on bounds.")
ALG("0129_matrix2_trace_i32", "2x2 trace on heap.", "Same family as 0064.", "diagonal loads, add.", "Off-diagonal included.")
ALG("0130_harmonic_sum_i32", "Truncated harmonic sum with int div.", "div_i32 each step—rounding sensitive.", "div in accumulating loop.", "Uses fp div; sum uses mul instead of div.")

# --- 0131-0164 stress + i64 ---
STRESS = reg
STRESS(
    "0131_loop_triple_if_carried_i32",
    "One loop, three nested if levels, three loop-carried i32 locals—deep merge graph.",
    "Nested if inside while; multiple carried locals; merge/phi suffix chain.",
    PHI_FAIL,
)
STRESS(
    "0132_matmul3x3_i32",
    "O(n^3) triple nested loops with 2D heap indexing.",
    "Three loops, array_i32_at, mul/add inner, many loads/stores.",
    "Wrong stride on row-major index; inner k bound wrong; C[i,j] never written.",
)
STRESS(
    "0133_sieve48_i32",
    "Sieve to 48 with inner marking loop—store-heavy.",
    "Nested loops, flag array stores, branch on flags.",
    "Marks composites wrong; inner loop starts at wrong multiple.",
)
STRESS(
    "0134_floyd_warshall4_i32",
    "All-pairs shortest paths—triple loop with relax.",
    "k,i,j loops, min relax on heap matrix.",
    "Relax uses max not min; k/i/j order wrong for FW.",
)
STRESS(
    "0135_bubble_sort8_i32",
    "Bubble sort eight elements—many compare-swaps.",
    "O(n^2) nested loops on heap array.",
    MEM_FAIL,
)
STRESS(
    "0136_knapsack01_i32",
    "0/1 knapsack DP table 5x11—2D recurrence.",
    "2D heap table, max of take/skip, triple structure.",
    "DP recurrence uses wrong index; table row stride wrong; max path broken.",
)
STRESS(
    "0137_mandelbrot_grid6_sum_i32",
    "6x6 grid Mandelbrot escape sum—heavy inner kernel.",
    "Nested pixel loops, div/mul in escape loop.",
    "Escape count wrong; inner loop never advances z.",
)
STRESS(
    "0138_mod_div_nested_accum_i32",
    "200 steps with mod/div in nested if on residues.",
    "sdiv/srem in branchy loop, carried acc.",
    "Uses udiv/urem; acc updated on wrong branch only.",
)
STRESS(
    "0140_selection_sort8_i32",
    "Selection sort eight elements—argmin scan inner loop.",
    "Nested loops, min index, swap stores.",
    MEM_FAIL,
)
STRESS(
    "0141_lcs_table_i32",
    "LCS DP 9x9 table on two length-8 strings.",
    "2D heap DP, max of three predecessors, nested loops.",
    "Table fill order wrong; max of three paths broken; stride errors.",
)
STRESS(
    "0142_heap_sift_down4_i32",
    "Sift-down on four-element max-heap.",
    "While with parent/child index compares and swaps.",
    "Child index 2i+1/2i+2 wrong; sift stops early.",
)
STRESS(
    "0143_rolling_hash_i32",
    "Polynomial rolling hash over 64 bytes.",
    "mul/add/mod recurrence each byte.",
    "Hash forgets to subtract outgoing term; mod applied once not per step.",
)
STRESS(
    "0144_matmul4x4_i32",
    "4x4 matrix multiply on heap.",
    "O(n^3) loops, 2D indexing like 0132 at larger n.",
    "Same indexing failures as 0132; result cell wrong.",
)
STRESS(
    "0145_insertion_sort10_i32",
    "Insertion sort ten elements.",
    "Inner shift while with many stores.",
    MEM_FAIL,
)
STRESS(
    "0146_collatz_stats_i32",
    "Collatz for n=1..80 with max steps and sum.",
    "Inner collatz while + outer batch, multiple carried locals.",
    PHI_FAIL,
)
STRESS(
    "0147_partition_dutch12_i32",
    "Dutch-flag partition on twelve 0/1/2 values.",
    "Three indices, many compare-branches, in-place swaps.",
    "Pointers cross; elements not grouped; infinite loop on indices.",
)
STRESS(
    "0148_gcd_batch_i32",
    "Batch GCD over twelve pairs.",
    "Nested GCD while inside outer accumulator loop.",
    "Outer acc wrong; inner GCD uses stale x/y between pairs.",
)
STRESS(
    "0149_binary_search_batch16_i32",
    "Sixteen sorted values, twelve binary searches in loop.",
    "Nested if in search, low/high/found carried, outer sum.",
    "Search returns wrong index; outer sum double-counts.",
)
STRESS(
    "0150_edit_distance6_i32",
    "Levenshtein DP 7x7 for length-6 strings.",
    "min of three, 2D table, nested loops.",
    "Insertion cost wrong; diagonal not initialized.",
)
STRESS(
    "0151_counting_sort12_i32",
    "Counting sort twelve values range 0..5.",
    "Count array, prefix, scatter phases.",
    "Prefix sum wrong; unstable scatter; count index off-by-one.",
)
STRESS(
    "0152_merge_sorted_halves8_i32",
    "Merge two sorted halves 4+4.",
    "Twin-pointer loop, compare, store to out.",
    "Skips elements; writes past buffer; compares wrong side.",
)
STRESS(
    "0153_sum_range_i64",
    "Sum 1..120 in i64—wide accumulator with i32 index.",
    "cast_i32_to_i64, add_i64, i32 loop index only.",
    "Accumulator truncated to i32; i64 add uses i32 ops.",
)
STRESS(
    "0154_factorial20_i64",
    "20! in i64—large product recurrence.",
    "mul_i64 loop on stack-carried fact.",
    "Product width wrong; mul overflows silently in IR type.",
)
STRESS(
    "0155_dot_product8_i64",
    "Dot product two length-8 i64 arrays.",
    "array_i64_at, load_i64, mul_i64, add_i64.",
    "Uses i32 mul on loaded i64; alignment 4 on i64 load.",
)
STRESS(
    "0156_gcd_i64",
    "Euclidean GCD on i64 pair.",
    "mod_i64, carried x/y on stack slots.",
    "mod uses i32 remainder; swap order wrong.",
)
STRESS(
    "0157_array_max8_i64",
    "Max of eight i64 heap values.",
    "gt_i64, load_i64, conditional set maxv.",
    "Max not updated in loop (let shadowing); compares signed as unsigned.",
)
STRESS(
    "0158_fibonacci30_i64",
    "Fibonacci F(30) with i64 values.",
    "add_i64, carried prev/cur on stack, mod at end.",
    "i64 add truncated; prev/cur not swapped.",
)
STRESS(
    "0159_power_mod_i64",
    "Modular exponentiation i64.",
    "mul_i64 and mod_i64 each square step.",
    "Square without mod; exp bit test uses wrong mask.",
)
STRESS(
    "0160_fixed_point_mean_i64",
    "Fixed-point mean of i64 samples (float proxy).",
    "div_i64 after sum loop over heap array.",
    "Division before sum complete; scale factor applied twice.",
)
STRESS(
    "0161_collatz_peak_i64",
    "Collatz on i64 with peak tracking over batch.",
    "div_i64/mod_i64/mul_i64, nested if, outer batch.",
    "Peak uses i32 compare; 3n+1 overflows wrong width.",
)
STRESS(
    "0162_bitwise_mix_i64",
    "i64 xor/and/shl/shr mix in 64-step loop.",
    "bitwise i64 ops chained per iteration.",
    "Shr uses shl; and mask wrong width; xor optimized away incorrectly.",
)
STRESS(
    "0163_horner_poly_i64",
    "Horner evaluation degree-6 in i64.",
    "mul_i64/add_i64 chain, i32 index.",
    "Polynomial order wrong; acc stays constant.",
)
STRESS(
    "0164_matmul2x2_i64",
    "2x2 i64 matrix multiply on heap.",
    "Triple nested loops, array_i64_at, i64 mul/add.",
    "Same indexing bugs as i32 matmul; i64 store size 4 bytes.",
)
STRESS(
    "0139_loop_twin_parallel_if_i32",
    "Twin parallel if ladders updating x when i is 0 and 1 in same trip.",
    "Sibling branch joins and mutable loop-carried state.",
    PHI_FAIL,
)
STRESS(
    "0165_const_f32_add",
    "f32 smoke: literal add and fptosi return.",
    "const_f32, fadd, cast_f32_to_i32.",
    "fadd typed as double add; literal parsed as integer; cast omitted.",
)
STRESS(
    "0166_sum_range_f32",
    "f32 sum 1..120 before LLVM promotion.",
    "add_f32, cast_i32_to_f32, i32 loop index.",
    "Accumulator widened to double; fadd uses i32 operands.",
)
STRESS(
    "0167_dot_product4_f32",
    "f32 dot product of four pairs in registers.",
    "fmul/fadd tree, no heap.",
    "Partial products dropped; uses fmul on i32 by mistake.",
)
STRESS(
    "0168_newton_sqrt_f32",
    "Newton sqrt(2) with eight f32 iterations.",
    "fdiv/fmul/fadd in loop, call_f32 helper.",
    "Guess not updated; fdiv by zero; comparison uses icmp.",
)
STRESS(
    "0169_const_f64_add",
    "f64 smoke: literal add and fptosi return.",
    "const_f64, fadd, cast_f64_to_i32.",
    "fadd typed as double; sitofp used where f64 literal expected.",
)
STRESS(
    "0170_sum_range_f64",
    "f64 sum 1..120; i64/f64 acc on stack like f32 batch.",
    "add_f64, cast_i32_to_f64, i32 loop index.",
    "Double-width accumulator; per-iteration sitofp of index.",
)
STRESS(
    "0171_factorial12_i64",
    "Factorial 12 with i64 product (phi gap vs i32 factorial).",
    "mul_i64, cast_i32_to_i64, mod_i64.",
    MEM_FAIL,
)
STRESS(
    "0172_horner_poly_f32",
    "Horner-style f32 recurrence acc*3+i for eight steps.",
    "fmul/fadd, f32 acc on stack in loop.",
    "Uses i32 mul for f32 acc; sitofp each step.",
)
STRESS(
    "0173_sum_range_i64_acc",
    "Sum 1..200 into i64 total; i32 index only promoted.",
    "add_i64, cast_i32_to_i64, wide accumulator.",
    MEM_FAIL,
)
STRESS(
    "0174_matvec3_f32",
    "3x3 by 3 f32 matvec on heap; identity matrix smoke.",
    "load_f32/store_f32, ptr_add, call_f32.",
    "GEP stride 4 vs 8; row/column major swap in loads.",
)


def wrap_field(label: str, text: str) -> list[str]:
    """Wrap body so each output line is at most LINE_WIDTH characters."""
    text = " ".join(text.split())
    if not text:
        return [f"; {label}".rstrip()]
    suffix = label if label.endswith((" ", "=")) else f"{label} "
    first = f"; {suffix}"
    cont = ";   "
    chunks = textwrap.wrap(
        text,
        width=LINE_WIDTH - len(cont),
        break_long_words=False,
        break_on_hyphens=False,
    )
    lines: list[str] = []
    for i, chunk in enumerate(chunks):
        prefix = first if i == 0 else cont
        room = LINE_WIDTH - len(prefix)
        if len(chunk) <= room:
            lines.append(prefix + chunk)
        else:
            sub = textwrap.wrap(
                chunk,
                width=room,
                break_long_words=False,
                break_on_hyphens=False,
            )
            for j, part in enumerate(sub):
                lines.append((first if i == 0 and j == 0 else cont) + part)
    return lines


def infer_tags(stem: str, reveals: str, failure: str) -> list[str]:
    n = int(stem[:4])
    name = stem[5:].lower()
    tags: list[str] = []

    if n <= 53:
        tags.append("smoke")
    elif n <= 60:
        tags.extend(["integration", "control-flow"])
    elif n <= 130:
        tags.append("algorithm")
    else:
        tags.append("stress")

    if "_i64" in stem:
        tags.append("i64")
    elif "_f32" in stem:
        tags.append("f32")
    else:
        tags.append("i32")

    if any(k in name for k in ("while", "loop", "iter", "fibonacci", "collatz", "range")):
        tags.append("loop")
    if any(
        k in stem
        for k in (
            "0080_loop_twin",
            "0131_loop_triple",
            "0139_loop_twin",
            "loop_twin",
            "loop_triple",
        )
    ):
        tags.extend(["loop-promotion", "if-merge"])
    if "phi" in failure.lower() or "merge" in failure.lower():
        if "loop-promotion" not in tags:
            tags.append("loop-promotion")
    if any(
        k in name
        for k in (
            "malloc",
            "array",
            "matmul",
            "heap",
            "knapsack",
            "table",
            "sieve",
            "dot_product",
            "merge_sorted",
        )
    ):
        tags.append("heap")
    if any(k in name for k in ("knapsack", "lcs", "edit_distance", "floyd", "mandelbrot_grid")):
        tags.append("dp")
    if "sort" in name or "bubble" in name or "insertion" in name or "selection" in name:
        tags.append("sort")
    if "binary_search" in name or "linear_search" in name:
        tags.append("search")
    if any(k in name for k in ("extern", "call", "function")):
        tags.append("call")
    if any(k in reveals.lower() for k in ("store", "load", "alloca")):
        tags.append("memory")
    if any(k in name for k in ("xor", "popcount", "bitwise", "trailing", "rolling_hash")):
        tags.append("bitwise")
    if "_f32" in stem or "_f64" in stem or "newton" in name or "float" in name:
        tags.append("float")
    if "_i64" in stem and "i32" not in stem:
        tags.append("i64")
    if "mod" in name or "pow" in name or "gcd" in name:
        tags.append("numeric")

    merged = TAGS_OVERRIDE.get(stem, [])
    out = sorted(set(tags + merged))
    return out


def infer_expected(stem: str) -> str:
    if stem in EXPECTED_OVERRIDE:
        return EXPECTED_OVERRIDE[stem]

    known: dict[str, str] = {
        "0002_return_42": "main returns 42.",
        "0003_add": "main returns 42 (20 + 22).",
        "0008_while": "main returns sum 0..n for configured n (see golden).",
        "0023_mod_i32": "main returns remainder-focused smoke value (see golden).",
        "0073_factorial_iter_i32": "main returns n! for configured n (see golden).",
        "0080_loop_twin_if_i32": "main returns 3 (x=0+1 then +2 on i=0,1).",
        "0139_loop_twin_parallel_if_i32": "main returns 110 (x+=10 at i=0, +=100 at i=1).",
        "0153_sum_range_i64": "main returns triangular sum 1..120 as i32 cast.",
        "0154_factorial20_i64": "main returns 20! mod 1_000_000_007 as i32.",
        "0158_fibonacci30_i64": "main returns fib(30) mod 1_000_000_007 as i32.",
        "0165_const_f32_add": "main returns 5 (float 2+3, fptosi).",
        "0166_sum_range_f32": "main returns 7260 (float sum 1..120, fptosi).",
        "0167_dot_product4_f32": "main returns 30 (dot of 1..4 · 1..4, fptosi).",
        "0168_newton_sqrt_f32": "main returns ~1414 (sqrt(2)*1000, fptosi; see golden).",
        "0169_const_f64_add": "main returns 5 (double 2+3, fptosi).",
        "0170_sum_range_f64": "main returns 7260 (f64 sum 1..120, fptosi).",
        "0171_factorial12_i64": "main returns 12! mod 1_000_000_007 as i32.",
        "0172_horner_poly_f32": "main returns 1636 (f32 Horner acc*3+i for i=0..7, fptosi).",
        "0173_sum_range_i64_acc": "main returns 20100 (sum 1..200 as i32).",
        "0174_matvec3_f32": "main returns 1 (identity matvec, first component).",
    }
    if stem in known:
        base = known[stem]
    elif stem.endswith("_42") or "return_42" in stem:
        base = "main returns 42 (conventional success marker)."
    else:
        base = f"Golden LLVM matches test/performance/expected-llvm/{stem}.ll."

    return (
        f"{base} llvm-as accepts emitted IR; "
        "opt -passes=mem2reg is an optional extra check."
    )


def format_header(stem: str, why: str, reveals: str, failure: str) -> str:
    tags = infer_tags(stem, reveals, failure)
    expected = infer_expected(stem)
    lines: list[str] = [f"; Performance: {stem}"]
    tag_text = ", ".join(tags)
    if len(f"; tags = {tag_text}") <= LINE_WIDTH:
        lines.append(f"; tags = {tag_text}")
    else:
        lines.extend(wrap_field("tags =", tag_text))
    lines.extend(wrap_field("Why hard:", why))
    lines.extend(wrap_field("Reveals:", reveals))
    lines.extend(wrap_field("Expected:", expected))
    lines.extend(wrap_field("If LLVM regresses:", failure))
    return "\n".join(lines) + "\n"


def strip_old_header(text: str) -> str:
    lines = text.splitlines(keepends=True)
    i = 0
    while i < len(lines) and lines[i].startswith(";"):
        i += 1
    while i < len(lines) and lines[i].strip() == "":
        i += 1
    return "".join(lines[i:])


def annotate_file(path: Path, dry_run: bool) -> bool:
    stem = path.stem
    if stem not in META:
        print(f"missing metadata: {stem}", file=sys.stderr)
        return False
    why, reveals, failure = META[stem]
    body = strip_old_header(path.read_text(encoding="utf-8"))
    new_text = format_header(stem, why, reveals, failure) + body
    if dry_run:
        print(f"would update {path.name}")
        return True
    path.write_text(new_text, encoding="utf-8")
    return True


def main() -> int:
    dry_run = "--dry-run" in sys.argv
    stems = sorted(p.stem for p in WIR_DIR.glob("*.wir"))
    missing = [s for s in stems if s not in META]
    if missing:
        print(f"Missing {len(missing)} entries:", ", ".join(missing), file=sys.stderr)
        return 1
    extra = sorted(set(META) - set(stems))
    if extra:
        print(f"Unused metadata ({len(extra)}):", ", ".join(extra[:5]), file=sys.stderr)
        return 1
    ok = True
    for path in sorted(WIR_DIR.glob("*.wir")):
        ok = annotate_file(path, dry_run) and ok
    print(f"{'dry-run: ' if dry_run else ''}updated {len(stems)} fixtures")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
