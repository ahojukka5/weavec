# Structured semantic type graph

Issue [#143](https://github.com/ahojukka5/weavec/issues/143) introduced the
compiler-owned representation that generic, variant, standard-library, and
ownership work share. Issue
[#144](https://github.com/ahojukka5/weavec/issues/144) moves the production
primitive and nominal semantic paths onto that representation without changing
surface syntax or WIR v2.

## Ownership rule

The compiler's language semantics are self-hosted. C is a platform boundary, not
a compiler implementation language.

The structured type system therefore lives under `src/types/`:

- `graph_*.weave` owns type-node representation, canonical identities, hashing,
  interning, equality, display metadata, composition, and read-only traversal;
- `semantic_state.weave` owns the compiler graph lifetime and the private binding
  from raw host struct slots to semantic graph references;
- `semantic_structs.weave` exposes graph-backed nominal struct operations to the
  rest of the self-hosted frontend; and
- `semantic_policy.weave` owns human display, concrete WIR lowering, and current
  compatibility rules.

The native bridge is deliberately smaller. `runtime/semantic_type_graph.c`
contains only one opaque process-wide pointer cell because surface Weave does not
yet have mutable process globals. C never dereferences or interprets that semantic
state. `runtime/semantic_surface_types.c` exposes only raw storage reset and the
defining module name needed to construct a nominal identity. Existing
`surface_symbols.c` and `module_struct_names.c` remain bounded host storage for
copied names, fields, module/import lookup, and deterministic helper names.

No native function decides whether two Weave types are equal or compatible, what
a type means, how it is displayed, or how it lowers to WIR.

## Why the graph exists

The original frontend represented primitive types as small integer codes and
allocated nominal struct codes in the same flat space. That model was sufficient
for the primitive and nominal language, but it could not represent type
application, generic parameters, function types, variant payloads, or future
ownership qualifiers without spreading new ad hoc conventions through every
semantic subsystem.

Production semantic facts now carry opaque structured graph references. Symbol
parameters and returns, locals, struct fields, expression inference, operators,
casts, contracts, and nominal compatibility pass those references through the
existing storage boundaries without assigning meaning to the integer carrier.

The old `1024 + struct-slot` values still exist inside the raw C name/field storage
as bounded implementation keys. Only `semantic_state.weave` translates those
private keys to graph references. They never become semantic identities and never
cross the public semantic facade.

## References and identities

A type reference is a process-local `i32` handle into one graph. Handle numbers
depend on insertion order and must never be serialized, hashed into public
interfaces, or compared across graphs. Zero is invalid and remains the
frontend's unknown/absent sentinel.

Each node instead owns a canonical identity string. The encoding is recursive and
length-prefixed, so names containing separators cannot create ambiguous
identities. Canonical identities are:

- independent of allocation and insertion order;
- independent of source enumeration and physical checkout paths;
- compared byte-for-byte after a deterministic 64-bit lookup hash; and
- suitable as stable inputs to later module-interface and specialization hashes.

The deterministic hash accelerates identity checks but is not itself the
identity: equal hashes still require exact canonical-string equality.

The current self-hosted interner performs a linear scan of the graph. This is an
intentional implementation choice while compiler type populations are small. The
semantic contract does not depend on lookup strategy, so a Weave-owned hash table
can replace it later without changing identities or callers.

## Node kinds

The graph admits:

- error and primitive types;
- module-qualified nominal types;
- owner-qualified generic parameters with stable ordinals;
- type applications;
- function parameter and result types;
- variants with payload types;
- typed pointers; and
- reserved `owned`, `borrow`, and `borrow-mut` qualifiers.

The ownership-qualified nodes reserve representation structure for epic #115.
They do not make those forms valid surface syntax and do not claim that ownership
checking exists.

Every composite node retains ordered child references for deterministic traversal.
Human display strings such as `collections::Vector<i32>` are separate from the
canonical identity encoding.

## Interning and equality

Equivalent nodes intern to one reference inside a graph. Cross-graph equality
compares deterministic hashes and then exact canonical identities, never local
handle numbers.

Nominal identity includes the compiler-owned defining module identity. Therefore
`a::Point` and `b::Point` remain distinct even though both declarations use the
source name `Point`. An imported nominal resolves to the defining module's
identity rather than gaining a new identity in the importing module.

An explicit error node exists for structured graph consumers. The zero reference
is invalid and is never a valid semantic type identity.

## Production semantic boundary

The self-hosted semantic layer owns policies that previously depended on raw
integer conventions:

- primitive interning;
- nominal identity construction;
- human type display;
- concrete WIR type lowering; and
- semantic compatibility.

Nominal structs continue to lower to `ptr` in WIR v2, and generated struct helper
names keep the established module-qualified mangling. Human diagnostics keep the
source struct name. A nominal value may still flow to an explicit low-level `ptr`
parameter, while the reverse conversion and conversion between distinct nominal
types remain forbidden.

`surface_symbols.c` and `module_struct_names.c` assign no language meaning to the
type values they store. They retain the raw host records needed by the current
bootstrap-era compiler implementation; removing those remaining storage tables is
a separate migration and does not require moving semantic policy back into C.

## Legacy adapter

The temporary primitive legacy-code adapter introduced with #143 is removed from
the production implementation. Primitive and nominal production typing now uses
structured references directly. There is no second C semantic representation to
keep synchronized with the self-hosted compiler.

## WIR and compatibility boundary

The migration does not change surface Weave, `weave.project`, generated symbol
names, the ABI, diagnostics, or frozen WIR core version 2. Existing programs keep
their established lowering.

`Qubit` continues to resolve to the current concrete `i64` semantic type. The
source-aware frontend retains the `lower-qubit-to-i64` compilation-trace event,
while the self-hosted semantic policy owns the eventual WIR spelling.

Future generic and variant features must resolve and specialize structured types
before WIR emission. WIR v2 should continue to receive concrete functions,
nominal layouts, calls, branches, and primitive operations unless a later issue
proves that a coordinated WIR change is unavoidable.

## Qualification

`test/semantic-type-graph/test.sh` first guards the architecture: the two native
semantic bridge files are rejected if graph or language-level semantic policy
creeps back into them. It then uses the built `weavec` compiler to compile the
actual `src/types/graph_*.weave` implementation together with
`test/semantic-type-graph/fixture.weave` and `main.weave`, and runs that native
test program.

The focused executable verifies:

- equivalent interning and duplicate reconstruction;
- insertion-order-independent cross-graph equality and hashing;
- module-qualified nominal identity;
- generic parameter ownership and ordinal metadata;
- applications, functions, variants, pointers, and reserved qualifiers;
- deterministic display and canonical identity strings;
- child traversal and invalid-reference behavior; and
- graph lifetime implemented by the self-hosted code itself.

The complete repository ladder builds the compiler before this focused test and
then continues through primitive, struct, module, contract, quantum, project,
release, and deep self-host qualification. That ensures the same Weave-owned type
implementation is exercised both directly and by the production compiler.
