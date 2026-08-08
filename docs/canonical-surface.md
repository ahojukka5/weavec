# Canonical LLM-facing surface forms

Weave keeps S-expressions as its primary source representation. Canonical surface
forms optimize for deterministic generation, validation, structural editing, and
repair rather than minimum character count.

This document describes the implemented typed-elaboration forms. WIR core version
2 is unchanged.

## Canonical calls

Ordinary source should use one return-type-independent call form:

```weave
(call add-two left right)
```

The compiler resolves `add-two` from declarations collected across all input
files, checks its arity and known argument types, and emits the corresponding
canonical WIR form such as:

```weave
(call_i32 add-two left right)
```

The caller may appear before the declaration or in another input file. Source
argument order does not limit semantic lookup.

Existing explicit forms such as `call_i32`, `call_i64`, `call_ptr`, and
`call_void` remain accepted for compatibility and low-level compiler sources.
They are not the preferred representation for newly generated application code.

## Canonical operators

Generated application source should use `(op NAME OPERANDS...)`. The compiler
selects the admitted typed WIR operator from the operand types:

```weave
(op add left right)
(op less-than index limit)
(op equal pointer null)
(op and ready valid)
(op not failed)
```

The canonical names are:

- arithmetic: `add`, `sub`, `mul`, `div`, and `mod`;
- integer bit operations: `bit-and`, `bit-or`, `bit-xor`, `shift-left`, and
  `shift-right`;
- comparisons: `equal`, `not-equal`, `less-than`, `less-or-equal`,
  `greater-than`, and `greater-or-equal`;
- Boolean operations: `and`, `or`, and `not`.

The short arithmetic names deliberately match the established WIR and common
programming-language vocabulary. The former long surface spellings `subtract`,
`multiply`, `divide`, and `remainder` are not canonical forms.

Arithmetic supports `i32`, `i64`, `f32`, and `f64`. Bit operations support
`i32` and `i64`. Ordered comparisons support numeric operands, while pointer
operands support only `equal` and `not-equal`. Nominal struct values use pointer
equality only with the same nominal type or an explicit `ptr` value such as
`null`. Boolean operations require `bool` operands.

Two otherwise unconstrained integer literals use the canonical `i32` default.
When one operand has a known type, an integer literal on the other side uses that
same numeric type. Mixed known operand types are rejected; the compiler never
inserts a numeric conversion.

A decimal atom with digits on both sides of the decimal point, such as `1.5` or
`7.0`, has intrinsic `f64` type when no stronger context exists. An authoritative
`f32` context may lower the same spelling to `const_f32`; there is still no
implicit promotion between already-typed numeric expressions.

## Canonical casts

An explicit conversion names only its target type:

```weave
(cast i64 count)
(cast f64 value)
(cast i32 wide-value)
```

The compiler determines the source type and emits the corresponding WIR v2 cast.
Only conversions already admitted by WIR are accepted:

- `i64` to `i32`;
- `i32` to `i64`, `f32`, or `f64`;
- `f32` to `i32` or `f64`;
- `f64` to `i32` or `f32`.

Unsupported pairs fail explicitly. There are no implicit casts, and a canonical
cast is not a request to guess a conversion path through intermediate types.

Legacy forms such as `add_i32`, `lt_i64`, `and_bool`, and
`cast_i64_to_i32` remain accepted for compatibility and compiler
implementation code.

## Semantic structs

Struct declarations introduce nominal surface types. Source construction and
field access use self-describing canonical forms:

```weave
(new Record
  (total 2)
  (flag true)
  (count 40))

(field-get record count)
(field-set record count new-count)
```

The compiler resolves the declaration across all input files, rejects unknown,
duplicate, missing, or mistyped constructor fields, and emits constructor
arguments in declaration order. Field operations resolve from the receiver's
nominal type; agents never synthesize generated accessor names.

A nominal struct lowers physically to WIR `ptr`, but distinct struct names remain
distinct surface types. A struct value may flow to an explicitly declared `ptr`
parameter, such as `free`, while the reverse conversion and cross-struct
substitution remain invalid. The generated `TYPE_new`, `TYPE_get_FIELD`, and
`TYPE_set_FIELD` names remain compatibility-only forms.

`weavec fmt` normalizes complete, unambiguous constructors into declaration order.
A comment immediately preceding a field clause moves with that field. Malformed,
unknown, duplicate, or incomplete constructors retain source order so formatting
does not conceal the compiler diagnostic. See
[Semantic structs](semantic-structs.md).

## Contextual literals

A literal may omit its WIR constructor when an authoritative expected type is
available locally. The current contexts are:

- typed `let` initializers;
- assignment to a known local;
- typed function arguments;
- function return expressions;
- operands whose canonical operator determines one exact type;
- named struct constructor fields.

Examples:

```weave
(let count i64 0)
(let gain f64 1.5)
(set count 1)
(return 42)
(call choose true 40 2)
(call consume-pointer null)
(call consume-string "weave")
(op add count 1)
(op add 1.5 2.25)
(new Record (count 42) (flag true))
```

The compiler emits explicit WIR constructors such as `const_i64`, `const_f64`,
`const_bool`, `const_null`, and `const_string_ptr`.

Context does not introduce numeric promotion. An explicit `i32` expression passed
to an `i64` parameter remains a type error. Use `(cast i64 expression)` when an
admitted explicit conversion is intended.

## Deterministic type rules

- Names resolve exactly and case-sensitively.
- Duplicate declarations are rejected.
- Call and operator arity must match the selected form.
- Known argument and operand types must match exactly.
- Nominal struct names are never treated as interchangeable because their layouts
  happen to match.
- Integer widths are never guessed or promoted.
- Unknown, mixed, or unsupported expressions fail rather than selecting an
  arbitrary WIR form.
- Legacy explicit expressions remain valid and can coexist with canonical forms.

## Contracts

Canonical calls, operators, casts, and contextual literals use the same
elaboration rules in function bodies, `requires`, and `ensures`. Semantic struct
field operations are currently body forms; contract-specific result substitution
for field access remains outside this experimental slice.

Within an `ensures` expression, `result` has the declared return type and is
substituted with the concrete expression at each return site. Canonical forms may
contain `result` at any nesting depth:

```weave
(ensures
  (op equal
    (cast i64 (call identity result))
    (cast i64 result)))
```

The compiler resolves and type-checks the canonical tree before emitting ordinary
WIR v2 forms. A call argument or operator operand whose known type disagrees with
the function return type is rejected; no conversion is inferred from the contract
context. `result` remains invalid in `requires`.

## Implementation boundary

The self-hosted frontend owns declarations, type codes, symbol resolution, type
checks, diagnostics, result substitution, and WIR selection. A narrow C host
component only retains copied symbol, local, struct, and field-name records across
separately parsed source files. It does not parse Weave, recognize syntax, or
choose language semantics.

Canonical operator, cast, contract-expression, and struct selection is
implemented in dedicated self-hosted frontend modules. They consume compiler-owned
semantic facts and emit only admitted WIR core-version-2 forms; they add no private
WIR dialect or target-runtime semantic state.
