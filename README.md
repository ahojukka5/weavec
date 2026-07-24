# weavec2 — Self-Hosted Weave Compiler

[![ci](https://github.com/ahojukka5/weavec2/actions/workflows/ci.yml/badge.svg)](https://github.com/ahojukka5/weavec2/actions/workflows/ci.yml)

> The compiler written in surface Weave. It combines surface lowering and WIR
> to LLVM emission in one self-hosted binary.

## Overview

The split bootstrap chain is:

```text
.weave
   ↓
weavefront
   ↓
 .wir
   ↓
weavec1
   ↓
 .ll
```

`weavec2` implements the same end-to-end surface compiler role in one binary:

```text
.weave
   ↓
weavec2
   ↓
 .wir or .ll
```

The repository contains:

- `src/frontend/` for surface validation, lowering, contracts, audit output,
  structs, and quantum rewrites;
- `src/llvm/` for WIR-to-LLVM emission and loop-phi handling;
- `src/core/` for shared tree, I/O, and runtime helpers;
- `src/main.weave` for the combined command-line entry point.

Design notes live under [`docs/`](docs/).

## Bootstrap status

The compiler is written in surface Weave and is initially bootstrapped through
`weavefront + weavec1`.

Two self-host levels are available:

- `test/selfhost/test.sh` recompiles `build/weavec2.wir` with the freshly built
  compiler and verifies the result with LLVM tools;
- `./selfhost.sh` performs the deeper stage1-to-stage2 flow and runs fixture
  smoke tests against the stage2 compiler.

Both flows pass. The deeper flow is not part of normal CI because it builds the
large compiler repeatedly; it is no longer blocked by the historical
string-constant bug described in older changelog entries.

## Prerequisites

- Bash 4 or newer;
- LLVM and Clang 14 or newer;
- Git for the current source-bootstrap dependencies.

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
git clone https://github.com/ahojukka5/weavec2.git
cd weavec2
./build.sh
./test-all.sh
```

The first build fetches pinned source releases into `build/vendor/`. Later
builds reuse those directories.

## Why this repository still uses source bootstrap

`weavec0` and `weavec1` now publish Linux x86-64 bootstrap SDKs, and
`weavefront` consumes the Stage 1 SDK on Linux. `weavec2` currently retains a
source-bootstrap path because it needs more than the compiler executables:

- the `weavefront` executable;
- `weavefront-cat.sh` for multifile lowering;
- generated parser modules such as `sexpr_tokens.ll`, `sexpr_tree.ll`,
  `sexpr_lexer.ll`, and `sexpr_parser.ll`;
- the Stage 0 runtime source used by the current final link.

Those frontend build products are not yet published as a versioned SDK. Until
that package exists, cloning the pinned source releases is the explicit and
documented bootstrap behavior rather than an accidental fallback.

## Build configuration

```sh
./build.sh
```

Current source pins:

- `WEAVEC0_TAG=v0.2.0`;
- `WEAVEC1_TAG=v0.1.0`;
- `WEAVEFRONT_TAG=v0.1.0`.

Overrides:

- `WEAVEC0=/path/to/weavec0` uses an existing Stage 0 source tree;
- `WEAVEC1=/path/to/weavec1` uses an existing Stage 1 source tree;
- `WEAVEFRONT=/path/to/weavefront` uses an existing frontend source tree;
- the corresponding `_TAG` variables select different source refs;
- `WEAVEC2_BACKEND=/path/to/weavec2` selects a self-hosted WIR backend.

Delete a cached `build/vendor/<dependency>/` directory when intentionally
changing a tag. The current vendor cache does not automatically switch refs.

## Build pipeline

`build.sh` performs these steps:

1. resolve and build the pinned `weavec0` source tree;
2. resolve and build `weavec1` with that Stage 0 tree;
3. resolve and build `weavefront` with the same lower stages;
4. concatenate `src/**/*.weave` into `build/weavec2.wir`;
5. compile WIR to LLVM IR with `weavec1` or `WEAVEC2_BACKEND`;
6. link the compiler with the frontend parser LLVM modules and
   `runtime/portable.c` support;
7. produce `build/weavec2`.

When `build/selfhost/stage2/weavec2` exists, the build may auto-select it as the
backend. An explicit `WEAVEC2_BACKEND` overrides this selection.

## Repository layout

```text
weavec2/
├── build.sh
├── test.sh
├── test-all.sh
├── selfhost.sh
├── surface-matrix.sh
├── src/
│   ├── core/
│   ├── frontend/
│   ├── llvm/
│   └── main.weave
├── test/
│   ├── correctness/
│   ├── performance/
│   ├── quantum/
│   └── selfhost/
├── runtime/
│   ├── portable.c
│   └── quantum_runtime.c
├── scripts/
├── docs/
└── build/
    └── vendor/{weavec0,weavec1,weavefront}/
```

## Tests

`./test-all.sh` runs:

| Bucket | Driver | Count |
|---|---|---:|
| Correctness, surface and WIR end to end | `test.sh` | 124 |
| Performance WIR and LLVM goldens | `test/performance/test.sh` | 168 |
| Quantum validation | `test/quantum/test.sh` | 4 |
| Quantum end to end | `test/quantum/test-e2e.sh` | 1 |
| Basic self-host | `test/selfhost/test.sh` | 1 |

A successful run ends with:

```text
all weavec2 checks passed
```

### Performance goldens

Regenerate only after an intentional backend change:

```sh
./test/performance/regen-golden.sh
git diff -- test/performance
```

### Deeper self-host

```sh
./selfhost.sh
```

This rebuilds the compiler through later generations and runs stage2 fixture
smokes. It is a local release and architecture check, not a normal CI job.

### Surface matrix

```sh
./surface-matrix.sh
```

The matrix reports how many surface fixtures reach each pipeline stage. It is a
development health report, not a pass/fail gate.

## Command roles

The combined binary supports several modes used across the repository:

- surface lowering to WIR;
- WIR backend emission to LLVM IR;
- full surface compilation;
- explanation and audit output;
- contract and effect analysis.

Use the test fixtures as the authoritative examples for admitted forms and
mode-specific command behavior.

## Examples

Useful starting points:

- [`test/correctness/surface/01_return_constant.weave`](test/correctness/surface/01_return_constant.weave)
- [`test/correctness/surface/07_if.weave`](test/correctness/surface/07_if.weave)
- [`test/correctness/surface/08_while.weave`](test/correctness/surface/08_while.weave)
- [`test/correctness/surface/57_struct_basic.weave`](test/correctness/surface/57_struct_basic.weave)
- [`test/quantum/`](test/quantum)

The complete surface corpus under `test/correctness/surface/` is also the
syntax reference used by the external `weave-mcp` grammar help.

## Compiler chain

| Stage | Repository | Role |
|---|---|---|
| `weavec0` | [`ahojukka5/weavec0`](https://github.com/ahojukka5/weavec0) | Hand-written Stage 0 compiler and bootstrap SDK. |
| `weavec1` | [`ahojukka5/weavec1`](https://github.com/ahojukka5/weavec1) | WIR-written compiler and Stage 1 SDK. |
| `weavefront` | [`ahojukka5/weavefront`](https://github.com/ahojukka5/weavefront) | Split surface-to-WIR bootstrap frontend. |
| `weavec2` | **this repository** | Self-hosted compiler written in surface Weave. |

The long-term direction is for `weavec2` to replace the split
`weavefront + weavec1` path for normal surface inputs while the lower stages
remain available as a small reproducible bootstrap chain.

## Known limitations

- The normal bootstrap still requires source checkouts for all three lower
  repositories because frontend parser build products are not yet packaged.
- `surface-matrix.sh` reports counts rather than enforcing thresholds.
- There is no dedicated source-style checker for `.weave` modules yet.
- `runtime/quantum_runtime.c` is a test stub, not a production quantum runtime.
- The vendor cache must be deleted manually when changing dependency tags.
- The deeper self-host flow is local-only due to build cost.

## License

Licensed under the Apache License, Version 2.0. See [`LICENSE`](LICENSE) and
[`NOTICE`](NOTICE).

## Contributing

Read [`CONTRIBUTING.md`](CONTRIBUTING.md), the known limitations above, and the
relevant design document before changing the surface contract, backend output,
or bootstrap source ordering.
