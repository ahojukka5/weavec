# LLVM code-generation analysis

## Evidence layers

`weavec` exposes distinct artifacts for distinct questions:

1. WIR records frontend semantics.
2. Raw LLVM records deterministic backend lowering and provenance.
3. Optimized LLVM records the selected LLVM profile's scalar and control-flow
   result.
4. Target assembly and linked-image disassembly record static native code.
5. Runtime measurements answer workload-specific performance questions.

Raw LLVM is intentionally not the final performance representation.

## Uniform mutable lowering

Mutable locals use stack slots in raw LLVM, including loop-carried `i32`, `i64`,
`f32`, and `f64` values. The optimizer then constructs the conventional phis and
removes eligible memory traffic. For example, raw Fibonacci state becomes an
optimized loop resembling:

```llvm
%i.phi = phi i32 [ %i.next, %while.body ], [ 2, %entry ]
%curr.phi = phi i32 [ %curr.next, %while.body ], [ 1, %entry ]
%prev.phi = phi i32 [ %curr.phi, %while.body ], [ 0, %entry ]
```

This boundary is the uniform mutable stack lowering described below: the
backend emits stack slots and LLVM reconstructs the phis.

## Why the custom SSA path was removed

The former backend contained dedicated loop-phi, branch-merge, latch, and
exit-synchronization logic. A 168-fixture A/B test found identical optimized
structural metrics for every fixture, byte-identical object text for 155 fixtures,
and no systematic runtime benefit. LLVM reconstructed the same optimized phis
from uniform stack semantics. This section is what remains of that evidence;
the separate comparison pages were removed with the subsystem they measured.

## Reading the generated raw report

[`llvm-codegen-analysis-report.md`](llvm-codegen-analysis-report.md) counts raw
allocas, loads, stores, loop-body address loads, conversions, and mutable
candidates. Its pressure score ranks how much work is delegated to LLVM. A high
score is not by itself a backend defect. Review the corresponding optimized LLVM
and linked-image disassembly before proposing compiler logic.

Useful questions include:

- Did an eligible stack slot survive the selected optimized profile?
- Did bounds, aliasing, or calls prevent a general LLVM transformation?
- Does the final machine code contain avoidable work?
- Is a difference repeatable in a representative runtime benchmark?
- Does `weavec` possess semantic information LLVM cannot recover?

Only the last question normally justifies additional compiler-side lowering.

## Reproducing the raw analysis

```bash
python3 scripts/analyze-performance-llvm.py \
  --markdown docs/llvm-codegen-analysis-report.md
```

For final-code evidence use the public native artifact options described in
[Native optimization and machine-code evidence](native-code-evidence.md), or use
`weave-loupe` to compare complete evidence bundles.

## Related documents

- [Performance demonstrations](performance-demonstrations.md)
- [Performance demonstrations](performance-demonstrations.md)
- [Architecture](architecture.md)
