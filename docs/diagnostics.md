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

The current additive schema is `weavec-diagnostics-v1`. Its JSON Schema is
[`schemas/weavec-diagnostics-v1.schema.json`](schemas/weavec-diagnostics-v1.schema.json)
with identifier `urn:weavec:schema:diagnostics:v1`.

```json
{
  "format": "weavec-diagnostics-v1",
  "status": "failed",
  "phase": "frontend",
  "exit_code": 10,
  "raw_exit_code": 1,
  "diagnostics": [
    {
      "code": "frontend.call.argument-type-mismatch",
      "severity": "error",
      "phase": "frontend",
      "message": "weavec: surface call: argument type mismatch for consume: expected i32, got i64",
      "source": "main.weave",
      "span_origin": "compiler-semantic",
      "span": {
        "start_byte": 201,
        "end_byte": 205,
        "start_line": 12,
        "start_column": 29,
        "end_line": 12,
        "end_column": 33
      },
      "analysis_complete": true,
      "expected_type": "i32",
      "actual_type": "i64",
      "argument_index": 0,
      "operand_role": "argument",
      "symbol": "consume",
      "candidates": [],
      "related_locations": [],
      "repairs": [
        {
          "kind": "replace",
          "replacement": "(cast i32 wide)",
          "replacement_span": {
            "start_byte": 201,
            "end_byte": 205,
            "start_line": 12,
            "start_column": 29,
            "end_line": 12,
            "end_column": 33
          },
          "confidence": "guaranteed-local"
        }
      ]
    }
  ]
}
```

Offsets are UTF-8 byte offsets with an exclusive end. Lines and columns are
one-based. Columns count Unicode code points rather than UTF-8 continuation
bytes.

## Serialization and publication

The compiler models diagnostics as a typed v1 document and serializes it through
the shared checked JSON writer. Diagnostic classification, source-span discovery,
and semantic repair selection remain separate from JSON syntax and filesystem
publication.

A requested diagnostics document is published transactionally through a sibling
temporary file. Serialization, flush, `fsync`, close, and final rename are all
checked. A failed publication removes the temporary file and leaves any previous
diagnostics document unchanged.

If compilation succeeds but the requested diagnostics document cannot be
published, the executable remains available and `weavec build` returns stable
publication code `14`. If compilation has already failed, its original stable
phase code remains authoritative while the diagnostics publication error is
reported on stderr.

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
| `analysis_complete` | Whether the compiler had authoritative structured facts for this failure. |
| `expected_type`, `actual_type` | Semantic type names when the failure is type-related. |
| `argument_index` | Zero-based argument position for a call mismatch. |
| `expected_count`, `actual_count` | Expected and observed child or argument counts. |
| `operand_role` | Named role such as `left`, `right`, `argument`, or `value`. |
| `symbol` | Relevant function, operator, type, or identifier text. |
| `candidates` | Deterministically ordered candidate names; empty when none are authoritative. |
| `related_locations` | Deterministically ordered definition or context locations. |
| `repairs` | Zero or more explicitly trusted bounded source repairs. |

The semantic fields are optional because code generation, linking, publication,
setup failures, direct WIR errors, and older compatibility paths may not retain
an authoritative source-language environment. The three list fields are always
present on a diagnostic so agents do not need to distinguish omitted data from an
empty result.

## Repair trust

Each repair declares its trust independently:

- `guaranteed-local` means the compiler proved that the replacement satisfies the
  immediate semantic requirement and changes only the indicated source subtree;
- `candidate` means the replacement is plausible but must be recompiled and may
  require another edit;
- `none` is represented by an empty `repairs` array rather than a speculative
  replacement.

The initial guaranteed repairs are explicit casts for admitted conversion pairs
when a call argument or canonical operator operand has a known mismatched type.
For example, an `i64` expression where `i32` is required may receive
`(cast i32 EXPR)`. The compiler does not suggest a cast pair that the canonical
surface language rejects.

Applying a repair never implies that the complete program is valid. Agents must
recompile after each repair. Multiple future repairs will be emitted in a stable
order rather than silently selecting one candidate.

## Semantic authority and private transport

Canonical `call`, `op`, and `cast` emitters remain the authority that decides
whether source is valid and produces human stderr. A self-hosted observer records
the first failing AST node, exact source range, resolved types, argument or
operand role, counts, and symbol while those facts are live.

A private versioned sidecar transports that fixed record from the frontend phase
to the diagnostics serializer. The host does not parse Weave, infer types, choose
operators, or invent repairs. The sidecar path is scoped to one diagnostics build,
is never part of the public command line or JSON document, and is removed after
publication.

## Current semantic coverage

The current compiler produces complete machine-actionable entries for:

- unresolved canonical call targets;
- canonical call arity mismatches;
- canonical call argument type mismatches;
- canonical operator arity and operand type mismatches;
- unsupported canonical operators for resolved operand types;
- invalid canonical casts and unknown cast types;
- a declaration whose name collides with reserved syntax:
  `frontend.declaration.reserved-syntax-name`.

This coverage is additive to the existing parse and backend diagnostics. Future
language features should publish their semantic failures through the same typed
boundary instead of adding stderr parsers in external tooling.

## Span provenance

`span_origin` is part of the protocol:

- `compiler-semantic` — an exact surface AST range selected while the
  self-hosted type and symbol environment was authoritative;
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
metadata. The comments are ignored by ordinary WIR consumers and do not alter
the WIR core version 3 semantic contract. The unique-token inference remains a
compatibility fallback for direct or older WIR without source-map comments.

## Current exact coverage

The current version provides exact preflight spans for:

- unmatched closing parentheses;
- unclosed lists;
- unterminated string literals;
- sources holding no S-expression at all, reported as
  `frontend.parse.unexpected-end-of-input` with a zero-width span at end of
  input;
- unreadable source files as source-level diagnostics without spans.

It also provides exact propagated spans for backend unknown-expression,
unknown-identifier, unresolved-call-target, wrong-arity, and expected-expression
errors when the failing WIR token originated from a copied surface node. Direct or
unannotated WIR retain conservative unique-token inference as a fallback.

## Command-line and file-I/O diagnostics

Every `weavec` command-line and file-I/O failure reports a stable code and a
message on stderr. The low-level modes have no `--diagnostics-json`, so the code
travels in the human line, using the shape the project and build drivers already
emit:

```text
weavec: error: MESSAGE [CODE]
weavec: error: PATH: MESSAGE [CODE]
weavec: error: PATH:LINE:COLUMN: MESSAGE [CODE]
```

Lines are one-based and columns count Unicode code points, matching the byte and
position rules used by `weavec-diagnostics-v1` spans.

| Code | Meaning |
|---|---|
| `driver.usage.missing-command` | `weavec` was invoked with no command. |
| `driver.usage.unknown-command` | The first argument is not a known command or mode. |
| `driver.usage.invalid-arguments` | A known mode received the wrong argument list or an option value it does not accept. |
| `driver.out-of-memory` | A host allocation failed. |
| `driver.output-unwritable` | A requested output file could not be created or written. |
| `frontend.source-unreadable` | A surface source input could not be opened or completely read. |
| `frontend.parse.unclosed-list` | A surface source ended inside an open list. |
| `frontend.parse.unmatched-closing-paren` | A surface source has a closing parenthesis with no open list. |
| `frontend.parse.unexpected-end-of-input` | A surface source ended where an expression was required. |
| `backend.input-unreadable` | A direct WIR input could not be opened or completely read. |
| `backend.invalid-module` | A WIR module has no `(decls ...)` section. |
| `backend.parse.unclosed-list` | A WIR input ended inside an open list. |
| `backend.parse.unmatched-closing-paren` | A WIR input has a closing parenthesis with no open list. |
| `backend.parse.unexpected-end-of-input` | A WIR input ended where an expression was required. |

A malformed command line also prints the accepted invocation forms. Exit status
is unchanged: the low-level modes still return `1`, and only `weavec build`
with `--diagnostics-json` returns the stable phase codes above.

The parser reports positions from a caller-owned parse-error record holding the
byte offset where it stopped and the token it required. An unclosed list is
reported at its own opening parenthesis, which is the same position the build
driver's preflight scanner selects for that source. See
[Command reference](command-reference.md) for the modes themselves.

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
- preserve `span_origin` whenever diagnostics are transformed or forwarded;
- check `analysis_complete` before assuming semantic context is exhaustive;
- apply only repairs whose declared trust satisfies their workflow;
- recompile after every applied repair.
