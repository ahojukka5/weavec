# Runtime implementation boundary

Weave application semantics should be implemented in Weave whenever the language
can express them. C is a narrow host boundary, not a second standard library or
compiler implementation language.

## Policy

- Formatting, parsing, numeric algorithms, collection logic, and other portable
  language behavior belong in Weave code.
- C may expose operating-system or platform ABI operations that Weave cannot yet
  express directly and safely.
- A missing Weave feature is a reason to add the smallest useful language feature,
  not a default reason to grow the C runtime.
- A C helper must remain mechanical: it must not choose language semantics,
  duplicate a portable algorithm, or become the only implementation of user-level
  behavior.
- New C runtime code requires a concrete executable example and an explanation of
  why the same behavior cannot yet be implemented in Weave.
- When the required Weave capability becomes available, the corresponding C helper
  should be removed in the same change.
- WIR is an intermediate representation and fixture format, not a production
  implementation language used to bypass the surface-Weave ownership rule.

## Floating-point example

`src/parser/lexer.weave` recognizes decimal numeric atoms and preserves their exact
source spelling. The self-hosted frontend assigns decimal literals their surface
floating type and lowers them to ordinary WIR `const_f32` or `const_f64` forms.
The self-hosted LLVM layer emits a `bitcast` of the IEEE bits so LLVM never
sees a non-representable decimal token. The bit conversion itself is
`weave_rt_float_literal_bits` in the compiler host: weavec1 cannot compile
`f64` compiler sources, so Weave cannot yet own that step. The helper copies
the source span and returns host IEEE bits; it does not choose a second
rounding rule.

`stdlib/io.weave` owns decimal rounding, digit generation, fixed-width fractional
output, and trailing-zero removal. Its only host dependencies are the platform
`write` and `strlen` ABI functions. The application runtime C source remains
unchanged.

This division is intentional: the host moves bytes, while Weave decides what a
floating-point program means and how its portable textual representation is
constructed.

## Compiler output writes

Frontend WIR and backend LLVM emission share file descriptors with C helpers
that write specialized enum WIR and source-location comments. Surface Weave has
no process globals, so a Weave-only buffer would interleave with those C
`write()` calls. The host therefore owns one grow-once 64KiB buffer in
`runtime/portable.c`. `src/core/io.weave` is the Weave API: `write_byte`,
`write_bytes`, and `write_cstr` append, and `write_finish` flushes, closes, and
reports failure. Stdout and stderr still flush immediately so diagnostics are
not delayed. A short write or `ENOSPC` prints `weavec: error: write failed` and
exits nonzero instead of leaving a truncated `.wir` or `.ll`.

When Weave gains process-global mutable storage, the buffer policy should move
into `src/core/io.weave` and the C helpers should call it, or the C emission
helpers should move into Weave.

## Process arguments and basic math

CLI programs opt into `stdlib/process.weave`, whose native entry wrapper receives
the platform `argc`/`argv` pair and captures it into a mechanical host store before
calling the application's high-level `program_main` function. The module owns the
user convention that the executable name is hidden and arguments are zero-indexed.
`stdlib/parse.weave` performs deterministic ASCII-to-`f64` parsing entirely in
Weave. `process_exit` is a mechanical `exit` wrapper. Environment lookup lives
in `stdlib/env.weave`: `getenv` is copied into an owned `String` and missing
names are `None`. Path joining lives in `stdlib/path.weave` in Weave.
`file_write_text` uses libc `fwrite` the same way `file_open_text` uses
`fopen`. There are no new `weave_rt_` symbols.

`stdlib/math.weave` implements reusable `sqrt_f64` and trigonometric
kernels in Weave. `sqrt` of a negative is `NaN`, not `0.0`. The
intended correctly rounded implementation is `llvm.sqrt` once WIR
admits it; see [Floating-point special values](floating-point.md).
The C runtime therefore contributes no numeric algorithm and no libm
dependency; for this feature it only stores and returns the
platform-provided raw argument values mechanically.

User-facing modules live in `stdlib/` and are named `std.<id>`. Application
source must not link the private target runtime or declare `weave_rt_` /
`__weave_` symbols. See
[Standard-library layout and module naming](stdlib.md).
