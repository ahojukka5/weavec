# Semantic index protocol

Status: schema-first design for issue #37

`weavec-semantic-index-v1` is the planned compiler-authoritative description of
Weave definitions, references, module interfaces, and call relationships. It is
designed for Jacquard and other structural tools that need bounded semantic
context without reimplementing compiler name resolution.

This document defines the first versioned data contract. It does not claim that a
public `weavec analyze` command is implemented yet.

## Design goals

The protocol must let a consumer answer, without parsing implementation text:

- where a symbol is defined and referenced;
- which module owns, imports, or exports a symbol;
- which call sites resolve to which callable;
- whether an analysis is complete;
- whether a module's public interface changed;
- which exact compiler, language, sources, and options produced the result.

`weavec` remains the only semantic authority. Consumers may map byte spans back
to their own node identities, but they must not infer missing module, type,
visibility, or call semantics.

## Top-level document

A document contains these required collections:

```json
{
  "format": "weavec-semantic-index-v1",
  "schema_id": "urn:weavec:schema:semantic-index:v1",
  "schema_version": 1,
  "compiler": {},
  "language": {},
  "analysis": {},
  "sources": [],
  "modules": [],
  "symbols": [],
  "references": [],
  "imports": [],
  "exports": [],
  "call_edges": [],
  "diagnostics": {}
}
```

The normative JSON Schema is
[`schemas/weavec-semantic-index-v1.schema.json`](schemas/weavec-semantic-index-v1.schema.json).
A representative complete document is stored under
[`schemas/examples/weavec-semantic-index-v1.example.json`](schemas/examples/weavec-semantic-index-v1.example.json).

## Source identity and spans

Sources retain command-line order. Their identifiers are exactly `source:N`,
where `N` is the zero-based supplied-source index. The published `path` is the
spelling supplied to the compiler; the protocol must not replace it with an
absolute host path.

All spans are half-open UTF-8 byte ranges:

```text
[start, end)
```

`start` and `end` are offsets into the exact source bytes identified by
`source_id`. A valid span satisfies:

```text
0 <= start <= end <= source.byte_length
```

Line and column numbers are intentionally not part of v1. A consumer can derive
them from the exact indexed bytes without introducing encoding ambiguity.

## Analysis completeness

`analysis.status` is one of:

- `complete`: all required semantic passes completed and all collections are
  authoritative;
- `incomplete`: parsing or semantic recovery produced useful partial facts, but
  consumers must not treat absence as proof;
- `failed`: no reliable semantic graph was produced.

`analysis.complete` must be true only for `complete`. The separate
`diagnostics.complete` field states whether the diagnostic list itself is
complete. A document may therefore carry useful diagnostics even when semantic
analysis failed.

Consumers must reject dependency-impact or safe-refactoring conclusions unless
`analysis.complete` is true.

## Deterministic identifiers

Identifiers are stable only within one exact analyzed source set, compiler
identity, and option set. They are not long-lived database keys.

The compiler assigns ordinals in these orders:

1. sources by supplied source index;
2. modules by source index, definition start, then UTF-8 module name;
3. symbols by module ordinal, definition start, kind, then UTF-8 name;
4. references by source index, start, end, role, then resolved symbol ID;
5. imports and exports by owning module ordinal and source span;
6. call edges by caller ID, call-reference ID, then callee ID.

IDs use the prefixes `source:`, `module:`, `symbol:`, `reference:`, `import:`,
`export:`, and `call-edge:` followed by the corresponding decimal ordinal.

Reordering input files intentionally changes source-dependent IDs. Repeating the
same command with identical source bytes and options must reproduce the complete
JSON byte-for-byte.

## Source-set and option hashes

`analysis.source_set_sha256` identifies the exact ordered input set. Its byte
stream is:

```text
UTF8("weavec-source-set-v1\0")
for each source in supplied order:
  UTF8(decimal(path_byte_length)) || ":" || UTF8(path) || "\0"
  UTF8(decimal(source_byte_length)) || ":" || source_bytes || "\0"
```

`analysis.options_sha256` hashes compact UTF-8 JSON containing the semantic
options that can change analysis results. Object keys use the documented
protocol order and arrays retain command-line order. Output paths and other
non-semantic publication details are excluded.

## Symbols and signatures

Every symbol records its owning module, source definition span, kind, name,
visibility, and a canonical signature string. The signature is compiler-produced
surface information, not WIR spelling. Private WIR name mangling therefore never
changes semantic symbol identity or interface hashes.

Initial symbol kinds are:

- `fn`, `entry`, `extern`, and `const`;
- `struct` and `field`;
- `module` may be represented only in the module collection, not duplicated as a
  symbol.

The schema permits later kinds through a versioned protocol extension, not by a
consumer guessing from syntax.

## Imports, exports, and references

Imports and exports are first-class records even when unresolved. Their `status`
explains whether resolution succeeded or failed. Nullable target IDs are allowed
only so incomplete and failed analyses can retain exact source facts.

References carry a semantic role such as `call`, `read`, `write`, `type`,
`import`, or `export`. A resolved reference links to one semantic symbol ID.
Unresolved references keep a null `symbol_id` and are accompanied by diagnostics
or an incomplete analysis state.

Call edges point to the call reference that created the edge. This preserves the
exact source site and permits multiple edges between the same caller and callee.

## Public interface hashes

Each module publishes one `interface` object. The hash algorithm identifier is:

```text
sha256-weave-interface-v1
```

The hashed compact UTF-8 JSON has this exact shape and key order:

```json
{"module":"MODULE","exports":[{"kind":"KIND","name":"NAME","signature":"SIGNATURE"}]}
```

Export entries are sorted by UTF-8 `name`, then `kind`, then `signature` byte
order. The hash excludes:

- source paths and spans;
- private symbols and private references;
- exported implementation bodies;
- compiler build identity;
- diagnostics and analysis status.

A private implementation-only change can therefore preserve the interface hash.
Changing an exported name, kind, canonical signature, or module name changes it.
Re-export semantics are not part of the current module surface and therefore are
not encoded in v1.

## Diagnostics

The document carries a minimal diagnostic projection so completeness is
self-contained. Diagnostic items include code, severity, message, and an optional
source span. A future implementation should reuse the same codes and span
conventions as `weavec-diagnostics-v1`; it should not invent semantic-index-only
meanings for an existing compiler error.

## Evolution rules

- New optional properties may be added while `schema_version` remains 1.
- Existing required properties, ID meanings, ordering, span units, or hash inputs
  require a new schema version.
- Consumers must ignore unknown optional properties but reject an unknown
  `format` or `schema_version`.
- Producers must never publish `analysis.complete: true` when any authoritative
  collection is knowingly partial.

## Planned command boundary

The intended command shape remains:

```text
weavec analyze source0.weave source1.weave \
  --semantic-index-json index.json
```

The exact CLI spelling is not normative until implemented and reported by
`weavec capabilities --json`. The schema, ordering rules, and hash algorithms in
this document are the contract for that implementation slice.
