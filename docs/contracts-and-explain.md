# Executable contracts and explain mode

Status: implemented in `weavec`

Weave functions may declare runtime preconditions and postconditions, plus
conservatively checked effect contracts. The compiler can also explain and audit
surface functions without generating WIR or LLVM.

## Runtime contracts

Optional `(requires ...)` and `(ensures ...)` clauses appear after `(returns ...)`
and before `(do ...)`:

```weave
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
```

Rules:

- Multiple `requires` and `ensures` clauses are allowed.
- Contract expressions use ordinary supported boolean and integer forms.
- In `ensures` only, `result` denotes the value at the current return site.
- Using `result` in `requires` is rejected during frontend lowering.
- Functions without contract clauses compile unchanged.

### Runtime behavior

| Clause | Check point | Failure behavior |
|---|---|---|
| `requires` | Function entry | `contract failed: requires` on stderr, exit `1`. |
| `ensures` | Before every return, including nested returns | `contract failed: ensures` on stderr, exit `1`. |

The frontend inserts runtime checks during surface-to-WIR lowering. The current
compiler does not attempt theorem proving or symbolic proof of these expressions.

Relevant implementation boundaries are:

- `src/frontend/contract-lower.weave` — contract lowering;
- `runtime/portable.c` — compiler-host definition of
  `weave_rt_contract_fail`;
- `runtime/program.c` — program-runtime definition packaged privately;
- `src/llvm/module.weave` — backend declaration used by linked programs.

## Effect contracts

Marker clauses have no expression child:

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

| Clause | Declared property |
|---|---|
| `pure` | No heap allocation and no known runtime I/O or impure external calls. |
| `no_alloc` | No allocation in the function or reachable local callees. |
| `deterministic` | No known nondeterministic or unknown external effects. |

Malformed markers such as `(pure true)` are rejected.

Analysis is conservative and name-based. Direct effects are collected from each
function body and propagated through calls to local functions until a fixpoint is
reached, including mutual recursion.

Examples of conservative classifications:

- `no_alloc` fails on `malloc`, `realloc`, or reachable local allocation;
- `pure` fails on allocation, known I/O/fatal calls, `free`, or unknown external
  callees;
- `deterministic` fails on known nondeterministic operations such as file reads
  and on unknown external callees.

Effect markers do not insert runtime checks. Ordinary frontend compilation keeps
working and audit output reports the result. Strict frontend mode rejects failed
claims:

```sh
weavec --frontend --strict-contracts output.wir input.weave
```

## Explain mode

Print a structural summary without generating code:

```sh
./build/weavec --explain path/to/program.weave
```

The report includes:

- function name and return type;
- parameters;
- `requires` and `ensures` clauses;
- return, loop, and call-site counts;
- external calls and callees;
- allocation count;
- number of runtime contract checks that lowering would insert.

JSON output for tooling:

```sh
./build/weavec --explain-json path/to/program.weave
```

Explain mode parses the surface file and walks its AST. It does not write WIR,
LLVM, or a native executable.

## Audit mode

Human-readable effect audit:

```sh
./build/weavec --audit path/to/program.weave
```

JSON audit:

```sh
./build/weavec --audit-json path/to/program.weave
```

Audit mode includes explain counts plus conservative purity and declared-effect
results. Representative JSON fields are:

```json
{
  "effect_contracts": {
    "no_alloc": "verified",
    "pure": "failed",
    "deterministic": "unknown"
  },
  "effect_reasons": [
    "pure failed: calls impure function"
  ],
  "purity": "impure"
}
```

Functions without effect declarations use `"effect_contracts": null` and still
receive a conservative `purity` classification in audit JSON.

## Entry-point handling

Each full `(fn ...)` is reported. An `(entry ...)` body is included when no
function with the same name exists. A stub `(entry name)` receives only an
entry-only summary.

## Field definitions

| Field | Meaning |
|---|---|
| Return sites | Number of `return` forms, including nested returns. |
| Contract checks inserted | Requires count plus ensures count multiplied by return sites. |
| Loop sites | Number of `while` forms. |
| Call sites | Number of typed and void call forms. |
| External calls | Calls whose target is not a local function or entry. |
| External callees | Sorted unique external target names. |
| Allocations | Pointer bindings and allocation calls recognized by the analysis. |

These are structural source summaries, not dynamic profiling measurements.

## Tests

Correctness fixtures live under:

```text
test/correctness/surface/
test/correctness/contracts/
```

They cover successful and failing runtime contracts, strict effect-contract
validation, indirect effects, mutual recursion, malformed markers, explain text
and JSON, and audit text and JSON.

Run correctness tests with:

```sh
./build.sh
./test.sh
```

Run the complete compiler ladder with:

```sh
./test-all.sh
```

The full ladder also includes performance, quantum, quantum end-to-end, LLVM, and
self-host checks.

## Limitations

- Contract expressions are limited to forms already accepted by the surface
  frontend.
- Runtime contracts are executable checks, not static proofs.
- Effect analysis is conservative and name-based; unknown external calls prevent
  strong conclusions.
- Exact per-contract source locations are not yet propagated through WIR.
- Contracted functions currently use the contract-aware lowering path rather than
  every optimization available to an uncontracted body.
