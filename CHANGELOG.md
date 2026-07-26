# Changelog

All notable changes to `weavec` are recorded here. The repository was named
`weavec2` through release `v0.1.2`; historical entries retain that name. The
format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [SemVer](https://semver.org/) and remains pre-1.0 while the
surface-language contract stabilises.

## [Unreleased]

### Added

- A canonical lowercase documentation index and complete final-compiler
  architecture document.
- Dedicated references for the public command line, implemented surface
  language, `weavec-build-manifest-v1`, and release-package `BUILD-MANIFEST`.
- A current quantum implementation guide that separates regression-tested
  behavior from future runtime and target design.
- A compiler source and fixture style guide covering `.weave` conventions,
  resource ownership, deterministic emission, and regression metadata.
- A WIR core version 2 contract document and permanent repository audit.
- Exact backend diagnostic source spans propagated through deterministic,
  comment-only WIR metadata, with unique-token inference retained as fallback.

### Changed

- Standardized maintained files under `docs/` on lowercase kebab-case names.
- Refocused the root README on the user-facing compiler product and moved detailed
  contracts into linked reference documents.
- Replaced stale rename, bootstrap patching, local-only self-host, proposal-era
  syntax, and workspace-specific guidance with current repository behavior.
- Made the release guide reusable for versions derived from `VERSION` rather than
  embedding one-time `v0.3.0` commands.
- Clarified performance fixture naming, documented fixture `0175`, and identified
  `0176` as the next free performance ID.
- Reframed LLVM code-generation analysis as an engineering snapshot rather than a
  stable language or performance contract.
- Preserved short redirect documents for historical quantum and lowering links
  without retaining competing proposal text.
- Migrated the self-hosted frontend, backend, runtime modules, correctness,
  performance, quantum, and self-host corpora to WIR core version 2.
- Added strict WIR v2 envelope validation and rejection fixtures for core version 1,
  missing or duplicate versions, missing or non-integer version values, and
  invalid roots.
- Removed partial LLVM output after every backend emission failure.
- Made identifier comparison sentinel-safe for missing optional AST children and
  added a malformed `call_ptr` regression that exercises effect analysis during
  self-hosted frontend lowering.

## [0.3.0] — 2026-07-25

### Added

- Public `weavec build <source...> -o <program>` source-to-executable command.
- Private target runtime discovery relative to the installed compiler package.
- `weavec-build-manifest-v1` build provenance output through
  `--manifest-json <path>`.
- Versioned `weavec-diagnostics-v1` output with stable public build-phase exit
  codes, exact frontend preflight spans, conservative backend token spans, and
  explicit span provenance.
- Static Linux x86-64 release packages for glibc and musl.
- Fresh-extraction package verification for public build, diagnostics, runtime
  discovery, and failure atomicity.
- A permanent deep self-host CI gate that builds and verifies stage-one and
  stage-two compiler generations.

### Changed

- Renamed the final compiler product and repository from `weavec2` to `weavec`.
- Renamed the former `weavefront` dependency to `weavec-bootstrap`.
- Removed current `weavec2`, `weavefront`, `WEAVEC2_*`, and `WEAVEFRONT_*`
  compatibility interfaces.
- Made explicit `--frontend` and `--backend` modes the only low-level compiler
  interfaces; removed implicit two-path backend invocation.
- Switched normal Linux source builds to checksum-verified `weavec1` and
  `weavec-bootstrap` SDK releases instead of cloning and building lower stages.
- Linked parser support through the published `libweave-sexpr.bc` boundary rather
  than individual generated modules.
- Split compiler host support from the private target program runtime.
- Made native output publication atomic and preserved existing output on failed
  builds.
- Updated CI and release workflows for Linux glibc SDKs, Linux musl SDKs, macOS
  source fallback, static packages, and extracted-package verification.

### Fixed

- Rejected unresolved WIR call targets before opening LLVM output.
- Preserved target-specific runtime and linker selection in release packages.
- Prevented frontend and backend failures from publishing partial native
  executables.

## [0.2.0] — 2026-07-24

### Added

- Native source-to-executable build orchestration through the compiler host
  support layer.
- Linux x86-64 package layouts with private target runtime archives.
- Build provenance manifests and package smoke tests.

### Changed

- Made the final compiler the single user-facing command.
- Replaced direct runtime arguments in normal user workflows with compiler-owned
  runtime discovery.

## [0.1.2] — 2026-07-24

### Changed

- Renamed the repository from `weavec2` to `weavec` after this release.

## [0.1.1] — 2026-07-23

### Fixed

- Corrected bootstrap and package naming inconsistencies.

## [0.1.0] — 2026-07-23

### Added

- Initial self-hosted final compiler release under the `weavec2` name.
