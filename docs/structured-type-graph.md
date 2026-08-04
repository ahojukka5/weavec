# Structured semantic type graph

Issue [#143](https://github.com/ahojukka5/weavec/issues/143) introduces the
compiler-owned representation that later generic, variant, standard-library, and
ownership work will share. It is deliberately a representation foundation: this
slice does not add surface syntax or change the meaning of existing programs.

## Why the graph exists

The established frontend represents primitive types as small integer codes and
allocates nominal struct codes in the same flat space. That model is sufficient
for the current primitive and nominal language, but it cannot represent type
application, generic parameters, function types, variant payloads, or future
ownership qualifiers without spreading new ad hoc conventions through every
semantic subsystem.

The structured graph gives all of those forms one identity and traversal model.
Migration of current production semantic consumers is tracked separately in
[#144](https://github.com/ahojukka5/weavec/issues/144).

## References and identities

A `weave_type_ref` is a process-local handle into one `weave_type_graph`. Handle
numbers depend on insertion order and must never be serialized, hashed into public
interfaces, or compared across graphs.

Each node instead owns a canonical identity string. The encoding is recursive and
length-prefixed, so names containing separators cannot create ambiguous
identities. Canonical identities are:

- independent of allocation and insertion order;
- independent of source enumeration and physical checkout paths;
- compared byte-for-byte after a deterministic 64-bit lookup hash; and
- suitable as the stable input to module-interface and specialization hashes.

The hash accelerates interning. It is not the identity: equal hashes still require
exact canonical-string equality.

## Node kinds

The initial graph admits:

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

Graphs intern nodes through open-addressed lookup. Reconstructing an equivalent
node in one graph returns the existing handle. Cross-graph equality compares the
canonical identities, not handles.

Nominal identity includes the compiler-owned module identity. Therefore
`a::Point` and `b::Point` remain distinct even though both declarations use the
source name `Point`.

An explicit error node represents unknown or failed typing. The zero reference is
invalid and is never a valid semantic type identity.

## Legacy adapter

The graph provides a narrow adapter for the current flat codes:

| Legacy code | Structured type |
| ---: | --- |
| 0 | error |
| 1 | `void` |
| 2 | `i32` |
| 3 | `i64` |
| 4 | `f32` |
| 5 | `f64` |
| 6 | `bool` |
| 7 | `ptr` |

The adapter exists only to make #144 incremental and reviewable. New type-system
features must use structured identities directly rather than allocating more
meaning in the legacy integer space.

## WIR and compatibility boundary

This issue does not change surface Weave, `weave.project`, module interfaces,
generated symbols, the ABI, diagnostics, or frozen WIR core version 2. Existing
programs keep their established lowering.

Future generic and variant features must resolve and specialize structured types
before WIR emission. WIR v2 should continue to receive concrete functions,
nominal layouts, calls, branches, and primitive operations unless a later issue
proves that a coordinated WIR change is unavoidable.

## Qualification

The focused harness compiles the real graph implementation with strict C11
warnings and verifies:

- interning and duplicate reconstruction;
- insertion-order-independent cross-graph equality and hashing;
- module-qualified nominal identity;
- generic parameter ownership and ordinal metadata;
- applications, functions, variants, pointers, and reserved qualifiers;
- deterministic display and canonical identity strings;
- child traversal and invalid-reference behavior; and
- complete legacy-code round trips.

Run it directly with:

```sh
bash test/semantic-type-graph/test.sh
```

The complete repository ladder invokes the same harness before building the final
compiler, so Linux, macOS, release-package, and self-host qualification all cover
the representation foundation.
