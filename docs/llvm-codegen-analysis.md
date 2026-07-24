# LLVM codegen analysis (weavec performance goldens)

This document explains what the performance demonstration LLVM files reveal
about weavec codegen quality and where to invest for faster generated code.

The suite is CPU-focused (`test/performance/`). Goldens are pre-optimization
IR (what weavec emits today). LLVM `opt -O2` is not the baseline; we first
make weavec output easy for LLVM to optimize.

## Tools

```bash
# Regenerate report table from all expected-llvm/*.ll
python3 scripts/analyze-performance-llvm.py

# Write the same table to a file (for CI or diffs)
python3 scripts/analyze-performance-llvm.py \
  --markdown docs/llvm-codegen-analysis-report.md
```

Re-run the analyzer after changing goldens or the emitter.

## What “fast compiler” means here

Two different goals:

1. weavec compile time — smaller emitter, less redundant work while printing IR.
2. Generated program speed — LLVM IR that promotes to registers and vectorizes.

This doc focuses on (2). The performance WIR programs are small; the LLVM
shape is what matters for eventual machine code.

## Pattern: i32 loop phis work well

`0073_factorial_iter_i32` promotes both `acc` and `i` to `%acc.phi0` /
`%i.phi0`. The loop body uses SSA names, not repeated `load`/`store` on
`%acc.addr` each iteration.

```llvm
%acc.phi0 = phi i32 [%acc.init0, %while.pre], [%acc.next0, %while.latch]
%acc.next0 = mul i32 %acc.phi0, %i.phi0
```

After `opt -mem2reg`, this is the shape LLVM expects for a tight multiply loop.

## Pattern: i64 / f32 / f64 carried locals stay on the stack

Compare `0158_fibonacci30_i64` and `0171_factorial12_i64`:

- Loop index `i` gets a phi (i32 promotion).
- `prev` / `cur` or `acc` (i64) use `%acc.addr` with `load`/`store` every trip.

```llvm
; 0171_factorial12_i64 while.body (abbreviated)
%t1 = load i64, ptr %acc.addr
%t2 = sext i32 %i.phi0 to i64
%t3 = mul i64 %t1, %t2
store i64 %t3, ptr %acc.addr
```

Priority fix: extend `src/llvm/loop-phi.weave` beyond `type_id == i32` so
`add_i64` / `mul_i64` / `add_f32` / `add_f64` on carried locals get `.nextN`
phis the same way as `mul_i32`.

New fixtures documenting this gap:

| Id | Fixture |
|----|---------|
| 0171 | `0171_factorial12_i64` |
| 0173 | `0173_sum_range_i64_acc` |
| 0170 | `0170_sum_range_f64` (f64 acc on stack) |
| 0172 | `0172_horner_poly_f32` (f32 acc on stack) |

## Pattern: redundant `add %x, 0` phi back-edges

`0061_fibonacci_iterative` (i32) uses:

```llvm
%prev.next1 = add i32 %curr.phi1, 0
%curr.next1 = add i32 %t2, 0
```

when a direct phi operand would suffice (`%curr.phi1` as back-edge for `prev`).

Fix: in loop-phi `set` lowering, detect `set name (local_get other)` with
same carried binding and emit `%name.nextN = %other.phiN` without add-zero.

## Pattern: `sitofp` inside float loops

`0166_sum_range_f32` and `0170_sum_range_f64` convert the loop index every
iteration:

```llvm
%t5 = sitofp i32 %i.phi0 to float
%t6 = fadd float %t4, %t5
```

Improvements:

- Hoist `sitofp` when the only use is adding the index to an accumulator.
- Or keep a running float index (`f32` / `f64` phi) when the source WIR uses
  float accumulation.

`const_f32` / `const_f64` in WIR still lower via `sitofp` from integer tokens
until decimal literals exist — see `0172` (`sitofp i32 3` for coefficient 3).

## Pattern: dead intermediate `let` slots

`0158_fibonacci30_i64` WIR has `(let next i64 ...)` then only `set prev` /
`set cur`. LLVM still allocates stack for `next` if not optimized away.

Fix: frontend or lowering could fold `let`+`set` chains when the binding is
not observed elsewhere.

## Pattern: heap + calls (0174)

`0174_matvec3_f32` exercises `load_f32` / `store_f32` / `call_f32` on heap
arrays. Opportunity is correct GEP strides and eventually SIMD — out of
scope until basic float loops promote.

## New fixtures (0169–0174)

| Id | Focus |
|----|--------|
| 0169 | f64 smoke (`const_f64`, `fadd`) |
| 0170 | f64 sum 1..120 (stack acc) |
| 0171 | i64 factorial (stack acc vs i32 phi index) |
| 0172 | f32 Horner recurrence in loop |
| 0173 | i64 sum 1..200, i32 index |
| 0174 | 3×3 f32 matvec on heap |

Next free id: `0176`.

## Suggested implementation order

1. Loop-phi for i64 (`add_i64`, `mul_i64`, `set` from `local_get`).
2. Loop-phi for f32/f64 (`fadd`, `fmul`, `add_f64`).
3. Copy/set phi back-edge without `add ..., 0`.
4. Fold dead `let` in fibonacci-style swaps.
5. Optional: `opt -O2` comparison script (not replacing goldens) to measure
   runtime of selected benchmarks.

## Related docs

- [performance-demonstrations.md](performance-demonstrations.md) — workflow
- [llvm-codegen-analysis-report.md](llvm-codegen-analysis-report.md) — auto-generated hotspot table
- [loop-phi-contract.md](loop-phi-contract.md) — i32 phi rules today
