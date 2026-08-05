# Runtime implementation boundary

Weave application semantics should be implemented in Weave whenever the language
can express them. C is a narrow host boundary, not a second standard library.

## Policy

- Formatting, parsing, numeric algorithms, collection logic, and other portable
  language behavior belong in Weave libraries.
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

## Current floating-point example

`stdlib/io.weave` owns decimal rounding, digit generation, fixed-width fractional
output, and trailing-zero removal. It uses only the platform `write` and `strlen`
ABI functions. The application runtime C source remains unchanged.

Decimal literal recognition currently needs a narrow compiler-host override in
`runtime/decimal_surface.c` because the published bootstrap parser predates decimal
atoms. This is compiler bootstrapping support, not application runtime behavior.
It should disappear when the lower bootstrap stage publishes native decimal-token
support.
