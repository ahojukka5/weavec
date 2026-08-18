# Semantic index protocol

Status: source-sensitive complete compiler emitter for issue #37

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

## Emitted semantic graph

A successful analysis publishes authoritative facts for:

- supplied source documents and their SHA-256 hashes;
- explicit modules and deterministic synthetic legacy modules;
- function, entry, external, constant, struct, and field declarations;
- definition spans and canonical signatures;
- explicit imports and exports;
- call references and compiler-resolved caller/callee edges;
- body-level reads and writes for canonical and admitted compatibility forms;
- explicit type references in declarations, bindings, casts, and constructors;
- semantic struct constructor, field-read, and field-write references;
- stable module interface descriptions and SHA-256 hashes;
- complete successful and explicit failed-analysis states.

The compiler validates the source set through the existing self-hosted frontend
passes. The semantic-index driver walks the same parser trees after validation;
it does not implement a second parser, type checker, or acceptance path.

For source sets composed of fully modeled canonical forms and admitted typed
expression compatibility forms, a successful document reports:

```json
{
  "analysis": {
    "status": "complete",
    "complete": true,
    "diagnostics_complete": true
  }
}
```

A semantic validation failure returns a nonzero exit status and publishes a
`failed` document with empty semantic graph collections and an explicit
diagnostic item.

## Reference roles and targets

`references` contains the following roles:

- `call`: a canonical or typed call target;
- `read`: a parameter, local, constant, or struct-field value read;
- `write`: an assignment target, constructor field, or struct-field update;
- `type`: an explicit type occurrence;
- `import`: an imported declaration name;
- `export`: an exported declaration name.

Module-level declarations use stable `symbol:N` identifiers. Named struct type
references and semantic field operations link to their `struct` or `field`
symbol. Primitive types are compiler-resolved built-ins and therefore have
`symbol_id: null` with `status: "resolved"`.

Parameters and locals are validated lexical bindings rather than module
symbols in schema version 1. Their read and write entries likewise use
`symbol_id: null` with `status: "resolved"`. The exact span identifies the
binding use, and the containing callable definition supplies its scope.
Consumers must distinguish this case from an unresolved reference by checking
`status`; a null symbol ID alone does not mean failure.

The body collector covers the canonical surface forms advertised by
`weavec capabilities --json`, including bare identifier reads, `let`, `set`,
`cast`, `new`, `field-get`, `field-set`, quantum operands, typed expression
forms, and the admitted `param_get`, `local_get`, `global_get`, `local_set`,
and `global_set` compatibility spellings. Call targets remain resolved through
the compiler's module-aware symbol registry.

The compatibility registry also admits a deliberately broad low-level WIR
family. When a valid source uses an unmodeled low-level form whose identifier
operands are not necessarily value references, analysis remains `incomplete`
rather than guessing roles or emitting false relationships. Nested modeled
expressions are still collected.

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
(fn (type-params T) (params (value T)) (returns T))
(entry (params) (returns i32))
(extern (params (value i64)) (returns void))
(struct (type-params T) (field value T))
```

Constants, structs, and fields use analogous compiler-owned canonical forms.
Generic parameter lists are part of the signature when present.
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
- `incomplete`: the source set contains an accepted low-level compatibility
  form whose identifier operand roles are not fully modeled;
- `failed`: semantic analysis did not produce a trustworthy graph.

`analysis.complete` is true only for `complete`. Consumers must inspect status
before answering absence questions.

The embedded diagnostics envelope uses `weavec-diagnostics-v1`. Diagnostic
completeness is independent of graph completeness.

## Consumer rules

A consumer must:

1. reject unknown major schema versions;
2. verify compiler, language, source-set, and option identity;
3. preserve supplied source ordering;
4. interpret spans as UTF-8 byte ranges;
5. inspect completeness before answering negative queries;
6. inspect reference status before interpreting a null symbol ID;
7. use interface hashes only with the documented algorithm identifier;
8. never infer visibility, imports, or semantic identity from filenames.

Jacquard should map compiler spans to stable structural node IDs. It must not
reconstruct Weave name resolution from source examples.

## Evolution

Future versions may add lexical binding symbols, richer expression-type records,
or additional relationship kinds. Additive fields remain ignorable by tolerant
v1 consumers; changes that alter required identity or interpretation require a
new major schema version.

The compiler remains the sole semantic authority throughout that work.
