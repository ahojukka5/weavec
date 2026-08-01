# Explicit modules and interfaces

Weave has an experimental explicit-module surface for bounding the names visible
to an LLM or structural tool. The compiler, not the filesystem or an external
indexer, validates module identity, imports, exports, and callable visibility.

This is the second implementation slice of issue #53. It establishes the source
interface, visibility model, and deterministic private-symbol naming without
changing WIR core version 2.

## Canonical roots

One source file contains one root. Existing sources may retain the legacy form:

```weave
(program
  (name "legacy-application")
  (version "0.1")
  ...)
```

New modular sources use an explicit identifier:

```weave
(module arithmetic
  ...)
```

A single compilation may use legacy `program` roots or explicit `module` roots,
but not both. Module identity never comes from an absolute path or command-line
position.

## Exports

An export clause names one or more declarations from the current module:

```weave
(module arithmetic
  (export add-two subtract-two)

  (fn add-two
    (params (left i32) (right i32))
    (returns i32)
    (do
      (return (op add left right))))

  (fn subtract-two
    (params (left i32) (right i32))
    (returns i32)
    (do
      (return (op subtract left right)))))
```

Each exported name must identify a callable or constant declared in that module.
Empty, duplicate, and missing exports are rejected. Declarations not listed by an
export clause are private.

## Imports

An import names one source module and an explicit symbol list:

```weave
(module application
  (import arithmetic (add-two))

  (entry main
    (params)
    (returns i32)
    (do
      (return (call add-two 40 2)))))
```

Wildcard imports are not supported. The compiler rejects:

- a missing source module;
- a missing source symbol;
- a private source symbol;
- the same imported binding repeated;
- two modules imported under the same local symbol name.

A call first resolves a declaration in its own module, then an explicitly
imported exported declaration. An exported name in another module is not ambient;
it remains unavailable until imported.

## Ordering and cycles

All module, import, export, and declaration facts are collected before interface
validation. An import may therefore refer to a module that appears later in the
command line. Reversing source arguments does not change name visibility or the
normalized semantic WIR produced by the module regression.

Import cycles are rejected in this initial design. The compiler reports a cycle
before emitting declarations, and failed frontend compilation does not publish a
partial WIR file.

## Private WIR names

Two modules may declare the same private callable or constant name. When a source
name collides across modules, the compiler emits a deterministic WIR identifier
from the module and source-name bytes. The encoding is independent of filenames,
absolute paths, source argument order, and host state.

For example, private `helper` declarations in `alpha` and `beta` lower to distinct
identifiers beginning with:

```text
__weave_m_616c706861__s_68656c706572
__weave_m_62657461__s_68656c706572
```

The hexadecimal form is deliberately mechanical and reversible for tools. It is
not a user-facing source name or a stability promise for external linkage.
Exported names, legacy-program names, `main`, and external-linkage declarations
retain their source spelling. Those raw linkage names must remain globally
unique.

Canonical `(call NAME ...)` forms use the same resolved WIR identifier as the
target declaration. Unique private names remain unchanged, so this slice does
not churn existing WIR when no collision exists.

## Current implementation boundary

The experimental slices provide:

- explicit module identities;
- explicit callable and constant exports;
- explicit imported bindings;
- private-by-default callable lookup;
- deterministic WIR names for colliding private callables and constants used by
  canonical calls;
- duplicate imports, conflicting imports, missing and private symbols,
  mixed-root inputs, raw-linkage collisions, and cycles are rejected;
- legacy `program` compatibility.

The following work remains under issue #53:

- module-aware rewriting for explicit WIR-shaped `call_*` compatibility forms;
- contract-lowered duplicate private callable names;
- explicit diagnostics for a local declaration colliding with an imported name;
- module-scoped struct type identities;
- structured module diagnostics in `weavec-diagnostics-v1`;
- semantic-index definitions, imports, exports, references, and interface hashes.

## Tooling contract

`weavec capabilities --json` reports the `modules` feature as experimental and
publishes the `module`, `import`, and `export` form heads with exact arities and
roles. Tools should check that status before generating modular source.

The compiler remains the semantic authority. Jacquard and other tools should not
infer visibility from filenames, directory layout, source argument order, or the
encoded WIR spelling.
