# Weave language design principles

This document defines the principles used to evaluate language-design decisions
in Weave. It is a design rationale and decision framework: it explains *why* the
language should take one direction rather than another when several designs are
plausible.

It is not the language reference, grammar, roadmap, or a promise that every
illustrative form below is implemented today. The compiler-authoritative grammar
and capability registry define what a particular `weavec` version actually
accepts. Examples in this document are deliberately forward-looking when that
makes the principle clearer.

The first version of these principles distills lessons from model feedback,
agent-driven development, and the existing Weave design. Models are evidence
sources, not design authorities. Claims about LLM ergonomics should be measured
where practical; in particular, the syntax evaluation in issue #296 remains the
decision gate for the pre-1.0 surface.

## How to use this document

A language-design issue or PR should be explainable against these principles.
For a nontrivial choice, record:

- which principles the proposal supports;
- which principles it costs or places in tension;
- whether the trade-off affects correctness, only ergonomics, or both;
- whether the decision is cheap to reverse before 1.0;
- what evidence would falsify the assumption.

The principles are not independent checkboxes. They deliberately overlap because
important language choices often solve several failure modes at once.

When principles conflict, use the following priority classes.

### Hard constraints

Correctness, explicit failure, compiler-checkable semantic intent, and
deterministic interpretation outrank syntax convenience and token count. A
proposal that weakens one of these needs a concrete safety argument, not only an
ergonomic preference.

### Strong preferences

Local reasoning, one canonical representation, stable edits, discoverable names
and dependencies, and structured compiler feedback should be preserved unless a
measured benefit justifies the cost.

### Optimization goals

Token density and model familiarity matter because source code is repeatedly
generated, read, and edited. They should remove ceremony, not semantic
information that the compiler can check.

## P1. Put intent before implementation

The grammar should make a declaration state what it means before its body states
how it is implemented.

This is useful to humans, but it is especially useful to a generative model:
earlier output becomes context for later output. A function that commits to its
purpose, types, dependencies, effects, and contracts before the body is
effectively prompting its own implementation.

The exact surface syntax is still a design choice. The ordering is the
principle.

Avoid:

```weave
(fn roots ((a f64) (b f64) (c f64)) Roots
  (let d (- (* b b) (* 4.0 a c)))
  ...
  (requires (!= a 0.0))
  (effects pure deterministic))
```

Prefer:

```weave
(fn roots ((a f64) (b f64) (c f64)) Roots
  (doc "Return the real roots in ascending order.")
  (uses (std.math sqrt))
  (effects pure deterministic)
  (requires (!= a 0.0))

  (let d (- (* b b) (* 4.0 a c)))
  ...)
```

The illustrative `doc` and `uses` forms above are design sketches, not a claim
that the current compiler implements those exact forms.

## P2. Local reasoning should be sufficient reasoning

Understanding a function should require as little distant context as practical.
A reader should not need to remember an import declared a thousand lines above,
a hidden global, an implicit receiver, or an exception path established in
another file.

A function's direct dependencies and behavioral boundary should be visible from
the function itself or queryable from compiler-owned metadata.

Avoid:

```weave
(module solver
  (use std.math sqrt)

  ; hundreds of lines ...

  (fn norm ((x f64)) f64
    (return (sqrt x))))
```

Prefer a design where the dependency is local:

```weave
(fn norm ((x f64)) f64
  (uses (std.math sqrt))
  (effects pure)

  (return (sqrt x)))
```

An alternative that also satisfies the principle is an explicitly qualified call
such as `(std.math.sqrt x)`. The final import syntax should balance locality
against output-token cost; the principle does not require one spelling.

Who writes a form and who reads it are separate design decisions. A
function-local dependency header serves the *reader*; it must not become the
*writer's* bookkeeping obligation. The intended workflow is write-optional,
read-present: an author — human or model — writes only the calls, the formatter
derives and inserts the canonical header, and the compiler verifies it. A
header that a model must hand-maintain on every edit is not local reasoning; it
is a per-edit tax and a new way to be wrong, and stale-header repair iterations
are spent on bookkeeping instead of the task.

Transitive implementation details do not belong in the local dependency list.
If `norm` calls `hypot`, and `hypot` uses `sqrt`, `norm` needs to know about
`hypot`, not every dependency of `hypot`.

## P3. One program tree has one canonical source representation

Formatting is serialization, not style.

For a canonical surface tree, there should be exactly one authoritative byte
representation. There are no formatter profiles or repository-specific style
dialects.

The intended laws are:

```text
fmt(fmt(source)) == fmt(source)
parse_surface(print_surface(tree)) == tree
```

Compatibility spellings may be accepted temporarily, but the canonical printer
has one present tense.

Avoid allowing both of these to persist as canonical source:

```weave
(call sqrt d)
```

```weave
(sqrt d)
```

Prefer accepting compatibility input only when needed and always printing:

```weave
(sqrt d)
```

This principle does **not** mean that semantically equivalent programs are
rewritten into the same source. The formatter must not commute operands,
reassociate floating-point arithmetic, rename variables, or remove explicit
type annotations merely because it can infer them.

Canonical whitespace is formatter-owned. Blank lines, indentation, and wrapping
are not surface-tree state, so two inputs that differ only in whitespace
normalize to one byte sequence. The printer derives vertical spacing from the
tree and a compiler-owned line-width rule: a form prints inline when it fits,
otherwise in one canonical multiline shape, with deterministic sibling
separation. Issue #334 records that derived layout. It does not preserve
author-owned paragraph metadata or a `leading_break` flag.

## P4. Distinct things should look distinct

When the type checker cannot distinguish two easy-to-confuse intentions, the
surface should help.

This is especially important for same-typed parameters, enum variants, range
boundaries, ownership modes, and operations with materially different failure
behavior.

Avoid:

```weave
(copy src dst)
```

when both arguments have the same type and their order is easy to transpose.

Prefer:

```weave
(copy :from src :to dst)
```

Avoid an unqualified variant:

```weave
(return None)
```

Prefer:

```weave
(return Option.None)
```

The redundancy is justified when the compiler checks the labels or qualification.
Purely decorative labels do not earn the same protection.

To stay out of taste-based review, the rules should be mechanical enough for
the formatter and compiler to enforce. The intended forms are:

- argument labels are canonically **required** whenever adjacent parameters
  share a type, and canonically absent where the types already distinguish the
  arguments;
- comparison operators are strictly binary. A chained comparison such as
  `(< a b c)` is rejected: dropping one operand silently changes its meaning,
  which is exactly the confusion this principle exists to prevent, and
  Lisp-family priors will tempt a model to write it.

## P5. The compiler is the agent's pair programmer, and it speaks data

An agent should obtain current truth from the compiler, not from stale training
data or source-code archaeology.

The compiler should publish the grammar, capabilities, APIs, diagnostics,
semantic facts, and guaranteed repairs in stable machine-readable forms. Human
renderings should be projections of the same authority.

Avoid a workflow such as:

```text
grep parser sources
read examples
guess which syntax is current
compile
interpret an unstructured error string
```

Prefer:

```text
weavec --grammar
weavec capabilities --json
weavec build --diagnostics-json ...
```

A useful diagnostic identifies at least the failure kind and exact source span,
and where provable may include a machine-applicable repair.

The planned `weavec --grammar` bootstrap card should be complete enough that a
fresh model can learn the core language without inspecting repository source.

## P6. Checked redundancy is a checksum; unchecked ceremony is waste

Redundancy is valuable when two independent statements of intent can disagree
and the compiler checks that disagreement.

Types at boundaries, contracts, exhaustive matches, effect declarations, named
arguments, and checked examples are useful redundancy.

Wrappers that only restate parse-tree structure are not.

Avoid:

```weave
(if
  (condition (op less-than d 0.0))
  (then
    (do
      (return Roots.None)))
  (else (do)))
```

Prefer:

```weave
(when (< d 0.0)
  (return Roots.None))
```

At the same time, do **not** remove:

```weave
(requires (!= a 0.0))
```

merely to save tokens. The compiler can parse, type-check, audit, and check the
contract according to the language's contract model; it carries semantic
information that the body alone does not state as clearly.

A useful rule of thumb is:

> Remove redundancy that describes syntax. Preserve redundancy that lets the
> compiler cross-check intent.

Checked redundancy also has an author, and that matters. Redundancy the
toolchain derives and verifies (a generated dependency header, a formatter-
inserted argument label) is strictly cheaper than redundancy a writer must
keep synchronized by hand. When a checked form can be derived, derive it;
reserve hand-authoring for statements of intent the compiler cannot infer,
such as contracts.

## P7. Spend source tokens on meaning

The language should be dense enough that an agent can keep more relevant program
context in its working window, but not so compressed that familiar structural
cues disappear.

Input cost for teaching a new language can be amortized across an agent session.
Generated source is paid repeatedly on every implementation and edit. Therefore
persistent source ceremony has a different cost from a compact grammar card.

Generated tokens are also error surface, not only context cost. Every emitted
token is an independent opportunity for a mistake, and a mistake in a ceremony
token — a dropped wrapper, a misplaced structural word — costs a full
compile-and-repair iteration while carrying no semantic information. Removing
ceremony therefore reduces both context pressure and the expected number of
failures per function.

Avoid a verbose AST serialization:

```weave
(op multiply alpha (op add x y))
```

Prefer a familiar Lisp-family form:

```weave
(* alpha (+ x y))
```

Also avoid inventing cryptic one-character notation merely to reduce token count.
The target is familiar, information-dense structure, not minimum character count.

Model familiarity is evidence, not law. Where two plausible surfaces compete,
measure generation cost, correctness, and repair iterations instead of choosing
only by taste.

## P8. Edits should be insertion-stable and deletion-stable

Adding, deleting, or moving an ordinary statement should not silently change the
meaning of its neighbors.

This argues against significant indentation, implicit tail returns, and syntax
whose meaning depends on a following line or an easy-to-miss delimiter variant.

Avoid implicit tail return:

```weave
(fn increment ((x i64)) i64
  (let y (+ x 1))
  y)
```

Moving another expression below `y` would silently change the result.

Prefer:

```weave
(fn increment ((x i64)) i64
  (let y (+ x 1))
  (return y))
```

The formatter may change whitespace freely because whitespace should not carry
block *meaning* in canonical Weave, and it is not preserved tree state under
P3. Visual adjacency of a one-line comment to a following multiline form is a
printer rule, not a semantic attachment.

Edit stability also argues for flat bodies over deep ones. Deep homogeneous
nesting — identical heads, long closer runs — is where bracket-balancing
mistakes concentrate, and an edit four layers inside a conditional is harder to
make safely than an edit in a flat statement list. The canonical style prefers
guard clauses with early `return` over nested conditionals, and the formatter
may bound canonical nesting depth.

## P9. Names and dependencies should be exactly discoverable

Navigation should work by exact search and compiler queries.

Prefer one name with one definition, qualified variants, explicit imports or
dependencies, and no hidden shadowing. Avoid glob imports and resolution rules
that require the whole program to know what a local identifier means.

Avoid:

```weave
(use std.math *)
(let value ...)
...
(let value ...)
```

Prefer:

```weave
(uses (std.math sqrt))
(let raw-value ...)
...
(let normalized-value ...)
```

A future dependency syntax may differ from this sketch. The invariant is that the
reader and compiler can identify the source of every nonlocal name without
guessing.

## P10. Failure should be loud by default

Silent wrong answers are worse than explicit failure, especially in an
unsupervised agent loop and in numerical software.

Do not use null, magic numeric sentinels, silent truncation, ignored recoverable
errors, or undefined behavior as ordinary safe-language conventions.

Avoid an API contract such as:

```weave
; Returns 0.0 when parsing fails.
(let value (parse_f64 text))
```

Prefer an explicit result:

```weave
(match (parse_f64 text)
  (case (Result.Ok value)
    (use-value value))
  (case (Result.Err error)
    (return error)))
```

Likewise, a negative square root must not quietly become `0.0`, and a
recoverable `Result` must not disappear merely because its return value was
unused.

The precise panic, trap, `Option`, and `Result` boundaries are language-design
decisions. The invariant is that failure is represented or diagnosed, not
silently converted into plausible data.

Unknown and reserved syntax is part of this principle. A form the compiler
does not implement, or a spelling reserved for a future feature, is rejected
with a diagnostic — never accepted and ignored. Silence is not a valid
response to unrecognized intent: a model's hallucinated feature must fail
loudly rather than parse as something else. Weave already practices this
(reserved ownership spellings are refused rather than skipped); it is recorded
here so the behavior survives as policy rather than habit.

## P11. Anything worth preserving is structure, not trivia

If information must survive parse, format, structural edit, diff, and
round-trip serialization, represent it in the surface tree.

This applies naturally to documentation, examples, and source annotations. It
may also apply to human comments.

Avoid relying on parser trivia whose attachment must later be guessed:

```weave
; Do not reassociate this expression.
(let total (+ a b))
```

Prefer an explicit surface node:

```weave
(comment "Do not reassociate this expression.")
(let total (+ a b))
```

A `comment` node may have no executable semantics while still surviving into WIR
or LLVM as an annotation or textual comment. Its presence changes source
identity, not necessarily executable semantics.

A `comment` node is a standalone sibling in the surface tree. It has no hidden
ownership or attachment relationship with the preceding or following statement.
Moving a neighboring statement does not implicitly move the comment; a tool may
select both nodes only by an explicit edit. The formatter may keep a one-line
comment visually adjacent to a following multiline form, but that adjacency is
presentation, not tree identity. Issues #337 and #334 specify the node and the
printer rule.

Structured forms can distinguish different roles:

```weave
(doc "Compute a deterministic reduction.")
(example ...)
(comment "Keep the grouping visible for review.")
```

Of these, `example` earns its place only if it executes: examples are compiled
and run by the test workflow, and a failing example fails the build. Under P6,
an unchecked example is worse than no example, because generated code will
imitate it after it has drifted from the implementation.

Runtime logging is different. A hypothetical `(log "...")` that writes an event
is observable program behavior; it must not be treated as equivalent to a
no-op `comment`.

This principle avoids a second shadow representation for comments and metadata.
It also makes canonical source round-tripping substantially easier.

## P12. Surface ergonomics and execution semantics are separate layers

The source language should express programmer intent compactly. WIR and backend
IR should express execution semantics explicitly. Neither layer should be forced
to mimic the other's preferred representation.

Avoid exposing WIR ceremony merely because lowering needs it:

```weave
(if
  (condition (op less-than d 0.0))
  (then (do
    (return Roots.None)))
  (else (do)))
```

Prefer the surface intent:

```weave
(when (< d 0.0)
  (return Roots.None))
```

The compiler may lower that form to a conditional branch with explicit basic
blocks. Conversely, WIR does not need to preserve the fact that the author used
`when` if that distinction has no later semantic purpose.

Canonical formatting operates on the surface representation. It must not
round-trip source through a lower-level IR that has already discarded useful
surface intent.

## Worked design decisions

The principles become useful when they expose a trade-off rather than merely
approve an obvious choice.

### Function-local dependencies

A module-level import is token-efficient but weakens P2 for long files.
Fully-qualified calls satisfy P2 and P9 but repeatedly spend tokens, which costs
P7. A compiler-checked function-local dependency header can be a reasonable
middle ground:

```weave
(fn norm ((x f64)) f64
  (uses (std.math sqrt))
  (effects pure)

  (return (sqrt x)))
```

This is good redundancy only if the compiler verifies that the list is complete,
contains no unused dependencies, and resolves every name exactly. If the list is
hand-maintained ceremony that can drift from the body, P6 argues against it.

The resolution is the write-optional, read-present rule from P2: the header is
**derived**. An author writes only the calls; the formatter inserts or updates
the header; the compiler rejects a header that disagrees with the body. Under
that rule the header is pure reader value — canonical source always shows it,
and no writer ever maintains it. Without that rule, prefer qualified calls and
drop the header entirely.

### Variadic floating-point arithmetic

Flat Lisp arithmetic improves P7:

```weave
(+ a b c d)
```

but floating-point reassociation can change results, which conflicts with P10
and deterministic numerical semantics.

A possible resolution is a language-defined left fold:

```text
(+ a b c d) == (+ (+ (+ a b) c) d)
```

The compiler may not interpret the flat spelling as permission to reassociate.
Explicit alternative nesting remains programmer intent.

### Comments as AST nodes

Treating comments as parser trivia is conventional and compact, but weakens P3
and P11 because the formatter must invent attachment rules, and structural
edits cannot name the comment independently.

A structured no-op node:

```weave
(comment "This transform is intentionally not fused.")
(let residual (- predicted observed))
```

costs source tokens but gives comments stable identity, structural position, and
round-trip behavior. Binding that node invisibly to the following statement
would recreate the trivia problem as hidden ownership: deleting or moving the
statement would silently take the comment with it. The derived rule in issue
#337 is that `comment` is an ordinary sibling. A printer may place a one-line
comment next to a following multiline form; that is layout, not AST attachment.

### Canonical whitespace is derived from structure

Authors group statements with blank lines, and the grouping helps a reader
chunk logic. Storing that grouping as tree metadata would make invisible author
state part of program identity: two trees that mean the same thing would print
differently, and tools would have to preserve or edit whitespace flags.

The earlier draft that represented paragraph breaks as surface-tree metadata is
rejected. Whitespace is not preserved information. The formatter discards
arbitrary input spacing and reconstructs one layout from the parsed tree and
the compiler-owned complete-form width. Issue #334 specifies that derived
layout. A one-line `comment` may sit next to a following multiline sibling only
as a printer adjacency rule, not as AST ownership.

## Standing exclusions

These features are excluded by default. Each exclusion exists because of a
specific failure mode, not taste; each can be revisited with the evidence its
row names. Inline examples elsewhere in this document assume these exclusions.

| Excluded | Principles | Failure mode it prevents | Revisit if |
|---|---|---|---|
| Glob imports | P2, P9 | unresolvable names without whole-project context | never; explicit lists are derivable |
| Shadowing / rebinding a live name | P9 | stale-binding reads in long contexts | measured evidence renames cost more than confusion |
| Null and sentinel returns | P10 | silent wrong answers in unsupervised loops | never |
| Exceptions / unwinding | P2, P10 | invisible control flow | a checked design with ownership-aware cleanup |
| Function overloading | P9 | one name, many definitions breaks exact search | never; generics cover the space |
| Implicit numeric conversion | P4, P10 | invisible precision loss | never |
| Chained comparisons `(< a b c)` | P4 | one dropped operand silently changes meaning | never |
| Significant indentation | P8 | edit-time block corruption | never |
| Implicit tail return | P8 | statement reordering changes the result | never |
| Unchecked examples in docs | P6, P11 | models imitate drifted documentation | never; examples execute or do not exist |
| Textual macros (pre-1.0) | P2, P5 | user-defined dialects defeat priors and tools | a module-scoped, inspectable, capability-registered design |

## Design-review template

Issues that introduce or materially change language behavior should include a
short rationale in this form:

```text
Principles supported:
- P2 Local reasoning
- P6 Checked redundancy
- P9 Exact discoverability

Principles under tension:
- P7 Source-token density

Decision:
Use a function-local dependency header because the compiler can derive and
cross-check it. The extra source tokens buy local, verified context rather than
unchecked ceremony.

Evidence / follow-up:
Measure source-token overhead and agent edit reliability in the syntax eval.
```

The purpose is not bureaucracy. The purpose is to preserve the reasoning so a
future contributor or agent can tell whether a decision still makes sense when
the surrounding compiler changes.

## Relationship to authoritative specifications

This document answers **why**.

Other artifacts answer **what**:

- the compiler capability and grammar registry describes admitted features;
- the language reference describes implemented surface semantics;
- canonical-formatting documentation describes the current textual normal form;
- WIR documentation describes the compiler IR contract;
- `weavec --grammar`, once implemented, is the compact agent bootstrap view of
  the current language.

When this document and an implementation document appear to conflict, do not
silently reinterpret either one. Determine whether the implementation is
temporary, the principle needs revision, or the design has intentionally changed,
and record that decision explicitly.
