# Machine-readable build diagnostics

`weavec build` can write a versioned diagnostics document without changing the
human-readable stderr stream:

```sh
weavec build main.weave -o main \
  --manifest-json main.build.json \
  --diagnostics-json main.diagnostics.json
```

The manifest and diagnostics paths must be different.

## Schema

The initial schema is `weavec-diagnostics-v1`:

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
| `0` | build succeeded |
| `2` | invalid command-line request |
| `10` | surface frontend or source parse failed |
| `11` | WIR backend failed |
| `12` | LLVM IR to object generation failed |
| `13` | target linker failed |
| `14` | atomic output publication failed |
| `15` | build driver or toolchain setup failed |

`raw_exit_code` preserves the underlying subprocess or legacy driver status.

## Span provenance

`span_origin` is part of the contract:

- `compiler-preflight` — exact source span produced by the compiler's canonical
  S-expression preflight scanner;
- `inferred-unique-token` — a human diagnostic named one token and that token
  occurred exactly once in all source inputs outside comments and strings;
- `none` — no trustworthy canonical-source span is available.

The compiler never invents a span when a token is ambiguous. Consumers may map
an exact or uniquely inferred span into their own source maps, but should retain
`span_origin` in the resulting diagnostic.

## Current coverage

The first version provides exact spans for:

- unmatched closing parentheses;
- unclosed lists;
- unterminated string literals;
- unreadable source files as source-level diagnostics without spans.

It also classifies common backend messages such as unknown expression operators,
unknown identifiers, and wrong arity. A canonical-source span is attached only
when the named token is unique.

Code generation, linking, publishing, and unclassified compiler errors remain
structured phase diagnostics without a source span. Future compiler work can
replace inferred token spans with locations propagated explicitly through WIR;
the `weavec-diagnostics-v1` outer document does not need to change for that
extension.

## Human diagnostics

stderr remains authoritative for interactive use and is replayed unchanged after
capture. The JSON document is an automation side channel; enabling it does not
silence or replace the existing messages.
