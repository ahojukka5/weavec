# Integer widths and the size type

This is the size and unsigned-integer decision for Weave. The compiler
does not yet admit these types; new standard-library signatures must
not keep baking `i32` into lengths while they are still cheap to
change.

## Decision

| Type | Role |
|---|---|
| `usize` | Lengths, indices, capacities, and byte counts. Unsigned, pointer-width. |
| `u64` | Explicit 64-bit unsigned values that are not sizes. |
| `u8` | A stored byte. `Bytes` indexing yields `u8`, not `i32`. |
| `i32` / `i64` | Signed arithmetic and existing APIs until they migrate. |

`usize` is not a distinct bit-width from `u64` on the current host
matrix (Linux x86_64). It is still a distinct *role*: a length is a
`usize` even when that is 64 bits, so a later 32-bit or wider pointer
target does not rewrite every container signature.

Do not add `u16` or `u32` until a concrete ABI or wire format needs
them. Do not use `i32` as an unsigned size.

## Current surface

Implemented primitives remain `i32`, `i64`, `f32`, `f64`, `bool`,
`ptr`, and `void`. `for` ranges, `Vec.len`, `string_len`, and
`bytes_len` are still `i32`. Those signatures are compatibility, not
the size model.

## Migration

1. Admit `u8`, `u64`, and `usize` as surface types and WIR integer
   widths in one coordinated change.
2. Use `usize` in every new length, index, and capacity parameter.
3. Migrate the existing ~15 standard modules while they are still
   small: `Vec`, `Slice`, `String`, `Bytes`, `samples_count`, `for`.
4. Keep `i32` loops working through an explicit `cast` until call
   sites move.

A later `usize` change after those signatures freeze is a breaking
stdlib rewrite. Adding the types without using them in new APIs is
the same freeze.

## What this does not decide

`Option`/`Result` specialization for non-`i32` payloads is required
before `bytes_get` can return `Option u8`. That is the same gap
recorded in [Standard-library API conventions](stdlib-conventions.md).
Signed-vs-unsigned arithmetic conversion remains explicit. There is
no implicit `i32` to `usize` promotion.
