# Performance demonstrations

Each fixture under `test/performance/wir/` is a small module in the current
self-hosted core-version-3 WIR shape. Its pre-optimization LLVM output is checked
into `test/performance/expected-llvm/`. The suite is a deterministic backend
regression and code-review corpus, not a runtime benchmark leaderboard.

The frozen seed bootstrap uses WIR v2; these fixtures exercise the separate
self-hosted `weavec --backend` boundary. See [Architecture](architecture.md).

## Naming

```text
NNNN_short_descriptive_name.wir
NNNN_short_descriptive_name.ll
```

- `NNNN` is a four-digit, zero-padded decimal identifier.
- `short_descriptive_name` uses lowercase snake_case.
- The `.wir` file is the input and the matching `.ll` file is the golden output.

Examples:

| ID | File | Purpose |
|---:|---|---|
| `0001` | `0001_return_constant.wir` | Minimal return. |
| `0008` | `0008_while.wir` | Loop-lowering smoke. |
| `0061` | `0061_fibonacci_iterative.wir` | Iterative algorithm. |
| `0073` | `0073_factorial_iter_i32.wir` | Loop-carried `i32` factorial. |

Historical gaps are retained. New fixtures use the next free identifier rather
than renumbering existing inputs or goldens.

## ID ranges

| Range | Intended coverage |
|---|---|
| `0001–0059` | Language and code-generation smokes. |
| `0054–0060` | Integration-style WIR and nested control flow. |
| `0061–0130` | Classical algorithms and small demonstrations. |
| `0131–0152` | Hard control-flow, dynamic-programming, grid, and sorting stress. |
| `0153–0164` | `i64` arithmetic and heap demonstrations. |
| `0165–0168` | `f32` demonstrations. |
| `0169–0175` | `f64`, wide-accumulator, matrix/vector, and additional `i64` demonstrations. |
| `0176–9999` | Available for new demonstrations. |

Ranges are conventions, not parser behavior.

## Stress batches

### Control-flow and algorithm stress (`0131–0140`)

| ID | Fixture | Primary stress |
|---:|---|---|
| `0131` | `0131_loop_triple_if_carried_i32` | Three-deep nested conditionals and carried locals. |
| `0132` | `0132_matmul3x3_i32` | Triple nested loops and heap indexing. |
| `0133` | `0133_sieve48_i32` | Nested marking loop. |
| `0134` | `0134_floyd_warshall4_i32` | Dynamic-programming table updates. |
| `0135` | `0135_bubble_sort8_i32` | Nested sorting loops. |
| `0136` | `0136_knapsack01_i32` | Knapsack DP table. |
| `0137` | `0137_mandelbrot_grid6_sum_i32` | Grid and nested numeric control flow. |
| `0138` | `0138_mod_div_nested_accum_i32` | Modulo/division in nested branches. |
| `0139` | `0139_twin_parallel_if_ladders_i32` | Parallel branch joins and loop-carried state. |
| `0140` | `0140_selection_sort8_i32` | Selection-sort control flow. |

### Second hard batch (`0141–0152`)

| ID | Fixture | Primary stress |
|---:|---|---|
| `0141` | `0141_lcs_table_i32` | LCS dynamic programming. |
| `0142` | `0142_heap_sift_down4_i32` | Heap sift-down. |
| `0143` | `0143_rolling_hash_i32` | Rolling hash. |
| `0144` | `0144_matmul4x4_i32` | Matrix multiplication. |
| `0145` | `0145_insertion_sort10_i32` | Insertion sort. |
| `0146` | `0146_collatz_stats_i32` | Batch loop and statistics. |
| `0147` | `0147_partition_dutch12_i32` | Dutch-flag partition. |
| `0148` | `0148_gcd_batch_i32` | Repeated Euclidean GCD. |
| `0149` | `0149_binary_search_batch16_i32` | Repeated binary search. |
| `0150` | `0150_edit_distance6_i32` | Levenshtein DP. |
| `0151` | `0151_counting_sort12_i32` | Counting sort. |
| `0152` | `0152_merge_sorted_halves8_i32` | Merge of sorted halves. |

## Wide and floating-point batches

### `i64` (`0153–0164`)

These fixtures cover wide arithmetic, bitwise operations, loops, calls, and heap
arrays. Representative cases include factorial, dot product, GCD, Fibonacci,
modular exponentiation, Collatz, Horner evaluation, and matrix multiplication.

### `f32` (`0165–0168`)

These cover constant/addition lowering, loop accumulation, dot products, and a
Newton iteration.

### `f64` and additional wide accumulators (`0169–0175`)

| ID | Fixture | Focus |
|---:|---|---|
| `0169` | `0169_const_f64_add` | `f64` constant and addition smoke. |
| `0170` | `0170_sum_range_f64` | `f64` loop accumulator. |
| `0171` | `0171_factorial12_i64` | `i64` product with `i32` loop index. |
| `0172` | `0172_horner_poly_f32` | `f32` recurrence. |
| `0173` | `0173_sum_range_i64_acc` | Wide integer accumulator. |
| `0174` | `0174_matvec3_f32` | Heap-backed `f32` matrix/vector flow. |
| `0175` | `0175_sum_squares_i64` | Additional `i64` carried-state regression. |

The next free identifier is `0176`.

## Current code-generation observations

Mutable loop-carried values are stack-backed in raw LLVM for every scalar type.
The selected LLVM profile promotes eligible slots uniformly. The generated raw
analysis report measures promotion pressure; final conclusions use optimized LLVM
and machine-code evidence.

Integer `const_f32` and `const_f64` tokens lower through `sitofp`. Decimal
tokens emit a `bitcast` of the IEEE bits so LLVM accepts values such as
`0.1` and keeps the sign of `-0.0`.

See:

- [LLVM code-generation analysis](llvm-codegen-analysis.md)
- [Generated LLVM analysis report](llvm-codegen-analysis-report.md)

## Required WIR header

Every performance input starts with descriptive comments before `(core-module)`:

```text
; Performance: NNNN_short_name
; tags = smoke, i32, loop
; Why hard: What makes this fixture demanding.
; Reveals: Which WIR and LLVM shapes it exercises.
; Expected: Semantic result and validation expectation.
; If LLVM regresses: Concrete bad outcomes to inspect.
```

Wrap prose at 80 columns including the leading `; `.

Common tags include:

| Tag | Meaning |
|---|---|
| `smoke` | Baseline lowering. |
| `integration` | Multi-feature glue. |
| `algorithm` | Classical algorithm. |
| `stress` | Hard code-generation shape. |
| `i32`, `i64`, `f32`, `f64` | Primary scalar type. |
| `loop`, `loop-promotion`, `if-merge` | Control-flow focus. |
| `heap`, `memory` | Load/store or allocation focus. |
| `dp`, `sort`, `search` | Algorithm family. |
| `call`, `numeric`, `float`, `bitwise` | Operation family. |

Metadata is maintained by:

```sh
python3 scripts/annotate-performance-wir-headers.py
```

New fixtures need corresponding metadata in that script.

## Adding a demonstration

1. Select the next free ID and a lowercase snake_case name.
2. Add `test/performance/wir/NNNN_name.wir` with the required header.
3. Build the compiler.
4. Generate and verify the LLVM golden:

   ```sh
   ./test/performance/regen-golden.sh NNNN_name
   ```

5. Inspect the complete generated LLVM, not only the semantic exit result.
6. Run:

   ```sh
   ./test/performance/test.sh
   ./test-all.sh
   ```

7. Regenerate the analysis report when the checked-in LLVM corpus changes:

   ```sh
   python3 scripts/analyze-performance-llvm.py \
     --markdown docs/llvm-codegen-analysis-report.md
   ```

## Commands

```sh
./test/performance/test.sh
./test/performance/regen-golden.sh
./test/performance/regen-golden.sh 0073_factorial_iter_i32
python3 scripts/analyze-performance-llvm.py
```

Performance tests also run `opt -passes=mem2reg` when `opt` is available. The
checked-in golden remains the deterministic pre-optimization LLVM emitted by
`weavec`.
