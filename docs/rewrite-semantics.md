# Typed deterministic rewrite semantics

Status: first semantic contract for compiled rewriting
([#456](https://github.com/ahojukka5/weavec/issues/456), milestone M0 of
[#455](https://github.com/ahojukka5/weavec/issues/455)).

This document freezes the domain-neutral rule model before any rewrite syntax,
optimizer IR, or search engine is added. The contract is prototyped with
ordinary Weave structs, enums, and functions. It is **not** a macro system, a
public language extension, or a WIR change.

The executable witness is
[`test/rewrite-semantics/main.weave`](../test/rewrite-semantics/main.weave).
That program applies the contract to two toy representation shapes: an ordered
operator sequence and a labelled undirected graph.

## What this contract is for

Compiled rewriting is a compiler-owned transformation substrate. A rule says
how a structured subject may change. A later cost model and search strategy
say which admitted change is chosen. Quantum circuit and ZX optimization is
the flagship consumer, but the first API must not hard-code that domain.

Three responsibilities stay separate:

1. **Rule semantics** — pattern, typed variables, guard, replacement.
2. **Soundness provenance** — why a rule is admitted as
   semantics-preserving, or why it is not.
3. **Search policy** — which match is applied, under which bound and cost.

The compiler is not a general theorem prover. Provenance records an
obligation; it does not discharge an arbitrary equivalence proof.

## Subjects and representation families

A **subject** is a compiler-owned structured value. A **representation
family** is a finite, named class of subjects that share:

- a typed view used by matching;
- a deterministic walk used to enumerate candidate sites;
- a constructor used to build a replacement subject.

The first two families the contract must support, in principle, are:

| Family | Site | Typical later consumer |
| --- | --- | --- |
| ordered sequence | a contiguous span of items | local circuit peepholes |
| labelled graph | a finite set of nodes and incident edges | ZX spider fusion |

A family adapter supplies matching and replacement. The rule engine does not
embed one family's walk into the public contract. Adding a family does not
change rule identity, provenance, cost, or search interfaces.

A subject is never source text. Macros remain source-to-source expansion; see
the product boundary in
[#455](https://github.com/ahojukka5/weavec/issues/455).

## Pattern variables

A **pattern** is a typed term over the subject family. Every hole is a
**pattern variable** with a declared sort. A sort is a compiler-checkable
type in the subject's view, not an untyped wildcard.

First sorts, as needed by the flagship and the toy:

| Sort | Meaning |
| --- | --- |
| `Op` | an operator or node label drawn from a finite alphabet |
| `Site` | a sequence index or graph node identifier |
| `Span` | a contiguous sequence interval `[start, start+span)` |
| `Param` | a classical parameter attached to an operator or node |
| `Bag` | a finite set of sites belonging to one match |

A variable may occur more than once. Repeated uses require the same bound
value. Binding is total for a successful match: every variable mentioned by
the pattern or guard is assigned.

Patterns do not capture source syntax, hygiene, or token streams.

## Guards

A **guard** is a pure deterministic predicate over the binding and the
subject. It may read, but must not mutate, the subject. Typical guards are
equality of labels, adjacency, parameter predicates, and family-specific
side conditions such as "the two operators act on the same wire."

A match is the pair `(site, binding)` for which the pattern structure holds
and the guard returns true. Failed guards do not produce a match.

Guards are ordinary Weave functions in this contract. They are not a new
constraint language.

## Replacements

A **replacement** is a pure deterministic function

```text
replace : (Subject, Binding) -> Subject
```

It constructs a new subject. It must not observe search policy, cost, or
unrelated matches. The engine installs the returned subject as the next
state.

Replacement construction is allowed to copy unchanged regions and to drop,
fuse, or insert structure that the pattern bound. It is not allowed to
"optimize further" inside `replace`. Extra rewrites are later matches.

## Rule identity

A **rule** is identified by a stable triple:

```text
rule-id = (namespace, name, version)
```

- `namespace` groups a domain pack or prototype (`toy.seq`, later
  `quantum.circuit`, `quantum.zx`).
- `name` is a portable identifier inside that namespace.
- `version` is a non-negative integer. Changing pattern, guard, replacement,
  or provenance requires a new version.

The toy witness uses small integer stand-ins for those triples. A later
compiler registry must preserve the triple as the public identity. Rule
order in a **rule set** is an explicit sequence of rule-ids. That order is
part of search input, not part of a rule's identity.

Every applied rewrite records provenance:

```text
event = (rule-id, site, step-index)
```

`step-index` is the number of successful applications before this one,
counting from zero. The same program, rule set, and strategy must emit the
same event sequence.

## Provenance and soundness classification

Every rule carries exactly one **soundness class**:

| Class | Meaning | May be used to preserve semantics? |
| --- | --- | --- |
| `trusted-algebraic` | an axiom of the declared domain, accepted by review | yes, in that domain |
| `independently-checked` | an external proof, exhaustive small-domain check, or frozen oracle admitted by the domain pack | yes, with the cited evidence |
| `heuristic` | a size, cost, or search rewrite with no semantic obligation | no, unless an explicitly unsound strategy opted in |

The class is data on the rule, not a search-time guess. A trusted rule does
not become a heuristic by being expensive, and a heuristic does not become
trusted by improving a cost.

The engine may filter matches by class before the strategy sees them. The
default compiled-optimizer path admits only `trusted-algebraic` and
`independently-checked` rules. Heuristic rules require an explicit strategy
flag.

This is the whole first soundness boundary. There is no kernel proof search,
rewrite completion, or SMT query in the contract.

## Testing semantic preservation without a prover

A rule claiming semantic preservation must be testable by at least one of
the following, recorded with the rule:

1. **Independent normal-form oracle** on a frozen finite family. The toy
   sequence rules cancel adjacent self-inverse operators and drop identity
   tokens; an independent stack reducer must agree with the engine.
2. **Exhaustive interpretation** on a bounded state space (for example a
   one-qubit simulator for a local gate identity).
3. **Cited external evidence** for `independently-checked` rules (a paper,
   a checked proof artifact, or a generated-and-verified identity). The
   compiler stores the citation; it does not recheck the proof.

Disagreement with the oracle falsifies the rule or the engine. Agreement on
a finite corpus does not prove the rule in general; it is qualification
evidence, not a theorem.

Heuristic rules are tested for determinism and for *not* being applied by
the default trusted strategy. They are not tested for semantic preservation.

## Match enumeration

Enumeration is a total, deterministic function of the subject, the admitted
rule set, and the family adapter. It yields a finite list of **matches**.
Each match has:

```text
match = (rule-id, site-key, span, payload-key)
```

- `site-key` is the family's ordered site identity. For a sequence it is
  the start index. For a graph it is the lexicographically sorted tuple of
  participating node ids, packed by the adapter into an integer key in the
  toy.
- `span` is the number of primary sites the match occupies. Longer matches
  at the same start outrank shorter ones.
- `payload-key` breaks remaining ties inside one rule (for example the
  deleted graph node).

**Walk order** is defined by the family, then used only to *discover*
matches. Discovery order must not affect which match wins. The engine
compares complete matches by the key below, independent of the order they
were found.

Sequence walk: increasing start index, and at each start every admitted
rule.

Graph walk: increasing node id, then increasing partner id, then admitted
rules.

Overlapping matches are all enumerated. The engine does not skip a later
site because an earlier candidate exists. Conflict is resolved after
enumeration, not during the walk.

## Conflict resolution and application

The **match key** is the lexicographic tuple

```text
(site-key ascending, span descending, rule-id ascending, payload-key
ascending)
```

The **selected match** is the unique minimum key, or none.

One rewrite step:

1. Enumerate all matches of admitted rules.
2. If the list is empty, stop.
3. Apply `replace` of the selected match, producing a new subject.
4. Increment `step-index`.
5. If `step-index` has reached the strategy bound, stop.
6. Re-enumerate from the new subject. Do not resume the previous walk.

This is leftmost, then longest, then rule-set order, then payload, with
full rescan. It is not innermost term rewriting, not parallel rewriting,
and not equality saturation.

Two matches conflict when their occupied sites intersect. The minimum key
wins; the other match is simply not selected on this step. After the
winning replacement, the loser is rediscovered or not on the next
enumeration.

The bound is part of search policy. Semantics of a single rule do not
depend on it.

## Cost-function interface

A **cost** is a total deterministic function

```text
cost : Subject -> CostVector
```

The first contract uses a single non-negative integer. Later domain packs
may publish a named vector (T-count, two-qubit count, depth) with a
documented comparison.

Cost is not a guard. A rule remains applicable when it increases cost. A
strategy may refuse such a match. That refusal is policy, not a failed
pattern.

The toy sequence cost is the remaining length. The toy graph cost is the
node count. Neither cost is used to decide trusted-rule applicability.

## Search-strategy interface

A **strategy** is a total deterministic function of

```text
(subject, admitted-matches, cost, bound) -> (apply match | stop)
```

First admitted strategies:

| Strategy | Behaviour |
| --- | --- |
| `fixed-point-greedy` | apply the minimum match key until none remain or the bound is hit |
| `trusted-only` | `fixed-point-greedy` restricted to non-heuristic provenance |
| `cost-guided` | among matches whose replacement does not increase cost, pick minimum cost, then minimum match key |

The toy implements `trusted-only` and an explicit heuristic opt-in used only
to prove that the filter changes the result. Bounded beam search and
backtracking belong to
[#459](https://github.com/ahojukka5/weavec/issues/459). They must keep the
same match key as the last tie-breaker.

A strategy may fail to find a cheap subject. That is not unsoundness of the
rules.

## Ordinary Weave API shape

The first implementation uses ordinary declarations, not new syntax. The
toy names the load-bearing types as follows:

```weave
(enum Soundness
  (variant TrustedAlgebraic)
  (variant IndependentlyChecked)
  (variant Heuristic))

(struct RewriteMatch
  (field rule i32)
  (field start i32)
  (field span i32)
  (field extra i32))
```

A later compiler-owned engine should keep this split even if the names
change:

- rule table: identity, soundness class, matcher, replacer;
- family adapter: enumerate matches for one subject;
- engine: select by match key, apply, rescan, honor bound;
- cost and strategy: separate functions over subjects and match lists.

There is no `rewrite` form, no `qrewrite` form, no e-graph type, and no
new WIR production in this issue.

## Toy domain

The sequence alphabet is:

| Token | Meaning | Algebra |
| --- | --- | --- |
| `0` | identity `I` | `I · x = x` |
| `1` | generator `A` | `A · A = I` |
| `2` | generator `B` | `B · B = I` |

Trusted sequence rules:

- `toy.seq/cancel-pair/1` — adjacent equal self-inverse tokens `A A` or
  `B B` are deleted;
- `toy.seq/drop-identity/1` — a single `I` token is deleted.

Heuristic sequence rule, not admitted by default:

- `toy.seq/drop-A/1` — delete one `A`. This is unsound relative to the
  free product of two copies of `Z_2` and exists to test provenance
  filtering.

The independent sequence oracle is a stack reducer: skip `I`; if the top
equals the next self-inverse token, pop; otherwise push. Trusted
fixed-point rewriting must agree with that oracle on the frozen cases in
the witness program.

The graph alphabet uses the same labels on nodes. Trusted graph rules:

- `toy.graph/fuse-equal/1` — two adjacent nodes with the same non-identity
  label become one node, inheriting the union of their edges;
- `toy.graph/drop-isolated-I/1` — an isolated identity node is deleted.

These are the smallest graph analogues of spider fusion and identity
cleanup. They are not ZX calculus.

## Determinism requirement

Same subject, same ordered rule set, same admitted soundness classes, same
strategy, and same bound must produce the same final subject and the same
event sequence. Enumeration that depends on hash iteration, pointer
identity, or discovery order is a contract violation.

## Non-goals

This issue does not add:

- public rewrite syntax;
- WIR or surface-language contract changes;
- a circuit IR, ZX IR, or extraction;
- equality saturation or a general e-graph;
- automatic rule discovery;
- hardware target packs;
- a theorem prover.

Those remain later milestones of #455, or are explicitly deferred.

## Follow-on use

[#457](https://github.com/ahojukka5/weavec/issues/457) supplies a
sequence-family adapter over a real gate IR, reusing this match key,
provenance split, and trusted-only default. The stop-rule measurement
kept production peephole lowering: the generic engine is a prototype,
not a replacement. See
[Circuit IR and compiled local rewrites](circuit-rewrite.md).
[#458](https://github.com/ahojukka5/weavec/issues/458) is a later
graph-family issue, not a continuation of an unresolved #457 gate.
[#459](https://github.com/ahojukka5/weavec/issues/459) may add strategies
but must not fold cost into guards.
