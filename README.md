# weavec — self-hosted Weave compiler

[![ci](https://github.com/ahojukka5/weavec/actions/workflows/ci.yml/badge.svg)](https://github.com/ahojukka5/weavec/actions/workflows/ci.yml)
[![release](https://github.com/ahojukka5/weavec/actions/workflows/release.yml/badge.svg)](https://github.com/ahojukka5/weavec/actions/workflows/release.yml)

`weavec` is the user-facing Weave compiler, written primarily in surface Weave.
It owns the complete source-to-executable product flow while retaining explicit
frontend and backend modes for compiler development and reproducible
bootstrapping.

This repository was named `weavec2` through release `v0.1.2`. It is now simply
`weavec` because it is the final compiler product.

## Compiler chain

```text
weavec0 → weavec1 → weavec-bootstrap → weavec
```

| Component | Role |
|---|---|
| [`weavec0`](https://github.com/ahojukka5/weavec0) | Minimal hand-written LLVM-IR seed and Stage 0 SDK. |
| [`weavec1`](https://github.com/ahojukka5/weavec1) | Complete stable WIR core version 2 to LLVM backend and Stage 1 SDK. |
| [`weavec-bootstrap`](https://github.com/ahojukka5/weavec-bootstrap) | Frozen surface-Weave to WIR core version 2 bootstrap frontend and parser SDK. |
| `weavec` | Evolving user-facing compiler, self-hosted frontend/backend, native build driver, diagnostics, and package runtime boundary. |

Normal users interact only with `weavec`. The three lower repositories are
frozen bootstrap infrastructure.

## Build a native program

```sh
weavec build main.weave -o main
./main
```

Multi-file programs use the same command:

```sh
weavec build main.weave library.weave platform.weave -o application
```

The compiler performs:

```text
surface Weave
    ↓ frontend
WIR core version 3
    ↓ backend
raw LLVM IR
    ↓ explicit LLVM optimization
optimized LLVM IR
    ↓ target code generation
native object
    + private target runtime
    ↓ target linker
executable
```

The seed and the self-hosted generations use **different** WIR versions, and
cannot share one: `weavec-bootstrap v0.3.1` and `weavec1 v0.3.2` are frozen
releases that construct the seed across core version 2, and the resulting
compiler emits and consumes core version 3 itself. The two boundaries never
meet. See [Architecture](docs/architecture.md) and
[WIR core version 3](docs/wir.md).

Intermediate files live in a private temporary directory. The linker writes a
temporary executable beside the requested output, and the compiler publishes it
with an atomic rename only after every phase succeeds. A failed build does not
replace an existing output.

See the complete [command reference](docs/command-reference.md).

## Automation contracts

A native build can emit three independent versioned JSON documents:

```sh
weavec build main.weave -o main \
  --manifest-json main.build.json \
  --diagnostics-json main.diagnostics.json \
  --trace-json main.trace.json
```

- [`weavec-build-manifest-v1`](docs/build-manifest.md) records the final phase,
  target, compiler, private runtime, code generator, linker, output, and ordered
  source paths.
- [`weavec-diagnostics-v1`](docs/diagnostics.md) provides stable phase exit codes,
  classified errors, and trustworthy source spans while preserving
  human-readable stderr.
- [`weavec-compilation-trace-v1`](docs/compilation-trace.md) records deterministic,
  source-linked lowering, rewrite, optimization, and contract-check events.

The executable and requested JSON output paths must all be different.

External tooling can also request stable intermediate artifacts:

```sh
weavec build main.weave -o main \
  -O3 --native \
  --emit-wir main.wir \
  --emit-llvm main.raw.ll \
  --emit-optimized-llvm main.optimized.ll \
  --emit-assembly main.s \
  --emit-disassembly main.disasm \
  --optimization-record main.opt.yaml \
  --llvm-provenance
```

The compiler publishes WIR and raw LLVM at their completed phases, then exposes
LLVM-optimized IR, target assembly, optimization remarks, and disassembly from
the final linked executable. Later failures do not erase completed evidence.
Report generation,
visualization, JSON parsing, and LLM-assisted review belong in tooling such as
`weave-loupe`, not in the compiler. See
[Tooling artifact outputs](docs/tooling-artifacts.md),
[Native optimization and machine-code evidence](docs/native-code-evidence.md),
and [LLVM source provenance and quality budgets](docs/llvm-provenance.md).

## Private target runtime

Runtime support is part of the compiler product but is not a user-managed API.
A release package stores one target runtime at:

```text
lib/weavec/<target-triple>/libweave-runtime.a
```

`weavec build` discovers the archive relative to the running compiler. A source
checkout may use `runtime/program.c` as a development fallback. `--runtime` and
`WEAVEC_RUNTIME` exist only for compiler development.

The runtime is a static archive, so the target linker pulls in only referenced
objects. Future packages can add target directories without changing the public
build command.

## Install a release

Published Linux x86-64 archives are provided separately for glibc and musl. Each
archive contains:

```text
weavec-vX.Y.Z-linux-x86_64-<libc>/
├── bin/weavec
├── lib/weavec/<target-triple>/libweave-runtime.a
├── BUILD-MANIFEST
├── VERSION
├── README.md
├── LICENSE
└── NOTICE
```

After extracting, add the package `bin` directory to `PATH`. The current driver
uses installed LLVM tools internally:

- glibc package: `clang` for LLVM IR optimization, `llc` for target code
  generation, and `clang` for linking;
- musl package: `clang` for LLVM IR optimization, `llc` for target code
  generation, and `musl-gcc` for linking;
- `llvm-objdump` is required only when `--emit-disassembly` is requested.

Release downloads include `SHA256SUMS`. See the reusable
[release procedure](docs/releasing.md).

## Build from source

Linux x86-64 source builds consume checksum-verified published SDKs. Required
tools are Bash 4 or newer, LLVM/Clang 14 or newer, `curl`, `tar`, `sha256sum`, and
Python 3.

```sh
git clone https://github.com/ahojukka5/weavec.git
cd weavec
./build.sh
./test-all.sh
```

macOS uses the matching published native SDKs:

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

## SDK-first seed bootstrap

The normal seed build downloads host-matched, checksum-verified lower-stage SDKs:

- `weavec1 v0.3.2`, a frozen WIR core version 2 to LLVM backend, for the seed;
- `weavec-bootstrap v0.3.1` for surface-to-WIR-v2 lowering and the multifile
  bootstrap driver.

The selected glibc, musl, or macOS archives are cached under `build/vendor/`.
The normal build does not clone or rebuild `weavec0`, `weavec1`, or
`weavec-bootstrap` from source.

The bootstrap frontend necessarily has a parser with which to read the final
compiler sources, but that lower-stage parser is a build tool rather than a
runtime component of the resulting compiler. The parser that ships in `weavec`
lives under `src/parser/` and is lowered from surface Weave together with every
other compiler source. Lower-stage parser bitcode is not linked into final
`weavec`, and deep self-hosting recompiles the same parser source at every stage.

## Low-level compiler modes

The public build command is supplemented by explicit compiler interfaces:

```text
weavec --frontend [--strict-contracts] <output.wir> <input.weave> [input2.weave ...]
weavec --backend <input.wir> <output.ll>
weavec --dump-quantum-stats <output.metrics> <input.weave>
weavec --explain <input.weave>
weavec --explain-json <input.weave>
weavec --audit <input.weave>
weavec --audit-json <input.weave>
```

The self-hosted `--frontend` emits WIR core version 3 for the self-hosted
`--backend`. The former implicit `weavec input.wir output.ll` backend spelling is
rejected.

See the [command reference](docs/command-reference.md),
[language reference](docs/language-reference.md), and
[contracts and audit guide](docs/contracts-and-explain.md).

## Tests and self-hosting

`./test-all.sh` builds the compiler and runs:

- direct WIR and surface correctness tests;
- performance LLVM goldens;
- quantum lowering and optimization tests;
- quantum runtime end-to-end tests;
- quantum LLVM validation;
- basic self-host integration tests.

CI executes the full ladder with Linux glibc SDKs and Linux musl SDKs. macOS is
a supported build host and is exercised locally, but no macOS job runs in CI.

Deep self-hosting is a separate permanent CI and release gate:

```sh
./build.sh
./selfhost.sh
```

It builds:

```text
build/selfhost/stage1/weavec
build/selfhost/stage2/weavec
```

Both generations use the same core version 3 frontend/backend boundary. Stage 2 must
reproduce representative surface WIR and native behavior.

## Current limitations

- Published compiler packages currently cover Linux x86-64 only.
- Each package installs one native target; `--target` rejects absent targets.
- Object generation and target linking use installed commands rather than a
  bundled LLVM toolchain.
- Some backend diagnostics still use conservative unique-token inference because
  exact locations are not yet propagated through WIR.
- `runtime/quantum_runtime.c` is a test stub, not a production quantum runtime.
- Surface Weave remains pre-1.0 and continues to evolve in this repository.

## Documentation

Start with [`docs/index.md`](docs/index.md). Primary references are:

- [Architecture](docs/architecture.md)
- [Command reference](docs/command-reference.md)
- [Surface language reference](docs/language-reference.md)
- [Build manifests](docs/build-manifest.md)
- [Machine-readable diagnostics](docs/diagnostics.md)
- [Releasing](docs/releasing.md)

Files under `docs/` use lowercase kebab-case names. Conventional root metadata
retains standard uppercase names.

## Contributing

Read [`CONTRIBUTING.md`](CONTRIBUTING.md) and the relevant design or protocol
document before changing surface syntax, backend output, source ordering,
runtime boundaries, automation schemas, target packaging, emitted WIR, or
bootstrap pins.

## License

Licensed under the Apache License, Version 2.0. See [`LICENSE`](LICENSE) and
[`NOTICE`](NOTICE).
