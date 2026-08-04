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

It also publishes `incremental_project_builds` with the independent
`weavec-project-module-cache-v1` report protocol, cache controls, default cache
location, validation order, interface-hash invalidation model, and relocation-safe
key policy.

Tools should check these capabilities instead of inferring support from the
presence of a `weave.project` file or undocumented command behavior.

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

Incremental caching does not replace protocol publication. Builds that request
manifests, diagnostics, traces, semantic indexes, contracts, audits, or phase
artifacts run through the established complete protocol pipeline. Cache reports
are separate additive evidence and cannot alias a project input or output.

## Acceptance command

The integrated public project workflow is qualified with one reusable command:

```sh
bash test/project-acceptance/test.sh
```

A specific compiler, including an extracted release compiler or a self-hosted
stage compiler, is selected explicitly:

```sh
bash test/project-acceptance/test.sh --compiler /path/to/weavec
```

The acceptance runner composes the focused module-interface, nominal-type,
project-selection, source-admission, graph-resolution, incremental-cache,
protocol, relocation, and failure suites. It requires representative executable
and library builds to succeed, native programs to return their expected status,
module cache keys and interface hashes to obey the deterministic edit matrix, and
failed builds to retain stable human and JSON diagnostics without partial
executables.

The standard qualification matrix invokes this command in three environments:

- the compiler built from published SDKs on Linux glibc, Linux musl, and macOS;
- each extracted static Linux release package, using only its packaged compiler
  and private runtime; and
- the stage-2 compiler produced by the deep self-host ladder.

Issue [#124](https://github.com/ahojukka5/weavec/issues/124) was completed only
after the exact merged `master` revision passed both the CI push workflow and the
release push workflow. Issue
[#125](https://github.com/ahojukka5/weavec/issues/125) applies the same merged-head
completion rule to incremental compilation.

## Compatibility boundary

Project facts and incremental compilation do not change surface syntax,
`weave.project` format version 1, WIR core version 2, generated symbol names, the
struct ABI, or existing diagnostic codes. Project context remains additive in
permissive version-one host protocols, while incremental reuse publishes the
separate `weavec-project-module-cache-v1` document described in
[Incremental project builds](incremental-project-builds.md).
