# Explicit modules and interfaces

Weave has an experimental explicit-module surface for bounding the names visible
to an LLM or structural tool. The compiler, not the filesystem or an external
indexer, validates module identity, imports, exports, callable visibility, public
nominal types, and module-scoped identities.

The completed issue #53 implementation series established the source interface,
visibility model, deterministic private-symbol naming, module-scoped nominal
types, structured diagnostics, and semantic-index representation without
changing WIR core version 3. Project-system issue #122 extends those interfaces
to public nominal struct types.

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

User-facing standard-library files currently use the `program` root with
name `std.<id>` and path `stdlib/<id>.weave`. That identity stays if a
later change adopts `(module std.<id> ...)`. See
[Standard-library layout and module naming](stdlib.md).

## Exports

An export clause names one or more declarations from the current module:

```weave
(module arithmetic
  (export Number add-two subtract-two)

  (struct Number
    (field value i32))

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

Each exported name must identify a callable, constant, or struct declared in that
module. Empty, duplicate, and missing exports are rejected. Declarations not
listed by an export clause are private. An imported declaration is not locally
owned and cannot be re-exported implicitly.

## Imports

An import names one source module and an explicit symbol list:

```weave
(module application
  (import arithmetic (Number add-two))

  (fn identity
    (params (value Number))
    (returns Number)
    (do (return value)))

  (entry main
    (params)
    (returns i32)
    (do
      (return (call add-two 40 2)))))
```

Wildcard imports are not supported. The compiler rejects:

- a missing source module;
- a missing source symbol or type;
- a private source symbol or type;
- the same imported binding repeated;
- two modules imported under the same local name;
- an imported binding that conflicts with any callable, constant, or struct
  declared in the current module.

Functions, constants, entries, externs, and nominal types share one local binding
namespace. A call resolves a local declaration and then an explicitly imported
exported declaration. A type annotation resolves a local struct and then an
explicit imported public struct. An exported name in another module is not
ambient; it remains unavailable until imported. This lookup never silently
shadows a valid import.

See [Public nominal type interfaces](public-nominal-types.md) for type ownership,
use sites, re-export policy, semantic-index representation, and diagnostics.

## Ordering and cycles

All module, import, export, callable, constant, and nominal-type facts are
collected before interface validation and declaration emission. An import may
therefore refer to a module that appears later in the command line. Imported type
references create the defining module's deterministic provisional identity and
the later declaration completes that identity.

Reversing source arguments does not change name visibility, nominal identity,
normalized semantic WIR, module interfaces, semantic references, call edges, or
interface hashes.

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
match.

A local type annotation resolves to the struct owned by the current module or to
one explicitly imported public struct. Importing a struct preserves the defining
module's identity; it does not create a structurally equivalent consumer-local
type.

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
- explicit callable, constant, and nominal struct exports;
- explicit imported bindings shared by value and type positions;
- private-by-default callable, constant, and nominal-type lookup;
- deterministic WIR names for colliding private callables and constants across
  canonical calls, explicit typed calls, and contract lowering;
- module-scoped nominal struct identities and deterministic generated helpers;
- construction, field access, mutation, parameters, returns, and locals using
  imported public structs;
- a single collision-checked local binding namespace;
- structured diagnostics for duplicate and conflicting imports, local/import
  collisions, type/value collisions, missing and private symbols, mixed roots,
  raw-linkage collisions, malformed interfaces, and import cycles;
- semantic-index module definitions, public struct symbols, imports, exports,
  references, call edges, and interface hashes;
- source-order-independent normalized module semantics and interface facts;
- legacy `program` compatibility.

## Roadmap boundary

Epic [#111](https://github.com/ahojukka5/weavec/issues/111) turns these compiler
semantics into a practical project and package foundation. Completed slices now
provide:

- a canonical project manifest;
- deterministic module-to-file discovery;
- local dependency graph resolution and entry-module selection;
- public nominal type exports and imports.

Remaining project-system work owns additive project facts in diagnostics,
manifests, traces, semantic indexes, integrated qualification, and later
interface-hash-based incremental compilation.

The module feature remains experimental until that project-level user experience
is stable. New work should be filed as focused subissues of #111 rather than
reopening the completed issue #53 implementation series.

## Tooling contract

`weavec capabilities --json` reports the `modules` and `semantic-structs` features
as experimental and publishes the `module`, `import`, `export`, `struct`, `new`,
`field-get`, and `field-set` forms with exact arities and roles.

`weavec analyze --semantic-index-json` publishes compiler-authoritative module
graphs, public struct symbols and signatures, import/export references, call edges,
and interface hashes. Tools should require the relevant capabilities and must not
infer visibility or nominal identity from filenames, directory layout, source
argument order, or encoded WIR spelling.
