# weavec architecture

`weavec` is the final user-facing compiler in the reproducible Weave compiler
chain. It is written primarily in surface Weave and publishes one public
source-to-executable command while retaining explicit frontend and backend modes
for compiler development and bootstrap verification.

## Compiler chain

```text
weavec0 → weavec1 → weavec-bootstrap → weavec
```

| Component | Stable responsibility |
|---|---|
| `weavec0` | Minimal hand-written LLVM-IR seed that builds Stage 1. |
| `weavec1` | Complete stable WIR core version 2 to LLVM backend and Stage 1 SDK. |
| `weavec-bootstrap` | Frozen surface-Weave to WIR core version 2 bootstrap frontend and parser SDK. |
| `weavec` | Evolving user-facing compiler, self-hosted frontend/backend, native build driver, diagnostics, and product runtime boundary. |

The three lower repositories are frozen bootstrap infrastructure. New surface
language features and compiler-product behavior belong in `weavec`.

## Unified WIR v2 boundary

The complete compiler chain now uses one intermediate-format version:

```text
surface compiler sources
        │ weavec-bootstrap v0.3.0
        ▼
WIR core version 2
        │ weavec1 v0.3.1
        ▼
LLVM IR for the seed weavec compiler
        │ self-hosted generations
        ▼
surface Weave → WIR v2 → LLVM IR
```

The frozen lower stages define the stabilized WIR v2 boundary. The self-hosted
`weavec --frontend` emits the same `(core-module (core-version 2) ...)` envelope,
and `weavec --backend` validates and consumes it. Core version 1 is rejected.

New surface features must lower through admitted WIR v2 forms. Changing WIR
semantics requires an explicit coordinated version transition rather than a
private final-compiler dialect. See [WIR core version 2](wir.md).

## Product boundary

The normal interface is:

```sh
weavec build main.weave -o main
```

The product flow is:

```text
surface-Weave source files
        │
        │ self-hosted frontend lowering
        ▼
WIR core-version-2 module
        │
        │ self-hosted backend
        ▼
LLVM IR
        │
        │ installed LLVM code generator
        ▼
native object
        │
        ├── private target runtime archive
        │
        │ installed target linker
        ▼
temporary executable beside requested output
        │
        │ atomic rename
        ▼
requested executable
```

Intermediate WIR, LLVM IR, and object files live in a private temporary
directory. The linker writes a temporary executable beside the requested output.
Only a successful atomic rename publishes the final program, so a failed build
does not replace an existing output.

## Source layers

The deterministic compiler source order is declared identically in `build.sh`
and `selfhost.sh`. Source ordering is part of the bootstrap contract.

### Core support

```text
src/core/extern.weave
src/core/io.weave
src/core/util.weave
src/core/trace_registry.weave
```

These modules define external host interfaces, shared compiler utilities, and
the canonical stable compilation-trace action metadata. Frontend transformations
call semantic registry wrappers rather than embedding free-form kind, pass, and
action strings at each lowering site.

### Surface frontend and analysis

```text
src/frontend/quantum_optimize.weave
src/frontend/quantum_nativize.weave
src/frontend/quantum_stats.weave
src/frontend/emit.weave
src/frontend/contract-lower.weave
src/frontend/struct.weave
src/frontend/lower.weave
src/frontend/driver.weave
src/frontend/explain-audit.weave
src/frontend/contract-effects.weave
src/frontend/audit-report.weave
```

This layer parses and combines ordered source modules, validates and lowers
surface forms to WIR core version 2, performs implemented quantum rewrites,
lowers executable contracts, and implements explain/audit modes.

### Self-hosted WIR backend

```text
src/llvm/ctx.weave
src/llvm/types.weave
src/llvm/locals.weave
src/llvm/strings.weave
src/llvm/expr.weave
src/llvm/loop-phi.weave
src/llvm/stmt.weave
src/llvm/fn.weave
src/llvm/module.weave
```

This layer validates WIR core version 2 and emits deterministic LLVM IR. It
owns type spelling, locals, strings, expressions, statements, function/module
emission, and the loop-carried SSA contract. Envelope and call-target validation
occur before output creation; emission failures remove partial LLVM output.

The implementation is self-hosted, while the frozen `weavec1` WIR v2 backend is
used only to construct the initial compiler seed.

### Command entry point

```text
src/main.weave
```

The entry module dispatches the public `build` command and low-level frontend,
backend, quantum statistics, explain, and audit modes.

## Parser-library boundary

The parser implementation is maintained by `weavec-bootstrap`. `weavec` does not
link individual generated parser modules or rewrite bootstrap build scripts. The
published dependency boundary is:

```text
weavec-bootstrap SDK/lib/libweave-sexpr.bc
```

The normal Linux build downloads the matching checksum-verified
`weavec-bootstrap` SDK and links this parser library as one unit. Unsupported
hosts and explicit development configurations use a pinned source fallback.

## Host support and target runtime

The C runtime directory contains two different responsibilities that must remain
separate.

### Compiler host support

`runtime/portable.c` is linked into the compiler executable. It provides portable
host operations, compiler process orchestration, strict-contract and audit state,
and includes the build and diagnostics drivers.

The build-driver implementation owns:

- compiler executable and private runtime discovery;
- temporary artifact paths;
- frontend and backend subprocess phases;
- LLVM IR to object generation;
- target linker execution;
- build-manifest output;
- atomic output publication.

The diagnostics driver wraps this pipeline with stable phase exit codes and
`weavec-diagnostics-v1` while preserving human-readable stderr.

### Private program runtime

`runtime/program.c` is compiled into `libweave-runtime.a` for the package target.
It is a private compiler resource, not a user-managed SDK. Installed packages
store it at:

```text
lib/weavec/<target-triple>/libweave-runtime.a
```

`weavec build` discovers the archive relative to the running compiler. Source
checkouts may use `runtime/program.c` as a development fallback. `--runtime` and
`WEAVEC_RUNTIME` are compiler-development overrides, not normal user inputs.

`runtime/quantum_runtime.c` remains a test stub and is not a production quantum
runtime.

## Bootstrap build

`./build.sh` performs six ordered operations:

1. resolve the published `weavec1` SDK or pinned source fallback;
2. resolve the published `weavec-bootstrap` SDK or pinned source fallback;
3. use `weavec-bootstrap` to lower ordered compiler sources into WIR core version
   2 at `build/weavec.wir`;
4. compile that WIR into `build/weavec.ll` with `weavec1`, or use an explicitly
   selected self-hosted backend only when the supplied WIR is compatible with it;
5. link compiler bitcode with `libweave-sexpr.bc` into `build/weavec.bc`;
6. link the development `build/weavec` executable with compiler host support.

Normal Linux x86-64 builds use glibc or musl SDK archives. macOS currently uses
the pinned source fallback. Stage 0 is resolved only when the Stage 1 source
fallback must be built.

## Self-host generations

`./selfhost.sh` starts from `build/weavec` and builds two further generations:

```text
bootstrap-built seed
        │
        ▼
build/selfhost/stage1/weavec
        │
        ▼
build/selfhost/stage2/weavec
```

Each stage uses the self-hosted frontend to emit WIR core version 2, uses the
self-hosted backend to emit LLVM, builds the parser runtime modules, links the
compiler, and must pass a frontend smoke before publication.
Stage 2 then compiles representative surface fixtures and reproduces their
expected WIR and native behavior.

Deep self-hosting is a permanent CI and release gate, not merely an optional
local experiment.

## Verification model

`./test-all.sh` runs:

1. compiler build;
2. correctness tests for direct WIR and surface lowering;
3. performance LLVM golden tests;
4. quantum lowering and optimization tests;
5. quantum native-runtime end-to-end tests;
6. quantum LLVM checks;
7. compilation-trace registry drift audit;
8. source-linked compilation-trace protocol tests;
9. basic self-host integration tests.

CI executes this ladder with Linux glibc SDKs, Linux musl SDKs, and the macOS
source fallback. A separate deep-selfhost job verifies two self-hosted compiler
generations.

The release workflow additionally:

- builds static glibc and musl compiler archives;
- rejects dynamic ELF compiler binaries;
- verifies the private runtime layout;
- exercises low-level frontend/backend modes;
- builds and runs a native executable through the public command;
- verifies manifest, diagnostics, and compilation-trace protocols;
- proves failed builds do not publish an executable;
- strips and retests the exact packaged compiler;
- extracts both workflow archives into fresh directories and repeats package
  checks before publication.

## Stable and evolving contracts

Source inspection can additionally enable comment-only LLVM provenance. The
frontend carries exact surface file identities and spans through private WIR v2
comments; the backend emits corresponding comments before generated function
and statement groups. This path is opt-in and semantically inert. Structural
LLVM budgets prevent instruction-count, stack-traffic, naming, and undefined-
value regressions across the performance suite.

Stable versioned automation contracts are:

- `weavec-build-manifest-v1`;
- `weavec-diagnostics-v1`;
- `weavec-compilation-trace-v1`;
- public phase exit codes used with diagnostics output;
- the private runtime package location;
- the explicit `--frontend` and `--backend` command shapes.

The emitted WIR core version is observable compiler behavior. The seed bootstrap
and self-hosted frontend/backend workflows all use core version 2; documentation,
audits, and fixtures enforce that shared boundary.

Surface Weave continues to evolve in this repository. Changes to public syntax,
semantics, command behavior, diagnostics, manifests, target packaging, emitted
WIR, or source ordering require corresponding documentation and regression
coverage.
