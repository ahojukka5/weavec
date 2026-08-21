# Ownership requirements for concurrency and GPU

This appendix is input to issue #115. It is a decision record, not shipped
behaviour. Ownership must be specified against aliasing, tasks, and
device kernels now, or those goals are priced out by a model built only
for sequential resource safety.

The first #115 stage remains the explicit `(unsafe ...)` boundary. These
rules constrain that design; they are not a parallel tracker.

## Exclusive borrow is `noalias`

An exclusive borrow (`&mut`-equivalent) must be strong enough that
lowering may put LLVM `noalias` on the pointer. Shared borrows must not.

If two live exclusive borrows can alias, the attribute is a lie and
optimizers will miscompile. The surface spelling, including a later
`foo!` mutable-access name from issue #336, consumes this fact. It does
not invent a second mutability lattice.

Interior pointers from inline struct fields are already borrows of the
parent ([Struct value semantics](struct-ownership.md)). They inherit
the parent's exclusivity. They never justify `noalias` on their own
unless the parent borrow is exclusive and no other path to those bytes
is live.

## Shareable across tasks

Every owned type is in one of two classes, even while there is only one
thread:

| Class | Meaning |
|---|---|
| Task-shareable | A value may be moved to another task or read through a shared borrow from more than one task. Scalars, `Copy` types, and later immutable buffers belong here. |
| Task-exclusive | A value may be owned by one task. Mutation stays behind an exclusive borrow. |

This is the Send/Sync seam. The names need not ship. The class must
exist in the model so GPU buffers, file handles, and later threads do
not all become "just `ptr`".

A type with an interior exclusive borrow is task-exclusive. A type that
owns a non-shareable resource (`TextFile`, a device buffer) is
task-exclusive until an explicit wrapper says otherwise.

## Parallel and GPU eligibility

A function is kernel-eligible when the existing effect auditor can
prove it `pure` and `no_alloc` over slice arguments that are either
exclusive (output, `noalias`) or shared-immutable (input). Do not add
a second effect system for devices.

`deterministic` is required for bit-reproducible kernels. It is not
enough by itself: a deterministic function that allocates is not a
GPU kernel.

Parallel loops and GPU launches are not surface forms yet. When they
appear, they reuse this eligibility, not OpenMP pragmas or CUDA
dialects in the frontend.

## Crossing `extern ptr`

A nominal value that flows to an explicit `ptr` parameter is a one-way
representation escape ([Semantic structs](semantic-structs.md)). Under
ownership that escape is the `(unsafe ...)` boundary:

- borrows do not survive across it
- `noalias` does not survive across it
- the callee may alias, retain, or free the pointer
- enum values still do not flow to `ptr`
  ([Enum values have no identity](enum-identity.md))

Generated `NAME_new` / `NAME_get_FIELD` / `NAME_set_FIELD` helpers are
the same boundary until they are taught ownership without changing
their ABI shape.

## What this does not settle

- Borrow spelling and whether borrows are inferred.
- The exact `Copy` set.
- Automatic cleanup at scope exit.
- A GPU or thread runtime.
- Whether `foo!` is the exclusive-call spelling; #336 only consumes
  the exclusive-borrow fact defined here.
