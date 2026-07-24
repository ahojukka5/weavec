# Changelog

All notable changes to `weavec` are recorded here. The repository was named
`weavec2` through release `v0.1.2`; historical entries retain that name. The
format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [SemVer](https://semver.org/) and remains pre-1.0 while the
surface-language contract stabilises.

## [Unreleased]

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
  `weavec-bootstrap v0.2.0` SDKs instead of cloning and rebuilding the lower
  compiler repositories.
- Added explicit glibc and musl SDK selection and local extracted-SDK overrides.
- Restricted Stage 0 and source-repository resolution to unsupported hosts or
  explicit source fallback requests.
- Expanded CI to require SDK mode on Linux glibc and musl and source mode on
  macOS.
- Removed the implicit `weavec input.wir output.ll` backend compatibility syntax; callers must use `weavec --backend input.wir output.ll`.

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
