# Project facts in compiler protocols

Issue [#123](https://github.com/ahojukka5/weavec/issues/123) makes project
selection and module-graph facts available through compiler-owned public
protocols. Tools no longer need to repeat `weave.project` discovery, filesystem
admission, import-graph ordering, entry selection, or public-interface analysis.

## Shared project object

Project-mode outputs carry an additive top-level `project` member. Its value uses
the versioned `weavec-project-facts-v1` contract defined by
[`weavec-project-facts-v1.schema.json`](schemas/weavec-project-facts-v1.schema.json).
The object is attached to:

- `weavec-build-manifest-v1` build manifests;
- `weavec-diagnostics-v1` diagnostic documents;
- `weavec-compilation-trace-v1` compilation traces; and
- `weavec-semantic-index-v1` semantic indexes.

Existing source-list commands retain their current documents without a project
object. The addition is therefore backward compatible for readers that already
permit unknown top-level members.

## Commands

A project build may publish all build protocols in one invocation:

```text
weavec build --project path/to/project \
  --manifest-json build.json \
  --diagnostics-json diagnostics.json \
  --trace-json trace.json
```

Project semantic analysis uses the same selection and graph rules:

```text
weavec analyze --project path/to/project \
  --semantic-index-json semantic-index.json
```

Omitting `--project` selects the nearest `weave.project` in the current directory
or its ancestors. Passing a project directory or the manifest file itself is
cwd-independent.

## Resolution phases

The project object reports how far compiler-owned resolution completed:

- `project-manifest` selects and parses `weave.project`;
- `project-sources` admits files and binds compiler-declared module names;
- `project-graph` resolves imports, dependency order, and entry ownership; and
- `complete` means all project facts are available.

Structured diagnostics and failed traces use these project phases instead of the
generic `driver` phase for project-owned failures. Stable diagnostic codes remain
unchanged. A missing imported module, for example, keeps
`project.graph.missing-module` and now carries phase `project-graph`.

## Manifest and selection facts

A complete object publishes:

- project name and kind;
- the selected manifest;
- configured source and test roots;
- executable entry module, when applicable;
- declared and resolved output paths;
- discovered source membership;
- deterministic dependency order; and
- the module import graph.

Incomplete objects retain the same shape. Facts that could not be established are
`null` or empty arrays, while `complete` is false and `resolution_phase` names the
failed boundary.

## Logical and physical paths

Logical project paths are compiler-normalized paths relative to the project root.
They are relocation-stable and are authoritative for source identity, graph facts,
semantic-index source paths, and deterministic comparisons.

Physical paths are observational host paths. They identify the selected manifest,
project root, admitted files, and resolved native output on the current machine.
They may change when a project is relocated and must not be used as semantic
identity or cache keys.

The `selection` field records the caller's explicit `--project` spelling, or
`null` for nearest-parent discovery. It is observational and is not part of the
project's semantic identity.

## Module graph and interfaces

The `sources` array is sorted by logical source path. `module_order` and
`module_graph` use the deterministic dependency order selected by the existing
project resolver. Each graph node names its source module, logical source path,
and direct imported modules.

The semantic index remains authoritative for declarations, exports, imports,
references, call edges, public nominal types, and module interface hashes. The
project object supplies project membership and graph context; it does not duplicate
symbol-level semantic facts.

## Capabilities

`weavec capabilities --json` publishes a `project_mode` object containing:

- experimental feature `project-builds`;
- protocol identifier `weavec-project-facts-v1`;
- the public protocols extended by the project object;
- project build and analysis command spellings;
- manifest name, version, and supported kinds; and
- logical-versus-physical path policy.

Tools should check this capability instead of inferring support from the presence
of a `weave.project` file.

## Safety and publication

Project protocol publication preserves the existing atomic-output and alias
rules. No requested build product or protocol document may replace the selected
manifest or an admitted source file. This remains true when the manifest itself
is malformed: the safety layer identifies the selected path before parsing and
prevents the additive protocol facade from reopening it after rejection.

Failed project resolution does not publish a native binary, WIR product, or
successful build manifest. Requested diagnostics and traces may still be
published with incomplete project facts so tools can explain the failure without
reimplementing project discovery.

## Compatibility boundary

This feature does not change surface syntax, `weave.project` format version 1,
WIR core version 2, generated symbol names, the struct ABI, or existing diagnostic
codes. It adds project context to permissive version-one JSON protocols and adds a
project-aware semantic-index entry point.

Incremental compilation and project caches remain later work. Issue
[#125](https://github.com/ahojukka5/weavec/issues/125) may consume the stable
logical paths, module order, and public interface hashes defined here without
changing this protocol.
