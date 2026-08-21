# Standard-library API conventions

This is the failure, naming, and mutation contract for `stdlib/` modules.
Layout and packaging remain in [Standard-library layout](stdlib.md).

New standard-library APIs follow these rules. Existing spellings that
violate them stay only as documented compatibility, not as patterns to
copy.

## Failure signaling

There are three admitted outcomes. Do not invent a fourth.

| Situation | Return | Example |
|---|---|---|
| A value may be absent | `Option T` | `string_get`, `vec_get`, `samples_get`, `process_arg` |
| An operation may fail with a cause | `Result T E` | `parse_f64`, `parse_float`, file open |
| A mutation may refuse | `bool` | `vec_set`, `vec_push`, `samples_add` |

`true` means the mutation happened. `false` means it did not: out of
range, out of capacity, or allocation failed. The receiver is unchanged
on `false`.

Do not return a plausible value for failure:

- no `0.0`, `0`, or `false` as a parse or lookup result;
- no null `ptr` as an out-of-range argument;
- no silent drop of a pushed sample or grown vector.

Unrecoverable invariant breaks (a proven in-range index that still
fails) may abort. They are not a substitute for `Option` or `Result` on
public APIs.

`parse_f64_valid` remains a predicate. `parse_f64` itself should return
`Result f64 i32`. Invalid text is `Err 1`. `parse_float` is the same
function for the convert module.

The compiler currently specializes `Option` and `Result` helpers for
`i32` payloads. `Option f64`, `Result f64 i32`, and `Option ptr` are
not yet emitted, so `parse_f64`, `samples_get`, and `process_arg` still
use their pre-convention returns until that specialization exists.
`vec_push` still returns the vector; new mutation APIs should return
`bool`.

## Naming

Exported names are `<module-stem>_<verb>` or a type-specific prefix
that already identifies the module (`string_`, `bytes_`, `vec_`,
`samples_`, `process_`).

`std.io` still exports unprefixed `write_stdout`, `write_stderr`, and
`print_f64`. Those names stay so existing programs keep building. New
I/O entry points use an `io_` prefix. `std.process` keeps `args_count`
and `arg`. The Option form should be named `process_arg` once `Option
ptr` specializes.

## Mutation and ownership

A function either:

- observes and returns `Option` / `Result` / a copyable scalar, or
- mutates a receiver and reports success with `bool`.

Do not mutate a receiver and also return it as the only success signal.
`string_append` currently returns the receiver; that is compatibility.
New buffer APIs return `bool` or `void` after a proven in-capacity
write.

Callers still release owned values they create (`samples_release`,
`free` through `std.memory`). This document does not add an ownership
checker; it only forbids hiding failure inside a returned handle.

## What this does not decide

Integer widths (`usize`) are issue #280. Floating specials (`NaN`,
`sqrt` of a negative) are issue #283. Bounds-check and I/O error
behavior for paths and files are issue #247.
