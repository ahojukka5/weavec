# Semantic structs

Weave structs are nominal surface types with a deterministic, compiler-owned
layout. Source code uses semantic construction and field operations; generated
constructor and accessor names remain a WIR-v2 compatibility detail.

The feature remains experimental while its broader surface contract stabilizes.
The compiler semantics, type checking, diagnostics, native behavior, and
constructor-field formatting described here are implemented and regression
tested.

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

## Construction

The canonical constructor is:

```weave
(new Record
  (total 2)
  (flag true)
  (count 40))
```

Constructor fields are named rather than positional. The compiler:

1. resolves the struct declaration;
2. rejects malformed, unknown, duplicate, or missing fields;
3. checks every value against its declared field type;
4. emits arguments in declaration order, independent of source order;
5. lowers to the generated `Record_new` compatibility function.

`weavec fmt` also writes complete, unambiguous constructors in declaration order.
A comment immediately preceding a field clause is attached to that field and
moves with it. Malformed, unknown, duplicate, and incomplete constructors retain
source order so formatting never hides or repairs the semantic error.

For the declaration above, the example lowers structurally to:

```weave
(call_ptr Record_new
  (const_i64 40)
  (const_bool true)
  (const_f64 2))
```

No source author or agent needs to synthesize `Record_new` or remember positional
field order.

## Field access

```weave
(field-get record count)
(field-set record count new-count)
```

The receiver's nominal type selects the generated getter or setter. The compiler
rejects an untyped pointer, a non-struct value, an unknown field, or an assigned
value with the wrong type.

Field operations are ordinary expressions or statements and compose with other
canonical forms:

```weave
(field-set record count
  (op add (field-get record count) 2))
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

## Forward and multi-file resolution

Type names are interned deterministically during declaration collection. A
function may refer to a struct declared later in the same source or in a later
input file. Before a parameter, return, or local type is emitted, the compiler
verifies that the provisional type was actually defined and reports the exact
type occurrence otherwise.

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

Diagnostics identify the relevant struct or field, expected and actual types when
known, operand role, and exact source span. A failed frontend compilation does
not publish partial WIR or a native executable.

## Compatibility ABI

The existing generated functions remain callable by low-level source:

```text
TYPE_new
TYPE_get_FIELD
TYPE_set_FIELD
```

They are represented in `weavec-capabilities-v1` as the
`generated-struct-abi` compatibility family. New code should use `new`,
`field-get`, and `field-set`.

See [Struct layout and compatibility ABI](struct-layout.md) for sizes,
alignments, memory operations, and allocation layout.
