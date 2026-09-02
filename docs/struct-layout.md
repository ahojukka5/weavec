# Struct layout and compatibility ABI

Surface `(struct ...)` declarations lower to WIR core version 3 functions. The
canonical LLM-facing API is documented in [Semantic structs](semantic-structs.md);
this document defines the generated storage and call ABI retained for low-level
compatibility.

The compiler never infers an unknown field representation or silently treats an
unsupported type as `i32`.

## Declaration and generated functions

```weave
(struct Mixed
  (field flag bool)
  (field count i64)
  (field ratio f32)
  (field total f64)
  (field data ptr)
  (field qubit Qubit)
  (field code i32))
```

The declaration produces compatibility functions named:

```text
Mixed_new
Mixed_get_flag
Mixed_set_flag
...
```

These names remain callable by existing low-level source. Canonical source uses
`new`, `field-get`, and `field-set`, and the compiler resolves these names and
argument positions internally.

## Field representation

| Surface field type | WIR representation | Size | Alignment | Load | Store |
|---|---|---:|---:|---|---|
| `bool` | `bool` value, byte in memory | 1 | 1 | `load_u8` plus comparison with zero | branch plus `store_i8` of `0` or `1` |
| `i32` | `i32` | 4 | 4 | `load_i32` | `store_i32` |
| `f32` | `f32` | 4 | 4 | `load_f32` | `store_f32` |
| `i64` | `i64` | 8 | 8 | `load_i64` | `store_i64` |
| `f64` | `f64` | 8 | 8 | `load_f64` | `store_f64` |
| `ptr` | `ptr` | 8 | 8 | `load_ptr` | `store_ptr` |
| `Qubit` | WIR `i64` | 8 | 8 | `load_i64` | `store_i64` |

`Qubit` follows the existing surface-to-WIR lowering contract and therefore has
the same physical representation as `i64`. Quantum validation remains separate
from this memory-layout rule.

`void`, undeclared field types, and future handle types are not admitted until
their complete representation is defined. They produce an error instead of
receiving fallback storage.

A WIR field type may also name a declared struct, laid out inline: the field
occupies the nested struct's bytes and takes its alignment. A struct containing
itself has no finite layout and is refused. The surface language does not yet
admit an aggregate field, because how such a field is constructed and copied is
bound up with value semantics.

## Natural layout

Fields remain in declaration order. Before placing a field, the current offset is
rounded up to that field's alignment. After the last field, the total allocation
size is rounded up to the largest field alignment.

For the `Mixed` example:

| Field | Offset |
|---|---:|
| `flag` | 0 |
| `count` | 8 |
| `ratio` | 16 |
| `total` | 24 |
| `data` | 32 |
| `qubit` | 40 |
| `code` | 48 |

The total size is 56 bytes and the aggregate alignment is 8 bytes. Padding bytes
are not initialized and cannot be addressed through generated accessors.

This is a deterministic compiler layout, not a promise of C ABI compatibility.
Interoperability with external structs requires a separate explicit ABI contract.

## Declaration validation

The frontend validates the complete declaration before emitting any constructor
or accessor. It rejects:

- a missing or non-identifier struct name;
- a struct name reserved by a built-in type;
- an empty struct;
- children other than `(field NAME TYPE)`;
- non-identifier field names or types;
- duplicate field names;
- every unsupported field type.

A failed declaration does not publish partial WIR or a native executable.
Declaration diagnostics include:

```text
frontend.struct.malformed
frontend.struct.unsupported-field-type
frontend.struct.duplicate-field
frontend.struct.reserved-type
```

Semantic construction and access diagnostics are listed in
[Semantic structs](semantic-structs.md).

## Compatibility policy

The compatibility constructor remains positional because changing its signature
would break existing WIR-shaped source. The semantic constructor is named and
reorders fields into declaration order:

```weave
(new Mixed
  (code 7)
  (flag true)
  ...)
```

Both paths use the same validated layout and generated WIR core-version-3
implementation. The compatibility ABI may be removed only through an explicit
future surface compatibility policy; WIR core version 3 is unchanged by semantic
structs.

## Where these rules should live

The layout on this page is resolved in the frontend, so WIR carries the result
of a target-shaped decision rather than the declaration it came from. Moving the
decision to the backend, and giving WIR a layout-free struct declaration and
typed field operations, is proposed for the next coordinated core-version
revision in [Next-version WIR struct fields](wir-next-struct-fields.md).
