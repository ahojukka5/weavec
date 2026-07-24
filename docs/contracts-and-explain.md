# Executable contracts and explain mode

Status: Implemented in weavec  
Date: 2026-05-27  
See also: [representation-lowering.md](representation-lowering.md)

## Overview

Weave surface functions may carry executable contracts: boolean promises checked
at runtime during normal compilation. A separate compiler mode, `--explain`,
prints those promises and a small audit summary without generating code.

This is an MVP toward reproducible scientific and systems code where the
compiler can both enforce and describe what a function claims.

Non-goals in this version:

- Static theorem proving or dependent types
- Symbolic algebra over contract expressions
- A separate contract language or non s-expression syntax

## Surface syntax

Contracts attach to the standard weavec function form. Optional
`(requires …)` and `(ensures …)` clauses sit after `(returns …)` and before
`(do …)`:

```weave
(program
  (name "clamp-demo")
  (version "0.1")
  (entry main)
  (fn clamp
    (params (x i32) (lo i32) (hi i32))
    (returns i32)
    (requires (le_i32 lo hi))
    (ensures (ge_i32 result lo))
    (ensures (le_i32 result hi))
    (do
      (if
        (condition (lt_i32 x lo))
        (then (do (return lo)))
        (else (do)))
      (if
        (condition (gt_i32 x hi))
        (then (do (return hi)))
        (else (do)))
      (return x)))
  (fn main
    (params)
    (returns i32)
    (do
      (return (call_i32 clamp (const_i32 12) (const_i32 0) (const_i32 10))))))
```

Rules:

- Multiple `(requires …)` and `(ensures …)` clauses are allowed.
- Optional marker clauses `(pure)`, `(no_alloc)`, and `(deterministic)` declare
  effect contracts audited by the compiler.
- Contract expressions use the same boolean and integer forms as ordinary
  surface code (`le_i32`, `ge_i32`, bare parameter names, literals, and so on).
- In `(ensures …)` only, the identifier `result` refers to the value being
  returned at that return site.
- Using `result` inside `(requires …)` is rejected at compile time.

Functions without contract clauses compile unchanged.

## Effect contracts (`pure`, `no_alloc`, `deterministic`)

Marker clauses `(pure)`, `(no_alloc)`, and `(deterministic)` sit after
`(returns …)` and before `(do …)`, like `(requires …)` and `(ensures …)`. They
have no expression child:

```weave
(fn scale
  (params (x i32))
  (returns i32)
  (pure)
  (no_alloc)
  (deterministic)
  (do
    (return (mul_i32 x (const_i32 2)))))
```

| Clause | Meaning | Default `--frontend` | With `--strict-contracts` |
|--------|---------|------------------------|---------------------------|
| `pure` | No heap allocation and no known runtime I/O or libc calls | Compiles; audit reports status | `contract failed: pure` on stderr, exit 1 |
| `no_alloc` | No heap allocation in the function body | Compiles; audit reports status | `contract failed: no_alloc` on stderr, exit 1 |
| `deterministic` | No known nondeterministic or unknown external effects | Compiles; audit reports status | `contract failed: deterministic` on stderr, exit 1 |

Malformed markers such as `(pure true)` are rejected at compile time with
`malformed effect clause: … must have no arguments`.

Analysis is conservative and name-based. Direct body effects are collected from
the AST, then propagated across `(fn …)` and `(entry …)` calls in the same
program:

- `no_alloc` fails when the function or any reachable local callee allocates
  (`malloc`, `realloc`, or `(call_ptr malloc …)`).
- `pure` fails on allocation, known I/O or fatal runtime calls (`puts`,
  `putchar`, `weave_rt_write_file`, `weave_rt_fatal`, `free`, …), or unknown
  external callees.
- `deterministic` fails on known nondeterministic calls (`weave_rt_read_file`,
  `read`, `open`, …) or unknown external callees.

Fixpoint iteration resolves mutual recursion (for example two `(pure)` functions
that call each other with no heap or runtime effects still satisfy `(pure)`).

Unlike `requires` and `ensures`, these markers are not lowered to runtime
checks. Use `--audit` to review declared effect contracts; use
`--frontend --strict-contracts` to reject violations at compile time.

Example audit excerpt:

```text
Effect contracts:
  no_alloc: verified
  pure: verified
  deterministic: verified
```

On violation:

```text
Effect contracts:
  pure: FAILED
Reasons:
  pure failed: calls allocation function malloc
```

Implementation: `src/frontend/contract-effects.weave`.

## Runtime semantics

| Clause | When checked | On failure |
|--------|--------------|------------|
| `requires` | Function entry | Message `contract failed: requires` on stderr, exit code 1 |
| `ensures` | Immediately before each `return` (including returns nested in `if`) | Message `contract failed: ensures` on stderr, exit code 1 |

Lowering inserts runtime checks in the WIR/LLVM pipeline. There is no static
proof pass.

Implementation files:

- `src/frontend/contract-lower.weave` — contract lowering in the frontend
- `runtime/portable.c` — `weave_rt_contract_fail`
- `src/llvm/module.weave` — declares `weave_rt_contract_fail` for linked programs

## Explain mode

Print a human-readable audit of each `(fn …)` in a source file:

```sh
cd weave/weavec
./build.sh
./build/weavec --explain test/correctness/surface/64_contract_ensures_multi_return.weave
```

Example output (abbreviated):

```text
Function: clamp
Requires:
  (le_i32 lo hi)
Ensures:
  (ge_i32 result lo)
  (le_i32 result hi)
Returns: i32
Parameters:
  x: i32
  lo: i32
  hi: i32
Return sites: 3
Contract checks inserted: 7
Loop sites: 0
Call sites: 0
External calls: 0
External callees:
  (none)
Allocations: 0
```

JSON output for tooling:

```sh
./build/weavec --explain-json path/to/program.weave
```

Audit report (structured review output with purity and warnings):

```sh
./build/weavec --audit path/to/program.weave
```

JSON audit output for CI and tooling (explain counts plus effect-contract
verification fields):

```sh
./build/weavec --audit-json path/to/program.weave
```

Rich JSON fields per function when effect clauses are declared:

```json
"effect_contracts": {"no_alloc": "verified", "pure": "failed", "deterministic": "unknown"},
"effect_reasons": ["pure failed: calls impure function"],
"purity": "impure"
```

Functions without effect clauses use `"effect_contracts": null` and still report
conservative `"purity"` from the effect table when audit JSON mode is active.

The weavec build patches vendored weavec-bootstrap to link with a 16 MiB main-thread
stack (`scripts/patch-weavec-bootstrap-stack.sh`); the default ~8 MiB stack overflows
when lowering the combined frontend that includes audit JSON helpers.

Explain and audit modes do not write WIR or LLVM. They parse the surface file and walk
the AST only.

Each `(fn …)` is listed. `(entry …)` forms are included when there is no
matching `(fn …)` with the same name: a full entry with body is summarized like
a function; a stub `(entry name)` only gets a minimal entry-only summary.

### Audit fields

| Field | Meaning |
|-------|---------|
| Return sites | Number of `(return …)` forms in the function body (including nested) |
| Contract checks inserted | `requires` count + `ensures` count × return sites (what lowering would emit) |
| Loop sites | Number of `(while …)` forms in the body |
| Call sites | Number of `(call_i32 …)`, `(call_i64 …)`, `(call_ptr …)`, `(call_void …)` forms |
| External calls | Call sites whose callee is not an `(fn …)` or `(entry …)` in the same program |
| External callees | Sorted unique names of external callees (for example `malloc`, `free`) |
| Allocations | `(let … ptr …)` bindings plus `(call_ptr malloc …)` sites |

These counts are structural summaries for development and review, not dynamic
profiling results.

## Tests

Correctness tests live under `test/correctness/surface/`:

| Test | Checks |
|------|--------|
| `61_contract_requires_ok.weave` | requires passes |
| `62_contract_requires_fail.weave` | requires failure message and exit 1 |
| `63_contract_ensures_ok.weave` | ensures passes |
| `64_contract_ensures_multi_return.weave` | ensures at every return (clamp) |
| `65_contract_ensures_fail.weave` | ensures failure |
| `66_contract_clamp_requires_fail.weave` | requires failure on bad bounds |
| `67_contract_pure_ok.weave` | `(pure)` satisfied; compiles with or without `--strict-contracts` |
| `68_contract_pure_fail.weave` | `(pure)` violated; rejected only with `--strict-contracts` |
| `69_contract_no_alloc_ok.weave` | `(no_alloc)` satisfied at compile time |
| `70_contract_no_alloc_fail.weave` | `(no_alloc)` violated; rejected only with `--strict-contracts` |
| `71_contract_pure_indirect_fail.weave` | `(pure)` violated via local callee |
| `72_contract_no_alloc_indirect_fail.weave` | `(no_alloc)` violated via local callee |
| `73_contract_pure_cycle_ok.weave` | mutually recursive `(pure)` functions |

Golden explain output: `test/correctness/contracts/64_explain.expected.txt`
(checked by `test/correctness/contracts/test-explain.sh`).

Malloc/while audit fixture: `test/correctness/contracts/explain_audit_malloc_while.weave`
with text and JSON goldens (checked by `test/correctness/contracts/test-explain-audit.sh`).

Audit report goldens: `test/correctness/contracts/audit_clamp.expected.txt`,
`test/correctness/contracts/audit_malloc_while.expected.txt`
(checked by `test/correctness/contracts/test-audit.sh`).

Run all weavec tests:

```sh
./test.sh
```

## Limitations and next steps

- Contract expressions are limited to forms the surface parser and lowering
  already support; there is no dedicated contract sub-language.
- Functions with contracts use a separate body-lowering path (no qgate peephole
  merge in that path).
- `declare void @weave_rt_contract_fail(ptr)` is emitted for all compiled
  modules today; contract tests link `runtime/portable.c` for the definition.

Planned extensions:

- Per-contract source spans in explain output
- Conditional `declare` of the contract runtime helper
