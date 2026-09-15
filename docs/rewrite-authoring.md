# Rule authoring

Status: production-Weave rewrite library under `src/rewrite/`, not linked
into the bootstrap seed compiler. See
[Typed deterministic rewrite semantics](rewrite-semantics.md) for the
match key and provenance contract.

A rewrite rule is an ordinary Weave value: identity, pattern, guard,
replacement, semantic domain, and soundness class. There is no
`rewrite` surface syntax. Do not add one unless measurement shows the
semantic model needs it.

## Where code lives

| Module | Role |
| --- | --- |
| `src/rewrite/engine.weave` | match key, packed rule ids, soundness filter, cost vector |
| `src/rewrite/circuit.weave` | circuit IR and compiled local rules |
| `src/rewrite/zx.weave` | ZX graph IR, conversion, graph rules, extraction |
| `src/rewrite/targets.weave` | topology-free target packs |

These files are classified with `!` in `compiler/sources.list`. They are
compiler-owned libraries built with production `weavec`, not seed
frontend sources. High-level quantum transformation stays above WIR.

## Rule identity

Pack a stable triple with `rw_pack_id`:

```text
rule-id = namespace * 1000 + name * 10 + version
```

Namespaces currently used:

- `3` `quantum.circuit`
- `4` `quantum.zx`

Changing pattern, guard, replacement, or provenance requires a new
version. Search order of a rule set is not part of the identity.

Name `9` is reserved as a heuristic probe. The default strategy rejects
it.

## Pattern matching

A family adapter enumerates candidate matches. The engine selects by
the contract key:

```text
(site ascending, span descending, rule-id ascending, payload ascending)
```

Discovery order must not change the winner. Overlapping matches are
all considered; conflict is resolved after enumeration.

Guards are ordinary functions. They must not mutate the subject. They
must not read search policy or cost.

A replacement constructs a new subject. It must not apply further
rewrites.

## Sequence example (circuit)

Adjacent self-inverse cancellation is one rule. Self-inverseness is a
table on `kind`; the matcher does not special-case `H`.

```weave
(fn circ_rule_cancel_ok
  (params (data (type-app Vec i32)) (start i32))
  (returns bool)
  (do
    ...
    (return (op and
      (call gate_is_self_inverse kind)
      (call same_qubits data start (op add start 1))))))
```

Search policy is trusted-only fixed-point greedy with a step bound. Cost
is not a guard. See [Circuit IR](circuit-rewrite.md).

## Graph example (ZX)

Spider fusion is the same match key over node ids. The payload is the
partner node. Fusion, identity removal, and Hadamard color-change share
`zx_find_match`. See [ZX graph IR](zx-ir.md).

## Side conditions

State them as predicates, not comments:

- same qubits for adjacent cancellation;
- same rotation axis for fusion;
- inverse pairs `S`/`Sdg` and `T`/`Tdg` (either order) on one qubit;
- simple edge and equal color for spider fusion;
- phase 0 and degree 2 for identity removal.

Do not assume commutativity. If two gates may not be adjacent, they are
not a match.

## Diagnostics

Match objects carry `rule`, `start`, `span`, and `extra`. Packed ids
decode with `rw_id_namespace`, `rw_id_name`, and `rw_id_version`. Failure
codes live on the engine:

- `rw_fail_unsupported`
- `rw_fail_extract`
- `rw_fail_equiv`
- `rw_fail_target`
- `rw_fail_bound`

Keep print-debugging out of benchmark drivers. Tests should assert
these codes.

## Cost and policy

`CostVector` reports non-Clifford count, two-qubit count, and depth
separately. `twoq` counts `CNOT`, `CZ`, and `SWAP` only. `CCNOT` is
arity 3 and is not folded into `twoq`; depth still includes it.
`rw_cost_better` compares `(nonclifford, twoq, depth)` lexicographically.
A later strategy may scalarize; the raw vector remains available.
A named three-qubit quantity would be a new field, not a redefinition
of `twoq`.

Target packs in `src/rewrite/targets.weave` decide legality by admitted
`kind`, not by arity. They do not implement matching or cost.

## Testing a rule

A semantics-preserving rule needs at least one of:

1. an independent oracle on a frozen finite family;
2. a small statevector check (the ZX suite uses
   `test/zx-rewrite/check_unitary.py`);
3. a cited external identity for `independently-checked` rules.

Disagreement falsifies the rule or the engine. Agreement on a corpus
is qualification, not a theorem.

## Using the library from another domain

Build with production `weavec` and the standard library, then the
engine, then a family adapter:

```sh
weavec build \
  stdlib/memory.weave stdlib/option.weave stdlib/vec.weave \
  stdlib/io.weave \
  src/rewrite/engine.weave \
  my-domain.weave \
  main.weave \
  -o domain-rewrite
```

Supply:

- a structured subject (not source text);
- typed pattern variables as ordinary locals;
- guards and replacements;
- packed rule ids in your namespace.

You do not need the quantum circuit or ZX modules.
