# Surface Weave language reference

This document describes the surface forms implemented by the current `weavec`
frontend. It is a reference for source `.weave` files, not a reference for
hand-written WIR. The frontend emits WIR core version 2; see
[WIR core version 2](wir.md) for the intermediate-format contract.

Weave source is an S-expression language. Semicolons introduce line comments.
Identifiers and operator names are case-sensitive.

## Program module

A source module is a `program` form:

```weave
(program
  (name "example")
  (version "0.1")
  declarations...)
```

`name` and `version` are descriptive module metadata. A native program must
provide an `entry main` body after all input files are combined.

Multiple source files are accepted by `weavec build` and `weavec --frontend`.
Their declarations are lowered into one WIR core-version-2 module. Source
argument order is preserved, while the frontend applies deterministic
main/declaration ordering rules to the combined output.

## Primitive types

The current language uses explicit low-level type names:

| Type | Meaning |
|---|---|
| `i32` | 32-bit integer. |
| `i64` | 64-bit integer. |
| `f32` | 32-bit floating-point value. |
| `f64` | 64-bit floating-point value. |
| `bool` | Boolean value. |
| `ptr` | Opaque pointer. |
| `void` | No return value. |
| `Qubit` | Quantum-handle surface type used by current quantum lowering. |

The language currently exposes explicit-width operations rather than implicit
numeric promotion. Cast operations must be written when moving between widths or
representations.

## External declarations

Declare an externally linked function with:

```weave
(extern malloc
  (params (size i64))
  (returns ptr))
```

Parameters are ordered `(name type)` pairs. A no-argument declaration uses
`(params)`.

External calls use the return-typed call form matching the declaration, for
example:

```weave
(call_ptr malloc (const_i64 64))
(call_void free buffer)
```

Unknown call targets are rejected by the backend before LLVM output is created.

## Functions and entry points

A function has explicit parameters, return type, optional contracts, and a `do`
body:

```weave
(fn add_two
  (params (left i32) (right i32))
  (returns i32)
  (do
    (return (add_i32 left right))))
```

The program entry uses the same shape:

```weave
(entry main
  (params)
  (returns i32)
  (do
    (return (const_i32 42))))
```

Bare parameter and local identifiers are accepted as operands where their type
is known. Explicit `(param_get name)` and `(local_get name)` forms remain valid
in the lower-level style used throughout compiler sources.

## Named constants

A module-level constant is:

```weave
(const ANSWER i64 42)
```

The current lowering represents a named constant as a zero-argument typed
function. Use the matching call form:

```weave
(call_i64 ANSWER)
```

## Struct declarations

A struct declaration is:

```weave
(struct Buffer
  (field data ptr)
  (field len i64)
  (field cap i64))
```

The current frontend lowers fields to generated getter and setter functions. For
the example above, generated names include:

```text
Buffer_get_data
Buffer_set_data
Buffer_get_len
Buffer_set_len
Buffer_get_cap
Buffer_set_cap
```

Struct storage is pointer-based and fields use the generated functions; the
current language does not expose a separate object or ownership model.

## Local bindings and assignment

A typed local binding is:

```weave
(let answer i32 (const_i32 42))
```

Integer literal sugar is accepted for typed `i32` and `i64` bindings:

```weave
(let x i32 40)
(let y i64 2)
```

Update an existing local with:

```weave
(set answer (add_i32 answer (const_i32 1)))
```

The raw backend represents mutable locals with stack slots. The selected LLVM
optimization profile promotes eligible loop-carried values to SSA phis. See
[Loop lowering contract](loop-lowering.md).

## Blocks and control flow

`do` is an ordered statement block:

```weave
(do
  statement...
  (return expression))
```

An `if` statement is:

```weave
(if
  (condition (lt_i32 value limit))
  (then (do
    statements...))
  (else (do
    statements...)))
```

A `while` loop is:

```weave
(while
  (condition (lt_i32 index limit))
  (do
    statements...))
```

`return` takes one expression for a typed function. Void functions use:

```weave
(return_void)
```

## Constants and scalar operations

Explicit constant forms include:

```weave
(const_i32 42)
(const_i64 42)
(const_f32 3)
(const_f64 3)
(const_bool true)
(const_null)
(const_string_ptr "text")
```

Floating constants currently use integer literal tokens and lower through an
integer-to-floating conversion. Decimal literal syntax is not yet part of the
stable surface contract.

Operations are named by operation and type. Representative forms are:

```weave
(add_i32 left right)
(sub_i32 left right)
(mul_i32 left right)
(div_i32 left right)
(mod_i32 left right)
(add_i64 left right)
(add_f32 left right)
(add_f64 left right)
(eq_i32 left right)
(lt_i32 left right)
(ge_i64 left right)
(and_bool left right)
(or_bool left right)
(not_bool value)
(cast_i64_to_i32 value)
```

The compiler rejects unknown operators and wrong arity rather than forwarding
invalid forms to LLVM.

## Typed calls

Function calls identify the expected return representation:

```weave
(call_i32 function arguments...)
(call_i64 function arguments...)
(call_f32 function arguments...)
(call_f64 function arguments...)
(call_bool function arguments...)
(call_ptr function arguments...)
(call_void function arguments...)
```

The call form must agree with the declared return type. A void call is a
statement; typed calls are expressions.

## Pointer and memory operations

The current low-level surface supports explicit pointer operations used by
compiler and systems code, including allocation through extern calls, pointer
addition, typed loads and stores, and pointer-valued calls.

Representative forms are:

```weave
(ptr_add pointer offset)
(load_i64 pointer)
(store_i64 pointer value)
(store_i8 pointer value)
(load_ptr pointer)
(store_ptr pointer value)
```

Memory safety, ownership, and lifetime inference are not currently enforced by a
higher-level type system.

## Executable contracts

Functions may declare runtime preconditions and postconditions:

```weave
(fn clamp
  (params (x i32) (lo i32) (hi i32))
  (returns i32)
  (requires (le_i32 lo hi))
  (ensures (ge_i32 result lo))
  (ensures (le_i32 result hi))
  (do
    ...))
```

Within `ensures`, `result` denotes the value at each return site. Using `result`
in `requires` is rejected.

Effect declarations are marker clauses with no child expression:

```weave
(pure)
(no_alloc)
(deterministic)
```

They are conservatively audited. `--frontend --strict-contracts` rejects failed
declarations; ordinary frontend lowering reports them through explain/audit
interfaces without changing code generation. See
[Executable contracts and explain mode](contracts-and-explain.md).

## Quantum forms

Gate application is a statement:

```weave
(qgate H qubit)
(qgate CNOT control target)
```

Measurement is also a statement and names the resulting classical `i32` local:

```weave
(qmeasure qubit result_name)
```

For example:

```weave
(let q0 Qubit (const_i64 0))
(qgate H q0)
(qmeasure q0 c0)
(return (local_get c0))
```

The frontend lowers measurement to an `i32` runtime call and introduces the
named local in emitted WIR. Current lowering uses external quantum-runtime calls,
and the included runtime is only a test stub. Hadamard nativization and selected
peephole optimizations occur before WIR emission. See
[Quantum surface support](quantum.md).

## Diagnostics and unsupported syntax

The compiler reports malformed forms, wrong arity, unknown operators,
unresolved identifiers, and contract violations through human-readable stderr.
`weavec build --diagnostics-json` additionally provides stable phase codes and
structured diagnostics.

The following are not current surface contracts:

- C-like or indentation-based alternate syntax;
- implicit numeric conversions;
- a separate quantum source format;
- arbitrary decimal floating literals;
- private final-compiler WIR forms added without a coordinated version transition;
- the removed implicit `weavec input.wir output.ll` backend command.
