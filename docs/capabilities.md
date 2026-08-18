# Compiler capability and grammar registry

`weavec capabilities --json` emits the compiler-authoritative
`weavec-capabilities-v1` document to standard output. The command takes no source
files and does not inspect a project.

```sh
weavec capabilities --json > weavec-capabilities.json
```

The registry is intended for Jacquard and other structural tools that need to
discover the actual final compiler contract without scanning examples or
reimplementing Weave semantics.

## Stability

The top-level `format` is `weavec-capabilities-v1`, with schema identifier
`urn:weavec:schema:capabilities:v1`. The corresponding JSON Schema is stored at
[`weavec-capabilities-v1.schema.json`](schemas/weavec-capabilities-v1.schema.json).

Within one compiler binary and target package, output is deterministic and
byte-for-byte repeatable. Compiler development builds naturally report their
embedded development version, while release packages report the release version.

Consumers must:

- reject an unknown top-level `format` when they require this protocol;
- ignore unknown object fields;
- use status and feature fields instead of assuming every listed form is stable;
- treat the `installed` target list as package-specific;
- avoid inferring bootstrap-stage products from this document.

The registry deliberately identifies the public variant as `final`. Lower
bootstrap compilers are implementation dependencies and are never advertised as
alternative user-facing Weave compilers.

## Document sections

### Compiler and language identity

`compiler` contains the final product name and embedded compiler version.
`language` identifies the S-expression surface contract, grammar identifier,
case sensitivity, and the WIR core version emitted by the frontend.

### Protocols and commands

`protocols` lists versioned compiler protocols, including:

- `weavec-capabilities-v1`;
- `weavec-build-manifest-v1`;
- `weavec-diagnostics-v1`;
- `weavec-compilation-trace-v1`;
- `weave-wir-core-v2`.

`commands` lists supported command spellings, their intended audience, stability,
and any versioned protocols they emit or consume.

### Targets

`targets.default` is the target installed for the current compiler package.
`targets.installed` reports package-specific target capabilities, supported
optimization levels, CPU-selection controls, runtime packaging, and whether
arbitrary cross-compilation is available.

Current packages contain one native target. A future multi-target package may add
entries without changing the schema.

### Features

`features` separates stable, experimental, and planned capabilities. Issue
numbers link planned work to the compiler roadmap but are metadata only; tools
must use `status` as the machine-readable state.

The `semantic-structs` feature is experimental. Its canonical `new`, `field-get`,
and `field-set` forms are implemented and nominally typed. The canonical
formatter orders complete constructors by the declared field sequence and keeps
field-leading comments attached during that move. Generated accessor names are
reported separately as the `generated-struct-abi` compatibility family.

The `modules` feature is experimental. The registry publishes exact `module`,
`import`, and `export` forms. The compiler validates explicit callable
interfaces, private-by-default visibility, conflicts, raw-linkage collisions,
module-scoped nominal struct identities, and import cycles while preserving
legacy `program` roots. It also emits deterministic private WIR names and
publishes semantic-index module definitions, imports, exports, references, call
edges, and interface hashes independently of source argument order.

The next module milestone is project and package usability rather than completion
of the closed issue #53 implementation series. Epic
[#111](https://github.com/ahojukka5/weavec/issues/111) owns project manifests,
deterministic source discovery, public type interfaces, entry-module selection,
and the later incremental-build boundary. Tools must continue to treat
`modules` as experimental until that user-facing project contract stabilizes.

The `explicit-generics` feature is experimental. It publishes the
`(type-params ...)` and `(type-app ...)` forms and links to issue
[#145](https://github.com/ahojukka5/weavec/issues/145). Generic declarations
resolve as structured types; they are not specialized to WIR yet.

The `string-literals` feature is experimental. It publishes raw
`#"..."` and multiline `"""..."""` spellings, including `#"""..."""`,
and links to issue [#239](https://github.com/ahojukka5/weavec/issues/239).
Ordinary escaped `"..."` is unchanged. All four lower to
`const_string_ptr`.

The application-language roadmap and its five epics are documented in
[`roadmap.md`](roadmap.md). Planned capabilities should link to their owning epic
or focused subissue instead of using completed historical issue numbers.

### Surface grammar

`surface` is the LLM-facing grammar registry. It reports:

- primitive type names;
- canonical operator groups and their admitted operand types;
- admitted explicit cast pairs;
- contextual literal kinds and authoritative contexts;
- exact canonical or experimental form heads;
- child-count constraints, excluding the list head itself;
- named child roles and cardinalities;
- whether type information is explicit, contextual, semantic, or absent;
- feature dependencies;
- compatibility families and canonical replacements.

Canonical forms are the preferred output for newly generated application source.
Compatibility families remain accepted where documented but should not be chosen
by generators when a canonical replacement exists.

The registry references
[`language-reference.md`](language-reference.md) for the complete implemented
surface and [`canonical-surface.md`](canonical-surface.md) for canonical
LLM-facing elaboration rules. Experimental module syntax is specified in
[`modules.md`](modules.md).

## Schema evolution

Version 1 is additive within the same `format`: new fields, commands, targets,
features, forms, and status values that are admitted by the schema may appear.
Removing or reinterpreting required fields requires a new top-level format and
schema identifier.

A consumer should combine:

1. exact top-level format checking;
2. tolerant unknown-field handling;
3. explicit feature/status checks;
4. compiler-version compatibility policy appropriate to its workflow.

## Implementation boundary

The capability registry and its deterministic serialization are owned by surface
Weave modules under `src/protocol/`. Protocol modules own the schema identifier,
field ordering, command/feature registry, surface forms, compatibility families,
and target representation.

The native runtime exposes only checked JSON byte mechanics and platform-derived
facts such as the embedded compiler version and installed default target. It does
not contain a second copy of the capability registry or decide public protocol
fields. This follows the repository-wide rule that C is a platform boundary, not
a compiler implementation language; see
[`protocol-boundary.md`](protocol-boundary.md).

Surface grammar changes must update the Weave-owned registry, schema, and
normalized regression fixture in the same pull request. The capability test
verifies determinism, uniqueness, status invariants, canonical replacements,
target normalization, schema identity, and the absence of bootstrap products.
