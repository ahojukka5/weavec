# Compiled transformation design

Status: design draft. This document records the current architecture decision before implementation of the specialization experiment tracked from issue #455.

## Purpose

Weave should support compiler transformations as typed, deterministic compiled programs.

The central design principle is:

> A general transformation substrate does not imply a general runtime transformation engine.

Transformation definitions may share one semantic contract while the compiler specializes statically known transforms and rewrite rules into representation-specific executable code whenever possible. The goal is not to build an interpreter for rewrite rules. The goal is to express transformation intent structurally and compile that intent into efficient ordinary Weave/WIR code.

Quantum compilation is the first proving ground, not the organizing principle of the language.

## Core concepts

Four concepts remain distinct:

```text
Transform
RepresentationFamily
RewriteRule
Strategy
```

### Transform

A `Transform<A,B>` describes a deterministic transformation from one structured representation to another. Conceptually it has:

```text
identity + version
input representation family
output representation family
requirements / capabilities
implementation
failure contract
resource contract
determinism contract
provenance / trace evidence
```

Examples include:

```text
SurfaceTree -> WIRTree
CircuitIR   -> ZXGraph
ZXGraph     -> CircuitIR
CircuitIR   -> CircuitIR
WIRTree     -> WIRTree
```

Conversion, lowering, extraction, canonicalization and optimization are all transforms. A transform is not necessarily a rewrite system.

### RepresentationFamily

A representation family defines the structured domain on which a transform operates. Examples are `SurfaceTree`, `CircuitIR`, `ZXGraph`, and `WIRTree`.

The family owns representation-specific structure and efficient operations such as traversal, site identity, element access, construction, replacement, invariants and validation. It does not own global search policy, rule soundness classification or generic transform identity.

There is deliberately no universal tree API. A circuit sequence and a ZX graph may use different efficient implementations.

### RewriteRule

A rewrite rule is a special case of a transform whose input and output family are the same:

```text
RewriteRule<A> : A -> A
```

Its semantic information is:

```text
stable identity + version
representation family
pattern and bindings
guard
replacement
soundness classification
provenance
```

The stable identity remains a triple `(namespace, name, version)`. Changing pattern, guard, replacement or semantic provenance requires a new version.

### Strategy

Strategy controls how valid rewrites are selected and applied. It is separate from rule semantics:

```text
admitted rules
conflict policy
cost policy
search policy
resource bound
tie breaking
```

Examples include fixed-point greedy, cost-gated greedy, bounded beam search and bounded backtracking. A rule does not inspect strategy to decide whether it is semantically valid, and cost is not a rule guard unless it is genuinely part of the transformation precondition.

## Macros remain separate

Three mechanisms must remain distinct:

```text
Macro:       SurfaceTree -> SurfaceTree
Transform:   Representation A -> Representation B
RewriteRule: Representation A -> Representation A
```

Macros concern source construction and expansion. Compiler transformations operate on structured semantic or optimization representations. The transformation design does not define the future macro system.

## Specialization-first execution model

Statically known transformations should normally be compiled into specialized transformation code rather than interpreted by a generic runtime matcher.

Intended path:

```text
static transform/rule specification
              |
              v
      compile-time analysis
              |
              v
 representation-specific specialization
              |
              v
       ordinary Weave / WIR
              |
              v
             LLVM
```

This is intentionally different from:

```text
rule objects -> generic runtime matcher -> generic replacement engine
```

A runtime-generic engine may remain useful for genuinely dynamic rule sets, but it is not the default execution model.

The semantic abstraction is allowed to disappear from generated code. Conflict semantics, rule identity and provenance remain observable contracts; `RewriteMatch` objects, candidate lists and runtime dispatch are not.

## StaticRuleSpec

The first experiment uses an internal compile-time representation, not public syntax and not a runtime object.

Conceptually:

```text
StaticRuleSpec
|- identity: namespace, name, version
|- family: RepresentationFamilyId
|- pattern
|  |- span
|  |- contiguity
|  `- binding shape
|- guard declaration reference
|- replacement declaration reference / result cardinality
|- soundness
|- effect summary
`- source provenance
```

Guard and replacement semantics remain ordinary Weave. `StaticRuleSpec` points to exact compiler-resolved declarations; it does not copy them into a second expression language and does not require first-class function pointers.

Version 1 may generate statically resolved direct calls to helper functions. Later inlining or cloning is a separate optimization decision.

## StaticRuleSetSpec

Rules are analyzed as a set:

```text
StaticRuleSetSpec
|- representation family
|- strategy
|- admitted soundness classes
|- ordered rules
|- resource bound
`- target/capability context
```

Rule order is strategy input, not part of rule identity.

## Effect qualification

Specialization reuses ordinary compiler effect analysis. Where required by a profile, guards and replacements must be provably `pure` and `deterministic`, or be explicitly compiler-trusted during the bounded experiment.

Do not introduce parallel concepts such as `rewrite-pure` or `rewrite-deterministic`.

## Specialization planner

The reusable compiler capability is a planner:

```text
Transform semantics
        +
RepresentationFamily capabilities
        +
Strategy semantics
        |
        v
static analysis
        |
        v
specialization profile selection
        |
        +--> SequenceLocal2
        +--> future graph specialization
        +--> future tree specialization
        `--> not specialized / explicit pass
```

Profile selection must depend on normalized facts, never domain names. For example, the compiler must not special-case `quantum` or `CircuitIR` merely by identity when selecting a sequence-local algorithm.

## CircuitIR first experiment

The first specialization target is the existing ordered circuit representation. The family exposes semantic operations for reading gates and maintaining an output stack; the packed representation remains an implementation detail.

The frozen rule set should remain aligned with the #457 local experiment:

1. adjacent self-inverse cancellation;
2. identity removal;
3. same-axis rotation fusion.

The first controlled experiment compares:

- **A: handwritten specialization** implementing the exact selected semantics with the intended efficient algorithm;
- **B: generic M0 semantics** using candidate enumeration, winner selection, `RewriteMatch`, one logical rewrite and full rescan;
- **C: generated specialization** from the same static rule specifications as B.

Historical #457 generic/special measurements and the current production peephole remain useful context, but they are not the matched A/B/C comparison because they implement different operational strategies and/or rule sets.

## Provenance and trace

Specialization may remove generic runtime machinery but must not make transformations unobservable.

Every logical rule application retains at least:

```text
rule-id
site
step-index
```

and may additionally retain source/provenance facts supplied by the representation family.

The existing compilation trace remains the canonical observational mechanism. Loupe may analyze transform evidence but does not participate in transformation selection or execution.

Trace-enabled and trace-disabled execution must produce the same transformed representation. Benchmark trace overhead separately from the fast path.

## Failure semantics

Transforms fail explicitly. Relevant categories include unsupported representation, invalid representation, target incompatibility, resource/search bound, extraction failure, equivalence qualification failure and internal invariant failure.

A failed transform must not silently publish a partially transformed program as valid output.

A specialization profile returns either a selected profile or an explicit `not-applicable(reason)`. The first experiment must not respond to rejection by silently building a larger general-purpose framework.

## Determinism

For identical input representation, transform versions, rule set, strategy, target/capability context, resource bounds and compiler version, the result must be deterministic. Requested logical event sequences must also be deterministic.

Implementation optimizations may change internal traversal or dispatch only when they preserve the declared observable semantics.

## First experiment non-goals

The specialization gate does not introduce:

- public `rewrite` or `qrewrite` syntax;
- hygienic macros;
- first-class callback/function-pointer machinery;
- dynamically loaded rules or runtime rule registries;
- equality saturation or e-graphs;
- automatic rule discovery;
- theorem proving;
- learned scheduling;
- topology/noise-aware compilation;
- a new WIR version.

## Decision criterion

The specialization approach remains promising if generated code approaches the handwritten specialization's runtime characteristics while materially reducing domain-specific authoring burden, preserving deterministic rule identity/provenance, and avoiding hidden domain-specific infrastructure.

A positive result does not require generated code to beat carefully hand-written code. A useful result is near-handwritten execution plus substantially smaller rule definitions plus reusable specialization machinery.

If specialization fails to remove the generic engine's complexity or performance penalty, keep explicit transform/pass contracts and domain-specific optimized passes without promoting a general declarative rewrite facility.

## Related documents

- [Typed deterministic rewrite semantics](rewrite-semantics.md)
- [SequenceLocal2 specialization profile](sequence-local2.md)
- [Circuit IR and compiled local rewrites](circuit-rewrite.md)
- [Source-linked compilation trace](compilation-trace.md)
- [Application-language roadmap](roadmap.md)

Implementation/research tracking: issue #455 and the related research study.
