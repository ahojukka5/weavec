# Semantic index protocol

Status: initial compiler emitter implemented for issue #37

`weavec-semantic-index-v1` is the compiler-authoritative description of Weave
sources, modules, declarations, interfaces, and semantic relationships. It is
intended for Jacquard and other structural tools that need bounded semantic
context without duplicating compiler name resolution.

The schema is published at
`docs/schemas/weavec-semantic-index-v1.schema.json`.

## Command

```text
weavec analyze source0.weave source1.weave ... \
  --semantic-index-json index.json
```

The output path must differ from every source path. The compiler writes a
temporary sibling and atomically renames it into place, so a consumer never
observes a partially written document. Frontend diagnostics remain on standard
error; standard output is not used for the protocol.

## Initial implementation

The first emitter publishes authoritative facts for:

- supplied source documents and their SHA-256 hashes;
- explicit modules and deterministic synthetic legacy modules;
- function, entry, external, constant, struct, and field declarations;
- definition spans and canonical signatures;
- explicit imports and exports;
- import, export, and call references;
- compiler-resolved caller/callee edges for canonical and typed calls;
- stable module interface descriptions and SHA-256 hashes;
- explicit successful-incomplete and failed-analysis states.

The compiler validates the source set through the existing self-hosted frontend
passes. The semantic-index driver does not implement a second parser, resolver,
or type system.

Body-level read, write, and type references are not emitted yet. Call targets
are resolved through the same compiler symbol registry used by lowering; the
emitter does not guess targets from source spelling alone. A successful document
therefore reports:

```json
{
  "analysis": {
    "status": "incomplete",
    "complete": false,
    "diagnostics_complete": true,
    "incomplete_reason":
      "read/write/type references are not emitted yet"
  }
}
```

The collections that are present remain authoritative. Consumers must not treat
an empty read, write, or type-reference subset as proof that no such uses exist.

A semantic validation failure returns a nonzero exit status and publishes a
`failed` document with empty semantic graph collections and an explicit
diagnostic item.

## Identity and ordering

Sources retain supplied command-line order:

```text
source:0
source:1
...
```

Modules use source order. Symbols use module order, then definition byte offset,
kind, and source name. Imports and exports use owning module order and source
offset. References use source order, byte offset, role, and target symbol.
Call edges are ordered by caller symbol, call-reference ID, and callee symbol.

IDs are stable only for an identical source set, compiler identity, target, and
analysis options. Tools must not persist them as global identities across
unrelated analyses.

All spans are zero-based half-open UTF-8 byte ranges:

```text
[start, end)
```

They refer to the exact bytes identified by the matching source record.

## Modules and legacy sources

An explicit `(module NAME ...)` root uses its declared module name. A legacy
`(program ...)` root receives a deterministic synthetic module name:

```text
legacy:0
legacy:1
...
```

Synthetic names depend only on supplied source order, not absolute paths or host
state.

Exports define public module interfaces. Private declarations are indexed but
do not participate in interface hashes unless a future public signature refers
to them through an explicitly specified canonical representation.

## Canonical signatures

A callable signature includes declaration kind, ordered parameter names and
types, and return type. Representative forms are:

```text
(fn (params (left i32) (right i32)) (returns i32))
(entry (params) (returns i32))
(extern (params (value i64)) (returns void))
```

Constants, structs, and fields use analogous compiler-owned canonical forms.
Signature text is protocol data rather than source formatting.

## Interface hashing

Each module reports:

```json
{
  "hash_algorithm": "sha256-weave-interface-v1",
  "sha256": "...",
  "exports": ["symbol:0"]
}
```

The hash input is compact UTF-8 JSON with keys in this exact order:

```json
{"module":"NAME","exports":[
  {"kind":"KIND","name":"NAME","signature":"CANONICAL"}
]}
```

Export tuples are ordered by UTF-8 bytewise name, then kind, then canonical
signature. The SHA-256 digest covers the exact compact byte sequence with no
trailing newline.

Changing only a private implementation preserves the interface hash. Changing an
exported name, kind, signature, or module identity changes it.

## Completeness and diagnostics

`analysis.status` is one of:

- `complete`: every collection required by the schema is authoritative;
- `incomplete`: emitted collections are authoritative, but at least one required
  semantic category is unavailable;
- `failed`: semantic analysis did not produce a trustworthy graph.

`analysis.complete` is true only for `complete`. Consumers must inspect status
before answering absence questions.

The embedded diagnostics envelope uses `weavec-diagnostics-v1`. Diagnostic
completeness is independent of graph completeness: the initial emitter can
report complete diagnostics while the reference graph remains incomplete.

## Consumer rules

A consumer must:

1. reject unknown major schema versions;
2. verify compiler, language, source-set, and option identity;
3. preserve supplied source ordering;
4. interpret spans as UTF-8 byte ranges;
5. inspect completeness before answering negative queries;
6. use interface hashes only with the documented algorithm identifier;
7. never infer visibility, imports, or semantic identity from filenames.

Jacquard should map compiler spans to stable structural node IDs. It must not
reconstruct Weave name resolution from source examples.

## Implementation path

The next bounded slice adds body-level read, write, and type references, allowing
successful analysis to become complete. Later work may extend diagnostic spans
and symbol kinds while remaining backward-compatible through additive fields
or a new major schema version.

The compiler remains the sole semantic authority throughout that work.
