# ZX graph IR

Status: first graph-family adapter for compiled rewriting
([#458](https://github.com/ahojukka5/weavec/issues/458)).

The representation is ordinary Weave structured data in
`src/rewrite/zx.weave`. It is not a WIR dialect and not a PyZX clone.
The first admitted family is the Clifford+T-oriented circuit subset
that conversion can represent honestly.

## Graph

A graph is one `Vec` of `i32` so it stays inside the current struct-field
layout:

```text
n, last, kinds[n], phases[n], qubits[n], adj[n*n]
```

| Slot | Meaning |
| --- | --- |
| `kinds` | `0` Z-spider, `1` X-spider, `2` input, `3` output |
| `phases` | integer multiples of `π/4` (same ticks as circuit `RZ`) |
| `qubits` | originating wire, used by extraction |
| `adj` | dense undirected matrix: `0` none, `1` simple, `2` Hadamard |
| `last` | node id of the most recent `zx_add_node`, or `-2` on convert failure |

Node ids are dense `0 .. n-1`. Removal compactly remaps ids. Match
enumeration walks increasing node id, then partner id, then rule id.
There is no hash-order walk and no hidden canonicalization between runs.

Inputs and outputs are boundary vertices, one pair per qubit in the
converted circuit.

## Circuit conversion

`zx_from_circuit` is deterministic. It fails with `ok = 0` for gates
the first mapping does not represent: `Y`, `RY`, `SWAP`, `CCNOT`.
Hadamard is a pending wire-edge type, so `H H` becomes a simple
input–output edge without introducing identity spiders.

| Gate | Mapping |
| --- | --- |
| `H` | pending Hadamard edge on the wire (no extra spider) |
| `X` | X-spider, phase `π` |
| `Z` | Z-spider, phase `π` |
| `RZ` / `S` / `T` / daggers | Z-spider with the corresponding ticks |
| `RX` | X-spider with the given ticks |
| `CNOT` | Z on control, X on target, simple edge (Hopf toggle) |
| `CZ` | Z on both wires, Hadamard edge |

A second `CNOT` on the same pair toggles the connecting edge away. That
is the Hopf law, not a hidden special case in extraction.

## Rewrites

Three trusted-algebraic rules share `zx_find_match` and the M0 match
key:

1. `quantum.zx/fuse/1` — adjacent same-color spiders joined by a simple
   edge merge; phases add; neighbor edges are inherited.
2. `quantum.zx/identity/1` — a phase-0 degree-2 spider is replaced by an
   edge whose type is the xor of the two incident types (`H·H = I`).
3. `quantum.zx/color/1` — a Hadamard edge between two Z spiders becomes
   a simple edge to an X spider.

Local complementation and pivot are not in this first kernel. They
need extraction invariants that this slice does not yet admit.

Provenance: spider fusion and identity removal are ZX calculus axioms.
Color change is the Hadamard conjugation of a Z spider. Citations
belong with later independently-checked graph-like simplification
(Kissinger & van de Wetering, Quantum 4, 279).

## Extraction

`zx_extract` is a compiler stage. It walks each input-to-output path
in qubit order and emits:

- `H` for a Hadamard wire edge;
- `RZ` / `RX` for a remaining spider phase;
- `CNOT` when a Z spider has an X neighbor on a higher qubit.

If the walk cannot reach the matching output, or the graph is not in
this admitted path class, extraction returns `ok = 0` and an empty
circuit. Callers must keep that failure. Do not drop the input.

The first admitted class is the image of conversion after the three
rules above. It is enough to cancel `H H`, fuse adjacent `RZ`, and
cancel `CNOT CNOT`. It is not a general gflow extractor.

## Equivalence

`test/zx-rewrite` runs the pipeline and an independent Python
statevector oracle (`check_unitary.py`) on the dumped IN/OPT pairs.
Global phase is ignored. Empty extracted circuits keep the input
width for the comparison. The tolerance is `1e-6` on matrix entries
after phase alignment. Structural checks cover qubit usage and
unsupported conversion.

## Determinism

The same circuit, rule set, and bound must produce the same graph after
rewriting and the same extracted circuit. Tests repeat the `RZ` fusion
pipeline twice.

## Non-goals

No equality saturation, no learned policy, no topology routing, no
claim that Weave invented ZX rewriting, no private quantum WIR.
