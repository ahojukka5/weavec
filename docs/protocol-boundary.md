# Public protocol ownership

The final compiler treats public machine-readable documents as compiler behavior,
not as a C runtime service.

The architectural rule is:

> **C is a platform boundary, not a compiler implementation language.**

## Ownership

`src/protocol/` owns public compiler protocol meaning. A protocol module owns:

- the format identifier and schema version;
- field names and deterministic field order;
- canonical representation of optional values;
- compiler and language registry facts;
- compatibility classifications and protocol-specific validation policy;
- composition of compiler facts into the published document.

Compilation, project-resolution, and analysis code produce facts. They do not
construct public JSON directly.

The initial Weave-owned serializers cover:

- `weavec-capabilities-v1`;
- `weavec-build-manifest-v1`;
- `weavec-diagnostics-v1`;
- `weavec-compilation-trace-v1`;
- the additive `weavec-project-facts-v1` object used by project-mode protocols.

## Native boundary

C remains responsible for mechanics that surface Weave cannot yet express safely
or portably:

- checked byte-level JSON emission and escaping;
- atomic file publication, `fsync`, rename, and host I/O failures;
- reading source bytes needed to resolve line and column positions;
- process- and filesystem-level project discovery;
- private trace-event transport;
- platform-derived values such as the compiler version and default target.

Those native functions expose opaque writers or raw facts. They must not decide a
public format name, field name, field order, feature registry entry, language
surface rule, or compatibility classification.

The checked JSON writer remains native temporarily because surface Weave does not
yet have safe owned `String`/`Bytes` values suitable for a general serializer.
When that capability exists, the byte writer can be reconsidered independently;
its current location is not permission to move protocol policy back into C.

## Data flow

```text
compiler / project / analysis facts
              |
              v
      src/protocol/*.weave
  schema + ordering + validation
              |
              v
   opaque checked JSON writer
              |
              v
 native atomic file/stdout publication
```

Project-mode builds follow the same rule. C may resolve `weave.project`, source
roots, module order, and physical paths, but `project.weave` owns the public
`project` object. Build manifests, diagnostics, and compilation traces append that
object directly while their Weave serializer is active instead of patching a JSON
file afterward.

The semantic-index implementation predates this boundary. Until its serializer is
migrated, project-mode semantic-index publication may use a schema-agnostic merge
of two already serialized JSON objects. The merge is allowed to understand JSON
object delimiters only; the `project` field and its value are still emitted by
Weave. No new public protocol may use this transitional mechanism.

## Dependency direction

The intended dependency is one-way:

```text
compiler facts -> protocol modules -> host mechanics
```

Host mechanics must never import or duplicate a compiler registry. Protocol
modules may consume compiler facts only through documented Weave functions or
narrow native fact accessors.

Tests enforce this boundary alongside byte/schema compatibility and the full
bootstrap, package, and deep-self-host ladders.
