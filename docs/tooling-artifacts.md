# Tooling artifact outputs

`weavec build` can publish the intermediate WIR and LLVM files to explicit,
reproducible paths for external analysis tools:

```sh
weavec build library.weave main.weave -o application \
  --emit-wir application.wir \
  --emit-llvm application.raw.ll \
  --emit-optimized-llvm application.optimized.ll \
  --emit-assembly application.s \
  --emit-disassembly application.disasm \
  --optimization-record application.opt.yaml \
  --trace-json application.trace.json \
  --diagnostics-json application.diagnostics.json \
  --manifest-json application.build.json \
  --llvm-provenance
```

These options define the compiler/tooling boundary. `weavec` owns deterministic
source lowering, WIR validation, raw LLVM emission, explicit LLVM optimization,
target code generation, final executable disassembly, diagnostics, trace events,
and source provenance. External tools such as `weave-loupe` own JSON parsing,
comparison, visualization, LLM-assisted review, and HTML report generation.

For example, a companion tool can capture the complete evidence set and derive a
report without parsing human stderr or private temporary paths:

```sh
loupe capture library.weave main.weave --output application.loupe
loupe report application.loupe --output application.html
```

`weavec` does not depend on that tool. The command only illustrates the stable
consumer boundary provided by the artifact outputs above.

## Phase-scoped publication

`--emit-wir <path>` atomically publishes the WIR file immediately after a
successful frontend phase. If a later backend, code-generation, link, trace, or
executable-publication phase fails, the WIR artifact remains available for
analysis.

`--emit-llvm <path>` atomically publishes raw backend LLVM immediately after a
successful backend phase. If optimization or any later phase fails, raw LLVM
remains available.

`--emit-optimized-llvm <path>` publishes after LLVM optimization succeeds.
`--emit-assembly <path>` publishes after target assembly emission succeeds.
`--optimization-record <path>` publishes after object generation succeeds.
`--emit-disassembly <path>` publishes after the temporary linked executable has
been disassembled successfully.

A phase that fails does not replace the corresponding existing artifact. For
example, a frontend failure leaves an existing `--emit-wir` destination
unchanged, and a backend failure leaves an existing `--emit-llvm` destination
unchanged.

The executable retains its stronger all-or-nothing rule: it is published only
after every requested build output has succeeded.

## Source provenance

`--llvm-provenance` adds semantically inert comments linking LLVM groups to exact
surface and WIR ranges. When `--emit-llvm` is present, the explicit LLVM output is
the stable inspection location and the private temporary directory is not kept
unless `--keep-temporaries` was also requested.

Without `--emit-llvm`, `--llvm-provenance` retains the historical behavior of
keeping the temporary directory so raw `program.ll`, optimized
`program.optimized.ll`, and other completed private artifacts remain inspectable.

## Path rules

The executable, WIR, raw LLVM, optimized LLVM, assembly, disassembly,
optimization record, manifest, diagnostics, and trace destinations must all be
distinct. Conflicts are rejected before compilation. Artifact files are
written beside their requested destinations and atomically renamed into place.

The output files contain compiler and native-code evidence only. `weavec`
deliberately does not produce report-specific JSON aggregates, databases, HTML, JavaScript, charts, or
LLM prompts. Those higher-level concerns belong in tooling repositories.

## Low-level modes

`--frontend` and `--backend` remain compiler-development and self-host interfaces.
General tooling should prefer `weavec build` with explicit artifact outputs so it
receives the same phase ordering, diagnostics, trace events, provenance, target
selection, and failure semantics as a real native build.
