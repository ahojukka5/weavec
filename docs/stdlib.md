# Standard-library layout and module naming

User-facing standard-library modules live in `stdlib/` at the repository
root and at the root of an extracted release package. That is the only
home for a new standard module.

This document is the naming and packaging contract. Failure, naming, and
mutation rules for exported APIs are in
[Standard-library API conventions](stdlib-conventions.md).

## Home and identity

Each standard module is one source file:

```text
stdlib/<id>.weave
```

`<id>` is the file stem: lowercase ASCII letters only. The module
identity is `std.<id>`. Today that appears as:

```weave
(program
  (name "std.io")
  (version "0.1")
  ...)
```

The file stem and the name suffix must match. `stdlib/io.weave` is
`std.io`. A later explicit-module spelling may use `(module std.io
...)` without changing the path or the identity.

Do not place standard modules under `src/`, `runtime/`, or a second
library tree. Do not give a standard module a name that is not `std.<id>`.

## Current catalog

| Path | Identity | Provides |
|---|---|---|
| `stdlib/memory.weave` | `std.memory` | The single `malloc`/`free` boundary. |
| `stdlib/process.weave` | `std.process` | Command-line arguments. |
| `stdlib/parse.weave` | `std.parse` | ASCII decimal number parsing. |
| `stdlib/io.weave` | `std.io` | Writing text and numbers. |
| `stdlib/math.weave` | `std.math` | Square root and trigonometry. |
| `stdlib/option.weave` | `std.option` | Canonical `Option`, plus `is_some`, `is_none`, and `unwrap_or`. |
| `stdlib/result.weave` | `std.result` | Canonical `Result`, plus `is_ok`, `is_err`, and `unwrap_or`. |
| `stdlib/vector.weave` | `std.vector` | Fixed `Vec3`, not a generic vector. |
| `stdlib/matrix.weave` | `std.matrix` | Fixed `Mat3`. |
| `stdlib/statistics.weave` | `std.statistics` | Mean and variance. |
| `stdlib/file.weave` | `std.file` | Reading a small text file as lines. |
| `stdlib/bytes.weave` | `std.bytes` | Owned byte buffer: length, append, get. |
| `stdlib/string.weave` | `std.string` | Owned text buffer: length, append, get. |
| `stdlib/vec.weave` | `std.vec` | Generic `Vec` and `Slice`, currently `i32` only. |
| `stdlib/convert.weave` | `std.convert` | Format and parse `i32`, `i64`, `f64`, and `bool`. |

`std.bytes` and `std.string` are owned buffers. Indexing uses `bytes_get`
and `string_get`, which return `None` when the index is out of range.
They do not abort. `std.memory` and `std.option` must appear before
them. `std.bytes` must appear before `std.string`.

`std.vec` is the generic growable vector. `vec_get` and `slice_get`
return `None` when the index is out of range; `vec_set` and `slice_set`
return false. They do not abort. The only admitted element type is
`i32` until layout-aware monomorphization exists. A `Slice` shares the
vector buffer; it is a data type, not a borrow checker. `std.memory`
and `std.option` must appear before `std.vec`. `std.vector` remains
the existing three-component `Vec3`.

`std.convert` formats admitted primitives to an owned `String` and
parses text into `Result`. There is no locale and no printf. `format_f64`
matches `write_f64_trimmed`: six-place rounding, trailing fractional
zeros removed, at least one fractional digit. `parse_float` wraps
`parse_f64_valid` and `parse_f64`. Invalid text is `Err 1`. `std.memory`,
`std.option`, `std.result`, `std.parse`, `std.io`, `std.bytes`, and
`std.string` must appear before `std.convert`.

## Adding a module

1. Create `stdlib/<id>.weave` with `(name "std.<id>")`.
2. Reuse an existing `<id>` only when replacing that module in place.
3. Declare host `extern`s in the module that owns them.
   `malloc` and `free` stay in `std.memory`.
4. List the module in this catalog and, if examples use it, in
   [`examples/README.md`](../examples/README.md).
5. Do not add collection, path, or I/O behavior here unless that is the
   owning issue.

Existing `stdlib/*.weave` paths and `std.*` names stay. There is no
rename migration.

## How programs use the modules

Standard modules are ordinary Weave sources. A program names the files
it needs, dependencies first:

```sh
weavec build \
  stdlib/memory.weave \
  stdlib/process.weave \
  stdlib/io.weave \
  examples/pythagoras/main.weave \
  -o pythagoras
```

The same relative paths work from a repository checkout and from an
extracted release package. The compiler does not yet invent this list
from a module name.

`std.memory` must appear before any module that allocates.
`std.vector` must appear before `std.matrix`.

## How packages ship the layout

Release archives copy the `stdlib/` directory to the package root next
to `bin/` and `examples/`. Extracted layout:

```text
weavec-vX.Y.Z-linux-x86_64-<libc>/
├── bin/weavec
├── lib/weavec/<target-triple>/libweave-runtime.a
├── stdlib/*.weave
├── examples/
└── ...
```

A new file added under `stdlib/` is part of the next package. Do not
split or flatten that directory during packaging.

## Private runtime ABI

The private target runtime is a compiler resource, not a user library.
Packages store it at `lib/weavec/<target-triple>/libweave-runtime.a`.
`weavec build` finds it. Users must not link that archive, pass
`--runtime`, or set `WEAVEC_RUNTIME`.

Names that begin with `weave_rt_` or `__weave_` are compiler-private.
Application source must not declare them. A standard module may call a
narrow, versioned private ABI when Weave cannot yet express the host
operation; that call stays inside `stdlib/`. See
[Runtime implementation boundary](runtime-boundary.md).
