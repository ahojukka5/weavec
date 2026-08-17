# WIR core version 3

`weavec` uses WIR core version 3 as its intermediate representation between
surface lowering and LLVM emission.

The required module envelope is:

```text
(core-module
  (core-version 3)
  (decls
    declaration...))
```

The version value is the integer token `3`. A missing value, a string such as
`"3"`, or additional values do not satisfy the envelope. Core versions 1 and 2
are rejected: a superseded version is refused by name rather than tolerated, so
a stale toolchain fails immediately instead of producing wrong code.

## Product pipeline

```text
surface Weave
    │ weavec --frontend
    ▼
WIR core version 3
    │ weavec --backend
    ▼
LLVM IR
```

The seed compiler is built across a **different** boundary:

```text
surface compiler sources
    │ weavec-bootstrap v0.3.1
    ▼
WIR core version 2
    │ weavec1 v0.3.2
    ▼
LLVM IR for the seed weavec compiler
```

The two boundaries do not agree, and cannot: `weavec-bootstrap` and `weavec1`
are frozen released artifacts, so they stay at core version 2 permanently. They
build the seed compiler and are not involved afterwards.

The two never meet. Every producer and consumer in the build is paired with one
of the same generation — `build.sh` pairs the bootstrap frontend with the
`weavec1` backend, and `scripts/selfhost.sh` and release packaging pipe one
`weavec` binary into itself. A mismatched pair fails on the envelope check
rather than producing wrong code. See
[Two WIR boundaries](architecture.md) for the same picture in context.

The final compiler does not maintain a private WIR dialect: changing admitted
forms or semantics requires a coordinated version transition.

## Envelope validation

`weavec --backend` validates the complete module envelope before opening its LLVM
output file. A valid input must:

1. have `core-module` as the root form;
2. contain exactly one `core-version` declaration;
3. declare the integer version token `2` as its only value;
4. contain a `decls` form;
5. satisfy the existing declaration and call-target checks.

The backend rejects every superseded version:

- core version 1;
- missing version declarations;
- duplicate version declarations;
- a missing version value;
- non-integer or additional version values;
- roots other than `core-module`.

Version-envelope and call-target failures occur before output creation. Errors
found during LLVM emission remove the partial output before the backend returns,
so every failed backend invocation leaves no LLVM file at the requested path.

## Compatibility policy

Core versions 1 and 2 are not accepted by the self-hosted backend. Surface Weave
and `weavec build` are pre-1.0, and each superseded path was an
internal discrepancy rather than a separately released stable WIR contract.

The frozen lower compiler stages maintain the core version 2 contract, which is
what the seed build consumes. The self-hosted compiler maintains core version 3.
Changing admitted WIR forms or semantics requires an explicit coordinated
version transition. New surface features should lower through existing forms
whenever possible.

Two capabilities are collected for the next coordinated transition rather than
lowered through existing forms, because each needs the parser, validator,
frontend, backend, fixtures, bootstrap, and self-host to change together:
[first-class source locations](wir-next-source-locations.md) and
[layout-free struct fields](wir-next-struct-fields.md). Neither justifies a
version change alone.

## Diagnostic and LLVM source maps

`weavec build --diagnostics-json` enables a private, comment-only source map in
its temporary WIR. The private comment forms are:

```text
; weavec-source-file-v1 <source-index> "<path>"
; weavec-source-span-v1 <source-index> <start-byte> <end-byte>
```

A zero-based source index follows the original build input order, preserving
exact file identity even when two inputs are byte-identical. The metadata is
deterministic, has no semantic meaning, and is ignored by the existing
lexer as an ordinary comment. It is not emitted by normal
`weavec --frontend`, build, fixture, or self-host flows. Backend diagnostics use
the spans to recover exact original surface locations.

`weavec build --llvm-provenance` additionally consumes both comment forms to
annotate LLVM function and statement groups with surface and WIR ranges. Direct
and older WIR remain accepted and use the documented inference fallback; the
comments never change WIR semantics.

The proposed first-class replacement belongs to a future coordinated WIR
revision and is documented separately in
[Next-version WIR source locations](wir-next-source-locations.md).

## Repository enforcement

The repository audit:

```sh
python3 scripts/check_wir_core_version.py
```

checks production emitters, self-host runtime modules, direct WIR fixtures,
surface and quantum WIR goldens, LLVM golden version headers, current
documentation, malformed-envelope fixtures, and failed-output cleanup. It
permits only the intentionally invalid fixtures used to prove rejection
behavior.

The audit runs at the start of:

```sh
./test-all.sh
```

The correctness suite verifies rejection of core version 1, missing or duplicate
version declarations, missing or non-integer version values, and invalid roots.
Each negative backend case must return failure without leaving an output file.

## Related documents

- [Architecture](architecture.md)
- [Command reference](command-reference.md)
- [Language reference](language-reference.md)
- [Next-version WIR source locations](wir-next-source-locations.md)
- [Next-version WIR struct fields](wir-next-struct-fields.md)
- [Source and fixture style](source-style.md)
- [Performance demonstrations](performance-demonstrations.md)
