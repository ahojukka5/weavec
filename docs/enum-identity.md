# Enum values have no identity

This is the representation decision that lets `Option` become unboxed
later without breaking programs. The current compiler still boxes every
enum value; that layout is not part of the language.

## Decision

An enum value is a tag and an optional payload. It is not a pointer.

- `=` / `!=` do not compare enum values.
- `eq_ptr` / `ne_ptr` do not compare enum values.
- An enum value does not flow to `ptr`, including comparison with
  `null`.
- Binding an enum does not create an alias that programs can observe.

Compare constructors with `match` or `variant-tag`. Compare payloads
after a successful match. Those operations stay valid if the compiler
later stores `Option i32` in a register or uses a niche in the payload.

## Current lowering

Each enum value is still a 16-byte heap object: an `i32` tag at offset
0 and an 8-byte payload slot at offset 8. `vec_get` and `string_get`
allocate a fresh `Option` per access. There is no `option_release`.
That cost is a compiler defect, not a semantic guarantee.

## Diagnostic

Observable identity uses `frontend.enum.no-identity`:

```text
weavec: surface enum: values have no identity; use match or variant-tag, not pointer equality
```

Struct values still participate in pointer equality. That is a
different, documented gap; see [Semantic structs](semantic-structs.md).

## What this does not decide

Ownership of enum payloads, move of `Some` contents, and whether
`None` is a niche in a pointer or `usize` are issue #115. Unboxed
layout is a later representation change under this rule, not a new
language feature.
