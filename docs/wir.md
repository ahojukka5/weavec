# WIR core version 2

`weavec` uses WIR core version 2 as its single intermediate representation
between surface lowering and LLVM emission.

The required module envelope is:

```text
(core-module
  (core-version 2)
  (decls
    declaration...))
```

The version value is the integer token `2`. A missing value, a string such as
`"2"`, or additional values do not satisfy the envelope.

## Product pipeline

```text
surface Weave
    │ weavec --frontend
    ▼
WIR core version 2
    │ weavec --backend
    ▼
LLVM IR
```

The initial seed compiler uses the same versioned boundary:

```text
surface compiler sources
    │ weavec-bootstrap v0.3.0
    ▼
WIR core version 2
    │ weavec1 v0.3.1
    ▼
LLVM IR for the seed weavec compiler
```

The seed and self-hosted paths therefore agree on the WIR version. The lower
repositories remain frozen; the final compiler does not maintain a private WIR
dialect.

## Envelope validation

`weavec --backend` validates the complete module envelope before opening its LLVM
output file. A valid input must:

1. have `core-module` as the root form;
2. contain exactly one `core-version` declaration;
3. declare the integer version token `2` as its only value;
4. contain a `decls` form;
5. satisfy the existing declaration and call-target checks.

The backend rejects:

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

Core version 1 is not accepted by the migrated self-hosted backend. Surface Weave
and `weavec build` are pre-1.0, and the previous core-version-1 path was an
internal discrepancy rather than a separately released stable WIR contract.

The stable WIR v2 contract is maintained by the frozen lower compiler stages.
Changing admitted WIR forms or semantics requires an explicit coordinated
version transition. New surface features should lower through existing WIR v2
forms whenever possible.

## Diagnostic source maps

`weavec build --diagnostics-json` enables a private, comment-only source map in
its temporary WIR. A mapping line has the form:

```text
; weavec-source-span-v1 <source-fingerprint> <start-byte> <end-byte>
```

The metadata is deterministic, has no semantic meaning in WIR v2, and is ignored
by the existing lexer as an ordinary comment. It is not emitted by normal
`weavec --frontend`, build, fixture, or self-host flows. Backend diagnostics use
it only to recover an exact original surface span; direct and older WIR remain
accepted and use the documented inference fallback.

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
- [Source and fixture style](source-style.md)
- [Performance demonstrations](performance-demonstrations.md)
