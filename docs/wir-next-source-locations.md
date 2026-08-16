# Next-version WIR source locations

This document specifies first-class source provenance for WIR core version 3.

Core version 3 is open: the self-hosted frontend and backend moved to it as part
of this coordinated revision. The model below is one of the two payloads that
revision exists to carry, and is not yet implemented.

The proposal standardizes three independent pieces:

1. a module-local source table;
2. an indexed table of provenance records;
3. a semantically transparent wrapper that attaches one record to a WIR node.

The representation is optional. A module without source metadata has the same
executable meaning as one whose metadata has been removed.

## Goals

The next WIR version should let producers and consumers exchange exact source
locations without compiler-specific comments or private sidecars. The model
must support:

- stable source identities within one WIR module;
- half-open UTF-8 byte spans;
- one source span lowering to many WIR nodes;
- many source spans lowering to one WIR node;
- generated nodes with no direct source span;
- deterministic serialization and comparison;
- metadata-preserving WIR-to-WIR tools;
- unchanged code generation when metadata is absent or stripped.

The model is observational. Source metadata must not affect types, symbol
resolution, control flow, instruction selection, linkage, or runtime behavior.

## Proposed module shape

A source-aware module uses a future core version and may contain `sources` and
`locations` before `decls`:

```text
(core-module
  (core-version 3)
  (sources
    (source 0
      (name "library.weave")
      (sha256 "0123456789abcdef..."))
    (source 1
      (name "main.weave")
      (sha256 "fedcba9876543210...")))
  (locations
    (location 0
      (origin direct (span 0 80 146)))
    (location 1
      (origin lowering (span 1 120 162))))
  (decls
    (located 0
      (fn add-two
        (params (left i32) (right i32))
        (returns i32)
        (do
          (located 1
            (return (add_i32 (param_get left) (param_get right)))))))))
```

The examples use core version 3, which is the version this model lands in. The
version being open does not make the forms below valid input yet: a compiler
accepts the forms it implements, and these are not implemented.

## Source table

Each `source` entry has a nonnegative module-local integer identifier. IDs are
unique and dense from zero in canonical output.

```text
(source SOURCE_ID
  (name LOGICAL_NAME)
  (sha256 CONTENT_DIGEST))
```

`name` is a logical diagnostic name, not a host filesystem lookup instruction.
Canonical producers must:

- encode it as UTF-8;
- use `/` as the separator;
- remove `.` path components;
- reject `..` components;
- avoid absolute paths, drive prefixes, home-directory expansion, and URI
  credentials.

Two source entries may have identical names or content. `SOURCE_ID`, rather than
name or digest, is the authoritative identity inside the module. This preserves
identity for duplicate build inputs and generated virtual documents.

`sha256` is the lowercase digest of the exact source bytes. It lets consumers
validate an external source without making source availability a prerequisite
for compilation. A future extension may admit a standardized unavailable or
virtual-source form, but it must not overload an invalid digest.

## Location table

Each `location` entry has a nonnegative module-local integer identifier. IDs are
unique and dense from zero in canonical output.

A direct location contains one origin:

```text
(location 4
  (origin direct (span 1 120 162)))
```

A many-to-one lowering contains multiple ordered origins:

```text
(location 5
  (origin lowering (span 0 80 95))
  (origin lowering (span 0 110 124)))
```

A generated node may have no direct span and may identify the records from which
it was derived:

```text
(location 6
  (generated)
  (derived-from lowering 4 5))
```

A span is:

```text
(span SOURCE_ID START_BYTE END_BYTE)
```

The range is half-open: `START_BYTE <= byte < END_BYTE`. Offsets count bytes in
the exact source content named by the source table, not Unicode scalar values,
UTF-16 code units, lines, or columns.

Validators must reject:

- unknown source or location IDs;
- negative offsets;
- `END_BYTE < START_BYTE`;
- offsets beyond the source length when source bytes are available;
- duplicate IDs;
- cyclic `derived-from` relationships;
- origin roles outside the versioned registry.

The initial origin roles are:

- `direct` — the WIR node directly represents the source form;
- `lowering` — the WIR node was introduced while lowering the source form;
- `expansion` — the node originates from an expanded source construct;
- `related` — the span is relevant but is not the primary origin.

Origins are serialized in semantic priority order and then by source ID, start,
end, and role. `derived-from` IDs are ascending within one relationship. These
rules make canonical output independent of hash-table or traversal order.

One source span maps to many WIR nodes by appearing in multiple location
records. Many source spans map to one WIR node by appearing as multiple origins
in one record.

## Node attachment

The generic attachment form is:

```text
(located LOCATION_ID NODE)
```

`located` is valid wherever `NODE` would be valid. It has exactly two children:
the location ID and one WIR node. Nested `located` wrappers are noncanonical and
must be rejected or normalized into one location record before publication.

The wrapper is semantically transparent:

- validation applies to the wrapped node;
- code generation emits the wrapped node exactly as if the wrapper were absent;
- symbol identity and child ordering come from the wrapped node;
- removing all wrappers and both metadata tables preserves executable
  semantics.

Producers should attach locations to declarations, statements, and expressions
that can produce diagnostics, optimization remarks, debugger stops, coverage
records, or profiling attribution. They need not annotate punctuation-like role
forms or every literal when a containing node provides sufficient provenance.

## Unknown metadata and round trips

The next WIR version should reserve a generic observational wrapper:

```text
(annotated
  (metadata NAMESPACE PAYLOAD...)
  NODE)
```

`located` is the standardized compact form for the common source-location case.
A WIR-to-WIR tool that claims metadata-preserving operation must retain unknown
`metadata` entries and unknown fields inside recognized observational tables in
their original tree order. A code-generating consumer may ignore unknown
observational metadata but must reject unknown semantic forms.

Canonical formatters may normalize whitespace and registered field ordering.
They must not silently delete unknown observational metadata unless explicitly
invoked in a metadata-stripping mode.

## Determinism and comparisons

Source metadata participates in canonical byte-for-byte WIR comparisons. A
producer must therefore avoid host-specific absolute paths, timestamps, inode
numbers, temporary directories, process IDs, and nondeterministic table order.

Two comparison modes are useful and must be named explicitly by tools:

- `canonical` compares the complete serialized module, including metadata;
- `executable` strips observational wrappers and tables before comparison.

A fixed-point compiler check may use `executable` comparison during migration,
but release reproducibility should use `canonical` comparison once every stage
emits the new version.

## Behavior when metadata is absent

`sources`, `locations`, and `located` are optional as a group. A module with no
source metadata remains valid in the next version. Consumers must not invent
locations from token positions unless they label the result as inferred and keep
it outside the authoritative WIR metadata model.

If a `located` wrapper is present, both tables must be present and its location
ID must resolve. Unreferenced source and location entries are noncanonical and
should be rejected by strict validation.

## Migration from WIR v2

The transition must be coordinated across the parser, validator, frontend,
backend, fixtures, bootstrap compiler, self-host stages, and released SDKs.

### Phase 0: specification and fixtures

- finalize this representation and the future core-version number;
- publish valid, malformed, generated, and multi-origin fixtures;
- define canonical formatting and metadata-stripping behavior.

### Phase 1: dual-read backend

- retain full WIR v2 support;
- add read-only support for the next version;
- unwrap `located` before existing semantic validation and LLVM emission;
- prove that metadata-present and metadata-stripped modules emit equivalent
  LLVM.

### Phase 2: opt-in frontend emission

- add an explicit frontend option for the next WIR version;
- keep WIR v2 as the default while lower compiler stages remain frozen;
- translate the existing comment-only source map into source and location
  tables when the new version is selected.

### Phase 3: coordinated bootstrap and self-host update

- release lower stages that can read and emit the next version;
- update direct fixtures and fixed-point evidence together;
- require canonical metadata equality across self-host stages.

### Phase 4: default transition

- make the next version the default only after all supported development and
  release paths pass the complete ladder;
- retain an explicit WIR v2 reader and emitter for the documented compatibility
  window;
- remove private source-map comments only after every supported consumer uses
  first-class locations.

No phase may reinterpret the existing WIR v2 comment channel as standardized
v2 semantics.

## Required acceptance tests

The coordinated implementation should include:

- direct declaration, statement, and expression locations;
- duplicate source names and byte-identical source inputs;
- one-to-many and many-to-one provenance;
- generated nodes with and without `derived-from` records;
- UTF-8 multibyte boundaries and empty spans;
- malformed IDs, ranges, cycles, wrappers, and table ordering;
- unknown observational metadata preservation;
- canonical and executable comparison modes;
- metadata stripping with byte-identical LLVM output;
- v2/vNext dual-read compatibility;
- frontend, backend, archive, and deep self-host fixed-point coverage.

## Current WIR v2 bridge

Until the coordinated transition, WIR v2 continues to use the deterministic,
comment-only bridge:

```text
; weavec-source-file-v1 <source-index> "<path>"
; weavec-source-span-v1 <source-index> <start-byte> <end-byte>
```

Those comments remain private compiler transport. They are intentionally ignored
by the WIR v2 lexer and do not alter WIR v2 semantics.
