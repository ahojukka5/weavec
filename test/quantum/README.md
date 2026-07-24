# Quantum tests

Surface `.weave` programs; goldens are `.expected.wir` beside each source.
Efficiency claims use `.metrics` sidecars (lowered gate counts) and the
LLVM-IR optimality harness.

Run (after `./build.sh`):

```bash
./test/quantum/test.sh        # WIR goldens + --dump-quantum-stats metrics
./test/quantum/test-e2e.sh    # Surface -> WIR -> LLVM -> exec, runtime trace
./test/quantum/test-llvm.sh   # Surface -> LLVM, structural optimality
```

`test-all.sh` runs all three.

## Layout

| Path | Checks |
|------|--------|
| `nativization/` | H nativize (Rigetti pack), measure |
| `gates/` | Single-qubit lowering: X, Y, Z, S, T, RX |
| `multi-qubit/` | 2- and 3-qubit lowering: CZ, SWAP, CCNOT |
| `benchmarks/` | Named circuits: Bell pair, GHZ-3, teleport, QFT-3 |
| `algorithms/` | Real algorithms verified end-to-end: Deutsch-Jozsa (constant + balanced) |
| `optimization/` | Self-inverse cancellation (H, X, Y, Z, CNOT, CZ, SWAP, CCNOT) |
| `validation/` | Frontend must reject |
| `e2e/` | Full pipeline + runtime amplitude/trace assertions |

The `algorithms/` and `e2e/` fixtures are both run by `test-e2e.sh` — they
build to a native binary and check the exit code against `.metrics`.

## Metrics format

One `key=value` per line (byte-stable, sorted keys in goldens):

```text
native_gates=3
two_qubit_gates=1
depth=3
```

Produced by:

```bash
./build/weavec --dump-quantum-stats /tmp/out.metrics test/quantum/benchmarks/bell-pair.weave
```

`native_gates` counts lowered `qrt_*` calls (H becomes RY+RZ). `depth` is the
same sequential count after peephole. `two_qubit_gates` counts CNOT/CZ/SWAP
and the 3-qubit CCNOT (a misnomer for the latter, kept for back-compat).

E2E fixtures may also use:

```text
trace_count=3
exit_code=3
```

## LLVM-IR optimality

`test-llvm.sh` compiles each fixture all the way to LLVM IR and asserts that
`@main` is exactly what a hand-written ideal implementation would emit:

- `call (void|i32) @qrt_*` count matches `native_gates` in the `.metrics` sidecar.
- Zero `alloca`, `store`, `load`, or arithmetic ops in `@main`. Qubit handles
  must flow through as `i64` immediates, not stack-roundtripped values.
- Every `qrt_*` call argument is an immediate — no `%register` operands.

For self-inverse-cancellation fixtures (`optimization/test-double-*-cancel`)
this means `@main` reduces to a single `ret i32 42` — the peephole erases the
pair before WIR emission, so there is literally nothing left to lower.

## Self-inverse cancellation

The frontend runs a generic gate-cancellation peephole driven by
`qgate_self_inverse_match` in `src/frontend/quantum_optimize.weave`. Two
consecutive `qgate` forms cancel iff:

1. Both name the same gate AND
2. The gate is in the self-inverse set
   `{ H, X, Y, Z, CNOT, CZ, SWAP, CCNOT }` AND
3. Every operand identifier compares equal by source text.

The predicate is intentionally syntactic — `CNOT q0 q1` and `CNOT q1 q0` do
NOT cancel, since the qubit roles differ.

Not self-inverse (and excluded): `S` (S² = Z), `T` (T² = S), `RX/RY/RZ`
(parameterized; cancellation depends on angles summing to a multiple of 2π).

## Statevector simulator

`runtime/quantum_runtime.c` is now a real 8-qubit statevector simulator
(2⁸ = 256 complex amplitudes). Each `qrt_*` call applies the matching
unitary to the global state; tests inspect the resulting amplitudes via:

```text
qrt_basis_prob_pct(idx)         -> P(|idx>) in percent (0..100, rounded)
qrt_marginal_prob_pct(q, value) -> P(qubit q = value) in percent
qrt_nonzero_basis_count()       -> count of significant basis states
qrt_get_trace_count()           -> gate count (unchanged)
qrt_measure(q)                  -> deterministic collapse to more-likely outcome
qrt_reset()                     -> back to |0...0>
```

Probabilities are expressed as integer percent so the test harness can use
them as the program exit code. For example, a Bell pair returns
`prob(|00>) + prob(|11>) = 100`.

## Algorithms verified end-to-end

- `algorithms/deutsch-jozsa-constant.weave` — DJ with `f(x) = 0` oracle
  (identity). Final marginal `P(q0=0) = 100%`.
- `algorithms/deutsch-jozsa-balanced.weave` — DJ with `f(x) = x` oracle
  (CNOT q0 q1). Final marginal `P(q0=1) = 100%`.

These exercise the full pipeline: H decomposition, CNOT lowering, statevector
update, and amplitude inspection. They are the first tests that would fail
if any of those is even *phase-wrong* (DJ depends on relative phase, not just
on measurement probabilities of single qubits).

## Implementation

- Self-inverse predicate + lowercase gate-name helper:
  `src/frontend/quantum_optimize.weave`
- H decomposition (Rigetti pack: `RZ(π)` then `RY(π/2)`, giving `H` up to
  global phase `-i`): `src/frontend/quantum_nativize.weave`
- Self-inverse peephole on emit: `src/frontend/emit.weave` (`emit_do_step`,
  `emit_do_body`)
- Multi-qubit lowering (CNOT, CZ, SWAP, CCNOT) + generic lowercase fallback:
  `src/frontend/emit.weave` (`emit_qgate_direct`)
- Stats counting (mirrors peephole): `src/frontend/quantum_stats.weave`
  (`stats_do_step`, `stats_count_do_body`)
- Statevector simulator: `runtime/quantum_runtime.c`
