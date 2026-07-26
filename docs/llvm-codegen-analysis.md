# LLVM code-generation analysis

Status: current optimization snapshot for the checked-in performance goldens

This document explains what the deterministic pre-optimization LLVM corpus under
`test/performance/expected-llvm/` reveals about current backend output. It is an
engineering snapshot, not a stable public compiler contract and not a claim about
final optimized machine-code performance.

The associated generated table is
[`llvm-codegen-analysis-report.md`](llvm-codegen-analysis-report.md).

## Regenerating the report

```sh
python3 scripts/analyze-performance-llvm.py
python3 scripts/analyze-performance-llvm.py \
  --markdown docs/llvm-codegen-analysis-report.md
```

Regenerate the report whenever checked-in performance goldens change.

## Two different performance questions

1. **Compiler throughput:** how much work `weavec` performs while parsing,
   lowering, and printing LLVM.
2. **Generated-program quality:** whether emitted LLVM has a shape that LLVM can
   promote, simplify, vectorize, and optimize effectively.

The current report measures static properties of generated LLVM and focuses on
the second question. It does not measure wall-clock compilation or execution.

## Strong current pattern: `i32` loop phis

Representative `i32` loops promote carried locals to explicit header phis:

```llvm
%acc.phi0 = phi i32 [%acc.init0, %while.pre], [%acc.next0, %while.latch]
%acc.next0 = mul i32 %acc.phi0, %i.phi0
```

This avoids repeated stack loads and stores in the loop body and gives later LLVM
passes a conventional SSA shape.

The invariants are documented in
[Loop-carried SSA contract](loop-phi-contract.md).

## Main current opportunity: wider carried locals

Many `i64`, `f32`, and `f64` carried locals remain stack-backed even when an
`i32` loop index is promoted. A representative wide accumulator therefore looks
like:

```llvm
%t1 = load i64, ptr %acc.addr
%t2 = sext i32 %i.phi0 to i64
%t3 = mul i64 %t1, %t2
store i64 %t3, ptr %acc.addr
```

The generated report identifies fixtures with loop-body loads, stores, and
stack-carried names. Extending the existing loop-phi model beyond `i32` is the
largest recurring backend cleanup visible in the current corpus.

Representative fixtures include:

- `0158_fibonacci30_i64`;
- `0161_collatz_peak_i64`;
- `0166_sum_range_f32`;
- `0168_newton_sqrt_f32`;
- `0170_sum_range_f64`;
- `0171_factorial12_i64`;
- `0172_horner_poly_f32`;
- `0173_sum_range_i64_acc`;
- `0175_sum_squares_i64`.

## Copy-like phi back edges

Some `i32` assignments use an arithmetic identity to create the next SSA value:

```llvm
%prev.next1 = add i32 %curr.phi1, 0
```

A direct carried-value edge would be simpler where the assignment is a pure copy.
This is a code-quality opportunity rather than a semantic defect; the golden
corpus keeps the current behavior reviewable.

## Floating conversion inside loops

Float accumulation fixtures may convert an integer loop index on every iteration:

```llvm
%t5 = sitofp i32 %i.phi0 to float
%t6 = fadd float %t4, %t5
```

Possible future improvements include a running floating index or safe conversion
hoisting. These should be evaluated against clear source and WIR semantics rather
than introduced only to make one golden smaller.

`const_f32` and `const_f64` also currently lower from integer literal tokens
through `sitofp`. Decimal literal syntax is a separate language and WIR design
question.

## Dead temporary storage

Some algorithm fixtures create a typed local used only to feed a subsequent
assignment. Pre-optimization LLVM may retain an `alloca` for that temporary.
Potential cleanup belongs in a general dead-binding or value-forwarding rule,
with regressions proving that control-flow and contract semantics remain intact.

## Heap and call-heavy fixtures

Heap-oriented fixtures exercise pointer arithmetic, typed loads/stores, external
calls, and stride calculations. Their current value is primarily correctness and
LLVM-shape coverage. SIMD, alias analysis, and target-specific optimization are
premature until scalar carried-state and basic memory patterns are consistently
clean.

## Interpreting the generated score

The report's opportunity score is a review aid based on static counts such as:

- `alloca`, `load`, and `store` instructions;
- loop phis;
- loads inside loop bodies;
- copy-like `add ..., 0` operations;
- `sitofp` conversions;
- detected stack-carried local names.

A high score means “inspect this golden,” not “this program is slow.” LLVM may
eliminate many pre-optimization artifacts, and instruction count alone does not
predict target performance.

## Recommended review order

When backend work resumes, review opportunities in this order:

1. generalize carried-local phis to admitted wider scalar types;
2. simplify copy-like back edges without breaking SSA provenance;
3. remove dead temporary bindings through a general rule;
4. assess conversion placement in floating loops;
5. compare selected cases after normal LLVM optimization and, only then, add
   runtime measurements where they answer a concrete question.

Every change requires regenerated goldens, `llvm-as` validation, semantic fixture
execution, the complete test ladder, and deep self-hosting when compiler output
changes.

## Related documents

- [Performance demonstrations](performance-demonstrations.md)
- [Generated LLVM analysis report](llvm-codegen-analysis-report.md)
- [Loop-carried SSA contract](loop-phi-contract.md)
- [Architecture](architecture.md)
