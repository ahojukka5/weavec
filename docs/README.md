# weavec2 documentation

User-facing notes for the self-hosted surface Weave compiler in
`weave/weavec2/`. These documents describe language features, compiler modes,
and how they fit the representation-lowering pipeline.

## Feature guides

| Document | Topic |
|----------|-------|
| [contracts-and-explain.md](contracts-and-explain.md) | Executable `(requires …)` / `(ensures …)` contracts and `--explain` audit output |
| [quantum-surface-syntax.md](quantum-surface-syntax.md) | Quantum gates, measurement, and `Qubit` surface forms |
| [representation-lowering.md](representation-lowering.md) | Surface → WIR → LLVM pipeline and transform passes |

## Compiler internals

| Document | Topic |
|----------|-------|
| [loop-phi-contract.md](loop-phi-contract.md) | Loop phi lowering contract |
| [llvm-codegen-analysis.md](llvm-codegen-analysis.md) | Reading performance-demo LLVM output |
| [llvm-codegen-analysis-report.md](llvm-codegen-analysis-report.md) | Tabulated codegen metrics |
| [performance-demonstrations.md](performance-demonstrations.md) | Performance WIR/LLVM fixture suite |

## Quick commands

Build the compiler:

```sh
cd weave/weavec2
./build.sh
```

Run correctness tests:

```sh
./test.sh
```

Explain contracts and simple function facts for a surface file:

```sh
./build/weavec2 --explain path/to/program.weave
```

See [contracts-and-explain.md](contracts-and-explain.md) for syntax and semantics.
