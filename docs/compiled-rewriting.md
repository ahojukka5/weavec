# Compiled rewriting

Status: strategic design direction; bounded implementation planned under
[#455](https://github.com/ahojukka5/weavec/issues/455)

Weave's proposed reusable optimization capability is **compiled declarative
rewriting over compiler-owned structured representations**. Quantum circuit and
ZX-calculus optimization is the flagship application, but the substrate is
intentionally domain-neutral so the same design can later be evaluated for
classical compiler IR, symbolic transformations, or numerical operator graphs.

The product thesis is simple:

> Transformations should be programs.

This does not mean that every transformation needs new language syntax. The
first implementation is deliberately built from ordinary Weave data structures,
functions, and compiler-owned IR APIs. Surface sugar is considered only after
measurement shows that the semantic model is useful and stable.

## Rewrites are not macros

Macros and optimization rewrites solve different problems.

A macro expands source syntax into source syntax. Its main concerns are hygiene,
module scope, source provenance, determinism, and inspectability.

An optimization rewrite operates on a semantic or optimization representation.
It additionally needs:

- typed pattern variables;
- side conditions;
- replacement construction;
- an explicit equivalence or admissibility boundary;
- deterministic match enumeration;
- deterministic conflict and application rules;
- provenance identifying the rule that changed the program;
- cost and search policy that are separate from semantic validity.

The compiler therefore must not implement quantum optimization by disguising a
rewrite system as ordinary source macros.

## First semantic contract

Issue [#456](https://github.com/ahojukka5/weavec/issues/456) owns the first
contract. It starts without public rewrite syntax and defines a small API that
can support both ordered circuit sequences and graph-shaped representations.

The first contract must distinguish three responsibilities:

1. **Rule semantics** — what pattern matches, what side conditions must hold,
   and how a replacement is constructed.
2. **Soundness provenance** — why the transformation is admitted as
   semantics-preserving for the declared domain. The first compiler is not a
   general theorem prover; trusted algebraic rules and independently checked
   rules must remain identifiable.
3. **Search policy** — which available rewrite is chosen and under which bounded
   cost model. Search may fail to find a good result without making the rules
   themselves unsound.

This split is required before adding convenience syntax or a larger search
engine.

## Quantum flagship

The first serious application is tracked by
[#455](https://github.com/ahojukka5/weavec/issues/455):

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

The first domain is a bounded Clifford+T-oriented gate set. The goal is not to
reproduce an entire production quantum SDK. The goal is to test whether compiled
rules can express a real optimizer compactly and execute it at useful compiler
cost.

The implementation sequence is:

- [#456](https://github.com/ahojukka5/weavec/issues/456) — typed deterministic
  rewrite semantics;
- [#457](https://github.com/ahojukka5/weavec/issues/457) — circuit IR and local
  compiled matcher;
- [#458](https://github.com/ahojukka5/weavec/issues/458) — ZX graph IR, rewrites,
  and deterministic circuit extraction;
- [#459](https://github.com/ahojukka5/weavec/issues/459) — bounded search and
  target/domain packs;
- [#460](https://github.com/ahojukka5/weavec/issues/460) — frozen comparison
  against the current Weave optimizer and PyZX.

## Claim boundary

Circuit rewriting and ZX-calculus optimization already have strong prior art.
PyZX demonstrates practical graph-theoretic ZX simplification and extraction.
Quartz demonstrates generated and verified gate-set-specific transformations
combined with cost-based search. Equality-saturation work demonstrates that
rewrite-driven optimization can represent large equivalence spaces, while also
showing that uncontrolled search can become expensive. Recent ZX work further
shows that rewrite ordering and policy selection are themselves optimization
problems.

The candidate Weave contribution is therefore not "we implemented ZX" or "we
use rewrite rules." It is the language/compiler substrate: concise typed rules
compiled into deterministic transformation code, explicit policy separation,
and target specialization that can be measured against established optimizers.

## Measurement before syntax

The flagship benchmark must report circuit quality and implementation cost
separately.

Circuit metrics include:

- T or non-Clifford gate count;
- two-qubit gate count;
- depth;
- semantic/equivalence qualification;
- deterministic repeatability.

Compiler/engineering metrics include:

- optimizer wall time;
- peak memory;
- domain-rule source size;
- generic matcher/search infrastructure size;
- target-pack size;
- target-specific special-case code outside the pack.

A faster optimizer that consistently produces worse circuits is not a win. A
short rule file backed by a large hidden pile of gate-specific native code is not
a compact rewrite system.

## Target/domain packs

Device and gate-set policy should not become language syntax. The first target
packs are expected to own:

- admitted/native gate set;
- exact decomposition rules;
- cost-vector definition and weights;
- capability metadata;
- later extension points for topology and routing.

Topology, calibration, and noise-aware compilation are intentionally absent from
the first pack contract. The abstraction boundary must work before those concerns
are added.

## Explicitly deferred

The first compiled-rewrite study does not include:

- unrestricted equality saturation or a general e-graph framework;
- automatic rewrite discovery;
- reinforcement-learning or other learned rewrite selection;
- production QPU execution;
- topology-aware routing;
- calibration or noise-aware optimization;
- GPU acceleration of the optimizer;
- new WIR forms added merely for quantum convenience.

These are possible follow-up research directions only after the bounded local and
ZX rewrite baseline is measured.

## Relationship to the compiler architecture

The rewrite direction builds on, but does not modify the meaning of, the
in-memory WIR migration in
[#270](https://github.com/ahojukka5/weavec/issues/270). High-level circuit and ZX
representations remain above ordinary WIR; the self-hosted compiler still lowers
accepted programs through WIR core version 3.

The structured type work should also make `Qubit` a real semantic type rather
than erase and re-derive quantum identity. That is a type-system correctness
requirement, not a reason to hard-code quantum hardware concepts into the core
language.

See [Quantum compiler flagship and current surface support](quantum.md) for the
implemented baseline that the new optimizer must preserve and eventually
replace where measurement justifies it.
