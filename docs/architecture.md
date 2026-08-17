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
| `weavec-bootstrap` | Frozen surface-Weave to WIR core version 2 bootstrap frontend. |
| `weavec` | Evolving user-facing compiler, self-hosted frontend/backend, native build driver, diagnostics, and product runtime boundary. |

The three lower repositories are frozen bootstrap infrastructure. New surface
language features and compiler-product behavior belong in `weavec`.

## Two WIR boundaries

The chain uses two intermediate-format versions, one per side of the bootstrap:

```text
surface compiler sources
        │ weavec-bootstrap v0.3.1
        ▼
WIR core version 2                      ← frozen bootstrap boundary
        │ weavec1 v0.3.2
        ▼
LLVM IR for the seed weavec compiler
        │ self-hosted generations
        ▼
surface Weave → WIR core version 3 → LLVM IR   ← current boundary
```

The frozen lower stages are version-2 artifacts permanently: `weavec-bootstrap`
emits core version 2 and `weavec1` consumes it, and no transition changes a
released stage. They build the seed compiler and are not involved afterwards.

The self-hosted `weavec --frontend` emits `(core-module (core-version 3) ...)`
and `weavec --backend` validates and consumes it. Core versions 1 and 2 are
rejected.

The two boundaries never meet. Every producer and consumer in the build is
paired with one of the same generation: `build.sh` pairs the bootstrap frontend
with the `weavec1` backend, and `scripts/selfhost.sh` and the release packaging
pipe one `weavec` binary into itself. A mismatched future pair would fail
immediately on the strict envelope check rather than producing wrong code, which
is what that check is for.

Changing WIR semantics requires an explicit coordinated version transition
rather than a private final-compiler dialect. See
[WIR core version 3](wir.md).

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
WIR core-version-3 module
        │
        │ self-hosted backend
        ▼
raw LLVM IR
        │
        │ explicit installed LLVM optimization profile
        ▼
optimized LLVM IR
        │
        │ installed LLVM target code generator
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

Intermediate WIR, raw LLVM, optimized LLVM, assembly, optimization records,
and object files live in a private temporary directory. The linker writes a
temporary executable beside the requested output. Only a successful atomic
rename publishes the final program, so a failed build
does not replace an existing output.

## Source layers

The deterministic compiler source order is declared once in
`compiler/sources.list`. `build.sh`, `selfhost.sh`, and bootstrap-stack
qualification all load and validate that same manifest. Source ordering is part
of the bootstrap contract; entries must be canonical relative `src/*.weave`
paths, unique, present, and non-symlinked.

Other `.weave` files under `src/` may be reference implementations or
optional target modules. They are not compiler inputs unless explicitly added
to the canonical manifest, and the manifest may exclude a file from linking
with a leading `!`.

This document describes what each layer owns. It deliberately does **not**
reproduce the file list: `compiler/sources.list` is the single authority, and a
handwritten second copy falls behind it. Read the manifest for the current set
and its order.

### Core support — `src/core/`

These modules define external host interfaces, shared compiler utilities, and
the canonical stable compilation-trace action metadata. Frontend transformations
call semantic registry wrappers rather than embedding free-form kind, pass, and
action strings at each lowering site.

### Self-hosted S-expression parser — `src/parser/`

These modules own the token store, syntax tree, lexer, and parser used by final
`weavec`. They are ordinary ordered compiler sources, not a separately linked
runtime. The lower bootstrap frontend parses these files only so it can lower
them into the initial seed compiler; stage 1 and stage 2 compile the same source
set with `weavec` itself.

WIR is an intermediate representation, not a production implementation language.
Repository WIR files may be backend inputs, golden fixtures, performance corpora,
or compatibility tests, but production compiler behavior belongs in surface
Weave whenever surface Weave can express it. Parser semantics must not be moved
into C or hand-written WIR to bypass that ownership rule.

### Structured types — `src/types/`

This layer owns the structured type graph: identity, storage, application,
qualifiers, variants, and the semantic state that surface elaboration queries.
Ownership qualifiers are modelled here; enforcing them is separate work.

### Protocol documents — `src/protocol/`

This layer owns the machine-readable outputs and the one checked streaming JSON
writer they share: capabilities, diagnostics, build manifests, compilation
traces, and the project and host protocols. Publication is transactional, so an
incomplete document never replaces a previous one.

### Surface frontend and analysis — `src/frontend/`

This layer parses and combines ordered source modules, validates and lowers
surface forms to WIR core version 3, performs implemented quantum rewrites,
lowers executable contracts, and implements explain/audit modes.

### Self-hosted WIR backend — `src/llvm/`

This layer validates WIR core version 3 and emits deterministic LLVM IR. It
owns type spelling, struct layout, locals, strings, expressions, statements,
function and module emission, and uniform mutable control-flow lowering. LLVM
owns scalar SSA promotion in the selected optimization profile. Envelope and
call-target validation occur before output creation; emission failures remove
partial LLVM output.

The implementation is self-hosted, while the frozen `weavec1` WIR v2 backend is
used only to construct the initial compiler seed.

### Command entry point — `src/main.weave`

The entry module dispatches the public `build` command and low-level frontend,
backend, quantum statistics, explain, and audit modes.

## Parser bootstrap boundary

`weavec-bootstrap` remains the frozen tool that reads and lowers the ordered
surface-Weave compiler sources for the seed build. Its parser is therefore part
of the lower-stage build tool itself, not a parser implementation inherited by
final `weavec`.

Final `weavec` obtains `lex`, `parse`, tree accessors, and token/node helpers from
`src/parser/*.weave` in `compiler/sources.list`. The seed link does not consume
lower-stage parser bitcode, and self-hosted generations do not compile or link a
private `src/runtime-wir` parser. This keeps one production parser implementation
in the same source language and ownership model as the rest of the compiler.

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
- optimization-profile and CPU selection;
- phase-scoped raw LLVM, optimized LLVM, assembly, remarks, and disassembly
  publication;
- target linker execution;
- build-manifest output;
- atomic output publication.

`runtime/llvm_toolchain.c` is the narrow host adapter for LLVM operations. It
currently invokes command-line tools, but the build driver depends on semantic
operations rather than concrete arguments. A future in-process LLVM integration
can replace this adapter without changing the public artifact contract.

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

1. resolve the published `weavec1` SDK for the host platform;
2. resolve the published `weavec-bootstrap` SDK for the host platform;
3. use `weavec-bootstrap` to lower ordered compiler sources into WIR core version
   2 at `build/weavec.wir`;
4. compile that WIR into `build/weavec.ll` with `weavec1`, or use an explicitly
   selected self-hosted backend only when the supplied WIR is compatible with it;
5. link compiler bitcode with the compiler-version module into `build/weavec.bc`;
6. link the development `build/weavec` executable with compiler host support.

Linux x86-64 uses glibc or musl SDK archives; macOS arm64 and x86-64 use native
SDK archives. There is no source-chain fallback and Stage 0 is never built by
this repository.

## Self-host generations

`./selfhost.sh` starts from `build/weavec` and builds two further generations
from the same canonical ordered compiler source manifest:

```text
bootstrap-built seed
        │
        ▼
build/selfhost/stage1/weavec
        │
        ▼
build/selfhost/stage2/weavec
```

Each stage uses the self-hosted frontend to emit WIR core version 3 for the
complete compiler source set, including `src/parser/`, then uses the self-hosted
backend to emit LLVM and links the compiler exactly once. Every stage must pass
version and frontend smoke validation before publication.

After both generations exist, self-host qualification verifies a fixed point:

- normalized stage-1 and stage-2 compiler WIR must match;
- normalized compiler LLVM must match;
- exported defined symbol sets must match independently of linked addresses;
- normalized hashes, LLVM structure summaries, symbol sets, and unified diffs are
  retained under `build/selfhost/fixed-point` when any comparison fails.

The stage-2 compiler then runs the full correctness suite plus the diagnostics,
compilation-trace, and tooling-artifact protocol suites. Those tests use the
stage-2 binary directly and isolate their generated correctness artifacts under
`build/selfhost/stage2-tests`.

Deep self-hosting is a release and manual qualification gate, not merely an
optional experiment.

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
9. compiler-source manifest and fixed-point verifier regressions;
10. basic self-host integration tests.

Platform automation may execute this ladder, but the repository contract does
not depend on hosted CI availability. `./selfhost.sh` itself verifies two
self-hosted compiler generations, their fixed point, and stage-2 protocol
behavior so the same qualification can be run locally.

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
frontend carries exact surface file identities and spans through private WIR
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
and self-hosted frontend/backend workflows all use core version 3; documentation,
audits, and fixtures enforce that shared boundary.

Surface Weave continues to evolve in this repository. Changes to public syntax,
semantics, command behavior, diagnostics, manifests, target packaging, emitted
WIR, or source ordering require corresponding documentation and regression
coverage.
