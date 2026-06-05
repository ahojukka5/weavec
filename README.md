# weavec2 — Weave Surface-Language Compiler (self-hosted)

[![ci](https://github.com/ahojukka5/weavec2/actions/workflows/ci.yml/badge.svg)](https://github.com/ahojukka5/weavec2/actions/workflows/ci.yml)

> The self-hosted Weave compiler. **Written in surface Weave**,
> bootstrapped by [`weavefront`](https://github.com/ahojukka5/weavefront)
> (surface → WIR) and [`weavec1`](https://github.com/ahojukka5/weavec1)
> (WIR → LLVM IR), then linked with [`weavec0`](https://github.com/ahojukka5/weavec0)'s
> runtime.

## Overview

The Weave compiler chain is split across separate stages that each do
one thing well:

```
.weave  ──[ weavefront ]──>  .wir  ──[ weavec1 / weavec2 ]──>  .ll  ──[ clang ]──>  exe
```

`weavec2` is the **top** of the chain. It is the first compiler in
the family to be written in **surface Weave** (the user-facing
syntax), not in WIR or LLVM IR. Once built, it can compile any
surface-Weave program — including, eventually, itself end-to-end
through the surface pipeline.

What's inside:

- **Frontend** (`src/frontend/`) — surface Weave → WIR lowering,
  including struct declarations, quantum-op normalisation, and
  driver glue.
- **Backend** (`src/llvm/`) — WIR → LLVM IR emission, including a
  loop-phi optimisation pass for direct SSA codegen of loop-carried
  scalars.
- **Core** (`src/core/`) — shared helpers: C-runtime externs,
  byte-write I/O, s-expression tree navigation.

See [`docs/`](docs/) for design notes on the loop-phi contract,
LLVM codegen, quantum syntax, and the representation-lowering
bridge.

---

## Prerequisites

`weavec2` builds with a standard LLVM toolchain plus `git`:

- `clang`, `llvm-as`, `llvm-link` — LLVM 14 or newer (opaque pointers).
- `git` — to fetch the pinned dependencies on first build.
- `bash` 4 or newer.

Installation hints:

```sh
# Debian / Ubuntu
sudo apt-get install -y llvm clang git

# macOS (Homebrew)
brew install llvm git
export PATH="$(brew --prefix llvm)/bin:$PATH"
```

CI runs on `ubuntu-latest` and `macos-latest` against the
package-manager LLVMs.

---

## Quick start

```sh
git clone https://github.com/ahojukka5/weavec2.git
cd weavec2
./build.sh
./test-all.sh
```

**Note**: the first `./build.sh` is slower than subsequent runs —
it also clones and builds the pinned `weavec0`, `weavec1`, and
`weavefront` tags into `build/vendor/`. Re-runs reuse the cached
vendor copies.

---

## Repository layout

```text
weavec2/
  build.sh                    # build driver
  test.sh                     # correctness tests
  test-all.sh                 # full ladder (build + all test buckets)
  selfhost.sh                 # deeper stage1/stage2 bootstrap (experimental)
  surface-matrix.sh           # surface-corpus health probe
  src/
    main.weave                # entry point
    core/                     # extern.weave, io.weave, util.weave
    frontend/                 # surface → WIR (lower, emit, struct,
                              # quantum_nativize, driver, ...)
    llvm/                     # WIR → LLVM IR (ctx, types, locals,
                              # strings, expr, loop-phi, stmt, fn,
                              # module)
  test/
    correctness/              # 124 cases (.weave + .wir fixtures)
    performance/              # 168 cases (.wir + .expected.ll goldens)
    quantum/                  # validation + e2e quantum-op tests
    selfhost/                 # weavec2 recompiles its own .wir
  runtime/quantum_runtime.c   # tiny C runtime for quantum e2e tests
  scripts/                    # performance-golden analyzer helpers
  docs/                       # design notes
  build/                      # build outputs (gitignored)
    vendor/{weavec0,weavec1,weavefront}/   # auto-fetched dependencies
```

---

## Build

```sh
./build.sh
```

Environment overrides:

- `WEAVEC0=/path/to/weavec0` — point at an existing weavec0 source
  tree. Skips the vendor fetch.
- `WEAVEC1=/path/to/weavec1` — same idea for weavec1.
- `WEAVEFRONT=/path/to/weavefront` — same idea for weavefront.
- `WEAVEC0_TAG=vX.Y.Z` — change the pinned weavec0 tag (default
  `v0.2.0`). Delete `build/vendor/weavec0/` to force a refetch.
- `WEAVEC1_TAG=vX.Y.Z` — same idea for weavec1 (default `v0.1.0`).
- `WEAVEFRONT_TAG=vX.Y.Z` — same idea for weavefront (default
  `v0.1.0`).

The script:

1. **Resolves weavec0** — via env or git-clone into
   `build/vendor/weavec0/`. We need it for `runtime.c`.
2. **Resolves weavec1** — via env or git-clone, then builds it
   with `WEAVEC0=$WEAVEC0_DIR` pre-set so the dependency isn't
   built twice.
3. **Resolves weavefront** — via env or git-clone, then builds it
   with both `WEAVEC0` and `WEAVEC1` pre-set.
4. **Concatenates `src/**/*.weave`** into `build/weavec2.wir` via
   `weavefront-cat.sh`.
5. **Compiles `weavec2.wir` → `weavec2.ll`** with weavec1.
6. **Links** with weavefront's parser-runtime modules
   (`sexpr_*.ll`) and weavec0's `runtime.c` into `build/weavec2`.

---

## Tests

`./test-all.sh` runs the full ladder:

| Bucket | Driver | Count |
|--------|--------|------:|
| Correctness (surface + WIR end-to-end) | `test.sh` | 124 |
| Performance (WIR + golden LLVM IR) | `test/performance/test.sh` | 168 |
| Quantum validation | `test/quantum/test.sh` | 4 |
| Quantum e2e (links `runtime/quantum_runtime.c`) | `test/quantum/test-e2e.sh` | 1 |
| Self-host basic (recompile `build/weavec2.wir`) | `test/selfhost/test.sh` | 1 |

A passing run ends with `all weavec2 checks passed`.

### Performance goldens

`test/performance/test.sh` diffs emitted LLVM against checked-in
`*.expected.ll` fixtures. Regenerate with:

```sh
./test/performance/regen-golden.sh
```

Review the resulting `git diff` before committing.

### Self-host workflows

- `test/selfhost/test.sh` (run by `./test-all.sh`) is the basic
  self-host gate: weavec2 compiles its own bootstrapped
  `build/weavec2.wir`, and the output is accepted by `llvm-as` and
  verified by `opt -passes=mem2reg`. This passes.
- `./selfhost.sh` is the deeper bootstrap flow: re-run the
  surface → WIR pass with the bootstrapped weavec2 and rebuild
  through stages 1 → 2, then run three fixture smoke tests
  against the stage2 binary. Passes end-to-end after the call-site
  guards, `main`-first codegen, and pass-2 `main.weave` ordering
  (see [`CHANGELOG.md`](CHANGELOG.md)).
  Not in CI — local-only since it builds weavec2 three times.
- `./build.sh` uses `weavefront-cat` for `build/weavec2.wir` and,
  when `build/selfhost/stage2/weavec2` exists, compiles that WIR with
  `weavec2 --backend` instead of weavec1. Override with
  `WEAVEC2_BACKEND=/path/to/weavec2 ./build.sh`.
- `./selfhost.sh` uses the same `SOURCES` order as `build.sh`
  (`main.weave` last). Pass-2 lowering emits `main.weave` first;
  the backend emits `(fn main ...)` before other functions in LLVM.

### surface-matrix.sh

`./surface-matrix.sh` walks `test/correctness/surface/` and reports
how many cases each pipeline stage (frontend, backend, llvm-as,
clang, run) accepts. It's a development health probe, not a
pass/fail gate.

---

## Examples

Suggested entry points for first-time readers:

- [`test/correctness/surface/01_return_constant.weave`](test/correctness/surface/01_return_constant.weave)
  — the smallest possible surface program.
- [`test/correctness/surface/07_if.weave`](test/correctness/surface/07_if.weave)
  — branching.
- [`test/correctness/surface/08_while.weave`](test/correctness/surface/08_while.weave)
  — loops and mutable locals.
- [`test/correctness/surface/57_struct_basic.weave`](test/correctness/surface/57_struct_basic.weave)
  — struct declarations and their lowered getter / setter accessors.
- [`test/quantum/`](test/quantum) — surface quantum operations
  (`qgate`, `qmeasure`) and their nativised WIR.

---

## Where weavec2 fits in the chain

The Weave compiler chain spans four separate repositories:

| Stage | Repo | Role |
|-------|------|------|
| `weavec0` | [`ahojukka5/weavec0`](https://github.com/ahojukka5/weavec0) | Hand-written LLVM-IR seed compiler. Compiles WIR → LLVM. Tiny, frozen. |
| `weavec1` | [`ahojukka5/weavec1`](https://github.com/ahojukka5/weavec1) | WIR-written compiler. Compiled by weavec0. Same WIR → LLVM contract, self-hosted. |
| `weavefront` | [`ahojukka5/weavefront`](https://github.com/ahojukka5/weavefront) | Surface → WIR frontend. Written in WIR, compiled by weavec1. |
| `weavec2` | **this repo** | Surface-Weave compiler (self-hosted). Same end-to-end role as `weavefront + weavec1` but in one binary written in surface Weave. |

Eventually `weavec2` should replace the `weavefront + weavec1`
chain for surface inputs entirely. Until then both pipelines
coexist; weavec2 is bootstrapped through the older one.

---

## Known limitations

These are intentional scope choices — not bugs:

- **No source-style checker for `.weave` modules yet.** The
  weavec1 checker only validates WIR style. A surface-Weave
  checker is a follow-up.
- **`surface-matrix.sh` reports compile counts**, not pass/fail
  thresholds. Development health probe, not a CI gate.
- **The vendored dependency caches** at `build/vendor/{weavec0,
  weavec1, weavefront}/` are not auto-updated when their `_TAG`
  pins change. Delete the directories and re-run `./build.sh` to
  refetch.
- **`runtime/quantum_runtime.c` is a stub.** It implements just
  enough surface area for the quantum e2e test (`test/quantum/`)
  to link. Not a production quantum runtime.

---

## License

Licensed under the Apache License, Version 2.0. See
[`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).

## Contributing

Pull requests and issues are welcome. The merge bar is described in
[`CONTRIBUTING.md`](CONTRIBUTING.md) — please read it, and the
**Known limitations** section above, before opening a PR.
