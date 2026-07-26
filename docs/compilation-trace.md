# Source-linked compilation trace

`weavec build` can emit a deterministic, machine-readable account of selected
surface-language transformations performed by the real compiler pipeline:

```sh
weavec build library.weave main.weave -o application \
  --trace-json application.trace.json
```

The output format is `weavec-compilation-trace-v1`. It is intended for IDEs,
compiler visualizers, regression analysis, agent tooling, and users who need to
understand why emitted code differs from the surface source.

The trace is observational. Requesting it does not change normal WIR or LLVM
semantics, and ordinary builds do not emit private trace metadata.

## Document shape

```json
{
  "format": "weavec-compilation-trace-v1",
  "status": "succeeded",
  "phase": "complete",
  "sources": ["library.weave", "main.weave"],
  "events": [
    {
      "kind": "rewrite",
      "pass": "frontend.quantum-nativize",
      "action": "decompose-h-to-rz-ry",
      "source_index": 1,
      "source": "main.weave",
      "span": {
        "start_byte": 418,
        "end_byte": 431
      },
      "surface": "(qgate H q0)",
      "detail": "H"
    }
  ]
}
```

Top-level fields are:

- `format` — always `weavec-compilation-trace-v1`;
- `status` — `succeeded` or `failed`;
- `phase` — `complete`, `frontend`, `backend`, `codegen`, `link`, `trace`, or
  `publish`;
- `sources` — ordered source paths exactly as supplied to `weavec build`;
- `events` — source-linked transformations in deterministic execution order.

A failed frontend parse still produces a valid document when the requested path
is writable. Its status is `failed`, its phase is `frontend`, and its event list
contains only transformations completed before the failure. The canonical
preflight scanner normally fails before lowering, so syntax failures usually
have an empty event list.

## Event fields

Each event contains:

- `kind` — broad category such as `lowering`, `rewrite`, `optimization`, or
  `contract-check`;
- `pass` — stable compiler subsystem identifier;
- `action` — stable transformation identifier;
- `source_index` — zero-based index into the top-level `sources` array;
- `source` — the corresponding source path for convenient streaming consumers;
- `span` — half-open UTF-8 byte range in the original source;
- `surface` — exact UTF-8 source bytes covered by the span;
- `detail` — an optional relevant source token or subexpression.

`surface` is deliberately redundant with the byte span. Consumers can display an
event without reopening the source, while still verifying that their local file
matches the compiler input.

## Current actions

The first format version records these actual frontend transformations:

| Action | Meaning |
|---|---|
| `lower-qubit-to-i64` | Lower the surface `Qubit` type to its current WIR representation. |
| `wrap-typed-integer` | Wrap integer sugar in the typed WIR constant form. |
| `lower-gate-to-runtime-call` | Lower a supported quantum gate to a runtime call. |
| `decompose-h-to-rz-ry` | Rewrite Hadamard into the native RZ/RY decomposition. |
| `cancel-self-inverse-pair` | Remove two adjacent identical self-inverse gates. |
| `lower-measurement-to-runtime-call` | Lower surface measurement to `qrt_measure`. |
| `insert-requires-check` | Insert the executable entry check for a requirement. |
| `insert-ensures-check` | Insert the executable return check for a guarantee. |

The event set is intentionally extensible within the versioned outer document.
New actions may be added when they describe real compiler behavior without
changing existing field meanings. Consumers should ignore unknown actions.
Incompatible document changes require a new format identifier.

## Action registry

Stable action metadata is centralized in `src/core/trace_registry.weave`. Each
entry has one semantic wrapper that owns its `kind`, `pass`, and `action` values.
Frontend lowering, rewriting, optimization, and contract code calls those
wrappers instead of passing free-form string triples to the generic trace
runtime.

`scripts/check-trace-registry.sh` is a permanent drift gate. It requires every
registered action to have:

- one unique declaration and wrapper implementation;
- metadata matching the wrapper body;
- at least one real frontend call site;
- no direct generic trace-helper bypass in frontend code;
- an entry in this reference table;
- an entry in `test/trace/expected-actions.txt` used by the end-to-end regression;
- the registry module in every deterministic compiler source list.

Adding a stable action therefore changes the registry, compiler call site,
documentation, and regression expectation as one logical unit. Renaming or
removing an action is an automation-contract change and needs explicit review of
Loupe and other consumers.

## Determinism and source identity

For identical ordered inputs and compiler version, the trace is byte-for-byte
deterministic. Source identity uses the original build-input index rather than a
content hash, so two byte-identical files remain distinguishable.

Byte offsets refer to UTF-8 input bytes, not Unicode scalar values or display
columns. S-expression events cover the complete source form, including nested
forms and any whitespace or comments between two forms removed as one
optimization.

## Failure atomicity

The trace is written before the native executable is published. If the requested
trace cannot be completed, the build fails and does not replace an existing
executable at the output path.

The executable, manifest, diagnostics, and trace paths must be distinct whenever
the corresponding outputs are requested.

## Relationship to diagnostics and explain mode

The trace and diagnostics protocols serve different purposes:

- [`weavec-diagnostics-v1`](diagnostics.md) reports errors and trustworthy source
  spans;
- `weavec-compilation-trace-v1` reports successful transformations and their
  original source constructs;
- [explain and audit modes](contracts-and-explain.md) summarize program structure
  and effect contracts without performing a native build.

A build may request manifest, diagnostics, and trace documents together. All
three describe the same ordered source inputs but remain independently versioned.
