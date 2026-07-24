# weavec — Self-Hosted Weave Compiler

[![ci](https://github.com/ahojukka5/weavec/actions/workflows/ci.yml/badge.svg)](https://github.com/ahojukka5/weavec/actions/workflows/ci.yml)

> The user-facing Weave compiler, written in surface Weave. It combines surface
> lowering and WIR-to-LLVM emission in one self-hosted binary.

This repository was previously named `weavec2`. It is now simply `weavec`
because it is the final compiler product. The numbered lower stages and
`weavec-bootstrap` exist only to reproduce it from a small trusted seed.

## Compiler chain

```text
weavec0 → weavec1 → weavec-bootstrap → weavec
```

| Component | Repository | Role |
|---|---|---|
| `weavec0` | [`ahojukka5/weavec0`](https://github.com/ahojukka5/weavec0) | Hand-written LLVM-IR seed and Stage 0 SDK. |
| `weavec1` | [`ahojukka5/weavec1`](https://github.com/ahojukka5/weavec1) | WIR-to-LLVM compiler and Stage 1 SDK. |
| `weavec-bootstrap` | [`ahojukka5/weavec-bootstrap`](https://github.com/ahojukka5/weavec-bootstrap) | Surface-Weave-to-WIR bootstrap frontend. |
| `weavec` | **this repository** | User-facing self-hosted compiler. |

Normal users should interact only with `weavec`.

## What the compiler does

```text
.weave source
      ↓
    weavec
      ↓
 WIR or LLVM IR
```

The source tree contains:

- `src/frontend/` — parsing, validation, lowering, contracts, audit output,
  structs, and quantum rewrites;
- `src/llvm/` — WIR-to-LLVM emission and loop-phi handling;
- `src/core/` — shared I/O, tree, and utility code;
- `src/main.weave` — the combined command-line entry point.

## Prerequisites

- Bash 4 or newer;
- LLVM and Clang 14 or newer;
- Git for fetching the pinned bootstrap sources.

Debian or Ubuntu:

```sh
sudo apt-get install -y clang git llvm
```

macOS:

```sh
brew install llvm git
export PATH="$(brew --prefix llvm)/bin:$PATH"
```

## Quick start

```sh
git clone https://github.com/ahojukka5/weavec.git
cd weavec
./build.sh
./test-all.sh
```

The build produces:

```text
build/weavec.wir
build/weavec.ll
build/weavec.bc
build/weavec
```

There are no `weavec2` compatibility aliases.

## Bootstrap dependencies

The initial build uses these pinned components:

- `weavec0 v0.2.1`;
- `weavec1 v0.2.0`;
- `weavec-bootstrap` commit
  `924dba10c8ac75657bd6fe65e9b1e54238f2bc80`.

Environment overrides:

- `WEAVEC0` and `WEAVEC0_TAG` select Stage 0;
- `WEAVEC1` and `WEAVEC1_TAG` select Stage 1;
- `WEAVEC_BOOTSTRAP` and `WEAVEC_BOOTSTRAP_REF` select the bootstrap frontend;
- `WEAVEC_BACKEND` selects an existing self-hosted compiler for WIR-to-LLVM
  emission.

`build.sh` refreshes the vendored `weavec-bootstrap` checkout to the selected
commit. Delete a cached `build/vendor/weavec0` or `build/vendor/weavec1`
directory when intentionally changing those tag pins.

## Parser-library boundary

`weavec-bootstrap` generates four parser implementation modules:

```text
sexpr_tokens.ll
sexpr_tree.ll
sexpr_lexer.ll
sexpr_parser.ll
```

Their **sources belong in `weavec-bootstrap`**, because they implement the
generic S-expression parser used by that frontend. The old design was wrong at
the binary boundary: this repository linked the four generated `.ll` files
individually from another repository's `build/` directory.

The canonical boundary is now one named artifact:

```text
weavec-bootstrap/build/libweave-sexpr.bc
```

`weavec` links that library as a unit. The individual generated parser files are
private build details of `weavec-bootstrap`.

The bootstrap executable also owns its 16 MiB main-thread stack requirement.
`weavec` no longer rewrites or probes the dependency's build script.

## Build pipeline

`./build.sh`:

1. builds or reuses `weavec0`;
2. builds or reuses `weavec1`;
3. checks out and builds the pinned `weavec-bootstrap` revision;
4. lowers the ordered `src/**/*.weave` sources into `build/weavec.wir`;
5. compiles WIR to `build/weavec.ll` with `weavec1` or `WEAVEC_BACKEND`;
6. links `build/weavec.ll` with `libweave-sexpr.bc`;
7. links the final `build/weavec` executable with `runtime/portable.c`.

The source order in `build.sh` and `selfhost.sh` is part of the deterministic
bootstrap contract.

## Tests

`./test-all.sh` runs:

| Bucket | Driver | Count |
|---|---|---:|
| Correctness and end-to-end surface/WIR tests | `test.sh` | 124 |
| Performance LLVM goldens | `test/performance/test.sh` | 168 |
| Quantum validation | `test/quantum/test.sh` | 4 |
| Quantum end to end | `test/quantum/test-e2e.sh` | 1 |
| Basic self-host | `test/selfhost/test.sh` | 1 |

CI runs the complete ladder on Linux and macOS.

Regenerate performance goldens only after an intentional backend-output change:

```sh
./test/performance/regen-golden.sh
git diff -- test/performance
```

## Deeper self-host

```sh
./selfhost.sh
```

This builds:

```text
build/selfhost/stage1/weavec
build/selfhost/stage2/weavec
```

and runs fixture smoke tests through the stage-2 compiler. The deeper flow is a
local release and architecture check because it repeatedly rebuilds the large
compiler.

## Repository layout

```text
weavec/
├── build.sh
├── test.sh
├── test-all.sh
├── selfhost.sh
├── surface-matrix.sh
├── src/{core,frontend,llvm}/
├── runtime/
├── scripts/
├── docs/
└── test/{correctness,performance,quantum,selfhost}/
```

## Known limitations

- The first-generation bootstrap still checks out source repositories; a
  published `weavec-bootstrap` SDK is the next packaging step.
- `surface-matrix.sh` reports counts rather than enforcing thresholds.
- There is no dedicated source-style checker for `.weave` modules yet.
- `runtime/quantum_runtime.c` is a test stub, not a production quantum runtime.
- The deeper self-host flow is local-only because of build cost.

## License

Licensed under the Apache License, Version 2.0. See [`LICENSE`](LICENSE) and
[`NOTICE`](NOTICE).

## Contributing

Read [`CONTRIBUTING.md`](CONTRIBUTING.md) and the relevant document under
[`docs/`](docs/) before changing the surface contract, backend output, source
ordering, or bootstrap boundary.
