# weavec documentation

`weavec` is the user-facing, self-hosted Weave compiler. This documentation
covers the released compiler product, its source language, public command-line
contracts, internal architecture, bootstrap dependencies, diagnostics, release
process, and focused implementation notes.

The repository was named `weavec2` through release `v0.1.2`. Current documents
use only the final product name `weavec`; historical changelog entries retain the
names used when they were released.

## Start here

- [Language design principles](design-principles.md) — the decision
  framework for evaluating language-design proposals: priority classes, twelve
  principles, worked trade-offs, standing exclusions, and the review template.
- [Architecture](architecture.md) — compiler layers, source-to-executable flow,
  bootstrap boundary, runtime ownership, self-hosting, and verification model.
- [Runtime implementation boundary](runtime-boundary.md) — Weave-first portable
  behavior, the narrow C/host ABI role, and removal rules for temporary helpers.
- [Application-language roadmap](roadmap.md) — the five usability epics,
  dependency order, subissue workflow, compatibility rules, and deferred work.
- [Structured semantic type graph](structured-type-graph.md) — canonical type
  identities, interning, node kinds, legacy migration, and the WIR-v3 boundary.
- [Weave project manifest version 1](project-manifest.md) — canonical
  `weave.project` grammar, defaults, path rules, project kinds, diagnostics, and
  command-line precedence for the project-system implementation.
- [Deterministic project source discovery](project-source-discovery.md) — admitted
  files, filesystem and symlink policy, compiler-declared module identities,
  logical paths, stable ordering, and diagnostics.
- [Project facts in compiler protocols](project-protocols.md) — shared project
  context in manifests, diagnostics, traces, semantic indexes, and capabilities.
- [Incremental project builds](incremental-project-builds.md) — interface-hash
  module caching, invalidation, controls, atomic storage, evidence, and safety.
- [Development builds](development-builds.md) — SDK-only final-compiler builds,
  canonical scripts, dependency overrides, and no-build test qualification.
- [Command reference](command-reference.md) — public build command,
  compiler-development overrides, and low-level compiler modes.
- [Compiler capability and grammar registry](capabilities.md) —
  `weavec-capabilities-v1`, installed targets, protocol versions, feature status,
  and the compiler-authoritative LLM-facing grammar contract.
- [Canonical Weave formatting](formatting.md) — parser-backed deterministic
  normal form, compatibility normalization, comment policy, and atomic updates.
- [Compiler version identity](compiler-version.md) — release and development
  version strings, build-time embedding, and reproducibility semantics.
- [Language reference](language-reference.md) — the implemented surface-Weave
  forms accepted by the current compiler.
- [Standard-library layout and module naming](stdlib.md) — where `stdlib`
  modules live, how they are named `std.<id>`, and how packages ship them.
- [Standard-library API conventions](stdlib-conventions.md) — Option,
  Result, and bool failure signaling, naming, and mutation rules.
- [Integer widths and the size type](integer-widths.md) — `usize` for
  lengths and indices, `u64`/`u8` roles, and why `i32` sizes must not
  freeze.
- [Canonical LLM-facing surface forms](canonical-surface.md) — typed canonical
  calls, contextual literals, compatibility forms, and deterministic elaboration.
- [WIR core version 3](wir.md) — the self-hosted frontend/backend envelope,
  compatibility policy, validation, and repository enforcement.
- [Build manifest](build-manifest.md) — `weavec-build-manifest-v1` and the
  separate release-package `BUILD-MANIFEST`.
- [Machine-readable diagnostics](diagnostics.md) —
  `weavec-diagnostics-v1`, stable phase exits, and source-span provenance.
- [Structured module diagnostics](module-diagnostics.md) — stable module,
  import, and export error codes, operand roles, and exact-span policy.
- [Source-linked compilation trace](compilation-trace.md) —
  `weavec-compilation-trace-v1`, deterministic lowering and optimization events,
  and exact original source spans.
- [LLVM source provenance and quality budgets](llvm-provenance.md) —
  comment-only source/WIR links, semantic IR naming, and structural regression
  ceilings for performance goldens.
- [Tooling artifact outputs](tooling-artifacts.md) — stable WIR and LLVM output
  paths, phase-scoped atomic publication, and the boundary with external tools.
- [Native optimization and machine-code evidence](native-code-evidence.md) —
  explicit LLVM profiles, optimized IR, assembly, final disassembly, remarks,
  and evidence-based evaluation of backend transformations.
- [Source and fixture style](source-style.md) — `.weave` compiler conventions,
  resource ownership, deterministic emission, and regression-fixture style.
- [Releasing](releasing.md) — reusable package, validation, and publication
  procedure.

## Language and feature guides

- [Executable contracts and explain mode](contracts-and-explain.md)
- [Explicit modules and interfaces](modules.md)
- [Public nominal type interfaces](public-nominal-types.md)
- [Semantic structs](semantic-structs.md)
- [Struct layout and compatibility ABI](struct-layout.md)
- [Struct value semantics](struct-ownership.md)
- [Quantum surface support](quantum.md)

## Backend and performance notes

- [Performance demonstrations](performance-demonstrations.md)
- [LLVM code-generation analysis](llvm-codegen-analysis.md)
- [Generated LLVM analysis report](llvm-codegen-analysis-report.md)

The backend and performance documents describe current self-hosted implementation
behavior and optimization opportunities. They do not extend the stabilized WIR
contract.

## Repository documents

- [README](../README.md) — product overview and quick start.
- [Contributing](../CONTRIBUTING.md) — change policy and required checks.
- [Changelog](../CHANGELOG.md) — release history.

## Naming policy

Files under `docs/` use lowercase kebab-case names. Conventional repository-root
files such as `README.md`, `CHANGELOG.md`, `CONTRIBUTING.md`, `LICENSE`, and
`NOTICE` retain their standard names.
