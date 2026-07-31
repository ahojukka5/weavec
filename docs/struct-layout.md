# Struct layout and compatibility ABI

Surface `(struct ...)` declarations lower to WIR core version 2 functions while
the higher-level semantic struct syntax is being completed. This document defines
the storage contract of that compatibility ABI. The compiler never infers an
unknown field representation or silently treats an unsupported type as `i32`.

## Current declaration form

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

A declaration currently produces compatibility functions named:

```text
Mixed_new
Mixed_get_flag
Mixed_set_flag
...
```

These generated names remain callable by existing low-level source, but they are
an implementation boundary rather than the final LLM-facing API. Issue #52 also
introduces canonical `new`, `field-get`, and `field-set` forms so agents do not
need to synthesize these names.

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

`void`, undeclared type names, aggregate names, and future handle types are not
admitted as fields until their complete representation is defined. They produce
a frontend error instead of receiving fallback storage.

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

## Validation

The frontend validates the complete declaration before emitting any constructor
or accessor. It rejects:

- a missing or non-identifier struct name;
- an empty struct;
- children other than `(field NAME TYPE)`;
- non-identifier field names or types;
- duplicate field names;
- every unsupported field type.

A failed declaration does not publish partial WIR or a native executable.
Diagnostics-enabled builds use exact compiler-semantic spans. Initial stable
classifications include:

```text
frontend.struct.malformed
frontend.struct.unsupported-field-type
frontend.struct.duplicate-field
```

## Compatibility and next step

The compatibility constructor remains positional because changing its signature
would break existing WIR-shaped source. Canonical semantic construction is named
and validated:

```weave
(new Mixed
  (flag true)
  (count 9)
  ...)
```

That semantic layer will reorder named constructor entries into declaration order,
resolve receiver types for field access, and produce field-specific type
diagnostics while retaining the layout and generated WIR-v2 implementation
defined here.
