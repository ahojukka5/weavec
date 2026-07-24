# weavec — Self-Hosted Weave Compiler

[![ci](https://github.com/ahojukka5/weavec/actions/workflows/ci.yml/badge.svg)](https://github.com/ahojukka5/weavec/actions/workflows/ci.yml)

> The user-facing Weave compiler, written in surface Weave. It combines surface
> lowering and WIR-to-LLVM emission in one self-hosted compiler.

This repository was previously named `weavec2`. The shorter name reflects its
actual role: this is the final compiler product. `weavec0`, `weavec1`, and
`weavec-bootstrap` remain as the reproducible bootstrap chain.

## Role

The split bootstrap path is:

```text
.weave
   ↓
weavec-bootstrap
   ↓
 .wir
   ↓
weavec1
   ↓
 .ll
```

`weavec` implements the complete surface compiler role:

```text
.weave
   ↓
 weavec
   ↓
.wir or .ll
```

The repository contains:

- `src/frontend/` for parsing, validation, lowering, contracts, audit output,
  structs, and quantum rewrites;
- `src/llvm/` for WIR-to-LLVM emission and loop-phi handling;
- `src/core/` for shared tree, I/O, and runtime helpers;
- `src/main.weave` for the combined command-line entry point.

Design notes live under [`docs/`](docs/).

## Compiler chain

| Component | Repository | Role |
|---|---|---|
| `weavec0` | [`ahojukka5/weavec0`](https://github.com/ahojukka5/weavec0) | Hand-written Stage 0 seed and SDK. |
| `weavec1` | [`ahojukka5/weavec1`](https://github.com/ahojukka5/weavec1) | WIR compiler and Stage 1 SDK. |
| `weavec-bootstrap` | [`ahojukka5/weavec-bootstrap`](https://github.com/ahojukka5/weavec-bootstrap) | Surface-to-WIR bootstrap frontend, formerly `weavefront`. |
| `weavec` | **this repository** | User-facing self-hosted compiler, formerly `weavec2`. |

```text
weavec0 → weavec1 → weavec-bootstrap → weavec
```

Normal users should interact only with `weavec`. The lower stages exist to make
the compiler reproducible from a small trusted seed.

## Bootstrap status

The compiler is written in surface Weave and is initially built through
`weavec-bootstrap + weavec1`.

Two self-host levels are available:

- `test/selfhost/test.sh` recompiles the bootstrapped WIR with the freshly built
  compiler and verifies the result with LLVM tools;
- `./selfhost.sh` performs the deeper stage1-to-stage2 flow and runs fixture
  smoke tests against the later compiler generation.

Both flows pass. The deeper flow is not in normal CI because it rebuilds the
large compiler repeatedly.

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
git clone https://github.com/ahojukka5/weavec.git
cd weavec
./build.sh
./test-all.sh
```

The current build output retains the historical compatibility path
`build/weavec2`. It is the `weavec` compiler; the old filename remains until
all downstream scripts and release packaging have migrated.

## Why the initial build still uses source bootstrap

`weavec0` and `weavec1` publish Linux bootstrap SDKs, and `weavec-bootstrap`
consumes the Stage 1 SDK on Linux. This repository currently needs additional
frontend build products:

- the bootstrap frontend executable;
- the historical `weavefront-cat.sh` multifile helper;
- generated parser modules such as `sexpr_tokens.ll`, `sexpr_tree.ll`,
  `sexpr_lexer.ll`, and `sexpr_parser.ll`;
- runtime support used by the final link.

Those frontend products are not yet published as one versioned SDK, so the
first-generation build still resolves pinned source releases explicitly.

## Build configuration

```sh
./build.sh
```

Current environment names retain historical compatibility:

- `WEAVEC0` and `WEAVEC0_TAG` select Stage 0;
- `WEAVEC1` and `WEAVEC1_TAG` select Stage 1;
- `WEAVEFRONT` and `WEAVEFRONT_TAG` select `weavec-bootstrap`;
- `WEAVEC2_BACKEND` selects an already built self-hosted `weavec` backend.

The old variable names remain supported because they are part of the current
bootstrap scripts. New prose and repository links use the final component
names.

Delete a cached `build/vendor/<dependency>/` directory when intentionally
changing a source tag; the cache does not automatically switch refs.

## Build pipeline

`build.sh`:

1. resolves and builds the pinned `weavec0` source tree;
2. resolves and builds `weavec1`;
3. resolves and builds `weavec-bootstrap`;
4. combines `src/**/*.weave` into the bootstrapped WIR module;
5. compiles WIR to LLVM IR with `weavec1` or a self-hosted backend;
6. links parser modules and portable runtime support;
7. produces the user-facing compiler at the historical path `build/weavec2`.

When a deeper self-host compiler exists, the build may select it as the backend.
An explicit `WEAVEC2_BACKEND` overrides that selection.

## Repository layout

```text
weavec/
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
├── scripts/
├── docs/
└── build/
    └── vendor/{weavec0,weavec1,weavec-bootstrap}/
```

The physical vendor directory may still be named `weavefront` in existing
builds because the current script retains the compatibility variable names.

## Tests

`./test-all.sh` runs:

| Bucket | Driver | Count |
|---|---|---:|
| Correctness, surface and WIR end to end | `test.sh` | 124 |
| Performance WIR and LLVM goldens | `test/performance/test.sh` | 168 |
| Quantum validation | `test/quantum/test.sh` | 4 |
| Quantum end to end | `test/quantum/test-e2e.sh` | 1 |
| Basic self-host | `test/selfhost/test.sh` | 1 |

A successful run currently ends with the historical message:

```text
all weavec2 checks passed
```

The name in that message is a compatibility detail, not a separate compiler.

### Performance goldens

```sh
./test/performance/regen-golden.sh
git diff -- test/performance
```

Regenerate only after an intentional backend change.

### Deeper self-host

```sh
./selfhost.sh
```

This rebuilds the compiler through later generations and runs stage fixture
smokes. It is a local release and architecture check rather than a normal CI
job.

### Surface matrix

```sh
./surface-matrix.sh
```

The matrix reports how many fixtures reach each pipeline stage. It is a
development health report, not a pass/fail gate.

## Command roles

The combined compiler supports:

- surface lowering to WIR;
- WIR backend emission to LLVM IR;
- full surface compilation;
- explanation and audit output;
- contract and effect analysis.

The fixtures under `test/correctness/surface/` are the authoritative examples
for admitted surface forms and are also indexed by external `weave-mcp` grammar
help.

## Known limitations

- The first-generation bootstrap still requires source checkouts because the
  bootstrap frontend parser products are not yet packaged as an SDK.
- Binary paths, helper scripts, environment variables, and some test output
  still use the historical names `weavec2` and `weavefront` for compatibility.
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
