# Canonical Weave formatting

`weavec fmt` parses surface Weave with the compiler's own S-expression parser and
emits one deterministic textual normal form. It is intended for LLM generation,
structural editing, review, and repair loops where irrelevant spelling choices
should disappear before semantic work continues.

## Commands

```text
weavec fmt SOURCE
weavec fmt --check SOURCE
weavec fmt --output OUTPUT SOURCE
```

`weavec fmt SOURCE` formats `SOURCE` in place. `--output` leaves the source
untouched and atomically publishes the formatted document at `OUTPUT`.
`--check` performs no modification and returns nonzero when formatting would
change the source.

| Exit | Meaning |
|---:|---|
| `0` | Formatting succeeded, or `--check` found canonical source. |
| `1` | `--check` found noncanonical source. |
| `2` | Invalid formatter command line. |
| `3` | Source read, parse, formatting, comparison, or publication failed. |

In-place and explicit-output publication use a sibling temporary file and final
rename. A failed parse or format never replaces the source or a previous output.
The formatter preserves the source file mode for in-place updates.

## Normal form

The normal form uses:

- UTF-8 source bytes and LF line endings;
- two-space indentation;
- one space between inline children;
- no trailing horizontal whitespace;
- exactly one final newline;
- an 88-column inline budget;
- multiline `program`, `fn`, `entry`, `struct`, `if`, and `while` forms;
- multiline `do` forms when they contain more than one statement;
- original declaration, statement, field, clause, and argument order.

Formatting never sorts declarations or children. Source order remains semantic
and continues to be part of the bootstrap and multi-file compilation contract.
Formatting twice must produce byte-identical output to formatting once.

## Canonical surface normalization

The formatter emits the canonical forms published by
`weavec capabilities --json` when it can preserve meaning from parser and local
semantic facts.

| Compatibility input | Canonical output |
|---|---|
| `(call_i32 f x)` or `(call f x)` | `(f x)` |
| `(add_i64 x y)` | `(op add x y)` |
| `(eq_ptr x y)` | `(op equal x y)` |
| `(cast_i64_to_i32 x)` | `(cast i32 x)` |
| `(param_get x)` or `(local_get x)` | `x`, when the binding is authoritative |
| `(const_i32 1)` | `1`, in an authoritative `i32` context |
| `(const_i64 1)` | `1`, in an authoritative `i64` context |
| `(const_bool true)` | `true`, in a Boolean context |
| `(const_null)` | `null`, in a pointer context |
| `(const_string_ptr "text")` | `"text"`, in a pointer context |

Raw `#"..."` and multiline `"""..."""` (including `#"""..."""`) keep
their source delimiters. Content bytes are not rewritten.

A typed operator whose type would otherwise be lost receives a canonical type
anchor. For example:

```weave
(add_i64 (const_i64 1) (const_i64 2))
```

normalizes to:

```weave
(op add (cast i64 1) 2)
```

The cast is not an implicit conversion. It is an explicit canonical form that
preserves the already-declared operand type.

Typed calls normalize even when their declaration is in another input file,
because the function name and arguments are unchanged and the declaration remains
the compiler authority. Argument literals are simplified only when the current
file supplies an unambiguous parameter or binding type. Unknown, ambiguous, or
unsupported forms retain their original structural spelling rather than receiving
a guessed rewrite.

## Comments

The bootstrap parser exposes exact node spans but not comment nodes. The formatter
therefore recovers comments only from source gaps between parsed nodes:

- every semicolon comment is retained verbatim except trailing spaces and CR;
- a comment is attached before the next structural node in the same list;
- an end-of-list comment remains before that list's closing delimiter;
- leading and trailing file comments remain outside the root form;
- inline and trailing comments become deterministic standalone comment lines;
- blank-line trivia is normalized away.

Any non-whitespace, non-comment bytes found outside parsed node spans cause exit
`3`. The formatter does not silently discard source it cannot attach.

## Invalid and partial source

Formatting requires a complete parse tree. Lexically or structurally malformed
source is rejected and no destination is published. The formatter does not infer
missing parentheses, choose among ambiguous symbols, add declarations, or apply
semantic diagnostic repairs. Use `weavec build --diagnostics-json` for structured
failure context and bounded repairs, then run the formatter again after editing.

Semantically invalid but parseable forms may still receive whitespace
normalization. Compatibility rewrites are intentionally conservative: a rewrite
is emitted only when the encoded form or local declaration provides enough
information to preserve its intended canonical tree.

## Canonical form examples

Top-level declarations:

```weave
(program
  (name "example")
  (version "0.1")
  (const limit i32 8)
  (struct Pair
    (field left i32)
    (field right i32))
  (extern puts (params (message ptr)) (returns i32))
  (fn add-one
    (params (value i32))
    (returns i32)
    (pure)
    (no_alloc)
    (deterministic)
    (requires (op greater-or-equal value 0))
    (ensures (op greater-than result value))
    (do (return (op add value 1))))
  (entry main
    (params)
    (returns i32)
    (do (return (call add-one 41)))))
```

Statements and control flow:

```weave
(do
  (let current i32 0)
  (set current (op add current 1))
  (if
    (condition (op less-than current 10))
    (then (do (set current (op multiply current 2))))
    (else (do (set current 10))))
  (while
    (condition (op less-than current 20))
    (do (set current (op add current 1))))
  (return current))
```

Expression families:

```weave
(call function argument)
(op add left right)
(op not predicate)
(cast i64 value)
```

Void and quantum forms retain their canonical structural heads:

```weave
(return_void)
(qgate H qubit)
(qmeasure qubit result-name)
```

Experimental forms are formatted structurally but remain experimental according
to the capability registry. Formatting does not promote a feature's stability.

## Implementation boundary

The formatter is linked into the final compiler runtime and traverses the same AST
node API as frontend lowering. It does not use regular expressions, invoke an
external formatter, change WIR core version 2, or move language authority into
Jacquard. The capability registry marks `canonical-formatting` as stable and lists
the public `fmt` command so tooling can discover it from the compiler binary.
