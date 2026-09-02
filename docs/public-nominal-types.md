# Public nominal type interfaces

Issue [#122](https://github.com/ahojukka5/weavec/issues/122) extends explicit
module interfaces from callable and constant bindings to nominal struct types.
The compiler remains the authority for visibility, identity, type checking, and
interface hashes; tools must not infer public types from filenames or generated
helper names.

## Surface syntax

Public types use the existing explicit interface forms. A defining module exports
a struct by source name:

```weave
(module records
  (export Record make-record)

  (struct Record
    (field value i32))

  (fn make-record
    (params (value i32))
    (returns Record)
    (do
      (return (new Record (value value))))))
```

A consumer imports the type in the same explicit symbol list as functions and
constants:

```weave
(module application
  (import records (Record make-record))

  (fn identity
    (params (item Record))
    (returns Record)
    (do
      (return item))))
```

No wildcard, implicit, filename-derived, or ambient type import exists. Import
aliases are not part of this slice.

## Binding namespace

Types, functions, externs, entries, and constants occupy one module binding
namespace. This prevents a source name from changing meaning according to whether
it appears in a type or value position.

The compiler rejects:

- a local struct and local callable or constant with the same name;
- an imported type that conflicts with any local declaration;
- an imported callable or constant that conflicts with a local struct;
- two imports that bind the same local name from different modules;
- duplicate imports of the same binding.

A module may contain a private type with the same spelling as a private type in
another module. Their identities remain distinct.

## Visibility and ownership

A struct is private unless its defining module lists it in `export`. Importing a
missing or private type uses the same stable module-interface diagnostics as other
bindings.

An imported type is owned by its defining module. An intermediate module cannot
implicitly re-export it by writing `(export Type)`; export declarations name local
declarations only. A future explicit re-export form would need separate syntax and
protocol semantics.

## Nominal identity

An explicit-module struct identity is the pair:

```text
(defining module identity, source type name)
```

Importing a type does not create a new nominal type in the consumer. Parameters,
returns, local bindings, constructors, field access, field mutation, and call
checking all retain the defining module's identity.

Consequently, `alpha.Record` and `beta.Record` are incompatible even when both
struct declarations have identical fields. The current surface does not expose a
qualified-name expression; imports introduce one unqualified local binding and
therefore cannot bind both names simultaneously without future alias syntax.

The registry creates deterministic defining-module placeholders when an imported
type is referenced before its source file is processed. The later declaration
completes that same placeholder. Reversing source arguments or moving an unchanged
project therefore does not change nominal identities, generated WIR names, or
interface hashes.

## Supported use sites

An imported public struct may appear in:

- function and extern parameter types;
- function return types;
- local `let` bindings;
- `new` constructors;
- `field-get` and `field-set` operations;
- call arguments and results;
- pointer equality and the documented low-level `ptr` escape.

All ordinary semantic-struct rules still apply. Constructor completeness, field
names, field value types, receiver types, return types, and call arguments are
checked against the defining declaration.

## Project builds

Manifest-selected builds discover modules and order their dependencies before
invoking the existing frontend. Public type imports use the same graph edge as any
other `(import MODULE (...))` clause. No additional manifest field, package
coordinate, or type search path exists.

Both explicit source-list builds and `weavec build --project` preserve the same
nominal identity and diagnostics. Project relocation does not affect the interface.

## Semantic index and interface hashes

`weavec analyze --semantic-index-json` represents a public type as a symbol with:

- `kind` equal to `struct`;
- `visibility` equal to `public`;
- its canonical field signature;
- an export fact owned by the defining module;
- resolved import references in consumers.

The defining module's interface hash includes the exported struct signature. A
field-name, field-order, or field-type change therefore changes that public
interface hash, while source argument order and checkout location do not.

The existing machine-readable capability combination is authoritative for this
slice:

- feature `modules` supplies explicit `module`, `import`, and `export` forms;
- feature `semantic-structs` supplies nominal `struct`, `new`, `field-get`, and
  `field-set` semantics;
- protocol `weavec-semantic-index-v1` publishes public struct symbols, imports,
  exports, and interface hashes.

Tools should require all relevant capabilities rather than inferring type-interface
support from one form alone.

## Diagnostics

Public nominal interfaces use existing module and semantic-struct codes plus one
binding-namespace code:

```text
frontend.module.import-missing-module
frontend.module.import-missing-symbol
frontend.module.import-private-symbol
frontend.module.duplicate-import
frontend.module.conflicting-import
frontend.module.import-local-collision
frontend.module.export-undeclared
frontend.module.type-value-collision
frontend.struct.undefined-type
frontend.call.argument-type-mismatch
```

Diagnostics point to the exact import, export, declaration, or type-use identifier.
Failed frontend compilation publishes neither partial WIR nor a native output.

## WIR compatibility boundary

This feature does not change WIR core version 3. Nominal values still lower
physically to `ptr`. Generated constructor and accessor functions use the existing
deterministic defining-module name:

```text
__weave_m_<module-bytes>__t_<type-bytes>_new
__weave_m_<module-bytes>__t_<type-bytes>_get_<field>
__weave_m_<module-bytes>__t_<type-bytes>_set_<field>
```

Those names are compiler-owned compatibility details, not source import names or a
public package ABI. Source code uses the nominal type spelling and canonical
`new`, `field-get`, and `field-set` forms.