# Changelog

All notable changes to `weavec` are recorded here. The repository was named
`weavec2` through release `v0.1.2`; historical entries retain that name. The
format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [SemVer](https://semver.org/) and remains pre-1.0 while the
surface-language contract stabilises.

## [Unreleased]

## [0.3.0] — 2026-07-25

### Added

- Public `weavec build <source...> -o <program>` source-to-executable command.
- Private target runtime discovery relative to the installed compiler package.
- `weavec-build-manifest-v1` build provenance output through
  `--manifest-json <path>`.
- `weavec-diagnostics-v1` machine-readable diagnostics through
  `--diagnostics-json <path>`.
- Stable phase exit codes for frontend, backend, LLVM code generation, target
  linking, atomic publication, and build-driver failures.
- Exact UTF-8 source spans for canonical S-expression parse preflight errors.
- Conservative backend source spans when a diagnostic token occurs uniquely in
  canonical source, with explicit `span_origin` provenance.
- Documentation and regression coverage for the build-driver and diagnostics
  contracts.

### Changed

- Normal users and downstream tools no longer need to invoke the surface
  frontend, WIR backend, `clang`, or the runtime archive separately.
- Linux glibc and musl compiler archives now include the private target runtime
  under `lib/weavec/<target>/libweave-runtime.a`.
- LLVM IR to object generation and target linking are separate internal driver
  phases, allowing musl packages to use `clang` for code generation and
  `musl-gcc` for final linking.
- Output executables are published atomically only after every build phase has
  succeeded.
- Human-readable stderr remains unchanged when machine-readable diagnostics are
  requested.

### Fixed

- The build driver now resolves its installed runtime without exposing a runtime
  path to normal callers.
- macOS temporary-directory creation no longer depends directly on an SDK
  declaration of `mkdtemp`.
- Failed compiler or linker phases cannot leave a partial executable at the
  requested output path.

## [0.2.0] — 2026-07-24

### Added

- Static Linux x86-64 compiler archives for glibc and musl.
- `VERSION`, `BUILD-MANIFEST`, release checksums, installed-binary smoke tests,
  and automated GitHub Release publication.
- `docs/RELEASING.md` and `scripts/package-linux-release.sh` for the final
  compiler package contract.
- A correctness regression proving that implicit backend invocation is rejected
  without creating output.

### Changed

- Renamed the repository from `weavec2` to `weavec` because it is the final
  user-facing compiler rather than another bootstrap stage.
- Renamed all current compiler artifacts to the canonical paths
  `build/weavec.{wir,ll,bc}` and `build/weavec`.
- Renamed the bootstrap dependency and environment contract from
  `weavefront`/`WEAVEFRONT_*` to
  `weavec-bootstrap`/`WEAVEC_BOOTSTRAP_*`.
- Documented the compiler chain as
  `weavec0 → weavec1 → weavec-bootstrap → weavec`.
- Replaced four cross-repository parser-module links with the single named
  `libweave-sexpr.bc` SDK boundary.
- Renamed the self-host backend override to `WEAVEC_BACKEND` and all stage
  outputs to `weavec`.
- Removed the remaining compatibility paths and former stack-patch helper
  scripts.
- Linux x86-64 now consumes checksum-verified `weavec1 v0.2.0` and
  `weavec-bootstrap v0.2.0` SDKs instead of cloning and rebuilding lower
  compiler repositories.
- Added explicit glibc and musl SDK selection and extracted-SDK overrides.
- Restricted Stage 0 and source-repository resolution to unsupported hosts or
  explicit source fallback requests.
- Expanded CI to require SDK mode on Linux glibc and musl and source mode on
  macOS.
- Removed the implicit `weavec input.wir output.ll` backend compatibility
  syntax. Callers must use `weavec --backend input.wir output.ll`.

### Fixed

- Tree walkers in the contract/explain frontend and LLVM backend no longer call
  `head_equals` on non-list AST nodes. WIR `and_bool` is strict; unguarded walks
  caused flaky SIGBUS during multi-file `--frontend`, `--explain`, and
  `--audit`.
- Backend codegen emits `(fn main ...)` first in string pre-scan and LLVM
  function emission when present, so multifile `--frontend` with `main.weave`
  last in argv matches bootstrap frontend concatenation stability.
- `lower_sources` pass 2 emits `main.weave` declarations before other inputs,
  matching the `SOURCES` order in `build.sh`.
- `./selfhost.sh` uses a stronger stage1-to-stage2 link smoke test and retries
  `clang` until the stage binary passes it.
- `weavec` no longer rewrites a dependency's `build.sh`; the 16 MiB bootstrap
  frontend stack contract is implemented and tested in `weavec-bootstrap`.
- SDK archives and checksums are revalidated before extraction, preventing a
  stale or mismatched download from entering the bootstrap chain.
- Release packaging rejects dynamic ELF executables, tests both compiler stages,
  verifies emitted LLVM IR, and retests the stripped archived binary.

## [0.1.2] — 2026-05-27

End-to-end self-hosting patch published under the repository name `weavec2`.

### Fixed

- Loop-phi optimisation produced silently wrong code for the
  "set-then-read-in-same-iteration" pattern. `emit_set_stmt` emitted a new
  `%NAME.next<TAG>` value, but the optimiser did not update current-value
  tracking, so a later `(local_get NAME)` in the same block read the old phi
  value.
- A new `name_get_after_set_in_subtree` gate keeps affected locals on the alloca
  path. The `0122_kadane5_i32` performance golden was regenerated.
- The complete 124 + 168 + 4 + 1 + 1 ladder continued to pass and the deeper
  self-host bootstrap completed through its three stage2 smoke fixtures.

### Changed

- `selfhost.sh` links `runtime/portable.c` into stage1 and stage2 binaries so
  `weave_rt_open_write_trunc` is available.

## [0.1.1] — 2026-05-27

Cross-platform portability patch published under the name `weavec2`.

### Fixed

- The compiler previously embedded the macOS value for
  `O_WRONLY | O_CREAT | O_TRUNC`, causing Linux output-file creation to fail.
  Calls now route through `runtime/portable.c::weave_rt_open_write_trunc`, which
  uses symbolic `<fcntl.h>` flags.
- The Linux and macOS CI matrix passed 124 correctness, 168 performance,
  4 quantum, 1 quantum end-to-end, and 1 basic self-host check.

## [0.1.0] — 2026-05-27

The first public release, published as `weavec2`.

### Added

- Apache-2.0 licensing, notices, and SPDX headers.
- `CONTRIBUTING.md`, this changelog, and repository formatting files.
- GitHub Actions CI on Linux and macOS.
- Surface correctness, WIR performance, quantum, and basic self-host ladders.

### Changed

- `build.sh` stopped assuming sibling checkouts and began resolving pinned
  `weavec0`, `weavec1`, and then-`weavefront` source releases under
  `build/vendor/`.
- Dependency source trees were built once and shared through the bootstrap.

### Fixed

- Loop-phi LLVM code generation was guarded against several invalid-SSA
  patterns, including multiple sets, inner lets, nested conditionals, and
  return-terminated branches.
- `emit_function` and `emit_extern_decl` accepted both `(params)` and the
  surface-lowered `(params ())` form.

### Historical known limitations

- At release time, the deeper `selfhost.sh` flow was blocked by a
  string-constant emission bug. This was fixed in `v0.1.2`; the deeper flow now
  passes.
- `surface-matrix.sh` reported counts rather than enforcing thresholds.
- Vendor caches did not automatically switch refs when dependency pins changed.
- No dedicated `.weave` source-style checker existed.
