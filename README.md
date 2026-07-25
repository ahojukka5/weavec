# weavec — Self-Hosted Weave Compiler

[![ci](https://github.com/ahojukka5/weavec/actions/workflows/ci.yml/badge.svg)](https://github.com/ahojukka5/weavec/actions/workflows/ci.yml)
[![release](https://github.com/ahojukka5/weavec/actions/workflows/release.yml/badge.svg)](https://github.com/ahojukka5/weavec/actions/workflows/release.yml)

> The user-facing Weave compiler, written in surface Weave. It owns the complete
> source-to-executable pipeline while retaining explicit low-level bootstrap
> interfaces for compiler development.

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
| `weavec` | **this repository** | User-facing self-hosted compiler and native build driver. |

Normal users should interact only with `weavec`.

## Public build interface

Compile one or more surface-Weave modules into a native executable:

```sh
weavec build main.weave -o main
./main
```

Multi-file programs use the same command:

```sh
weavec build main.weave library.weave platform.weave -o application
```

The caller does not select or name a runtime library. Internally the command
performs:

```text
surface Weave
    ↓ frontend
WIR
    ↓ backend
LLVM IR
    ↓ LLVM code generation
native object
    + private target runtime
    ↓ target linker
executable
```

Intermediate files are created in a private temporary directory. The final
executable is linked beside the requested output under a temporary name and then
published with an atomic rename. A failed build never replaces the previous
output.

## Automation contracts

A build can emit two separate versioned JSON documents:

```sh
weavec build main.weave -o main \
  --manifest-json main.build.json \
  --diagnostics-json main.diagnostics.json
```

The paths must be different.

### Build manifest

`weavec-build-manifest-v1` records the final status and phase, source paths,
target, compiler, private runtime resource, LLVM code generator, linker, and
output path.

### Machine-readable diagnostics

`weavec-diagnostics-v1` preserves the existing human-readable stderr stream and
adds an automation side channel:

```json
{
  "format": "weavec-diagnostics-v1",
  "status": "failed",
  "phase": "backend",
  "exit_code": 11,
  "raw_exit_code": 1,
  "diagnostics": [
    {
      "code": "backend.unknown-expression-operator",
      "severity": "error",
      "phase": "backend",
      "message": "unknown expression operator: unknown_form",
      "source": "main.weave",
      "span_origin": "inferred-unique-token",
      "span": {
        "start_byte": 109,
        "end_byte": 121,
        "start_line": 6,
        "start_column": 18,
        "end_line": 6,
        "end_column": 30
      }
    }
  ]
}
```

Offsets are UTF-8 byte offsets with an exclusive end. Lines and columns are
one-based. `span_origin` distinguishes exact compiler-preflight locations from
uniquely inferred token locations. Ambiguous locations remain `null` rather than
being guessed.

Stable public exit codes when `--diagnostics-json` is used:

| Code | Meaning |
|---:|---|
| `0` | build succeeded |
| `2` | invalid command-line request |
| `10` | surface frontend or source parse failed |
| `11` | WIR backend failed |
| `12` | LLVM IR to object generation failed |
| `13` | target linker failed |
| `14` | atomic output publication failed |
| `15` | build driver or toolchain setup failed |

`raw_exit_code` preserves the underlying phase status. Full schema details and
current span coverage are documented in [`docs/DIAGNOSTICS.md`](docs/DIAGNOSTICS.md).

## Private runtime contract

Runtime support is part of the compiler product but is not a user-managed API.
A release package stores it under the compiler's private target directory:

```text
weavec-vX.Y.Z-linux-x86_64-<libc>/
├── bin/
│   └── weavec
├── lib/
│   └── weavec/
│       └── <target-triple>/
│           └── libweave-runtime.a
├── BUILD-MANIFEST
├── VERSION
├── README.md
├── LICENSE
└── NOTICE
```

`weavec build` resolves the archive relative to the running compiler executable.
A source checkout uses `runtime/program.c` as a development fallback. The
`WEAVEC_RUNTIME` or `--runtime` override exists for compiler development and is
not part of normal user operation.

The runtime is a static archive so the target linker pulls in only referenced
object modules. Future target packages can add target directories without
changing the public command.

## Install a release

Linux x86-64 releases are provided separately for glibc and musl. After
extracting an archive, add its `bin` directory to `PATH` and invoke `weavec`.
The compiler discovers the adjacent private runtime automatically.

Native builds currently use an installed LLVM code generator and target linker:

- glibc package: `clang`;
- musl package: `clang` for LLVM IR → object and `musl-gcc` for final linking.

These tools are implementation dependencies of the current build driver; users
do not invoke their commands or provide runtime paths themselves.

Release downloads include `SHA256SUMS`. See
[`docs/RELEASING.md`](docs/RELEASING.md).

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

./build/weavec build test/correctness/surface/01_return_42.weave \
  -o /tmp/weave-example
bash test/diagnostics/test-build-diagnostics.sh
```

macOS currently uses the pinned source fallback:

```sh
brew install llvm git
export PATH="$(brew --prefix llvm)/bin:$PATH"
./build.sh
./test-all.sh
```

The compiler build produces:

```text
build/weavec.wir
build/weavec.ll
build/weavec.bc
build/weavec
```

There are no current `weavec2` or `weavefront` compatibility aliases.

## Command line

Public user interface:

```text
weavec build <input.weave> [input2.weave ...] -o <program>
             [--target <triple>]
             [--manifest-json <path>]
             [--diagnostics-json <path>]
             [--keep-temporaries]
```

Compiler-development overrides:

```text
--runtime <path>   / WEAVEC_RUNTIME
--codegen <path>   / WEAVEC_CODEGEN
--linker <path>    / WEAVEC_LINKER
```

Low-level bootstrap and analysis interfaces:

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

The normal Linux source build downloads:

- `weavec1 v0.2.0` for WIR-to-LLVM compilation;
- `weavec-bootstrap v0.2.0` for surface lowering and `libweave-sexpr.bc`.

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
