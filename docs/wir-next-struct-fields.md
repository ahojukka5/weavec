# Next-version WIR struct fields

This document specifies first-class struct declarations and field access for WIR
core version 3.

Core version 3 is open: the self-hosted frontend and backend moved to it as part
of this coordinated revision, and core version 2 is now a frozen bootstrap-stage
version that the current compiler rejects.

This is implemented. The frontend emits these forms and computes no offsets;
the backend resolves layout in `src/llvm/struct_layout.weave`.
`test/struct-forms` asserts the derived offsets against emitted LLVM, and
`test/struct-layout` asserts that no layout number survives into WIR.

It is a sibling of
[Next-version WIR source locations](wir-next-source-locations.md). Both are
collection items for the same coordinated version change, and neither justifies
a version bump on its own.

## What WIR said about structs before this

Recorded because it is the reasoning the decision rests on, not because it still
describes the compiler.

A surface `(struct ...)` declaration did not appear in WIR at all. The frontend
lowered it to generated functions and lowered every field operation to a call:

```text
(call_f64 Point_get_x (local_get p))
```

`Point_get_x` was a generated WIR function whose body computed a byte offset:

```text
(load_f64 (ptr_add (param_get self) (const_i64 8)))
```

The offset came from `stl_field_offset` in `src/frontend/struct.weave`, which
walked the declared fields applying the sizes and alignments recorded in
[Struct layout and compatibility ABI](struct-layout.md). That function and its
helpers no longer exist.

So the frontend chose a physical layout. WIR did not describe a struct; it
described the consequences of one layout decision already made, spread across
one generated function per field.

## Why that placement was wrong

Layout is a property of the target. Size, alignment, padding, and field order
are the things a target ABI gets to decide, and they are the things a backend is
positioned to decide because it is the component that knows the target.

Resolving layout in the frontend had three consequences:

- WIR was target-shaped. The same program produced different WIR for targets
  differing in alignment, so WIR could not be a portable interchange format for
  any program using a struct.
- Layout could not change without regenerating WIR. A better packing rule, a
  target-specific rule, or a debug-vs-release layout were all frontend edits.
- The struct was not recoverable. Once WIR said `ptr_add self 8`, "field `y` of
  `Point`" was gone, and every consumer downstream of the frontend saw pointer
  arithmetic rather than a field access.

## Rejected: spelling field access as pointer arithmetic

The cheapest change is to drop the generated accessors and emit `ptr_add` plus a
typed load directly at each use site. It needs no version change, because
`ptr_add` and typed loads are already admitted forms.

It is rejected because it makes every consequence above worse rather than
better. It does not introduce the target-shaped assumption, but it multiplies
it: the offset moves from one generated function per field to every use site in
every program. It is the direction of travel that matters, and this is the wrong
direction taken for the reason that it is cheap.

## Rejected: keeping accessor calls and inlining them in the backend

The other cheap change is to leave WIR alone and teach the backend to recognise
and inline the generated accessors. It needs no version change and no fixture
migration.

It is rejected because it asks the backend to recover semantics from a naming
convention. `Point_get_x` is an implementation artifact presented as a public
symbol, and a backend that pattern-matches the name is depending on something no
document promises. It also leaves WIR describing a field read as a function
call, so no consumer gains anything.

## Decision

WIR gains layout-free struct declarations and typed field operations. The
backend resolves layout, because it is the component that knows the target.

WIR says what the program means. The backend decides how it is stored.

### Declaration

A struct declaration appears in `(decls ...)` alongside functions and externs:

```text
(struct Point
  (field x f64)
  (field y f64))
```

The declaration carries no offset, no size, no alignment, and no packing
directive. Field order is significant, because it is the declared order the
backend derives a layout from, not a layout in itself.

The admitted field types are the WIR scalar types: `bool`, `i32`, `i64`, `f32`,
`f64`, and `ptr`. A surface `Qubit` has already lowered to `i64` before it
reaches WIR, so no surface-only type appears in a declaration — the
correspondence is in [Struct layout and compatibility ABI](struct-layout.md).

A field type may also name a declared struct, which is laid out **inline**: the
field occupies the nested struct's bytes directly rather than a pointer to them,
and takes the nested struct's alignment. This needed no version change, because
the declaration form already carries a type name per field.

A type naming neither a scalar nor a declared struct is refused rather than
defaulted, because an unrecognised type would silently take `i32`'s size and
alignment and move every field after it.

A struct that contains itself, directly or through other structs, has no finite
layout and is refused by name.

### Size

```text
(struct_size Point)
```

A constant expression of type `i64`. It exists so that a producer can request
storage for a struct without computing its size, which is the one remaining
place a layout number would otherwise have to appear in WIR.

The allocation strategy itself is deliberately not part of this proposal. The
frontend continues to pair `struct_size` with an ordinary allocation call, and
whether a non-escaping struct should instead use stack storage is a separate
decision that this form does not prejudge.

### Field address

```text
(field_addr Point x (local_get p))
```

Fixed arity: struct name, field name, receiver expression. The result is `ptr`.
No load is performed.

This is the composition primitive. A struct-typed field yields the address of
the nested struct, which is the receiver of the next `field_addr` or
`field_get_*`, so nested access composes without a path form:

```text
(field_get_f64 Inner b (field_addr Outer inner (param_get o)))
```

Each step is a constant-offset `getelementptr`, and LLVM folds the chain into a
single one at the absolute offset. Composition therefore costs nothing against
a dedicated path form, which is why no path form exists.

### Field read and write

```text
(field_get_f64 Point x (local_get p))
(field_set_f64 Point x (local_get p) (const_f64 1.5))
```

The result type appears in the opcode, matching `load_f64`, `call_f64`, and
`add_i32`. This is redundant with the declaration, deliberately and consistently
with `call_*`, which spells a result type that is equally derivable from the
callee declaration. It lets a consumer type an expression tree without resolving
a symbol table.

The typed suffixes are `bool`, `i32`, `i64`, `f32`, `f64`, and `ptr`. A `bool`
field occupies one byte, so `field_get_bool` narrows the loaded byte to `i1` and
`field_set_bool` widens the stored value, matching the representation table in
[Struct layout and compatibility ABI](struct-layout.md).

The suffix must agree with the declared field type. Without that check,
`field_get_i32` on an `f64` field would emit a four-byte load from an
eight-byte field and read half a double as an integer. A struct-typed field has
no scalar type and so matches no suffix: it is reached with `field_addr`.

`field_get_T` is equivalent to a `field_addr` followed by `load_T`, and
`field_set_T` to a `field_addr` followed by the matching store. Both are kept
rather than decomposed, because a single node is what preserves "this is a field
access" for diagnostics and for analysis consumers — which is the property the
whole decision exists to protect.

### What a backend does with this

A field access becomes a `getelementptr` with a constant index and, for the read
and write forms, one load or store. A constant-index `getelementptr` folds into
the addressing mode, so the emitted code is the same one the current generated
accessors reach after inlining.

The layout rules themselves are not new work. `stl_type_size`,
`stl_type_alignment`, `stl_align_up`, and `stl_field_offset` already implement
them and are already exercised by the struct suites. The change relocates them
from the frontend to the backend rather than reimplementing them.

## Consumer survey

The decision to change the core version needs the consumers named rather than
assumed. This is what reading them found.

### The compiler's own sources declare no structs

No file under `src/` contains a `(struct ...)` declaration. Only four standard
modules do: `stdlib/vector.weave`, `stdlib/matrix.weave`, `stdlib/file.weave`,
and `stdlib/statistics.weave`.

The compiler therefore compiles itself without emitting a single struct form.
The bootstrap chain, the self-host fixed point, and the stage comparison are
unaffected by the new forms, and only affected by the version number.

### The build pipes WIR between binaries, but never between versions

`build.sh` lowers the compiler sources to WIR with the `weavec-bootstrap` SDK
and compiles that WIR with the `weavec1` SDK. `scripts/selfhost.sh` and
`scripts/package-linux-release.sh` pipe `--frontend` output into `--backend`.

Every one of these pairs a producer and a consumer of the same generation, so
the change introduces no cross-version pipe. The constraint it does introduce is
on the next SDK release: a bootstrap SDK that emits the new version must not be
paired with a `weavec1` SDK that does not accept it. The version check in
`src/llvm/module.weave` is a strict equality, so that mistake fails immediately
and by name rather than producing wrong code.

### Loupe parses WIR structurally and pins the version twice

`src/weave_loupe/wir_syntax.py` is a positional S-expression parser with no
opcode allowlist, so unknown forms parse. `wir_analysis.py` counts opcodes
generically and interprets only the forms it must: the envelope, the declaration
and contract roles, the control-flow and operand forms it builds a control-flow
graph from, and any operator matching `^call(_|$)`, which is how it recovers the
call graph.

A new expression form is therefore counted but not otherwise interpreted, which
is the correct outcome: a field access is not a call and should not appear as a
call-graph edge.

The version is a different matter. Loupe rejects anything but 2 in two places:

- `wir_analysis.py`, which requires "the single integer token 2";
- `bundle/ingest.py`, whose `_WIR_CORE_V2` regex gates bundle ingest.

Both are hard failures, not degradations. Loupe must be updated before it can
analyse anything the new compiler emits.

Loupe bundles retain WIR text, so previously published bundles hold version 2
WIR permanently. Loupe must therefore read both versions, while the compiler
reads only the current one. That asymmetry is correct and worth stating as a
rule: a compiler consumes the contract it targets, and an analyser consumes
every contract that was ever published.

### One further Loupe consequence, from a later step rather than this one

Once field access stops being a call, the generated accessors disappear from the
call graph and the function census. Loupe's diffs will show that as a large
removal. It is a real reporting change, but it belongs to the step that removes
the accessors, not to this one, and it is a change in what is true rather than a
change in what Loupe can see.

### Fixture migration is mechanical apart from the version fixtures

The corpus holds 239 hand-written WIR sources and 337 `.wir` files in total,
plus 168 LLVM goldens carrying a version header. Their version line is a
mechanical rewrite and their expected outputs regenerate.

The deliberate part is small and already localised.
`scripts/check_wir_core_version.py` audits the whole corpus and inlines the
intentionally invalid fixtures it permits, and the correctness suite proves
rejection of core version 1, missing versions, duplicate versions, non-integer
versions, and invalid roots. Superseding a version adds a rejection case rather
than replacing one: version 1 and version 2 must both be rejected afterwards.

## Migration

- One core version is live in the compiler at a time. Accepting two would make
  the version stop identifying a fixed grammar, which is the only thing it is
  for.
- The corpus moves to the new version in one step, including the sources that
  contain no struct at all.
- `scripts/check_wir_core_version.py` and the envelope rejection fixtures are
  updated deliberately, and gain a case rejecting the superseded version.
- Loupe gains dual-version support before the compiler emits the new version,
  since its two pins are hard failures.
- [WIR core version 3](wir.md) and
  [Struct layout and compatibility ABI](struct-layout.md) are revised together:
  the layout tables move from a frontend description to a backend one.

## Compatibility

The generated `NAME_new`, `NAME_get_FIELD`, and `NAME_set_FIELD` functions are a
documented compatibility ABI for existing low-level source. This proposal does
not remove them. A producer may continue to call them, and the frontend may
continue to generate them from the same declaration, with their bodies expressed
in the new forms rather than in byte offsets.

Removing them remains subject to the explicit surface compatibility policy in
[Struct layout and compatibility ABI](struct-layout.md).

## Deliberately unanswered

- Whether a non-escaping struct should use stack storage, and what form would
  express it.
- Whether a struct assignment copies, and what a copy form would be. This is
  bound up with ownership and belongs with that work.
- Whether the layout rule should stay a single deterministic compiler layout or
  become target-selected once a second target exists. The point of this proposal
  is that the question becomes answerable in the backend; it does not answer it.
- Whether a future ABI contract for interoperating with external structs
  constrains the declaration form.

## Related documents

- [WIR core version 3](wir.md)
- [Semantic structs](semantic-structs.md)
- [Struct layout and compatibility ABI](struct-layout.md)
- [Next-version WIR source locations](wir-next-source-locations.md)
- [Architecture](architecture.md)
