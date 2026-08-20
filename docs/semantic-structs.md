# Semantic structs

Weave structs are nominal surface types with a deterministic, compiler-owned
layout. Source code uses semantic construction and field operations; generated
constructor and accessor names remain a WIR-v2 compatibility detail.

The feature remains experimental while its broader surface contract stabilizes.
The compiler semantics, type checking, diagnostics, native behavior, module
interfaces, and constructor-field formatting described here are implemented and
regression tested.

## Declaration

```weave
(struct Record
  (field count i64)
  (field flag bool)
  (field total f64))
```

A struct name is a nominal type. Built-in names such as `i32`, `ptr`, and
`Qubit` are reserved. `Record`, another structurally identical type, and plain
`ptr` are distinct surface types. Parameters, local bindings, and
return declarations may use the struct name directly:

```weave
(fn identity
  (params (value Record))
  (returns Record)
  (do
    (return value)))
```

Nominal struct types lower physically to WIR `ptr`; WIR core version 2 is not
extended.

## Module interfaces

An explicit module may export a struct through the ordinary symbol interface:

```weave
(module records
  (export Record)
  (struct Record
    (field value i32)))
```

A consumer must import that type explicitly before using it:

```weave
(module application
  (import records (Record))
  (fn identity
    (params (value Record))
    (returns Record)
    (do (return value))))
```

The imported name retains the defining module's nominal identity. Importing it
does not create a consumer-local copy, and two modules' same-spelled structs
remain incompatible. Types share the module binding namespace with functions,
externs, entries, and constants, so local and imported name collisions are
rejected deterministically.

See [Public nominal type interfaces](public-nominal-types.md) for visibility,
re-export policy, project behavior, semantic-index facts, and stable diagnostics.

## Construction

The canonical constructor is:

```weave
(new Record
  (total 2)
  (flag true)
  (count 40))
```

Constructor fields are named rather than positional. The compiler:

1. resolves the local or imported struct declaration;
2. rejects malformed, unknown, duplicate, or missing fields;
3. checks every value against its declared field type;
4. emits arguments in declaration order, independent of source order;
5. lowers to the generated defining-module compatibility function.

`weavec fmt` also writes complete, unambiguous constructors in declaration order.
A comment immediately preceding a field clause is attached to that field and
moves with it. Malformed, unknown, duplicate, and incomplete constructors retain
source order so formatting never hides or repairs the semantic error.

For a legacy-program declaration named `Record`, the example lowers structurally
to:

```weave
(call_ptr Record_new
  (const_i64 40)
  (const_bool true)
  (const_f64 2))
```

Explicit modules use a deterministic module-qualified helper name instead. No
source author or agent needs to synthesize either helper or remember positional
field order.

## Field access

```weave
(field-get record count)
(field-set record count new-count)
```

The receiver's nominal type selects the generated getter or setter from the
defining module. The compiler rejects an untyped pointer, a non-struct value, an
unknown field, or an assigned value with the wrong type.

Field operations are ordinary expressions or statements and compose with other
canonical forms:

```weave
(field-set record count
  (+ (field-get record count) 2))
```

## Pointer boundary

A nominal struct value may flow to an explicitly declared low-level `ptr`
parameter, which permits operations such as:

```weave
(extern free (params (value ptr)) (returns void))
(call free record)
```

This is a one-way representation escape. The compiler does not implicitly turn
an arbitrary `ptr` into `Record`, and it does not allow one nominal struct type
where another is expected.

Nominal struct values participate in pointer equality, including comparison with
`null`. Arithmetic, ordering, casts, and Boolean use remain invalid unless a
future language feature defines them explicitly.

## Binding and release, and what is not yet checked

A struct value is a pointer, so binding aliases rather than copying:

```weave
(let a Counter (new Counter (n 1)))
(let b Counter a)
(field-set b n 42)
(field-get a n)                  ; 42 — one object, two names
```

The intended model is that a struct is an owned value which binding moves, with
aliasing requiring an explicit borrow. That is recorded in
[Struct value semantics](struct-ownership.md) and implemented by the ownership
work, not yet by this compiler.

Until then the compiler enforces none of it, and three mistakes compile without
a diagnostic:

- **releasing twice**, directly or through an alias;
- **using a value after releasing it**;
- **releasing a value a called function already released.**

Every standard module that allocates exposes an explicit release —
`vec3_release`, `mat3_release`, `samples_release`, `text_file_close` — and each
must be called exactly once on each allocation. A struct passed to a function
that releases it must not be used or released again by the caller.

Note that copying would not remove these. `Samples` and `TextFile` each hold a
`ptr` field naming storage they own, so a field-wise copy shares that storage
and releasing both copies frees it twice.

## Forward and multi-file resolution

Type names are interned deterministically during declaration collection. A
function may refer to a struct declared later in the same source or in a later
input file.

For an imported type, the compiler creates a provisional identity from the
explicitly named defining module and source type name. The later declaration
completes that same identity. Before a parameter, return, or local type is emitted,
the compiler verifies that the provisional type was actually defined and reports
the exact type occurrence otherwise.

Source argument order and absolute checkout path therefore do not affect nominal
identity, generated helper names, or interface hashes.

## Diagnostics

Semantic struct failures use exact compiler-semantic source spans. Stable codes
introduced by this feature include:

```text
frontend.struct.undefined-type
frontend.struct.duplicate-type
frontend.struct.reserved-type
frontend.struct.constant-unsupported
frontend.struct.constructor.malformed
frontend.struct.constructor.unknown-field
frontend.struct.constructor.duplicate-field
frontend.struct.constructor.missing-field
frontend.struct.receiver-type
frontend.struct.field.unknown
frontend.struct.field.malformed
frontend.struct.field-type-mismatch
```

Module visibility and binding failures use the stable `frontend.module.*` codes
documented in [Public nominal type interfaces](public-nominal-types.md).
Diagnostics identify the relevant struct, import, export, declaration, or field,
expected and actual types when known, operand role, and exact source span. A failed
frontend compilation does not publish partial WIR or a native executable.

## Compatibility ABI

The existing generated functions remain callable by low-level source. Legacy
programs use:

```text
TYPE_new
TYPE_get_FIELD
TYPE_set_FIELD
```

Explicit modules use deterministic defining-module-qualified bases before the
same `_new`, `_get_FIELD`, and `_set_FIELD` suffixes. Both forms are represented
in `weavec-capabilities-v1` by the `generated-struct-abi` compatibility family.
New code should use `new`, `field-get`, and `field-set`.

See [Struct layout and compatibility ABI](struct-layout.md) for sizes,
alignments, memory operations, and allocation layout.
