# Incremental project builds

`weavec build` can reuse compiler-produced module objects without skipping project
or language validation. The compiler still discovers the selected manifest,
admits sources, resolves the complete module graph, validates every module
interface, and computes current public interface hashes before consulting the
cache.

The cache is an optimization. Removing it or passing `--no-cache` must not change
successful program behavior, diagnostics, project facts, module interfaces, or
other public compiler contracts.

## Commands

A normal project build uses the default project-local cache:

```sh
weavec build
```

The default cache base is:

```text
<project-root>/.weave/cache
```

The compiler owns versioned subdirectories below that base. Their contents are
private implementation data and may be replaced when the cache format changes.

Useful controls are:

```sh
weavec build --no-cache
weavec build --clean
weavec build --cache-dir /path/to/shared-cache
weavec build --cache-report cache-report.json
```

`--no-cache` reads and writes no cache entries. `--clean` removes the selected
versioned cache before compiling. `--cache-dir` selects a base directory without
changing project identity. `--cache-report` atomically publishes deterministic
reuse and invalidation evidence.

## Module cache model

The compiler emits and optimizes one WIR/object unit per project module. Every
unit is built from the complete source set so imported declarations, public
nominal types, visibility, cycles, entry ownership, and exact diagnostics remain
compiler-authoritative.

A module object key includes:

- the cache format version and compiler version;
- target, optimizer, code generator, linker, optimization profile, CPU, and tune
  CPU selections;
- private runtime bytes;
- project kind, compiler-declared module identity, and logical source path;
- the module's complete source bytes and current public interface hash; and
- each direct imported module identity and public interface hash.

Physical checkout paths are excluded. Equivalent relocated projects therefore
produce the same module keys and can share a selected cache directory.

## Invalidation

A private implementation edit changes only the owning module key when its public
interface hash remains stable. Direct and transitive users may reuse their
objects.

An exported interface edit changes the edited module key and the key of every
direct importer. Recalculation continues deterministically through the graph only
where a module's required imported interfaces change.

Manifest, compiler, target, profile, CPU, runtime, or source-input changes are
explicit key material. They cannot silently reuse an incompatible entry.

## Storage and corruption

Each cache entry contains one regular artifact and its SHA-256 digest. Entries are
published through a temporary directory and an atomic rename. Restoration verifies
the digest before copying the artifact atomically to the current build workspace.

Missing, partial, corrupt, stale, or incompatible entries are cache misses. They
never produce a successful build by themselves and never bypass current semantic
validation. A failed cache write does not invalidate a successfully produced
program; the report records the failure reason.

## Cache report

`--cache-report` publishes
[`weavec-project-module-cache-v1`](schemas/weavec-project-module-cache-v1.schema.json).
A successful report contains the cache directory and one item per module in
deterministic dependency order. Each item records:

- compiler-declared module name;
- relocation-stable logical source path;
- current public `interface_sha256`;
- complete module cache `key`;
- `decision`, either `rebuilt` or `reused`; and
- a deterministic `reason`.

Timing, host process identifiers, temporary paths, and physical checkout paths are
not part of the report. Cache reports cannot alias a project manifest, admitted
source, or native output.

Example:

```json
{
  "format": "weavec-project-module-cache-v1",
  "status": "succeeded",
  "cache_dir": "/cache/weavec-project-cache-v1/modules",
  "exit_code": 0,
  "modules": [
    {
      "name": "arithmetic",
      "source": "src/arithmetic.weave",
      "interface_sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
      "key": "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789",
      "decision": "reused",
      "reason": "implementation-and-import-interfaces-match"
    }
  ]
}
```

## Protocol and safety boundary

Builds that request diagnostics, traces, semantic indexes, manifests, contracts,
audits, or phase artifacts run through the established full project protocol path.
The cache does not replace or synthesize those documents.

Manifest UTF-8 and forbidden-NUL checks, output alias protection, source admission,
symlink policy, graph validation, and failure publication run before cache use.
Internal source-registry and graph reporters likewise retain their established
compiler path.

## Platform equivalence

Clean and incremental builds require identical module keys, public interface
hashes, diagnostics, and executable behavior. Native executable bytes are compared
where the platform linker specifies stable output. On macOS, the required Mach-O
UUID may differ across equivalent links and is not a semantic cache input.

## Qualification

The deterministic edit matrix covers:

- exact reuse and relocation;
- private implementation edits;
- direct and transitive exported-interface invalidation;
- unrelated module reuse;
- corrupt object recovery;
- optimization-profile changes;
- clean and no-cache builds; and
- report-output alias safety.

It runs through `test/project-acceptance/test.sh` on Linux glibc, Linux musl,
macOS, extracted release packages, and the stage-2 deep self-host compiler.

## Compatibility boundary

Incremental project builds do not change surface Weave syntax, `weave.project`
format version 1, WIR core version 3, module interface hashing, generated symbol
names, the struct ABI, or existing diagnostic and project-protocol formats. The
cache report is a separate additive protocol.
