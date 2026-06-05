# Changelog

All notable changes to `weavec2` are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning is
[SemVer](https://semver.org/) with the caveat that `0.x` is the early
phase: minor versions may break things until the surface-language
contract stabilises.

## [Unreleased]

### Fixed
- Tree walkers in the contract/explain frontend and LLVM backend no
  longer call `head_equals` on non-list AST nodes. WIR `and_bool` is
  strict; unguarded walks caused flaky SIGBUS during multi-file
  `--frontend`, `--explain`, and `--audit`.
- Backend codegen emits `(fn main ...)` first in string pre-scan and
  LLVM function emission when present, so multifile `--frontend` with
  `main.weave` last in argv matches weavefront-cat stability.
- `lower_sources` pass-2 emits `main.weave` decls before other inputs
  (same `SOURCES` order as `build.sh`).
- `./selfhost.sh` stage1 → stage2 bootstrap: stronger link smoke test
  and retried `clang` until the stage binary passes it.

### Changed
- `build.sh` accepts `WEAVEC2_BACKEND` and auto-selects
  `build/selfhost/stage2/weavec2` when present for WIR → LLVM (weavec1
  miscompiles the guarded combined frontend module).
- LLVM modules call `list_head_ne` in `ctx.weave` instead of raw
  `head_equals` when the node may not be a list.

## [0.1.2] — 2026-05-27

End-to-end self-hosting patch on top of v0.1.1.

### Fixed
- Loop-phi optimisation produced silently-wrong code for the
  "set-then-read-in-same-iteration" pattern: emit_set_stmt's fast
  path emits `%NAME.next<TAG>` for `(set NAME ...)`, but the
  optimiser does not update the local's current-value tracking,
  so a subsequent `(local_get NAME)` in the same basic block
  reads the pre-set `%NAME.phi<blk>` instead of the just-stored
  `%NAME.next<TAG>`. The seed weavec2 binary (built by weavec1,
  which keeps these locals on the alloca path) didn't exhibit the
  bug, but stage1 weavec2 (built by seed-weavec2, which promotes
  to loop-phi mode) did — most visibly in `write_i64_dec`'s
  print-digit loop, which then mis-emitted string-constant array
  lengths during stage2 (`[ 1 x i8] c"(local_get \00"` for what
  should have been `[12 x i8]`).

  Fix: new gate predicate `name_get_after_set_in_subtree` joins
  the existing predicates at both mode-3 marking sites. Locals
  with the set-then-read pattern stay on the alloca path where
  the next load picks up the new value via the address slot.
  Re-generated the `0122_kadane5_i32` performance golden — it had
  captured the buggy output (`%cur.phi0` was being read after
  `(set cur ...)`, but the existing if-merge logic happened to
  produce LLVM that `llvm-as` accepted even though the runtime
  semantics were wrong).

  After this fix:
    - test-all.sh still passes 124 + 168 + 4 + 1 + 1 (one perf
      golden regenerated, all others unchanged)
    - selfhost.sh's deeper stage1 → stage2 bootstrap now
      completes end-to-end, including the three stage2 fixture
      smoke tests.

### Changed
- `selfhost.sh` now links `runtime/portable.c` into the stage1
  and stage2 binaries (build.sh already did this in v0.1.1).
  Without the link, the new `weave_rt_open_write_trunc` extern
  was undefined at stage1's clang step.

## [0.1.1] — 2026-05-27

Cross-platform portability patch on top of v0.1.0.

### Fixed
- weavec2 binary failed wholesale on Linux: all 124 correctness
  tests exited with `weavec2 failed`. Root cause was three call
  sites in `src/main.weave` and `src/frontend/driver.weave` that
  baked the macOS-specific value `1537`
  (`O_WRONLY | O_CREAT | O_TRUNC` on Darwin) in as a flag literal
  for `open()`. On Linux the same constants decode to `577`, so
  the literal meant something different and `open()` refused. The
  v0.1.0 CHANGELOG comment even acknowledged the platform split
  but kept the macOS value in source.

  Fix: route through a new C portability shim
  `runtime/portable.c::weave_rt_open_write_trunc`, which calls
  `open()` with the symbolic `<fcntl.h>` flags. The WIR layer
  doesn't see the integer constants anymore. `build.sh` links
  `runtime/portable.c` into the final binary.

  After this fix, the full CI matrix
  (`ubuntu-latest` + `macos-latest`) passes 124 correctness + 168
  performance + 4 quantum + 1 quantum-e2e + 1 self-host basic.

## [0.1.0] — 2026-05-27

The first public release of `weavec2`.

### Added
- Apache-2.0 licensing (`LICENSE`, `NOTICE`, SPDX headers on every
  owned source file).
- `CONTRIBUTING.md` describing the merge bar.
- `CHANGELOG.md` (this file).
- `.editorconfig` and `.gitattributes` for consistent line endings /
  indentation. `.gitattributes` covers `.weave`, `.wir`,
  `.expected.ll`, `.expected.wir`, `.c`, `.h` in addition to the
  weavec1 baseline.
- GitHub Actions CI matrix (`ubuntu-latest`, `macos-latest`) that
  fetches the pinned `weavec0` v0.2.0, `weavec1` v0.1.0, and
  `weavefront` v0.1.0 dependencies and runs the full ladder.

### Changed
- `build.sh` no longer assumes `../weavec0/`, `../weavec1/`, and
  `../weavefront/` siblings. It now honours `WEAVEC0`, `WEAVEC1`,
  and `WEAVEFRONT` env vars (paths to existing source trees); when
  unset, it git-clones the pinned `WEAVEC0_TAG` (default `v0.2.0`),
  `WEAVEC1_TAG` (default `v0.1.0`), and `WEAVEFRONT_TAG` (default
  `v0.1.0`) from GitHub into `build/vendor/`. Vendored copies are
  gitignored. weavec1 is built with `WEAVEC0` pre-set; weavefront
  with both `WEAVEC0` and `WEAVEC1` pre-set, so each dependency
  builds exactly once.

### Fixed
- Loop-phi LLVM codegen produces invalid SSA for four interacting
  patterns: (a) multi-set in the same do block, (b) `let`-binding
  inside the loop body, (c) outer-if then-do containing a nested if
  that doesn't touch the loop-carried local, and (d) if-branch
  terminating with a return. The fix gates the mode-3 promotion on
  per-pattern predicates and lands a small correction in
  `emit_if_loop_phi_merges` for the nested-if-without-participation
  case. Selfhost compilation of `build/weavec2.wir` now produces
  LLVM IR that `llvm-as` accepts and `opt -passes=mem2reg`
  verifies. See commit `2b2ed22`.
- `emit_function` and `emit_extern_decl` now handle the
  `(params ())` form produced by surface lowering (alongside the
  canonical `(params)`). Previously triggered a segfault in
  `parse_type` via a -1 sentinel. See commit `bb7bec1`.

### Known limitations
- **`selfhost.sh` is incomplete.** `test/selfhost/test.sh` (run by
  `./test-all.sh`) passes: the weavec2 binary compiles
  `build/weavec2.wir` and the output verifies through `llvm-as` and
  `opt -passes=mem2reg`. The deeper `./selfhost.sh` workflow that
  re-runs the surface → WIR pass with the bootstrapped weavec2
  hits a separate, pre-existing string-constant emission bug
  (`[1 x i8]` array length for a 12-byte string) in the frontend
  surface → WIR pipeline. Fixing that bug is tracked separately.
- **`surface-matrix.sh` reports compile counts**, not pass/fail
  thresholds. It is a development aid, not a CI gate.
- **The vendored dependency caches** at `build/vendor/{weavec0,
  weavec1, weavefront}/` are not auto-updated when their `_TAG`
  pins change. Delete the directories and re-run `./build.sh` to
  refetch.
- **No source-style checker** for `.weave` modules yet — the
  weavec1 checker only validates WIR style. Adding a surface-Weave
  checker is a follow-up.
