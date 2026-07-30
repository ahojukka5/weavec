# Canonical LLM-facing surface forms

Weave keeps S-expressions as its primary source representation. Canonical surface
forms optimize for deterministic generation, validation, structural editing, and
repair rather than minimum character count.

This document describes the first typed-elaboration slice. WIR core version 2 is
unchanged.

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

## Contextual literals

A literal may omit its WIR constructor when an authoritative expected type is
available locally. The initial contexts are:

- typed `let` initializers;
- assignment to a known local;
- typed function arguments;
- function return expressions.

Examples:

```weave
(let count i64 0)
(set count 1)
(return 42)
(call choose true 40 2)
(call consume-pointer null)
(call consume-string "weave")
```

The compiler emits explicit WIR constructors such as `const_i64`, `const_bool`,
`const_null`, and `const_string_ptr`.

Context does not introduce numeric promotion. An explicit `i32` expression passed
to an `i64` parameter remains a type error. Existing explicit casts remain
required until the canonical `(cast TYPE EXPR)` slice is implemented.

## Deterministic type rules

- Function names resolve exactly and case-sensitively.
- Duplicate declarations are rejected.
- Call arity must match the registered signature.
- Known argument types must match exactly.
- Integer widths are never guessed or promoted.
- Unknown or ambiguous calls fail rather than selecting an arbitrary WIR form.
- Legacy explicit expressions remain valid and can coexist with canonical calls.

## Contracts

Canonical calls are elaborated inside ordinary contracted function bodies and in
contract expressions that do not substitute `result` through the call.

A canonical call containing `result` inside an `ensures` expression is rejected
by this initial slice with an explicit frontend error. Existing explicit typed
call syntax remains available there until result-aware canonical call emission is
implemented.

## Implementation boundary

The self-hosted frontend owns declarations, type codes, symbol resolution, type
checks, diagnostics, and WIR selection. A narrow C host component only retains
copied symbol and local-name records across separately parsed source files. It
does not parse Weave, recognize type names, or choose language semantics.

The next issue-#49 slices add canonical generic operations and canonical casts.
The capability registry in issue #36 will eventually expose canonical versus
legacy forms to Jacquard and other agents.
