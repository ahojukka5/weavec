# Quantum compiler flagship and current surface support

Status: partially implemented baseline; strategic rewrite-compiler work planned
under [#455](https://github.com/ahojukka5/weavec/issues/455)

Quantum operations are surface-Weave forms compiled by the same self-hosted
frontend and backend as classical code. There is no separate quantum source
extension or parallel compiler. Current support demonstrates parsing, selected
rewrites, current WIR lowering, LLVM emission, statistics, and execution against
a test runtime stub.

It is not yet a production quantum-hardware runtime or complete quantum language.
The current path is the baseline for a larger strategic experiment: using quantum
circuit and ZX-calculus optimization as the flagship application of Weave's
planned [compiled rewriting](compiled-rewriting.md) substrate.

## Strategic position

Quantum compilation is important to the project because it is a demanding and
measurable use case for structured transformation, not because quantum hardware
concepts should define the core language.

The intended split is:

- **core reusable capability:** typed compiler-owned representations, compiled
  deterministic rewrite rules, explicit cost functions, and bounded search;
- **flagship application:** circuit and ZX-calculus optimization;
- **experimental compatibility surface:** current `Qubit`, `qgate`, `qmeasure`,
  quantum statistics, nativization, and test runtime;
- **domain/target policy:** native gate sets, decomposition policy, cost weights,
  and later topology/routing belong in packs rather than hard-coded language
  semantics.

The current quantum peephole and nativization code must remain correct while the
new substrate is developed. It is a comparison baseline, not the final optimizer
architecture.

## Current source model

Quantum handles use the surface type `Qubit`. Current regression fixtures use an
integer-backed handle supplied to quantum forms:

```weave
(entry main
  (params)
  (returns i32)
  (do
    (let q0 Qubit (const_i64 0))
    (qgate H q0)
    (return (const_i32 42))))
```

The current compiler accepts quantum operations inside ordinary functions and
entries alongside classical control flow and values.

`Qubit` is currently narrower than the planned semantic model. The structured
type work should eventually make it a real nominal semantic type whose lowering
may still use an integer handle, rather than erasing quantum identity and
re-deriving it in a side path.

## Gate application

A gate application is a statement:

```weave
(qgate H q0)
(qgate CNOT q0 q1)
(qgate RZ q0 angle)
```

The first operand is the gate name. Remaining operands are qubit handles and, for
parameterized gates, classical angle values supported by the current lowering.

`qgate` is not an ordinary function call. Keeping it as a distinct surface form
allows frontend nativization, statistics, and peephole optimization before WIR
emission.

This syntax is not the proposed rewrite language. Future optimization rules act
on structured circuit/graph representations; a later `qrewrite`-style spelling
would be ergonomic sugar only after the rule semantics have been validated.

## Measurement

Measurement is a statement with a qubit handle and a result-local name:

```weave
(qmeasure q0 c0)
```

The frontend lowers this to an `i32` call to `qrt_measure` and introduces the
named local in emitted WIR. A complete current example is:

```weave
(program
  (name "hadamard-measure")
  (version "0.1")
  (extern qrt_ry (params (q i64) (theta_nr i64)) (returns void))
  (extern qrt_rz (params (q i64) (phi_nr i64)) (returns void))
  (extern qrt_measure (params (q i64)) (returns i32))
  (entry main
    (params)
    (returns i32)
    (do
      (let q0 Qubit (const_i64 0))
      (qgate H q0)
      (qmeasure q0 c0)
      (return (local_get c0)))))
```

Basis selection, ownership, hardware scheduling, and richer classical-bit types
are not stable language contracts yet.

## Current frontend pipeline

Quantum processing is implemented in ordered frontend modules under
`src/frontend/`: gate optimization, native-gate rewriting, statistics
collection, and the shared emission path. `compiler/sources.list` declares which
files participate and in what order.

The current self-hosted sequence is:

```text
surface source
    │ parse and combine modules
    ▼
quantum surface forms
    │ selected hand-written peephole optimization
    ▼
optimized quantum forms
    │ gate nativization
    ▼
runtime-call-compatible forms
    │ normal surface lowering
    ▼
WIR core version 3
    │ self-hosted backend
    ▼
LLVM IR
```

The LLVM backend does not own high-level gate decomposition. It emits the WIR
produced by the frontend, keeping quantum transformations above the WIR backend.

This quantum path uses the current WIR boundary; the frozen seed bootstrap
remains at core version 2. See [Architecture](architecture.md) and
[WIR core version 3](wir.md).

## Planned flagship pipeline

The first compiled-rewrite experiment is deliberately bounded:

```text
surface quantum program
  -> circuit IR
  -> compiled local circuit rewrites
  -> ZX graph IR
  -> compiled ZX rewrites
  -> deterministic circuit extraction
  -> bounded cost-based selection
  -> optimized circuit
```

The initial domain is a small Clifford+T-oriented gate set. The purpose is to
measure whether the generic rewrite substrate can replace special-case pass code
compactly and efficiently, while producing competitive circuit quality.

The implementation is split into:

- [#456](https://github.com/ahojukka5/weavec/issues/456) — rewrite semantics;
- [#457](https://github.com/ahojukka5/weavec/issues/457) — circuit IR and local
  compiled rewrites;
- [#458](https://github.com/ahojukka5/weavec/issues/458) — ZX graph rewrites and
  circuit extraction;
- [#459](https://github.com/ahojukka5/weavec/issues/459) — deterministic bounded
  search and target packs;
- [#460](https://github.com/ahojukka5/weavec/issues/460) — comparison against the
  current Weave path and PyZX.

Automatic rewrite discovery, equality saturation, learned rewrite selection,
routing, and noise-aware compilation are follow-up questions rather than
requirements for the first result.

## Hadamard nativization

The implemented Hadamard rule lowers one `H` gate to runtime calls corresponding
to rotations. Current expected WIR orders them as:

```text
qrt_rz(q0, π)
qrt_ry(q0, π/2)
```

The regression fixture declares these runtime targets explicitly and compares the
complete emitted WIR. Angle values use the current integer-number representation
expected by the runtime stub; this is not yet a general floating-parameter
quantum ABI.

## Peephole optimization

The frontend includes selected local quantum optimizations. Current regression
coverage includes cancellation of adjacent Hadamard operations where the
implemented rules prove the pair redundant.

These are deterministic compiler rewrites, not runtime circuit optimization.
They must preserve expected WIR/LLVM fixtures and quantum statistics.

The new circuit-rule work in #457 must compare against this implementation rather
than silently deleting the baseline before generic matching is measured.

## Runtime boundary

Quantum lowering currently emits external `qrt_*` calls. The repository contains:

```text
runtime/quantum_runtime.c
```

This file exists for tests and native end-to-end validation. It is explicitly a
test stub:

- it does not submit work to quantum hardware;
- it does not model full quantum state semantics;
- it is not included as the production private program runtime contract;
- it is not a supported device API.

A future production runtime or target package requires its own versioned ABI,
validation, and packaging design. Production hardware execution is not required
for the first compiled-rewrite study.

## Quantum statistics

The compiler can write deterministic metrics for one source file:

```sh
weavec --dump-quantum-stats output.metrics input.weave
```

The quantum regression suite compares these sidecars to expected results. The
mode reports compiler-visible quantum operations; it is not dynamic profiling or
hardware telemetry.

Future optimizer benchmarks need stronger circuit-level metrics such as T count,
two-qubit count and depth. Those benchmark metrics belong to the optimization
study and must not silently change the current command's published meaning.

## Tests

The full quantum coverage is run by `./test-all.sh` and consists of:

```text
test/quantum/test.sh
test/quantum/test-e2e.sh
test/quantum/test-llvm.sh
```

Together these validate:

- surface parsing and lowering;
- Hadamard nativization;
- implemented peephole rewrites;
- deterministic quantum metrics;
- LLVM validity;
- native linkage and execution against the test runtime stub.

Run only the quantum layers with:

```sh
./test/quantum/test.sh
./test/quantum/test-e2e.sh
./test/quantum/test-llvm.sh
```

Run the complete compiler and self-host ladder with:

```sh
./test-all.sh
```

## Current limitations

- `Qubit` is a compiler-visible handle, not a complete ownership-checked resource.
- The runtime is a test stub rather than a device or simulator product.
- Gate set, arity validation, angle representation, and measurement types are
  intentionally narrow.
- There is no production scheduling, routing, noise model, target calibration,
  or hardware execution interface.
- The compiled rewrite substrate, ZX graph stage, target packs, and bounded
  search are planned work under #455, not implemented behavior.
- Quantum source locations are subject to the same current diagnostic limits as
  other backend-originated errors.

## Design rules for future work

Future quantum features should continue to follow these boundaries:

1. quantum code remains ordinary `.weave` source;
2. high-level circuit and graph transformations stay above the ordinary WIR
   backend;
3. optimization rewrites use the shared compiled-rewrite semantics instead of
   accumulating gate-specific matcher branches when that substrate is ready;
4. macros remain distinct source-expansion machinery rather than an implicit
   optimizer-rule system;
5. new WIR forms require a coordinated versioned compiler-chain decision rather
   than a private final-compiler dialect;
6. hardware/runtime interfaces require explicit versioned ABIs or target packs;
7. every implemented form or rewrite requires surface, structural/IR, and where
   applicable end-to-end regression coverage;
8. circuit quality, optimizer cost, and rule/infrastructure source size are all
   measured before calling the quantum path a flagship success.
