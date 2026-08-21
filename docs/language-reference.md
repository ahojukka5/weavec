# Surface Weave language reference

This document describes the surface forms implemented by the current `weavec`
frontend. It is a reference for source `.weave` files, not a reference for
hand-written WIR. The frontend emits WIR core version 3; see
[WIR core version 3](wir.md) for the intermediate-format contract.

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
Their declarations are lowered into one WIR core-version-3 module. Source
argument order is preserved, while the frontend applies deterministic
main/declaration ordering rules to the combined output.

## Types

The current primitive and built-in surface types are:

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

`u8`, `u64`, and `usize` are decided but not yet admitted. Lengths and
indices are `usize`; see [Integer widths and the size type](integer-widths.md).

`f32` and `f64` are IEEE-754 binary32 and binary64. Invalid operations
yield `NaN`, not `0.0`. See
[Floating-point special values](floating-point.md).

A `(struct NAME ...)` declaration additionally introduces `NAME` as a nominal
surface type. Nominal struct types lower physically to WIR `ptr`, but two
different struct names are not interchangeable.

A type annotation is a bare name or an explicit type application:

```weave
(let count i32 0)
(let n 1)
(let box (type-app Box i32) ...)
```

`(let NAME EXPR)` is accepted when EXPR has exactly one known type. A bare
integer is `i32`. A decimal such as `1.5` is `f64`. An initializer whose type
is unknown, void, or not unique still requires an explicit annotation.
`(let NAME TYPE EXPR)` remains valid.

Other parenthesised types such as `(owned Vec3)` are rejected wherever they
appear — in a binding, a parameter, or a return declaration:

```text
weavec: surface binding: type must be a name, not a compound expression
```

The qualified spellings that ownership and borrowing will introduce are
therefore refused rather than ignored until they mean something.

A function or struct may declare explicit type parameters immediately after its
name. Type applications name the constructor and its arguments:

```weave
(fn identity
  (type-params T)
  (params (value T))
  (returns T)
  (do
    (return value)))

(struct Box
  (type-params T)
  (field value T))

(fn wrap-i32
  (params (value i32))
  (returns (type-app Box i32))
  ...)
```

Generic declarations are surface templates. A call to a generic function must
supply explicit type arguments; the compiler emits one concrete WIR function
per distinct instantiation and reuses it for later calls:

```weave
(return (call identity (type-args i32) 1))
```

The specialized name is deterministic from the source name and the type-argument
identities, so file order does not change it. `entry` and `extern` cannot take
type parameters. Constructing a generic struct still requires a later
specialization of `new`.

A tagged `enum` is a nominal type. Variants are numbered in source order. A
nullary variant has only a tag; a payload variant stores one value in a fixed
8-byte slot beside the tag:

```weave
(enum Result
  (type-params T E)
  (variant Ok T)
  (variant Err E))

(let ok (type-app Result i32 i32) (variant Result (type-args i32 i32) Ok 1))
(return (variant-tag Result ok))
```

`match` is exhaustive over that enum. Each `case` names a constructor; a
payload constructor binds one name in the arm. `_` is an explicit wildcard
for constructors not listed, must be last, and is rejected when every
constructor is already covered. Missing constructors without `_` are
rejected. Arm result types must agree. `match` initializes a `let` or is
returned.

Enum values have no identity. `=` / `!=`, `eq_ptr` / `ne_ptr`, and
implicit conversion to `ptr` are rejected (`frontend.enum.no-identity`).
Compare with `match` or `variant-tag`. The current 16-byte heap object is
an implementation detail; see [Enum values have no identity](enum-identity.md).

```weave
(return (match Result value
  (case Ok x x)
  (case Err e 0)))
```

`Option` and `Result` are the canonical generic enums for absence and
recoverable errors. They live in `stdlib/option.weave` and
`stdlib/result.weave` as `std.option` and `std.result`, and are passed
with the program that uses them. See
[Standard-library layout and module naming](stdlib.md).

```weave
(enum Option
  (type-params T)
  (variant None)
  (variant Some T))

(enum Result
  (type-params T E)
  (variant Ok T)
  (variant Err E))
```

`std.option` and `std.result` also provide helpers implemented with
`match`. They are ordinary generic functions and do not abort:

```weave
(call option_is_some (type-args i32) some)
(call option_unwrap_or (type-args i32) none 0)
(call result_is_ok (type-args i32 i32) ok)
(call result_unwrap_or (type-args i32 i32) err 0)
```

There is no function-valued `map` yet; map a payload with `match`.

`String` and `Bytes` are owned buffers in `stdlib/string.weave` and
`stdlib/bytes.weave`. Application source constructs them from a text
literal, appends, and indexes without naming `ptr`:

```weave
(let s (call string_from_text "hello"))
(call string_append s (call string_from_text " world"))
(let ch (call string_get s 0))
```

`string_get` and `bytes_get` return `None` when the index is out of
range. They do not abort. Convert with `string_from_bytes` and
`bytes_from_string`.

`Vec` and `Slice` are the generic growable vector and a view over its
buffer in `stdlib/vec.weave`. The only admitted element type is `i32`.
Application source constructs, grows, and indexes without naming `ptr`:

```weave
(let v (call vec_new (type-args i32)))
(call vec_push (type-args i32) v 10)
(let n (call vec_len (type-args i32) v))
(let item (call vec_get (type-args i32) v 0))
(let sl (call vec_as_slice (type-args i32) v))
```

`vec_get` and `slice_get` return `None` when the index is out of range.
`vec_set` and `slice_set` return false. They do not abort. A `Slice`
shares the vector buffer; it is a data type, not a borrow checker.
Later counted `for` over a vector uses `vec_len` and `vec_get`.
`std.vector` remains the fixed `Vec3` module.

`std.convert` formats admitted primitives to `String` and parses text
into `Result`. There is no locale and no printf:

```weave
(let s (call format_i32 42))
(let f (call format_f64 1.5))
(let n (call parse_i32 "42"))
(let x (call parse_float "1.5"))
```

`format_i32` is signed decimal. `format_f64` matches `write_f64_trimmed`:
six-place rounding, trailing fractional zeros removed, at least one
fractional digit. `1.5` is `1.5` and `1.0` is `1.0`. `format_bool` is
`true` or `false`. `parse_i32`, `parse_i64`, `parse_bool`, and
`parse_float` return `Err 1` when the text is invalid. `parse_float`
wraps `parse_f64_valid` and `parse_f64`. `parse_f64` itself still
returns `0.0` on invalid text.

A complete program that uses these forms together is
[examples/parse-digits](../examples/parse-digits/README.md).

`(try EXPR)` unwraps a `Result`. The enclosing function must return a
`Result` with the same error type. `try` initializes a `let`; on `Err` it
returns that error, and on `Ok` the binding receives the success payload.
There is no stack unwinding and no implicit conversion between error
types.

```weave
(fn double
  (params (n i32))
  (returns (type-app Result i32 i32))
  (do
    (let v i32 (try (call parse-digit n)))
    (return (variant Result (type-args i32 i32) Ok (+ v v)))))
```

Invalid constructors and payload types are rejected with exact diagnostics.

Duplicate, empty, reserved, and unknown type-parameter names are rejected with
exact diagnostics. Applying a non-generic type, or applying a generic type with
the wrong number of arguments, is also rejected.

The language exposes explicit-width operations rather than implicit numeric
promotion. Cast operations must be written when moving between admitted numeric
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

Canonical source uses Lisp head-position calls:

```weave
(malloc 64)
(free buffer)
```

The wrapper `(call malloc 64)` remains accepted.

Explicit WIR-shaped forms remain accepted for low-level source:

```weave
(call_ptr malloc (const_i64 64))
(call_void free buffer)
```

Unknown call targets are rejected before LLVM output is created.

## Functions and entry points

A function has explicit parameters, return type, optional contracts, and a `do`
body:

```weave
(fn add_two
  (params (left i32) (right i32))
  (returns i32)
  (do
    (return (+ left right))))
```

The program entry uses the same shape:

```weave
(entry main
  (params)
  (returns i32)
  (do
    (return 42)))
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
function. Canonical source may call it with `(call ANSWER)`; the explicit
compatibility spelling is `(call_i64 ANSWER)`.

Nominal struct constants are not admitted. Construct a value inside a function
with `(new TYPE ...)` instead.

## Struct declarations and semantic operations

A struct declaration is:

```weave
(struct Buffer
  (field data ptr)
  (field len i64)
  (field cap i64))
```

The name `Buffer` becomes a nominal type and may appear in parameters, returns,
and local declarations. Forward references within one input set are resolved
deterministically; an unresolved type name is rejected before successful output
publication.

Canonical construction uses named fields:

```weave
(let buffer Buffer
  (new Buffer
    (cap capacity)
    (data pointer)
    (len 0)))
```

The compiler rejects malformed, unknown, duplicate, missing, or mistyped fields
and emits constructor arguments in declaration order. Source field order does not
change the generated object layout or call ABI.

Canonical field operations are:

```weave
(field-get buffer len)
(field-set buffer len new-length)
```

The receiver's nominal type resolves the field and generated accessor. Plain
`ptr`, non-struct values, unknown fields, and incompatible assigned values are
rejected.

A nominal struct value may be passed to an explicitly declared `ptr` parameter,
for example `(call free buffer)`. The reverse conversion from arbitrary `ptr` to
a struct and substitution between distinct struct types are not implicit.
Nominal values support equality or inequality with the same nominal type or an
explicit pointer value such as `null`; arithmetic and ordering are not admitted.

For low-level compatibility, each declaration still generates:

```text
Buffer_new
Buffer_get_data
Buffer_set_data
Buffer_get_len
Buffer_set_len
Buffer_get_cap
Buffer_set_cap
```

New source should use `new`, `field-get`, and `field-set`. See
[Semantic structs](semantic-structs.md) and
[Struct layout and compatibility ABI](struct-layout.md).

## Local bindings and assignment

A typed local binding is:

```weave
(let answer i32 42)
```

Integer literal sugar is accepted in authoritative numeric contexts:

```weave
(let x i32 40)
(let y i64 2)
```

Update an existing local with:

```weave
(set answer (+ answer 1))
```

The raw backend represents mutable locals with stack slots. The selected LLVM
optimization profile promotes eligible loop-carried values to SSA phis. See
[LLVM code-generation analysis](llvm-codegen-analysis.md).

## Blocks and control flow

`do` is an ordered statement block:

```weave
(do
  statement...
  (return expression))
```

An `if` statement is `(if CONDITION THEN ELSE)`. Each branch is one form.
Multi-statement branches use `do`. No-else guards use `when`:

```weave
(if (< value limit)
  (return value)
  (return limit))
(when (< value 0)
  (return 0))
```

An `if` whose branches are expressions is a value; else is required and the
branch types must agree. It initializes a `let` or is returned:

```weave
(let n i32 (if flag 1 2))
```

A `while` loop is `(while CONDITION STATEMENT...)`:

```weave
(while (< index limit)
  (set index (+ index 1)))
```

A counted `for` binds a name over a half-open integer range `[START, END)`:

```weave
(for (range i 0 n)
  (do
    statements...))
```

`i` is `i32`. `START` and `END` must be `i32`. `(break)` leaves the nearest
loop. `(continue)` skips the rest of the current iteration; a `for` still
advances the index. Both are rejected outside a loop.

`return` takes one expression for a typed function. There is no implicit
tail-expression return: every path of a non-void function must reach
`(return EXPR)`. Void functions use a bare `(return)` or:

```weave
(return_void)
```

Falling off the end of a function is a frontend error with code
`frontend.function.missing-return`. The diagnostic names the function and
spans the statement that can fall through.

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

Surface string literals are:

```weave
"hello\nworld"
#"hello\nworld"
"""hello
world"""
#"""hello\n
world"""
```

`"..."` is the existing escaped spelling. `#"..."` is raw: every byte
between the quotes is kept, including backslash. `"""..."""` is
multiline: the closer is three quotes and newlines are part of the
content. `#"""..."""` is both raw and multiline. There is no
interpolation. All four lower to one `(const_string_ptr "...")`. Raw
and multiline content is re-escaped so the existing WIR decode
reconstructs the source bytes.

`(interp PIECE...)` builds one text pointer from adjacent pieces:

```weave
(interp "count=" n " ok=" flag)
```

String literals and expressions of type `i32`, `i64`, `bool`, or `ptr`
are admitted. Integers print as decimal without leading zeros. Booleans
print as `true` or `false`. A text pointer is copied as a C string.
Floating values, `void`, `null`, and unknown types are rejected. The
result is `ptr` until a `String` type exists. There is no printf-style
format string and no interpolation inside `"..."`.

Floating constants currently use integer literal tokens and lower through an
integer-to-floating conversion. Decimal literal syntax is not yet part of the
stable surface contract.

Canonical operators occupy Lisp head position:

```weave
(+ left right)
(< left right)
(= pointer null)
(and ready valid)
(not failed)
```

`(op add left right)` and the other wrapped long names remain accepted
compatibility input, and `weavec fmt` rewrites them to the compact heads.

Canonical casts name the target type:

```weave
(cast i64 value)
(cast i32 wide-value)
```

Explicit WIR-shaped operators such as `add_i32`, `eq_ptr`, `and_bool`, and
`cast_i64_to_i32` remain accepted for compatibility and compiler implementation
code. The compiler rejects unknown operators, wrong arity, mixed known operand
types, unsupported casts, and pointer equality on enum values.

## Calls

Canonical calls occupy Lisp head position:

```weave
(function arguments...)
```

`(call function arguments...)` remains accepted compatibility input, and
`weavec fmt` rewrites it to the head-position form. A function whose name
collides with reserved syntax is rejected.

The compiler resolves the declaration, return representation, arity, and known
argument types. Explicit compatibility forms remain available:

```weave
(call_i32 function arguments...)
(call_i64 function arguments...)
(call_f32 function arguments...)
(call_f64 function arguments...)
(call_bool function arguments...)
(call_ptr function arguments...)
(call_void function arguments...)
```

A void call is a statement; typed calls are expressions.

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
(fn clamp ((x i32) (lo i32) (hi i32)) i32
  (requires (<= lo hi))
  (ensures (>= result lo))
  (ensures (<= result hi))
  ...)
```

Verbose `(params ...)`, `(returns ...)`, and a wrapping function-level
`(do ...)` remain accepted. Within `ensures`, `result` denotes the value at
each return site. Using `result` in `requires` is rejected.

Effect declarations use a grouped clause of registry identifiers:

```weave
(effects pure deterministic)
```

Standalone `(pure)`, `(no_alloc)`, and `(deterministic)` remain accepted
compatibility markers.

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
(return c0)
```

The frontend lowers measurement to an `i32` runtime call and introduces the
named local in emitted WIR. Current lowering uses external quantum-runtime calls,
and the included runtime is only a test stub. Hadamard nativization and selected
peephole optimizations occur before WIR emission. See
[Quantum surface support](quantum.md).

## Diagnostics and unsupported syntax

The compiler reports malformed forms, wrong arity, unknown operators, unresolved
identifiers and types, nominal mismatches, and contract violations through
human-readable stderr. `weavec build --diagnostics-json` additionally provides
stable phase codes and structured diagnostics.

The following are not current surface contracts:

- C-like or indentation-based alternate syntax;
- implicit numeric conversions;
- implicit conversion from arbitrary `ptr` to a nominal struct;
- aggregate-valued struct fields;
- a separate quantum source format;
- arbitrary decimal floating literals;
- private final-compiler WIR forms added without a coordinated version transition;
- the removed implicit `weavec input.wir output.ll` backend command.
