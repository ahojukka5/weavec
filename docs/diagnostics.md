# Machine-readable build diagnostics

`weavec build` can write a versioned diagnostics document without changing the
human-readable stderr stream:

```sh
weavec build main.weave -o main \
  --manifest-json main.build.json \
  --diagnostics-json main.diagnostics.json \
  --trace-json main.trace.json
```

The executable and requested JSON paths must all be different. The manifest and
trace protocols are documented separately in [Build manifests](build-manifest.md)
and [Source-linked compilation trace](compilation-trace.md).

## Schema

The current schema is `weavec-diagnostics-v1`:

```json
{
  "format": "weavec-diagnostics-v1",
  "status": "failed",
  "phase": "frontend",
  "exit_code": 10,
  "raw_exit_code": 1,
  "diagnostics": [
    {
      "code": "frontend.parse.unclosed-list",
      "severity": "error",
      "phase": "frontend",
      "message": "unclosed list",
      "source": "main.weave",
      "span_origin": "compiler-preflight",
      "span": {
        "start_byte": 0,
        "end_byte": 1,
        "start_line": 1,
        "start_column": 1,
        "end_line": 1,
        "end_column": 2
      }
    }
  ]
}
```

Offsets are UTF-8 byte offsets with an exclusive end. Lines and columns are
one-based. Columns count Unicode code points rather than UTF-8 continuation
bytes.

A successful build writes:

```json
{
  "format": "weavec-diagnostics-v1",
  "status": "succeeded",
  "phase": "complete",
  "exit_code": 0,
  "raw_exit_code": 0,
  "diagnostics": []
}
```

## Stable exit codes

When `--diagnostics-json` is requested, `weavec build` returns a stable public
phase code:

| Code | Meaning |
|---:|---|
| `0` | Build succeeded. |
| `2` | Invalid command-line request. |
| `10` | Surface frontend or source parse failed. |
| `11` | WIR backend failed. |
| `12` | LLVM optimization or target code generation failed. |
| `13` | Target linker failed. |
| `14` | Atomic output publication failed. |
| `15` | Build driver or toolchain setup failed. |

`raw_exit_code` preserves the underlying subprocess or legacy driver status.
The stable code is the automation contract; the raw status is diagnostic
context.

## Diagnostic fields

| Field | Meaning |
|---|---|
| `code` | Stable machine-readable classification when one is available. |
| `severity` | Currently `error` for failed builds. |
| `phase` | Compiler or driver phase that produced the diagnostic. |
| `message` | Human-readable message extracted from the existing stderr stream. |
| `source` | Canonical input path associated with the diagnostic, when known. |
| `span_origin` | Provenance and trust level of the source span. |
| `span` | Source range or `null` when no trustworthy range is available. |

The outer document may contain diagnostics without a source span for code
generation, linking, publication, setup failures, or unclassified compiler
errors.

## Span provenance

`span_origin` is part of the protocol:

- `compiler-preflight` — exact source span produced by the compiler's canonical
  S-expression preflight scanner;
- `propagated-wir-location` — an exact surface file identity and byte span
  carried through comment-only WIR source-map metadata during a diagnostics
  build;
- `inferred-unique-token` — a human diagnostic named one token and that token
  occurred exactly once in all source inputs outside comments and strings;
- `none` — no trustworthy canonical-source span is available.

The compiler never invents a span when a token is ambiguous. Consumers may map
an exact or uniquely inferred span into their own source maps, but should retain
`span_origin` in the resulting diagnostic.

Diagnostics builds propagate exact source locations through comment-only WIR
metadata. The comments are ignored by ordinary WIR consumers and do not alter the
WIR v2 semantic contract. The unique-token inference remains a compatibility
fallback for direct or older WIR without source-map comments.

## Current exact coverage

The current version provides exact preflight spans for:

- unmatched closing parentheses;
- unclosed lists;
- unterminated string literals;
- unreadable source files as source-level diagnostics without spans.

It also provides exact propagated spans for backend unknown-expression,
unknown-identifier, unresolved-call-target, wrong-arity, and expected-expression
errors when the failing WIR token originated from a copied surface node. Direct or
unannotated WIR retains conservative unique-token inference as a fallback.

## Human diagnostics

stderr remains authoritative for interactive use and is replayed unchanged after
capture. The JSON document is an automation side channel; enabling it does not
silence or replace existing messages.

## Compatibility rules

Consumers should:

- require the exact `format` value they support;
- accept additional diagnostic entries and future optional fields;
- use `exit_code` for automation and retain `raw_exit_code` for investigation;
- treat `span` as optional even for classified errors;
- preserve `span_origin` whenever diagnostics are transformed or forwarded.
