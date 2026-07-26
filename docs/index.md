# weavec documentation

`weavec` is the user-facing, self-hosted Weave compiler. This documentation
covers the released compiler product, its source language, public command-line
contracts, internal architecture, bootstrap dependencies, diagnostics, release
process, and focused implementation notes.

The repository was named `weavec2` through release `v0.1.2`. Current documents
use only the final product name `weavec`; historical changelog entries retain the
names used when they were released.

## Start here

- [Architecture](architecture.md) — compiler layers, source-to-executable flow,
  bootstrap boundary, runtime ownership, self-hosting, and verification model.
- [Command reference](command-reference.md) — public build command,
  compiler-development overrides, and low-level compiler modes.
- [Language reference](language-reference.md) — the implemented surface-Weave
  forms accepted by the current compiler.
- [Build manifest](build-manifest.md) — `weavec-build-manifest-v1` and the
  separate release-package `BUILD-MANIFEST`.
- [Machine-readable diagnostics](diagnostics.md) —
  `weavec-diagnostics-v1`, stable phase exits, and source-span provenance.
- [Source and fixture style](source-style.md) — `.weave` compiler conventions,
  resource ownership, deterministic emission, and regression-fixture style.
- [Releasing](releasing.md) — reusable package, validation, and publication
  procedure.

## Language and feature guides

- [Executable contracts and explain mode](contracts-and-explain.md)
- [Quantum surface support](quantum.md)

## Backend and performance notes

- [Loop-carried SSA contract](loop-phi-contract.md)
- [Performance demonstrations](performance-demonstrations.md)
- [LLVM code-generation analysis](llvm-codegen-analysis.md)
- [Generated LLVM analysis report](llvm-codegen-analysis-report.md)

The backend and performance documents describe current self-hosted implementation
behavior and optimization opportunities. They do not extend either the current
core-version-1 format or the frozen lower-stage WIR v2 contract.

## Repository documents

- [README](../README.md) — product overview and quick start.
- [Contributing](../CONTRIBUTING.md) — change policy and required checks.
- [Changelog](../CHANGELOG.md) — release history.

## Naming policy

Files under `docs/` use lowercase kebab-case names. Conventional repository-root
files such as `README.md`, `CHANGELOG.md`, `CONTRIBUTING.md`, `LICENSE`, and
`NOTICE` retain their standard names.
