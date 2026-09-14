# Circuit IR and compiled local rewrites

Status: first executable circuit matcher under
[#457](https://github.com/ahojukka5/weavec/issues/457), using the M0
contract in [Typed deterministic rewrite semantics](rewrite-semantics.md).

This is not public rewrite syntax and not a WIR change. The production
quantum peephole in `src/frontend/quantum_optimize.weave` still owns
surface `qgate` lowering. The engine here is an ordinary-Weave circuit
optimizer compared against that peephole on a frozen in-memory corpus.

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

Three trusted-algebraic rules share one generic enumerator
(`circ_find_match`) and the M0 match key (leftmost site, then longest
span, then rule id):

1. `quantum.circuit/cancel-pair/1` — adjacent equal self-inverse gates
   on the same qubits cancel. Self-inverseness is a table on `kind`, so
   `H·H` is not a special matcher branch.
2. `quantum.circuit/drop-identity/1` — drop `I`, or a rotation whose
   fused angle is `0`.
3. `quantum.circuit/fuse-rotation/1` — adjacent same-axis rotations on
   one qubit add their ticks.

Search policy is trusted-only fixed-point greedy with a step bound.
Cost is remaining gate count and is not used as a guard.

## Comparison arms

On the same `Vec` corpus:

- **hand-written peephole** — pending-pair scan copied from
  `emit_do_step`: only self-inverse cancellation, one left-to-right
  pass;
- **generic engine** — the three rules above, full rescan after each
  rewrite.

The production compiler is unchanged, so current quantum surface
fixtures stay valid.

## Frozen corpus and results

`test/circuit-rewrite` encodes the cases and asserts them on every run:

| Circuit | Peephole | Generic |
| --- | --- | --- |
| `H H` | empty | empty |
| `X q0; X q1` | two `X` | two `X` |
| `CNOT CNOT` | empty | empty |
| `H I H` | three gates | empty |
| `RZ(2) RZ(3)` | two `RZ` | one `RZ(5)` |
| `RZ(3) RZ(-3)` | two `RZ` | empty, repeat-identical |

Self-inverse-only circuits match both arms. Identity elimination and
rotation fusion make the generic engine strictly stronger on the last
three rows. That is expected: those identities are in the generic rule
set and not in today's AST peephole.

Repeated generic runs on `RZ(3) RZ(-3)` produce the same empty circuit.

## Engineering metrics

Source size is measured by the suite from the files themselves:

- generic witness (`test/circuit-rewrite/main.weave`): 573 lines, including
  IR, three rules, engine, peephole twin, and corpus driver;
- hand-written predicate module
  (`src/frontend/quantum_optimize.weave`): 173 lines.

Wall time of one optimized corpus process was `0.001` s on the LUMI
debug runner that executed the suite. Max RSS from GNU `time` was not a
usable figure (`0` KB). These are smoke numbers: the circuits are too
small to decide the #455 stop rule. The qualitative result is that the
generic matcher is more code than the special-case predicate, and
faster-or-slower is not yet a meaningful comparison.

## Stop-rule note

Do not replace `emit_do_step` yet. The generic engine is not materially
more compact than the current pass once IR, apply, and the comparison
driver are counted, and it has not been shown faster on realistic
circuits. Keep the AST peephole as the production path. Use this engine
as the sequence-family adapter for later ZX work rather than hiding
cost with a native special case.

## Non-goals

No `rewrite` syntax, no new WIR forms, no ZX, no equality saturation,
no compiler-pipeline wiring, no hardware pack.
