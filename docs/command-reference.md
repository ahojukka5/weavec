# weavec command reference

This document describes the command-line interfaces implemented by the current
`weavec` compiler. The normal user interface is `weavec build`; the other modes
are retained for compiler development, self-host verification, analysis, and
tooling.

## Native build

Explicit source-list mode is:

```text
weavec build <input.weave> [input2.weave ...] -o <program>
             [--target <triple>]
             [--manifest-json <path>]
             [--diagnostics-json <path>]
             [--trace-json <path>]
             [--emit-wir <path>]
             [--emit-llvm <path>]
             [--emit-optimized-llvm <path>]
             [--emit-assembly <path>]
             [--emit-disassembly <path>]
             [--optimization-record <path>]
             [-O0|-O1|-O2|-O3|-Os|-Oz]
             [--native]
             [--cpu <name>] [--tune-cpu <name>]
             [--llvm-provenance]
             [--keep-temporaries]
```

Project mode is selected when no explicit `.weave` source arguments are present:

```text
weavec build [--project <directory-or-manifest>] [-o <program>]
             [the same target, optimization, tooling, and evidence options]
```

Explicit source-list example, using Option, Result, match, and try:

```sh
weavec build \
  stdlib/process.weave \
  stdlib/parse.weave \
  stdlib/option.weave \
  stdlib/result.weave \
  stdlib/io.weave \
  examples/parse-digits/main.weave \
  -o parse-digits

./parse-digits 1 2 3
```

Expected output:

```text
digits = 1 2 3
sum = 6
```

See [Parse digits](../examples/parse-digits/README.md) for the other documented
invocations. The same command works from an extracted release package.

The source-list command performs surface lowering to WIR core version 3,
self-hosted backend compilation to raw LLVM IR, explicit LLVM optimization,
target assembly and object generation, private runtime selection, target linking,
optional final disassembly, and atomic output publication. The seed is built
across a separate, frozen core version 2 boundary. See
[Architecture](architecture.md) and [WIR core version 3](wir.md).

### Build-mode precedence

The command chooses exactly one input mode:

1. Any explicit non-option source argument selects source-list mode. Nearby
   `weave.project` files are ignored.
2. `--project` cannot be combined with explicit source arguments.
3. With no source arguments, `--project PATH` or `--project=PATH` selects either a
   project directory or a regular file named exactly `weave.project`.
4. With neither sources nor `--project`, discovery starts at the current working
   directory and selects the nearest `weave.project` while walking toward the
   filesystem root.
5. A nearer malformed or unreadable manifest is authoritative. Discovery never
   skips it to use a more distant parent project.

An explicit project path is independent of the current directory. Relative paths
are resolved from the invocation directory; the selected manifest is then
canonicalized to its physical path for reading and output-alias protection.

The selected manifest is parsed against
[Weave project manifest version 1](project-manifest.md). Manifest diagnostics use
stable `project.manifest.*` codes, and `--diagnostics-json` reports them through
`weavec-diagnostics-v1` with stable driver exit `15`.

Project mode discovers admitted source modules, resolves their import graph into a
deterministic dependency order, validates executable entry ownership, and invokes
the same frontend and backend used by explicit source-list builds. Library projects
publish their normalized WIR bundle instead of a native executable. Project-owned
machine-readable outputs include the additive `weavec-project-facts-v1` object
documented in [Project facts in compiler protocols](project-protocols.md).

### Inputs and output

- Source-list mode requires at least one `.weave` source.
- Project mode requires a selected valid `weave.project`.
- In source-list mode, `-o` or `--output` names the native executable.
- In project mode, `-o` or `--output` overrides the manifest `output`; otherwise
  the default output is anchored in the selected project directory.
- Source order is preserved in source-list build manifests and passed to the
  frontend.
- Executable, WIR, raw LLVM, optimized LLVM, assembly, disassembly, optimization
  record, manifest, diagnostics, and trace paths must be distinct when requested.
- No requested or manifest-default output may alias the selected
  `weave.project`, including when the manifest itself is malformed.
- A failed build does not publish a partial executable at the requested path.

### Target selection

`--target <triple>` selects a runtime target installed in the compiler package.
Current release archives install one target:

- glibc: `x86_64-unknown-linux-gnu`;
- musl: `x86_64-unknown-linux-musl`.

A package rejects any target not present in that package. The option establishes
the multi-target command contract; current packages do not perform arbitrary
cross-compilation.

### Optimization and native CPU selection

The default build profile is portable `-O2`. The optimization level is explicit
and can be selected with `-O0`, `-O1`, `-O2`, `-O3`, `-Os`, or `-Oz`.

`--native` requests the current host CPU and tuning model. `--cpu <name>` and
`--tune-cpu <name>` select them independently. `--march` and `--mtune` are
familiar aliases. Native artifacts may not run on another machine.

The current subprocess adapter uses Clang for the LLVM IR optimization profile
and `llc` for target assembly and object generation. These are public semantic
build choices, not a permanent commitment to subprocess invocation; a future
in-process LLVM implementation must preserve the same behavior.

### Native-code evidence outputs

`--emit-llvm <path>` publishes raw backend LLVM.

`--emit-optimized-llvm <path>` publishes the readable LLVM IR produced by the
selected LLVM optimization profile.

`--emit-assembly <path>` publishes target assembly.

`--emit-disassembly <path>` disassembles the actual linked executable with
`llvm-objdump` (or the `--objdump` override) and publishes the result.

`--optimization-record <path>` combines LLVM IR and target-code-generation
optimization remarks into one YAML stream.

See [Native optimization and machine-code evidence](native-code-evidence.md).

### Automation outputs

`--manifest-json <path>` writes `weavec-build-manifest-v1`. See
[Build manifest](build-manifest.md).

`--diagnostics-json <path>` writes `weavec-diagnostics-v1` and enables stable
public phase exit codes while preserving human-readable stderr. See
[Machine-readable diagnostics](diagnostics.md).

`--trace-json <path>` writes `weavec-compilation-trace-v1`, a deterministic list
of source-linked frontend transformations performed by the real lowering and
optimization paths. See [Source-linked compilation trace](compilation-trace.md).

In project mode, each requested JSON document carries the same additive top-level
`project` member. It identifies the selected project, logical source membership,
entry module, deterministic module graph, and current resolution phase without
changing the enclosing version-one document format.

`--emit-wir <path>` and `--emit-llvm <path>` atomically publish the successful
frontend and backend artifacts at stable paths. They are intended for external
compiler tooling and remain available when a later phase fails. See
[Tooling artifact outputs](tooling-artifacts.md).

`--llvm-provenance` adds comment-only function and statement provenance to the
generated LLVM. When `--emit-llvm` is present, that explicit path is the stable
inspection location; otherwise provenance implies `--keep-temporaries` and the
compiler prints the retained directory containing `program.ll`. The comments
link exact surface and WIR byte ranges without changing ordinary WIR, LLVM
semantics, or direct-WIR compatibility. See
[LLVM source provenance and quality budgets](llvm-provenance.md).

### Temporary artifacts

By default, WIR, LLVM IR, and object files are removed after the build.
`--keep-temporaries` retains the private temporary directory and prints its path
to stderr. This is a compiler-development aid, not a reproducible output
location.

## Semantic analysis

Explicit source-list analysis is:

```text
weavec analyze <input.weave> [input2.weave ...]
               --semantic-index-json <path>
```

Project analysis is:

```text
weavec analyze [--project <directory-or-manifest>]
               --semantic-index-json <path>
```

Project analysis uses the same manifest selection, source admission, dependency
order, and module identities as `weavec build`. The semantic index keeps its
existing module, symbol, import, export, reference, call-edge, public nominal type,
specialization, match, and interface-hash facts and adds the shared
`weavec-project-facts-v1` context.
Project-relative logical source paths are relocation-stable; documented physical
paths remain observational.

The semantic-index output path may not alias the selected manifest or an admitted
project source. Project selection or graph failures do not publish a partial
semantic index.

## Canonical formatter

```text
weavec fmt <source.weave>
weavec fmt --check <source.weave>
weavec fmt --output <output.weave> <source.weave>
```

The formatter parses one complete surface source with the compiler parser,
normalizes layout and supported compatibility forms, preserves declaration and
child order, and emits the deterministic canonical normal form. The default mode
updates the source atomically. `--output` writes a separate destination, and
`--check` returns `0` for canonical input or `1` when the source would change.
Invalid usage returns `2`; read, parse, formatting, comparison, and publication
failures return `3` without replacing an existing source or output.

See [Canonical Weave formatting](formatting.md) for the normalization, comment,
idempotence, and compatibility policies.

## Compiler-development overrides

The public build command accepts explicit overrides:

```text
--runtime <path>
--optimizer <command>
--target-codegen <command>
--linker <command>
--objdump <command>
```

`--codegen` remains a compatibility alias for `--optimizer`; `--llc` is an
alias for `--target-codegen`. Equivalent environment variables are:

```text
WEAVEC_RUNTIME
WEAVEC_OPTIMIZER
WEAVEC_TARGET_CODEGEN
WEAVEC_LINKER
WEAVEC_OBJDUMP
```

`WEAVEC_CODEGEN` remains a compatibility fallback for `WEAVEC_OPTIMIZER`, and
`WEAVEC_LLC` remains a compatibility fallback for `WEAVEC_TARGET_CODEGEN`.

Normal users should not set these. Installed packages discover their private
runtime automatically and define appropriate default code-generator and linker
commands.

## Surface frontend

```text
weavec --frontend [--strict-contracts] <output.wir>
                  <input.weave> [input2.weave ...]
```

This mode lowers ordered surface-Weave source files to one WIR module:

```text
(core-module (core-version 3) ...)
```

The frozen lower-stage bootstrap emits core version 2; this compiler emits
core version 3, and neither accepts the other's output. See
[WIR core version 3](wir.md).

`--strict-contracts` turns violations of declared effect contracts such as
`(pure)` and `(no_alloc)` into frontend failures. Runtime `(requires ...)` and
`(ensures ...)` clauses are lowered into executable checks in either mode.

The mode is a low-level compiler and self-host interface. Normal native builds
should use `weavec build`.

## Self-hosted WIR backend

```text
weavec --backend <input.wir> <output.ll>
```

This mode validates and compiles WIR core version 3 to LLVM IR. Core versions 1
and 2, missing or duplicate version declarations, and invalid module roots are
rejected.
Any backend failure removes a partial LLVM output.

The explicit `--backend` marker is required; the former implicit
`weavec input.wir output.ll` syntax is rejected.

The backend validates call targets against the complete declaration set before
opening the LLVM output file. Backend failure therefore does not leave a
partially emitted output.

## Quantum statistics

```text
weavec --dump-quantum-stats <output.metrics> <input.weave>
```

This mode parses one surface source and writes deterministic quantum-operation
statistics used by the quantum regression suite. It does not execute a quantum
program or provide a production hardware runtime.

## Explain mode

```text
weavec --explain <input.weave>
weavec --explain-json <input.weave>
```

Explain mode reports functions, parameters, return sites, contracts, loops,
calls, external callees, and allocations without generating WIR or LLVM.

The JSON form provides the same structural information for tooling.

## Audit mode

```text
weavec --audit <input.weave>
weavec --audit-json <input.weave>
```

Audit mode adds conservative effect analysis and verifies declared `(pure)`,
`(no_alloc)`, and `(deterministic)` contracts. It reports reasons for failed or
unknown classifications. The JSON form is suitable for CI and other tools.

See [Executable contracts and explain mode](contracts-and-explain.md).

## Process exit behavior

Without `--diagnostics-json`, low-level compiler modes retain their historical
success or failure status and human-readable stderr.

When `weavec build` writes diagnostics JSON, the public stable phase exits are:

| Code | Meaning |
|---:|---|
| `0` | Build succeeded. |
| `2` | Invalid command-line request. |
| `10` | Surface frontend or source parse failed. |
| `11` | Self-hosted WIR backend failed. |
| `12` | LLVM IR to object generation failed. |
| `13` | Target linker failed. |
| `14` | Atomic output publication failed. |
| `15` | Build driver, project selection, or toolchain setup failed. |

The diagnostics document also records `raw_exit_code` from the underlying phase.
