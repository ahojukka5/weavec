# weavec command reference

This document describes the command-line interfaces implemented by the current
`weavec` compiler. The normal user interface is `weavec build`; the other modes
are retained for compiler development, self-host verification, analysis, and
tooling.

## Native build

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

Example:

```sh
weavec build main.weave library.weave -o application
./application
```

The command performs surface lowering to WIR core version 2, self-hosted
backend compilation to raw LLVM IR, explicit LLVM optimization, target assembly
and object generation, private runtime selection, target linking, optional final
disassembly, and atomic output publication. The seed and self-hosted compiler
generations use the same WIR v2 boundary. See [Architecture](architecture.md) and
[WIR core version 2](wir.md).

### Inputs and output

- At least one `.weave` source is required.
- `-o` and `--output` name the native executable.
- Source order is preserved in the build manifest and passed to the frontend.
- Executable, WIR, raw LLVM, optimized LLVM, assembly, disassembly, optimization
  record, manifest, diagnostics, and trace paths must be distinct when requested.
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

This mode lowers ordered surface-Weave source files to one WIR v2 module:

```text
(core-module (core-version 2) ...)
```

The output uses the same versioned envelope as the frozen lower-stage bootstrap.
See [WIR core version 2](wir.md).

`--strict-contracts` turns violations of declared effect contracts such as
`(pure)` and `(no_alloc)` into frontend failures. Runtime `(requires ...)` and
`(ensures ...)` clauses are lowered into executable checks in either mode.

The mode is a low-level compiler and self-host interface. Normal native builds
should use `weavec build`.

## Self-hosted WIR backend

```text
weavec --backend <input.wir> <output.ll>
```

This mode validates and compiles WIR core version 2 to LLVM IR. Core version 1,
missing or duplicate version declarations, and invalid module roots are rejected.
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
| `15` | Build driver or toolchain setup failed. |

The diagnostics document also records `raw_exit_code` from the underlying phase.
