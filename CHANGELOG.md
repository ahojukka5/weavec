# Changelog

All notable changes to `weavec` are recorded here. The repository was named
`weavec2` through release `v0.1.2`; historical entries retain that name. The
format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [SemVer](https://semver.org/) and remains pre-1.0 while the
surface-language contract stabilises.

## [Unreleased]

### Changed

- Pull-request CI is a light GitHub-hosted contract smoke and commit-message
  lint. The full ladder and deep self-host run only after merge on `master`.

### Added

- Canonical `Option` and `Result` types in `stdlib/option.weave` and
  `stdlib/result.weave`, plus `(try EXPR)` to unwrap `Ok` or return
  `Err` from a Result-returning function.
- Exhaustive `match` over tagged enums: `(match ENUM VALUE (case CTOR
  [BIND] EXPR)*)`, with `_` as an explicit last-arm wildcard. Missing,
  duplicate, and unreachable arms fail with exact diagnostics. The form
  lowers to ordinary WIR tag tests.
- Tagged `enum` declarations with optional payloads, explicit
  `(variant ...)`, `(variant-tag ...)`, and `(variant-payload ...)`
  forms, and deterministic 16-byte tag-plus-payload lowering. Generic
  enums specialize like generic functions.
- Deterministic monomorphization of generic functions: `(call identity
  (type-args i32) 1)` emits one concrete WIR function per distinct
  instantiation and reuses it for later calls.
- Explicit generic type parameters and type applications as surface and
  semantic forms: `(type-params T E)` on functions and structs, and
  `(type-app CONSTRUCTOR ARG...)` in type positions. Declarations resolve onto
  the structured type graph and appear in module-interface signatures;
  unspecialized generic functions are not emitted to WIR.
- A design contract for layout-free struct declarations and typed field
  operations in the next coordinated WIR core-version revision, resolving
  layout in the backend rather than the frontend, with the consumer survey it
  was decided from.
- An `if` without an else, normalized to the explicit form so both spellings
  lower to the same WIR.
- A bare `(return)` as the void return spelling, meaning exactly
  `(return_void)`.
- A user-facing index of the example programs, listing all eleven with their
  standard-module dependencies.
- A file-based numeric summary example, with `std.file` for reading a small
  text file as lines, `std.statistics` sharing one mean and variance
  implementation with the command-line example, and `std.memory` owning the
  host allocation boundary.
- A Newton square-root example with an explicit convergence test, named
  tolerance and iteration limit, and a deterministic non-convergence exit.
- A projectile-motion calculator reporting flight time, maximum height, and
  range for a documented gravity constant, plus `print_f64_fixed6`.
- A quadratic equation solver distinguishing two roots, one repeated root, no
  real roots, and a rejected zero leading coefficient.
- A descriptive-statistics example reporting count, mean, population variance,
  and population standard deviation over any number of command-line values.
- A fixed `Mat3` standard module whose matrix-vector product reuses the existing
  dot product, plus `write_f64_trimmed`, demonstrated by the matrix-vector
  example.
- Deterministic `acos_f64`, `radians_to_degrees`, and `f64_abs`, demonstrated by
  the vector-geometry example that reports vector lengths and their angle.
- A nominal `Vec3` standard module with a three-dimensional dot product,
  demonstrated by the command-line vector-dot example.
- Reusable `f64` sine, cosine, tangent, degree conversion, and fixed-six output
  demonstrated by the deterministic trigonometric function table.
- Minimal command-line argument access, deterministic Weave-owned `f64` parsing,
  and a reusable square-root module demonstrated by the Pythagorean example.
- Decimal `f64` literals, canonical `add`/`sub`/`mul`/`div`/`mod` arithmetic,
  and a Weave-owned floating-point output library demonstrated by an executable
  exact-output example.
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
- `weavec-compilation-trace-v1` output with deterministic, source-linked
  lowering, rewrite, optimization, and executable-contract events.
- Opt-in LLVM provenance comments linking generated function and statement
  groups to exact surface and WIR byte ranges.
- Structural LLVM quality budgets that ratchet instruction counts, memory
  traffic, control flow, semantic naming, and identity-operation regressions.
- A compiler-native compilation-trace action registry with a permanent drift
  audit covering metadata, frontend call sites, documentation, and regressions.
- An explicit LLVM optimization and native-code evidence pipeline with portable
  `O2` defaults, `O3`/native profiles, optimized LLVM, assembly, optimization
  records, final executable disassembly, and phase-scoped publication.
- A canonical validated compiler source manifest consumed by bootstrap, self-host,
  and bootstrap-stack qualification.
- Stage-1/stage-2 fixed-point evidence with normalized hashes, LLVM structure
  summaries, exported symbol sets, and retained mismatch diffs.
- Compiler-owned typed surface elaboration for canonical `(call ...)` forms and
  contextual literals in bindings, assignments, arguments, and returns.
- Canonical `(op ...)` and `(cast TYPE EXPR)` elaboration, including
  result-aware canonical expressions in executable contracts.
- `weavec-capabilities-v1`, a deterministic compiler-authoritative registry of
  commands, protocols, installed targets, feature status, and surface grammar.
- Machine-actionable semantic diagnostics with exact type/count context,
  explicit trust classifications, and bounded local cast repairs for agents.
- A parser-backed `weavec fmt` normal form with deterministic layout,
  compatibility normalization, preserved comments, check mode, and atomic updates.
- An explicit human and machine-readable diagnostic when `result` appears in a
  `requires` clause.
- Nominal semantic struct types with named `(new ...)`, `(field-get ...)`,
  and `(field-set ...)` forms, deterministic cross-file resolution, and exact
  constructor, receiver, field, and type diagnostics.
- Experimental explicit `(module ...)`, `(import ...)`, and `(export ...)`
  interfaces with private-by-default callable lookup, cycle rejection, legacy
  program compatibility, and compiler-authoritative capability metadata.

### Changed

- Evaluated the sine and cosine series only on a quarter turn after range
  reduction and extended them to ten terms, replacing a truncation error that
  reached `1e-4` near half a turn with one near binary64 precision across the
  whole interval.
- Moved the production S-expression token store, tree, lexer, and parser from
  hand-written WIR into the ordinary self-hosted surface-Weave compiler source
  set; seed and deep-self-host links no longer inherit lower-stage parser
  bitcode or compile a private `src/runtime-wir` implementation.
- Moved canonical development entrypoints under `scripts/`, made final-compiler
  builds consume released lower-stage SDKs on every supported host, and added
  `scripts/test-all.sh --no-build` for qualification without rebuilding.
- Made `weavec fmt` order complete semantic struct constructor fields by their
  declaration while preserving field-leading comments and invalid source order.
- Replaced duplicated handwritten compilation-trace, build-manifest, and
  diagnostics JSON assembly with typed protocol serializers backed by one
  checked streaming JSON writer and one transactional document publisher.
- Made requested build-manifest publication checked and failure-propagating: an
  incomplete document never replaces the previous manifest, and an otherwise
  successful build returns nonzero when its requested manifest cannot be
  published.
- Made requested diagnostics publication transactional and failure-propagating:
  successful builds return publication code `14` when the document cannot be
  published, while failed builds retain their original stable phase code.
- Expanded deep self-host qualification from three representative fixtures to a
  fixed-point comparison plus the complete correctness, diagnostics, trace, and
  tooling-artifact suites executed by the stage-2 compiler.
- Replaced the 1,529-line custom loop-phi and branch-merge subsystem with
  uniform mutable stack lowering after a 168-fixture A/B test found identical
  optimized LLVM structure, equal behavior, and no systematic native-code or
  runtime benefit.
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

### Fixed

- Rejected function bodies that can reach their end without returning, naming
  the function, instead of emitting a basic block with no terminator and
  failing as an LLVM parse error against generated text.
- Reported malformed sources on stderr from an ordinary `weavec build`, which
  previously failed with a non-zero exit status and no message unless
  `--diagnostics-json` was also requested.
- Replaced fallback-packed struct fields with validated natural alignment and
  explicit bool, integer, floating-point, pointer, and Qubit memory operations.
- Rejected malformed, duplicate, and unsupported struct fields before publishing
  generated compatibility constructors or accessors.

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
