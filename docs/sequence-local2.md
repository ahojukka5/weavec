# SequenceLocal2 specialization profile

Status: design draft. This document specifies the first bounded specialization profile proposed by [Compiled transformation design](transform-design.md).

## Purpose

`SequenceLocal2` identifies a restricted class of deterministic rewrite systems that can be compiled into a specialized sequence reducer without runtime rule enumeration, whole-subject rescans or `RewriteMatch` allocation.

The specialization must preserve the observable semantics of the generic rewrite contract. It is an implementation specialization, not a different rewrite strategy.

## Representation contract

The subject is an ordered finite sequence:

```text
S = [e0, e1, ..., en-1]
```

The family must provide efficient semantic operations equivalent to:

```text
length
get
push
peek-last
peek-second-last
pop or truncate
replace-last
```

Element representation remains family-specific. The first experiment uses the current packed `CircuitIR` gate representation; the profile does not require redesigning it.

The generic collection layer needs a proper stack-contraction capability (`pop` or `truncate`) rather than rewrite code reaching into private vector storage.

## Admitted rule shapes

Version 1 accepts only strictly length-reducing contiguous rules:

```text
[A]    -> []
[A,B]  -> []
[A,B]  -> [C]
```

Therefore:

```text
match span in {1,2}
replacement length < match span
```

Not admitted in version 1:

```text
[A]      -> [B]
[A]      -> [B,C]
[A,B]    -> [C,D]
[A,B,C]  -> ...
```

Every successful rewrite reduces sequence length by at least one, so the number of successful logical rewrites is bounded by the original sequence length.

## Guard and replacement restrictions

A guard is pure, deterministic and local. It may inspect the matched elements, their bound fields, immutable domain tables and compile-time target/capability metadata.

It may not inspect global optimizer state, search history, current cost, wall clock, random state, mutable external state or unrelated subject elements. Version 1 also excludes absolute-position-dependent semantics.

A replacement is likewise pure and deterministic. For a binary rule it may remove both elements or replace them with one element derived from the bindings. For a unary rule it may only remove the element.

Replacement code does not recursively apply another rewrite; any newly enabled rewrite is another logical event.

## Strategy semantics

The semantic strategy remains the M0 ordering from `rewrite-semantics.md`:

```text
site ascending
span descending
rule-id ascending
payload ascending
```

Conceptually the generic engine finds the globally winning match, applies exactly one rule, records one logical event, and rescans.

`SequenceLocal2` must produce the same selected rule sequence, final representation and logical event sequence. It need not perform literal whole-sequence rescans.

## Why suffix reduction is possible

Maintain a processed prefix that is already in M0 normal form. When a new element reaches the transformation frontier, no match can exist wholly inside the already-normal prefix. With maximum pattern width two, every newly enabled match must touch the suffix.

A replacement of two elements by zero or one element may expose a new match with the previous left neighbour. Therefore the implementation needs suffix backtracking on a mutable stack rather than an irreversible one-way emitter.

This is the key reason the specializer can avoid global rescans while preserving logical rewrite semantics.

## Unary/binary overlap requires lookahead

Unary rules cannot always be committed immediately because a longer binary rule beginning at the same site wins under M0.

Example:

```text
RZ(0), RZ(3)
```

The first element may match identity removal, while the pair may match rotation fusion. Since both begin at the same site, the span-2 rule wins before the unary rule.

Therefore version 1 uses an unresolved frontier with at least one-element lookahead. A unary decision is committed only after the immediate right neighbour is known not to enable a winning binary rule from the same site.

## Conceptual execution state

The generated reducer maintains:

```text
resolved stack/frontier
pending element
one-element lookahead
untouched input tail
logical rewrite step counter
```

When a binary replacement produces one element, that replacement remains unresolved and may interact with its new left neighbour or next right neighbour before being permanently committed.

At end-of-input, no future right neighbour exists, so deferred unary rules may be resolved safely.

## Conceptual specialized algorithm

The exact emitted control flow is an implementation detail, but it must be equivalent to:

```text
while input or unresolved frontier remains:

    expose pending and immediate right neighbour when available

    test eligible binary rules in deterministic rule-id order
    if one matches:
        replace two elements with zero or one element
        record one logical rewrite event
        continue suffix reduction

    if no winning binary rule can begin at pending:
        test eligible unary rules in deterministic rule-id order
        if one matches:
            remove pending
            record one logical rewrite event
            continue suffix reduction

    commit pending and advance
```

The implementation may share fetched fields, merge predicates or eliminate comparisons when static analysis proves alternatives mutually exclusive.

## Frozen first circuit rules

The first controlled experiment should retain the three local rule families from #457.

### Self-inverse pair cancellation

```text
pattern: [a,b]
guard:
    self_inverse(a.kind)
    a.kind == b.kind
    a.qubits == b.qubits
replacement: []
soundness: trusted-algebraic
```

### Identity removal

```text
pattern: [a]
guard: identity(a)
replacement: []
soundness: trusted-algebraic
```

### Rotation fusion

```text
pattern: [a,b]
guard:
    rotation(a)
    rotation(b)
    a.axis == b.axis
    a.qubit == b.qubit
replacement:
    rotation(a.axis, a.qubit, normalize(a.angle + b.angle))
    or [] when the normalized result is identity
soundness: trusted-algebraic
```

The current circuit angle convention uses eight ticks per full turn.

## Adversarial qualification cases

The corpus must include cases that specifically challenge specialization equivalence.

Binary-over-unary precedence:

```text
RZ(0), RZ(3)
```

Deletion exposing a later cancellation:

```text
H, RZ(3), RZ(-3), H
```

Replacement-induced suffix reduction:

```text
RZ(1), RZ(2), RZ(5)
```

Operand inequality:

```text
H(q0), H(q1)
```

Non-self-inverse negative case:

```text
T, T
```

Before any performance result is admitted, all controlled arms must produce identical final representations and identical logical event sequences on the frozen corpus.

## Static profile recognition

The compiler analyzes normalized facts, not domain names.

A rule set is eligible only if all of the following hold:

```text
family shape == ordered sequence
rule set statically known
strategy compatible with deterministic M0 fixed point
all patterns contiguous
all pattern spans in {1,2}
all replacements strictly length reducing
guards local and position independent
guards/replacements pure and deterministic
soundness admission known statically
required stack operations available
```

Selection must not contain rules such as:

```text
if namespace == quantum: use SequenceLocal2
if family == CircuitIR: use SequenceLocal2
```

Equivalent sequence-local domains should be eligible automatically.

## StaticRuleSpec relationship

`StaticRuleSpec` is compiler-owned metadata. It records identity, family, pattern shape, result cardinality, soundness and compile-time references to the ordinary-Weave guard/replacement declarations.

It does not contain a second guard or replacement expression language, and it does not create runtime callback objects.

A `StaticRuleSetSpec` supplies the family, strategy, ordered rules, admitted soundness classes, resource bound and target/capability context.

## RuleSetFacts

Before profile selection, the compiler derives a summary equivalent to:

```text
rule_count
maximum_match_span
maximum_replacement_length
contiguous
strictly_length_reducing
local
position_independent
pure
deterministic
strategy_kind
soundness_filter_static
unary_binary_overlap_present
required_family_capabilities
```

For the frozen circuit rules, the expected result is an explicit selection of `SequenceLocal2`.

If the profile is not applicable, return an explicit reason such as:

```text
non-sequence-family
dynamic-rule-set
unsupported-strategy
non-contiguous-pattern
pattern-too-wide
non-reducing-replacement
impure-guard
nondeterministic-guard
nonlocal-access
position-dependent-rule
missing-stack-capability
dynamic-soundness-filter
```

Profile rejection is a valid result. Do not automatically respond by constructing a larger generic framework.

## Rewrite bounds

If the selected semantic strategy has an explicit logical rewrite bound, the specialized implementation keeps the same logical step counter.

When the bound is reached, no further rewrites may be applied. The implementation must publish the representation corresponding to the generic engine after the same number of logical rewrites: current resolved/frontier state plus unconsumed input, with no hidden extra normalization.

## Provenance and trace

Specialization may eliminate `RewriteMatch` objects but not logical rule identity. Every successful reduction conceptually records:

```text
rule-id
site
step-index
```

Trace-on and trace-off execution must produce identical transformed output. Benchmark trace overhead separately.

## Required generated-code shape

Successful specialization should structurally contain:

```text
one forward input traversal
mutable output/frontier stack
bounded lookahead
suffix rule checks
suffix replacement
logical step counter
optional event publication
```

It must not retain the equivalent of:

```text
runtime rule-list iteration
candidate list allocation
global candidate enumeration
global winner scan
whole-sequence copy after every rewrite
whole-sequence fixed-point rescans
rule-id dispatch after match selection
```

The experiment must inspect generated WIR to verify that the abstraction was actually compiled away.

## WIR boundary

`SequenceLocal2` lowers to ordinary WIR. No new WIR form is required.

The generated transform is conceptually an ordinary function over the representation family. The compiler may emit statically resolved calls to guard/replacement helper declarations in version 1. General inlining is not required and must not be added after observing benchmark results without defining a new experiment version.

## Controlled experiment

Historical measurements remain context only:

- #457 generic full-rescan engine;
- #457 hand-written repeated-sweep arm;
- current production `emit_do_step` peephole.

The controlled comparison is:

- **A — handwritten specialization:** hand-written implementation of the exact selected semantics using the same specialization algorithm expected from C;
- **B — generic M0 semantics:** same rules, ids, ordering and bound using the generic candidate/winner/full-rescan machinery;
- **C — generated specialization:** the same static rule specifications as B, automatically recognized as `SequenceLocal2` and lowered to specialized code.

A, B and C must share rule semantics, rule ids, ordering, bound and expected logical event sequence.

## Complexity target

For input length `n` and a fixed compile-time rule set, strictly length-reducing suffix reduction should be effectively linear in input length, with memory proportional to the retained sequence.

The first experiment does not need an asymptotically optimal general matcher. It needs evidence that static semantics can be compiled to an implementation structurally comparable with a hand-written reducer.

## Decision criterion

The key question is:

> Can common rewrite semantics be specialized automatically into code whose runtime structure and performance approach a handwritten reducer while keeping domain rule definitions substantially smaller and more explicit?

If generated C approaches handwritten A and preserves the full semantic/provenance contract, continue toward broader transformation specialization and later graph/ZX work.

If C remains structurally or operationally close to generic B, narrow the declarative rewrite direction.

## Related documents

- [Compiled transformation design](transform-design.md)
- [Typed deterministic rewrite semantics](rewrite-semantics.md)
- [Circuit IR and compiled local rewrites](circuit-rewrite.md)
- [Rule authoring](rewrite-authoring.md)
