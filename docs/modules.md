# Explicit modules and interfaces

Weave has an experimental explicit-module surface for bounding the names visible
to an LLM or structural tool. The compiler, not the filesystem or an external
indexer, validates module identity, imports, exports, and callable visibility.

This is the first implementation slice of issue #53. It establishes the source
interface and visibility model without changing WIR core version 2.

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

## Current implementation boundary

The experimental slice provides:

- explicit module identities;
- explicit callable and constant exports;
- explicit imported bindings;
- private-by-default callable lookup;
- duplicate imports, conflicting imports, missing and private symbols,
  mixed-root inputs, and cycles are rejected;
- legacy `program` compatibility;
- deterministic WIR v2 lowering for programs whose emitted declaration names are
  globally unique.

The following work remains under issue #53:

- deterministic compiler-owned WIR name mangling;
- admitting the same private source name in multiple modules;
- explicit diagnostics for a local declaration colliding with an imported name;
- module-scoped struct type identities;
- structured module diagnostics in `weavec-diagnostics-v1`;
- semantic-index definitions, imports, exports, references, and interface hashes.

Until name mangling lands, declaration names that become observable in WIR must
remain globally unique across the compilation. The compiler rejects duplicates
rather than silently choosing one module.

## Tooling contract

`weavec capabilities --json` reports the `modules` feature as experimental and
publishes the `module`, `import`, and `export` form heads with exact arities and
roles. Tools should check that status before generating modular source.

The compiler remains the semantic authority. Jacquard and other tools should not
infer visibility from filenames, directory layout, or source argument order.
