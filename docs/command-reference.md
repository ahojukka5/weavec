# weavec command reference

This document describes the command-line interfaces implemented by the current
`weavec` compiler. The normal user interface is `weavec build`; the other modes
are retained for compiler development, bootstrap verification, analysis, and
tooling.

## Native build

```text
weavec build <input.weave> [input2.weave ...] -o <program>
             [--target <triple>]
             [--manifest-json <path>]
             [--diagnostics-json <path>]
             [--keep-temporaries]
```

Example:

```sh
weavec build main.weave library.weave -o application
./application
```

The command performs surface lowering, WIR v2 backend compilation, LLVM IR to
object generation, private runtime selection, target linking, and atomic output
publication.

### Inputs and output

- At least one `.weave` source is required.
- `-o` and `--output` name the native executable.
- Source order is preserved in the build manifest and passed to the frontend.
- The manifest and diagnostics paths, when both requested, must be different.
- A failed build does not publish a partial executable at the requested path.

### Target selection

`--target <triple>` selects a runtime target installed in the compiler package.
Current release archives install one target:

- glibc: `x86_64-unknown-linux-gnu`;
- musl: `x86_64-unknown-linux-musl`.

A package rejects any target not present in that package. The option establishes
the multi-target command contract; current packages do not perform arbitrary
cross-compilation.

### Automation outputs

`--manifest-json <path>` writes `weavec-build-manifest-v1`. See
[Build manifest](build-manifest.md).

`--diagnostics-json <path>` writes `weavec-diagnostics-v1` and enables stable
public phase exit codes while preserving human-readable stderr. See
[Machine-readable diagnostics](diagnostics.md).

### Temporary artifacts

By default, WIR, LLVM IR, and object files are removed after the build.
`--keep-temporaries` retains the private temporary directory and prints its path
to stderr. This is a compiler-development aid, not a reproducible output
location.

## Compiler-development overrides

The public build command accepts explicit overrides:

```text
--runtime <path>
--codegen <command>
--linker <command>
```

Equivalent environment variables are:

```text
WEAVEC_RUNTIME
WEAVEC_CODEGEN
WEAVEC_LINKER
```

Normal users should not set these. Installed packages discover their private
runtime automatically and define appropriate default code-generator and linker
commands.

## Surface frontend

```text
weavec --frontend [--strict-contracts] <output.wir>
                  <input.weave> [input2.weave ...]
```

This mode lowers ordered surface-Weave source files to one WIR v2 module.

`--strict-contracts` turns violations of declared effect contracts such as
`(pure)` and `(no_alloc)` into frontend failures. Runtime `(requires ...)` and
`(ensures ...)` clauses are lowered into executable checks in either mode.

The mode is a low-level compiler and bootstrap interface. Normal native builds
should use `weavec build`.

## WIR backend

```text
weavec --backend <input.wir> <output.ll>
```

This mode compiles WIR v2 to LLVM IR. The explicit `--backend` marker is
required; the former implicit `weavec input.wir output.ll` syntax is rejected.

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
| `11` | WIR backend failed. |
| `12` | LLVM IR to object generation failed. |
| `13` | Target linker failed. |
| `14` | Atomic output publication failed. |
| `15` | Build driver or toolchain setup failed. |

The diagnostics document also records `raw_exit_code` from the underlying phase.
