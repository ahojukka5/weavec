# Circuit IR and compiled local rewrites

Status: #457 stop-rule measurement on a frozen three-rule set.
Uses the M0 contract in
[Typed deterministic rewrite semantics](rewrite-semantics.md).

This is not public rewrite syntax and not a WIR change. Production
quantum peephole lowering in `src/frontend/quantum_optimize.weave` and
`emit_do_step` is unchanged. The engine here is an ordinary-Weave
circuit optimizer.

## Decision

**STOP.** The generic matcher is acceptable as a sequence-family
prototype, but it must not replace the special-case production path.

On the same three local rules, the special-case linear scan is smaller
and much faster. Keep `qgate` peephole lowering as-is. Do not start ZX
(#458) as a follow-on of this gate: #457 is resolved as a negative
engineering result.

## Circuit representation

A circuit is a compiler-owned sequence of five-tuples stored in a `Vec`
of `i32`:

```text
(kind, q0, q1, q2, param)
```

Unused qubit slots are `-1`. `param` is an exact integer angle in
eighths of a turn (`8` ticks = `2π`) so rotation fusion does not need a
floating-point ABI.

| `kind` | Gate | Self-inverse |
| --- | --- | --- |
| 0 | `I` | no (deleted by identity elimination) |
| 1–4 | `H` `X` `Y` `Z` | yes |
| 5–8 | `CNOT` `CZ` `SWAP` `CCNOT` | yes |
| 9–11 | `RX` `RY` `RZ` | no |

Matching walks this structured sequence. It does not parse source text
or WIR.

## Rules

Four trusted-algebraic rules share one generic enumerator
(`circ_find_match`) and the M0 match key (leftmost site, then longest
span, then rule id):

1. `quantum.circuit/cancel-pair/1` — adjacent equal self-inverse gates
   on the same qubits cancel. Self-inverseness is a table on `kind`, so
   `H·H` is not a special matcher branch.
2. `quantum.circuit/drop-identity/1` — drop `I`, or a rotation whose
   fused angle is `0`.
3. `quantum.circuit/fuse-rotation/1` — adjacent same-axis rotations on
   one qubit fuse; the angle is reduced by full turns (`8` ticks).
4. `quantum.circuit/cancel-inverse/1` — adjacent `S`/`Sdg` or `T`/`Tdg`
   on the same qubit cancel. These are not self-inverse, so they are
   not covered by rule 1.

Search policy is trusted-only fixed-point greedy with a step bound.
Cost is remaining gate count and is not used as a guard.

The special-case arm implements the **same three rules** as a pending
buffer: drop identity, fuse adjacent same-axis rotations, then cancel
adjacent self-inverses, and repeat until a fixpoint. It is not the
production self-inverse-only peephole. That production pass stays
narrower on purpose.

## Comparison arms

On the same `Vec` corpus:

- **generic engine** — enumerate the three rules, apply one M0 winner,
  rescan, bound;
- **special-case scan** — one left-to-right pending-buffer pass per
  sweep, same three identities, repeat to fixpoint.

`test/circuit-rewrite` asserts that both arms produce the same circuit
on the small corpus and on the 200-gate bench block.

## Frozen corpus

| Circuit | Both arms |
| --- | --- |
| `H H` | empty |
| `X q0; X q1` | two `X` |
| `CNOT CNOT` | empty |
| `H I H` | empty |
| `RZ(2) RZ(3)` | one `RZ(5)` |
| `RZ(3) RZ(-3)` | empty, repeat-identical |
| bench block `H H I X X RZ(1) RZ(2) RZ(-3) CNOT CNOT` | empty |

Repeated generic runs on `RZ(3) RZ(-3)` produce the same empty circuit.

## Engineering metrics

Source size is the marked arm regions in
`test/circuit-rewrite/main.weave` (shared IR helpers are excluded from
both counts). The suite prints the counts on every run:

| Arm | Lines |
| --- | --- |
| generic (`circ_find_match`, three rules, apply, rewrite) | 225 |
| special (`circ_special_scan` + `circ_special`) | 117 |

The generic arm is almost twice the special-case source. Compactness
does not favor replacement.

Timed work is 20 copies of the 10-gate bench block (200 gates) reduced
to empty, repeated many times in-process. Wall time is Python
`perf_counter` around the child. Peak RSS is Linux `ru_maxrss` of that
child, in KiB. LUMI `debug`, account `project_462001519`, LLVM 20
Clang, `--mem=2G`:

| Job | Reps | Generic wall | Generic RSS | Special wall | Special RSS |
| --- | --- | --- | --- | --- | --- |
| 22043233 | 4000 | 1.1863 s | 16384 KiB | 0.0051 s | 4624 KiB |
| 22043258 | 20000 | 5.9324 s | 86016 KiB | 0.0192 s | 2792 KiB |

Wall time scales with reps: generic is about **230–310×** the
special-case arm. Special-case time at 20000 reps is 19.2 ms, well
above the 0.001 s smoke floor. Generic peak RSS grows with rewrite
steps because each greedy apply allocates a new circuit vector;
special-case RSS stays a few MiB. Neither compactness nor time nor
memory favors replacement.

The default suite uses 4000 reps so GitHub PR compile stays short.
Override with `CIRCUIT_REWRITE_BLOCKS` / `CIRCUIT_REWRITE_REPS`.

## Stop-rule note

Do not replace `emit_do_step`. The generic engine is slower and larger
on this bounded three-rule sequence problem. Keep production `qgate`
peephole lowering as-is. The engine still belongs in the compiler as a
library: `src/rewrite/circuit.weave` is the sequence-family adapter,
and [ZX graph IR](zx-ir.md) is a separate graph-family milestone, not a
way to reverse this stop rule.

## Library modules

The #457 measurement program in `test/circuit-rewrite` stays frozen so
the stop-rule numbers remain reproducible. Shared types and the
circuit adapter used by later work live in `src/rewrite/`, excluded
from the seed link. See [Rule authoring](rewrite-authoring.md).

## Non-goals of #457

No `rewrite` syntax, no new WIR forms, no equality saturation, no
replacement of `emit_do_step`.
