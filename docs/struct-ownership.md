# Struct value semantics

This document records what binding, passing, and returning a struct means, and
why that question is answered by the ownership model rather than separately from
it.

It is a decision record, not a description of shipped behaviour. The current
behaviour is in "What the compiler does today", and it is a known gap.

## What the compiler does today

A struct value is a pointer, so binding aliases:

```weave
(let a Counter (new Counter (n 1)))
(let b Counter a)
(field-set b n 42)
(field-get a n)          ; 42 — a and b are the same object
```

Nothing in the surface says so, and every failure that follows is silent. This
program compiles and links with no diagnostic:

```weave
(fn consume (params (o Owner)) (returns void)
  (do (call free (field-get o block)) (call free o) (return)))

(entry main (params) (returns i32)
  (do
    (let a Owner (new Owner (block (call malloc 64)) (n 7)))
    (call consume a)              ; releases it
    (let after i32 (field-get a n))  ; use after release
    (call free a)                    ; second release
    (return after)))
```

Every standard module that allocates exposes an explicit release —
`vec3_release`, `mat3_release`, `samples_release`, `text_file_close` — and each
must be called exactly once, by convention only.

## Why "does it copy or alias" is the wrong question

The issue that raised this asked whether binding should copy or alias. Neither
answer solves the problem it was raised for.

Of the four standard struct types, `Vec3` and `Mat3` hold only scalars, while
`Samples` and `TextFile` each hold a `ptr` field naming heap storage they own. A
copy is field-wise, so copying a `Samples` produces two structs pointing at one
allocation, and releasing both frees it twice. Copy semantics moves the double
release from the struct to its contents; it does not remove it.

Deep copy would avoid that, but only by knowing which fields own their referent
and which merely point at something — which is ownership, reached by a longer
road and paid for with an allocation per binding.

So the question is not how a struct is duplicated. It is who is responsible for
releasing it, and that is what makes double release and use after release
detectable.

## Decision

**A struct value is an owned reference. Binding, passing, and returning move it;
there is no implicit copy. An alias requires an explicit borrow.**

This is not a separate decision from the ownership epic. Its second stage
already specifies move-only owned values that reject use after move and double
destruction. Structs are the first and most pressing instance of that, not a
special case beside it.

The consequence for this document is deliberate: **it does not add a
struct-specific ownership model.** A model built only for structs would be
replaced by the general one and would teach the compiler a second set of rules
in the meantime.

## What this decision contributes that the ownership epic does not

The general model has to hold for structs specifically, and struct
representation constrains it in ways worth stating before the model is built.

### Interior addresses are borrows, never owners

Inline nested layout means a struct-typed field occupies its parent's bytes.
Taking its address yields an interior pointer:

```text
(field_addr Outer inner (param_get o))   →   getelementptr i8, ptr %o, i64 8
```

That address must never be released, and it cannot outlive the parent. It is a
borrow whose lifetime is the owner's, and the model must be able to say so
before struct-typed fields reach the surface language.

This constraint did not exist before nested layout shipped; it is the direct
consequence of choosing inline layout over a pointer field.

### The compatibility ABI is a pointer boundary

[Struct layout and compatibility ABI](struct-layout.md) promises that `NAME_new`
returns `ptr` and that `NAME_get_FIELD` and `NAME_set_FIELD` take one. Those
signatures are a compatibility commitment, so ownership tracking must either
treat the generated helpers as an unsafe boundary or teach them ownership
without changing their shape.

### The existing pointer escape is where ownership is lost

[Semantic structs](semantic-structs.md) already documents that a nominal struct
value may flow to an explicitly declared `ptr` parameter, and calls it a one-way
representation escape. That is precisely the point at which an owner becomes an
untracked pointer, which makes it the natural home for the explicit `(unsafe
...)` boundary the ownership epic's first stage introduces, rather than a
separate mechanism.

### Struct-typed surface fields are blocked on this, deliberately

Nested layout is implemented in the backend, and the surface language still
admits no aggregate field. That is not an omission. `(new Outer (inner ...))`
has no answer without copy and move rules:

- what does the constructor receive for an inline field — a value to copy in, or
  an owner to move in;
- what does a generated `Outer_get_inner` return when `inner` is not a pointer;
- does assigning a nested struct copy its bytes.

Answering those inside the layout work would have decided value semantics
implicitly, which is the mistake this epic already made once by ordering the WIR
representation decision last.

## What this decision does not settle

- Whether any struct type is `Copy`. `Vec3` holds three `f64` and could
  reasonably be copied; `Samples` could not. That is the explicit `Copy` set the
  ownership epic's second stage defines, and it should be decided there with the
  primitives rather than here for structs alone.
- What the borrow spelling is, and whether borrows are inferred or written.
- Whether release becomes automatic at scope exit, which is the epic's fourth
  stage.
- Whether the standard modules' release functions disappear or become
  impossible to misuse. They cannot be removed until cleanup is automatic, so
  they outlive this decision.

## Interim posture

Until move checking exists, the alias semantics stay as they are and are
**documented as a gap rather than left unstated**. The failure modes are named
in [Semantic structs](semantic-structs.md) so a reader learns them from the
documentation instead of from a double free.

Nothing here should be worked around with a partial check. A release counter, a
dynamic guard, or a struct-only move pass would each add a rule the general
model then has to remove.

## Related documents

- [Semantic structs](semantic-structs.md)
- [Struct layout and compatibility ABI](struct-layout.md)
- [Next-version WIR struct fields](wir-next-struct-fields.md)
- [Language reference](language-reference.md)
