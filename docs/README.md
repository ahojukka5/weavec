# weavec documentation

User-facing and internal notes for the self-hosted Weave compiler. This
repository was formerly named `weavec2`; new documentation uses the final
product name `weavec`.

## Feature guides

| Document | Topic |
|---|---|
| [contracts-and-explain.md](contracts-and-explain.md) | Executable `(requires …)` / `(ensures …)` contracts and `--explain` audit output |
| [quantum-surface-syntax.md](quantum-surface-syntax.md) | Quantum gates, measurement, and `Qubit` surface forms |
| [representation-lowering.md](representation-lowering.md) | Surface → WIR → LLVM pipeline and transform passes |

## Compiler internals

| Document | Topic |
|---|---|
| [loop-phi-contract.md](loop-phi-contract.md) | Loop-phi lowering contract |
| [llvm-codegen-analysis.md](llvm-codegen-analysis.md) | Reading performance-demo LLVM output |
| [llvm-codegen-analysis-report.md](llvm-codegen-analysis-report.md) | Tabulated code-generation metrics |
| [performance-demonstrations.md](performance-demonstrations.md) | Performance WIR/LLVM fixture suite |

## Compiler chain terminology

```text
weavec0 → weavec1 → weavec-bootstrap → weavec
```

- `weavec-bootstrap` was formerly `weavefront`.
- `weavec` was formerly `weavec2`.
- Historical scripts, paths, and examples may retain the old names until their
  compatibility interfaces are migrated.

## Quick commands

Build the compiler:

```sh
git clone https://github.com/ahojukka5/weavec.git
cd weavec
./build.sh
```

Run the full test ladder:

```sh
./test-all.sh
```

Explain contracts and simple function facts for a surface file. The current
binary path retains the historical filename:

```sh
./build/weavec2 --explain path/to/program.weave
```

See [contracts-and-explain.md](contracts-and-explain.md) for syntax and
semantics.
