# Quantum surface support

Status: partially implemented and regression-tested

Quantum operations are surface-Weave forms compiled by the same frontend and
backend as classical code. There is no separate quantum source extension or
parallel compiler. Current support demonstrates parsing, validation, selected
rewrites, WIR lowering, LLVM emission, statistics, and execution against a test
runtime stub.

It is not yet a production quantum-hardware runtime or complete quantum language.

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

## Measurement

Measurement is an expression:

```weave
(let result i32 (qmeasure q0))
```

The current lowering targets a test runtime call. Basis selection, ownership,
hardware scheduling, and richer classical-bit types are not stable language
contracts yet.

## Frontend pipeline

Quantum processing is implemented in ordered frontend modules:

```text
src/frontend/quantum_optimize.weave
src/frontend/quantum_nativize.weave
src/frontend/quantum_stats.weave
src/frontend/emit.weave
```

The compiler uses this conceptual sequence:

```text
surface source
    │ parse and combine modules
    ▼
quantum surface forms
    │ selected peephole optimization
    ▼
optimized quantum forms
    │ gate nativization
    ▼
runtime-call-compatible forms
    │ normal surface-to-WIR lowering
    ▼
WIR v2
    │ ordinary backend
    ▼
LLVM IR
```

The LLVM backend does not own high-level gate decomposition. It emits the WIR
produced by the frontend, keeping quantum transformations in the surface compiler.

## Hadamard nativization

The implemented Hadamard rule lowers one `H` gate to native rotations:

```weave
(qgate H q0)
```

becomes calls corresponding to:

```text
qrt_ry(q0, π/2)
qrt_rz(q0, π)
```

The regression fixture declares the generated runtime targets explicitly and
checks the expected WIR. Angle values use the current integer-number
representation expected by the runtime stub; this is not yet a general
floating-parameter quantum ABI.

## Peephole optimization

The frontend includes selected local quantum optimizations. Current regression
coverage includes cancellation of adjacent Hadamard operations where the
implemented rules prove the pair redundant.

These are deterministic compiler rewrites, not runtime circuit optimization.
They must preserve the expected WIR/LLVM fixtures and quantum statistics.

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
- it must not be presented as a supported device API.

A future production runtime or target package requires its own versioned ABI,
validation, and packaging design.

## Quantum statistics

The compiler can write deterministic metrics for one source file:

```sh
weavec --dump-quantum-stats output.metrics input.weave
```

The quantum regression suite compares these sidecars to expected results. The
mode reports compiler-visible quantum operations; it is not dynamic profiling or
hardware telemetry.

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
- First-class user-defined transform registries and target packs remain future
  design work.
- Quantum source locations are subject to the same current diagnostic limits as
  other backend-originated errors.

## Design rule for future work

Future quantum features should continue to follow these boundaries:

1. quantum code remains ordinary `.weave` source;
2. high-level gate validation and decomposition belong in frontend passes;
3. WIR changes require a coordinated versioned compiler-chain decision;
4. hardware/runtime interfaces require explicit versioned ABIs;
5. every implemented form or rewrite requires surface, WIR/LLVM, and where
   applicable end-to-end regression coverage.
