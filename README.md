# weavec — Self-Hosted Weave Compiler

[![ci](https://github.com/ahojukka5/weavec/actions/workflows/ci.yml/badge.svg)](https://github.com/ahojukka5/weavec/actions/workflows/ci.yml)
[![release](https://github.com/ahojukka5/weavec/actions/workflows/release.yml/badge.svg)](https://github.com/ahojukka5/weavec/actions/workflows/release.yml)

> The user-facing Weave compiler, written in surface Weave. It combines surface
> lowering and WIR-to-LLVM emission in one self-hosted binary.

This repository was previously named `weavec2`. It is now simply `weavec`
because it is the final compiler product.

## Compiler chain

```text
weavec0 → weavec1 → weavec-bootstrap → weavec
```

| Component | Repository | Role |
|---|---|---|
| `weavec0` | [`ahojukka5/weavec0`](https://github.com/ahojukka5/weavec0) | Hand-written LLVM-IR seed and Stage 0 SDK. |
| `weavec1` | [`ahojukka5/weavec1`](https://github.com/ahojukka5/weavec1) | WIR-to-LLVM compiler and Stage 1 SDK. |
| `weavec-bootstrap` | [`ahojukka5/weavec-bootstrap`](https://github.com/ahojukka5/weavec-bootstrap) | Surface-Weave-to-WIR bootstrap frontend and parser SDK. |
| `weavec` | **this repository** | User-facing self-hosted compiler. |

Normal users should interact only with `weavec`.

## Install a release binary

Release `v0.2.0` publishes static Linux x86-64 archives for glibc and musl:

```text
weavec-vX.Y.Z-linux-x86_64-<libc>/
├── bin/weavec
├── BUILD-MANIFEST
├── VERSION
├── README.md
├── LICENSE
└── NOTICE
```

The compiler binary itself does not require LLVM, Python, or any bootstrap
repository. LLVM tools are needed only when assembling or linking emitted LLVM
IR.

After extracting an archive:

```sh
./bin/weavec --frontend output.wir input.weave
./bin/weavec --backend output.wir output.ll
```

Release downloads include `SHA256SUMS`. The musl archive is the most portable
choice for Linux systems; the glibc archive uses the standard GNU libc runtime.
See [`docs/RELEASING.md`](docs/RELEASING.md).

## Build from source

Linux x86-64 source builds consume published, checksum-verified SDKs. They need:

- Bash 4 or newer;
- LLVM and Clang 14 or newer;
- `curl`, `tar`, `sha256sum`, and Python 3.

```sh
sudo apt-get install -y clang curl llvm python3

git clone https://github.com/ahojukka5/weavec.git
cd weavec
./build.sh
./test-all.sh
```

macOS currently uses the pinned source fallback:

```sh
brew install llvm git
export PATH="$(brew --prefix llvm)/bin:$PATH"
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

There are no current `weavec2` or `weavefront` compatibility aliases.

## Command line

```text
weavec --backend <input.wir> <output.ll>
weavec --frontend [--strict-contracts] <output.wir> <input.weave> [input2.weave ...]
weavec --dump-quantum-stats <output.metrics> <input.weave>
weavec --explain <input.weave>
weavec --explain-json <input.weave>
weavec --audit <input.weave>
weavec --audit-json <input.weave>
```

Backend compilation is intentionally explicit. The former
`weavec input.wir output.ll` spelling is rejected.

## SDK-first bootstrap

The normal Linux build downloads:

- `weavec1 v0.2.0` for WIR-to-LLVM compilation;
- `weavec-bootstrap v0.2.0` for surface lowering and
  `libweave-sexpr.bc`.

Both archives are selected for `glibc` or `musl`, verified against release
checksums, and cached under `build/vendor/*-sdk/`. The normal Linux path does not
clone or build `weavec0`, `weavec1`, or `weavec-bootstrap` from source.

Environment overrides:

- `WEAVEC1_SDK=/path/to/sdk` or `WEAVEC1_VERSION=vX.Y.Z`;
- `WEAVEC1_LIBC=glibc|musl`;
- `WEAVEC_BOOTSTRAP_SDK=/path/to/sdk` or
  `WEAVEC_BOOTSTRAP_VERSION=vX.Y.Z`;
- `WEAVEC_BOOTSTRAP_LIBC=glibc|musl`;
- `WEAVEC1=/path/to/source` and `WEAVEC_BOOTSTRAP=/path/to/source` force source
  dependencies;
- `WEAVEC_BACKEND=/path/to/weavec` selects an existing self-hosted backend.

Unsupported hosts fall back to the pinned source refs. Stage 0 is resolved only
when the Stage 1 source fallback must be built.

## Parser-library boundary

The parser implementation sources remain in `weavec-bootstrap`:

```text
sexpr_tokens.wir
sexpr_tree.wir
sexpr_lexer.wir
sexpr_parser.wir
```

Downstream code does not consume their generated `.ll` files individually. The
published boundary is one artifact:

```text
weavec-bootstrap SDK/lib/libweave-sexpr.bc
```

`weavec` links that library as a unit. The bootstrap executable also owns its
main-thread stack requirement; this repository does not rewrite dependency
build scripts.

## Build pipeline

`./build.sh`:

1. resolves the `weavec1` SDK or source fallback;
2. resolves the `weavec-bootstrap` SDK or source fallback;
3. lowers the ordered compiler sources into `build/weavec.wir`;
4. compiles WIR to `build/weavec.ll` with `weavec1` or `WEAVEC_BACKEND`;
5. links the compiler with `libweave-sexpr.bc`;
6. links the development `build/weavec` executable with
   `runtime/portable.c`.

Release packaging relinks `build/weavec.bc` into separate static glibc and musl
executables. The module order in `build.sh` and `selfhost.sh` is part of the
deterministic bootstrap contract.

## Tests

`./test-all.sh` runs:

| Bucket | Driver | Count |
|---|---|---:|
| Correctness and end-to-end surface/WIR tests | `test.sh` | 125 |
| Performance LLVM goldens | `test/performance/test.sh` | 168 |
| Quantum validation | `test/quantum/test.sh` | 4 |
| Quantum end to end | `test/quantum/test-e2e.sh` | 1 |
| Basic self-host | `test/selfhost/test.sh` | 1 |

The correctness count includes the CLI regression proving that implicit backend
syntax remains rejected.

CI validates Linux glibc SDKs, Linux musl SDKs, and the macOS source fallback.
The release workflow additionally builds, inspects, strips, smokes, and archives
both static Linux compiler variants.

Regenerate performance goldens only after an intentional backend-output change:

```sh
./test/performance/regen-golden.sh
git diff -- test/performance
```

## Deeper self-host

```sh
./selfhost.sh
```

This builds `build/selfhost/stage1/weavec` and
`build/selfhost/stage2/weavec`, then runs stage-2 fixture smokes. It remains a
local release and architecture check because it rebuilds the large compiler
multiple times.

## Repository layout

```text
weavec/
├── build.sh
├── test.sh
├── test-all.sh
├── selfhost.sh
├── surface-matrix.sh
├── VERSION
├── scripts/package-linux-release.sh
├── src/{core,frontend,llvm}/
├── runtime/
├── scripts/
├── docs/
└── test/{correctness,performance,quantum,selfhost}/
```

## Known limitations

- Published compiler binaries currently cover Linux x86-64 only.
- `surface-matrix.sh` reports counts rather than enforcing thresholds.
- There is no dedicated source-style checker for `.weave` modules yet.
- `runtime/quantum_runtime.c` is a test stub, not a production quantum runtime.
- The deeper self-host flow is local-only because of build cost.

## License

Licensed under the Apache License, Version 2.0. See [`LICENSE`](LICENSE) and
[`NOTICE`](NOTICE).

## Contributing

Read [`CONTRIBUTING.md`](CONTRIBUTING.md),
[`docs/RELEASING.md`](docs/RELEASING.md), and the relevant design document before
changing the surface contract, backend output, source ordering, or bootstrap
boundary.
