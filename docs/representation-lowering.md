# Representation lowering

Status: Active design  
Date: 2026-05-25  
Audience: weavec0 / weavec1 / weavec, quantum surface syntax, transform passes

## Principle: quantum is surface Weave

Quantum gates and circuits are not a separate language or file format. They are
ordinary Weave surface syntax — types, functions, statements, and transform
rules — compiled by the same pipeline as classical code.

There is no `.qir` (or similar) test or source extension. Programs are `.weave`
files. Lowering stages are compiler phases and optional dump flags, not new
on-disk formats.

Older design notes may say "QIR" for an in-memory quantum node family (S-expr
shapes inside the compiler). That is not a user-facing artifact. See
[quantum pipeline](../../../docs/design/quantum-computing/02-pipeline-architecture.md)
with this clarification in mind.

## Compiler chain

```text
weavec0   LLVM seed → compiles WIR
weavec1   WIR-written compiler → built by weavec0
weavec-bootstrap surface parse + sexpr runtime (in weavec)
weavec   surface .weave → WIR → LLVM
```

pybs is out of scope. All work uses `weave/weavec0`, `weave/weavec1`,
`weave/weavec`.

## Two mechanisms

| Mechanism | When | Role |
|-----------|------|------|
| Macro expansion | Early surface | Syntax sugar, DSL conveniences |
| Transform pass | Typed IR phases | H → native rotations, opts, routing prep |

Example surface code (target shape, not final syntax):

```weave
(program
  (name "bell-prep")
  (entry main
    (params ())
    (returns Int32)
    (body
      (let q0 Qubit (qubit-alloc))
      (let q1 Qubit (qubit-alloc))
      (gate H q0)
      (gate CNOT q0 q1)
      (measure q0 c0)
      (return 42))))
```

The user writes `gate H q0`. A `lower` transform pass rewrites it to the target
native gate sequence before codegen. That rewrite is not a separate file — it
runs inside the compiler on the same AST/IR graphs as everything else.

## Pipeline (classical + quantum in one program)

```text
.weave source
  │  parse
  ▼
Surface AST (classical + quantum forms together)
  │  macros expand
  ▼
Typed surface
  │  transform passes (category lower): nativize, desugar, …
  ▼
Mid IR / WIR (quantum ops lowered or embedded per target)
  │  weavec backend
  ▼
LLVM (+ device calls for quantum hardware when targeting QPUs)
```

Classical regression today: `test/performance/*.wir` → LLVM goldens.

Quantum regression (planned): `test/quantum/*.weave` — surface programs and
expected compiler output (WIR slice, LLVM slice, or `--dump-phase=` text), same
discipline as performance tests, no extra extension.

## Hadamard nativization example

Surface:

```weave
(gate H q0)
```

After `nativize-hadamard` for a device whose native set includes `RY` and `RZ`
but not `H`:

```weave
(gate RY q0 1.5707963267948966)
(gate RZ q0 3.141592653589793)
```

Declared as a first-class transform rule (see
[transformations](../../../docs/design/transformations/03-syntax-overview.md),
[rewrite metadata](../../../docs/design/quantum-computing/06-rewrite-system.md)):

```weave
(transform-rule nativize-hadamard
  (metadata
    (consumes (gate H ?q))
    (emits (gate RY ?q ...) (gate RZ ?q ...))
    (stage nativization)
    (cost-delta +1))
  (pattern (gate H ?q:Qubit))
  (replacement
    (seq
      (gate RY ?q (const 1.5707963267948966))
      (gate RZ ?q (const 3.141592653589793))))
  (when (native? RY RZ)))
```

Exact surface spellings (`gate`, `qubit-alloc`, …) will follow the language
grammar when implemented; the invariant is: one language, many lowering passes.

## weavec boundaries

| Layer | Location | Responsibility |
|-------|----------|----------------|
| Surface grammar | language spec + `src/frontend/` | Parse quantum and classical forms |
| Lowering passes | `src/frontend/` or dedicated transform module | Nativize, validate, target packs |
| WIR → LLVM | `src/llvm/` | Codegen only; no gate decomposition |
| Tests | `test/performance/` (today), `test/quantum/` (planned) | Goldens from `.weave` inputs |

## Implementation status

| Component | Status |
|-----------|--------|
| weavec0 / weavec1 / weavec classical path | Active |
| Surface `qgate` / `qmeasure` | Implemented in `emit.weave` (v1) |
| Transform engine in Weave | Spec only; rules stub in `targets/rigetti-nativize.weave` |
| Quantum frontend goldens | `test/quantum/test.sh` (nativization, benchmarks, optimization) |
| Quantum metrics (`--dump-quantum-stats`) | `.metrics` sidecars in `test/quantum/` |
| H·H peephole | `test/quantum/optimization/test-double-h-cancel.weave` |
| Separate `.qir` files | Rejected — not used |

## Recommended order

1. Surface types and statements: `Qubit`, `gate`, `measure`, …
2. Parse and typecheck in weavec frontend (same as `let`, `if`, calls).
3. `transform-pass nativize` on typed surface (first rule: H).
4. Golden tests: `test/quantum/nativization/test-hadamard-single.weave` + expected
   dump or lowered WIR fragment.
5. Architecture packs, routing, device codegen.

## See also

- [Quantum surface syntax (proposal)](quantum-surface-syntax.md)
- [Performance demonstrations](performance-demonstrations.md)
- [Quantum computing design (concepts)](../../../docs/design/quantum-computing/README.md)
- [Transformations proposal](../../../docs/design/transformations/README.md)
