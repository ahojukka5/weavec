# Explicit modules and interfaces

Weave has an experimental explicit-module surface for bounding the names visible
to an LLM or structural tool. The compiler, not the filesystem or an external
indexer, validates module identity, imports, exports, callable visibility, and
module-scoped nominal identities.

The completed issue #53 implementation series established the source interface,
visibility model, deterministic private-symbol naming, module-scoped nominal
types, structured diagnostics, and semantic-index representation without
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
- two modules imported under the same local symbol name;
- an imported binding that conflicts with a callable or constant declared in
  the current module.

A call first resolves a declaration in its own module, then an explicitly
imported exported declaration. An exported name in another module is not ambient;
it remains unavailable until imported. Because imported bindings and local
declarations cannot share a name, this lookup order never silently shadows a
valid import.

## Ordering and cycles

All module, import, export, and declaration facts are collected before interface
validation. An import may therefore refer to a module that appears later in the
command line. Reversing source arguments does not change name visibility,
normalized semantic WIR, module interfaces, semantic references, call edges, or
private-stable interface hashes.

Import cycles are rejected. The compiler reports a cycle before emitting
declarations, and failed frontend compilation does not publish a partial WIR
file.

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
target declaration. Explicit WIR-shaped compatibility forms `call_i32`,
`call_i64`, `call_f32`, `call_f64`, `call_bool`, `call_ptr`, and `call_void` also
resolve their callee through the module registry. Contract-lowered declarations
and calls use the same module-aware symbol emitter. Unique private names remain
unchanged, so module resolution does not churn existing WIR when no collision
exists.

## Module-scoped struct identities

A struct declared in an explicit module has a nominal identity formed from its
module identity and source type name. Two modules may therefore both declare
`Record`; the resulting types are distinct even when their field lists happen to
match. A local type annotation resolves only to the struct owned by the current
module. Public type export and import syntax is part of the project-system
roadmap rather than the completed callable-interface slice.

Generated constructor and accessor helpers use deterministic compiler-owned WIR
base names. For `Record` in modules `alpha` and `beta`, the bases are:

```text
__weave_m_616c706861__t_5265636f7264
__weave_m_62657461__t_5265636f7264
```

The `_new`, `_get_FIELD`, and `_set_FIELD` suffixes are appended to those bases.
Diagnostics continue to display the source spelling `Record`, not the encoded
helper name. Legacy `program` sources retain the historical `Record_new`,
`Record_get_FIELD`, and `Record_set_FIELD` compatibility ABI.

## Current implementation status

The completed module implementation provides:

- explicit module identities;
- explicit callable and constant exports;
- explicit imported bindings;
- private-by-default callable lookup;
- deterministic WIR names for colliding private callables and constants across
  canonical calls, explicit typed calls, and contract lowering;
- module-scoped nominal struct identities and deterministic generated helpers;
- structured diagnostics for duplicate and conflicting imports, local/import
  collisions, missing and private symbols, mixed roots, raw-linkage collisions,
  malformed interfaces, and import cycles;
- semantic-index module definitions, imports, exports, symbol references, call
  edges, and private-stable interface hashes;
- source-order-independent normalized module semantics and interface facts;
- legacy `program` compatibility.

## Roadmap boundary

Epic [#111](https://github.com/ahojukka5/weavec/issues/111) turns these compiler
semantics into a practical project and package foundation. It owns:

- a canonical project manifest;
- deterministic module-to-file discovery;
- local dependency graph resolution and entry-module selection;
- public type exports and imports;
- project-level build, diagnostics, manifest, trace, and semantic-index behavior;
- later interface-hash-based incremental compilation.

The module feature remains experimental until that project-level user experience
is stable. New work should be filed as focused subissues of #111 rather than
reopening the completed issue #53 implementation series.

## Tooling contract

`weavec capabilities --json` reports the `modules` feature as experimental and
publishes the `module`, `import`, and `export` form heads with exact arities and
roles. `weavec analyze --semantic-index-json` publishes the compiler-authoritative
module graph, symbol interfaces, references, call edges, and interface hashes.
Tools should check feature status before generating modular source.

The compiler remains the semantic authority. Jacquard and other tools should not
infer visibility from filenames, directory layout, source argument order, or the
encoded WIR spelling.
