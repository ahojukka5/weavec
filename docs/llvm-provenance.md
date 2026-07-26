# LLVM source provenance and quality budgets

`weavec build` can annotate generated LLVM IR with comment-only provenance from
its original ordered surface inputs:

```sh
weavec build library.weave main.weave -o application \
  --llvm-provenance
```

`--llvm-provenance` implies `--keep-temporaries`. The compiler prints the
retained build directory on stderr, and its `program.ll` contains comments such
as:

```llvm
; weave.source kind=statement index=1 bytes=144..190 \
;   wir-bytes=627..844 path="main.weave"
```

The actual comment is one line. It identifies:

- `kind` — `function` or `statement`;
- `index` — the zero-based original build-input index;
- `bytes` — a half-open UTF-8 byte range in the original surface file;
- `wir-bytes` — the corresponding half-open byte range in temporary WIR;
- `path` — the source path exactly as supplied to `weavec build`.

A comment appears immediately before the LLVM group generated for that source
form. Instructions inside the group therefore remain easy to relate to both the
surface form and its lowered WIR representation without introducing LLVM debug
metadata or changing code generation semantics.

## Compatibility

The feature is opt-in. Without `--llvm-provenance`, ordinary WIR and LLVM remain
unchanged. The transport uses comments that are already legal under frozen WIR
v2 and LLVM syntax:

```text
; weavec-source-file-v1 <source-index> "<path>"
; weavec-source-span-v1 <source-index> <start-byte> <end-byte>
```

Direct WIR without these comments remains accepted. Even when the internal LLVM
provenance channel is enabled, plain WIR produces no invented source comments.
The metadata is observational and must never affect instruction selection,
control flow, names, or runtime behavior.

## Naming and inspection

Generated LLVM deliberately uses stable semantic names where the compiler knows
the role:

- `%name.addr` for mutable stack storage;
- `%name.phiN`, `%name.nextN`, and `%name.mergeN` for loop-carried values;
- `while.*`, `then*`, `else*`, and `endif*` for control-flow blocks;
- `%tN` only for short-lived expression temporaries.

This keeps the pre-optimization IR reviewable. A provenance comment establishes
the surface and WIR context; semantic SSA and block names then make unnecessary
loads, stores, casts, branches, and identity operations visible within that
context.

## Structural quality budgets

The repository runs:

```sh
scripts/check-llvm-quality.sh
```

against every checked-in performance LLVM golden. The versioned baseline stores
per-fixture ceilings for:

- total LLVM instructions;
- `alloca`, `load`, and `store` counts;
- calls, phis, and branches;
- obvious identity operations such as integer `add ..., 0`.

The check also rejects anonymous numeric SSA values, numeric block labels,
`undef`, and `poison`. Lower counts pass automatically. An increase requires an
explicit baseline update and review:

```sh
scripts/check-llvm-quality.sh --write-baseline
```

The budgets are regression guards, not a mathematical proof of globally optimal
machine code. They create a ratchet: as code generation improves, budgets can be
lowered and cannot silently rise again. LLVM optimization tools may still be
used to identify remaining headroom, but the long-term target is for important
performance fixtures to approach an optimization fixed point where generic LLVM
passes cannot remove meaningful work.

## Relationship to the compilation trace

[`weavec-compilation-trace-v1`](compilation-trace.md) explains which frontend
lowerings and rewrites occurred. LLVM provenance answers where the resulting
functions and statements came from. Together they provide a continuous path:

```text
surface source -> trace event -> WIR form -> LLVM instruction group
```

A future report renderer should consume these stable compiler outputs through a
reusable JSON/HTML library boundary. It should not duplicate lowering logic or
introduce an unrelated scripting-language implementation into the compiler.
