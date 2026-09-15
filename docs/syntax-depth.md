# Syntax tree-walk depth budget

Status: compiler-owned resource bound for untrusted S-expression
input ([#386](https://github.com/ahojukka5/weavec/issues/386),
[#466](https://github.com/ahojukka5/weavec/issues/466)).

Deeply nested generated source must fail with a stable diagnostic. It
must not crash with `SIGSEGV` or `SIGBUS`. Over-limit input is rejected
before recursive `parse_sexpr`, so diagnosing it does not need a large
host stack.

## Budgets

There are two finite budgets. Neither path is unbounded.

| Budget | Depth | Who it applies to |
| --- | ---: | --- |
| Public | **64** | Untrusted source and WIR |
| Internal generated WIR | **65** | Frontend output reparsed by `weavec build` |

The public integer is `tree_walk_max_depth` in
`src/parser/parser.weave` and `WEAVEC_TREE_WALK_MAX_DEPTH` in
`runtime/tree_walk_depth.h`. The internal integer is
`tree_walk_internal_wir_max_depth` and
`WEAVEC_TREE_WALK_INTERNAL_WIR_MAX_DEPTH`.

Opening one list past the active budget fails in the owning phase.
Ordinary programs and the compiler sources sit below the public bound
(the deepest current module is about 22). The numbers are a resource
contract, not a style preference.

The internal allowance is exactly one extra open list. Generated WIR
wraps the admitted surface tree in the `core-module` / `decls`
envelope, so a surface program at the public limit can become one list
deeper as WIR. That is why 65 is sufficient; the compiler never needs
an unlimited recursive parse.

A left-deep expression chain at depth 64 still uses one recursive
Weave frame per list in lowering and emission. That shape is not how
real modules are written; the qualification suite compiles a shallow
program plus compiler/stdlib modules, and rejects over-limit input
without compiling a 64-deep `add_i32` spine.

## Trust boundary

Ambient process environment cannot change the budget.
`WEAVEC_INTERNAL_WIR_PARSE` and any other inherited variable are
ignored.

| Invocation | Budget |
| --- | --- |
| `weavec build` surface sources | Public 64 |
| `weavec --frontend` | Public 64 |
| `weavec --backend <in.wir> <out.ll>` | Public 64 |
| `weavec fmt` | Public 64 |
| Project and semantic parser entry points | Public 64 |
| `weavec build` / project-cache reparse of frontend WIR | Internal 65 |

`weavec build` compiles generated WIR in a forked child of the same
process image. The child calls `weave_rt_tree_walk_enable_generated_wir`
and then `compile_file` in-process. It does not exec a user-spoofable
`--backend` with a public environment flag.

The same enable function is used by
`weavec --backend --generated-wir <in.wir> <out.ll>`, which exists so
tests can hit the exact internal bound. Direct `weavec --backend` with
two path arguments stays on the public budget even when that extra
marker is omitted and even when the caller sets leftover environment
variables.

On failure the diagnostic is:

- code `frontend.parse.nesting-too-deep` or
  `backend.parse.nesting-too-deep`
- message `nesting exceeds the compiler depth budget of N`, where `N`
  is the active budget (64 for untrusted input, 65 for generated WIR)
- span at the `(` that would exceed the budget
- no executable, WIR, or formatted output is published

## Where it is enforced

| Path | Mechanism |
| --- | --- |
| `weavec build` surface sources | Heap preflight in `runtime/diagnostics_driver.c`, then the parser |
| `weavec --frontend` | Iterative token walk in `parse_recorded`, then `parse_sexpr` |
| Direct `weavec --backend` | The same parser on untrusted WIR, public budget |
| Generated-WIR reparse | The same parser, internal budget 65 |
| `weavec fmt` | `parse_recorded`, then the formatter walk of a bounded tree |

The preflight and the token walk use an explicit heap stack or a
token-index loop, so over-limit input never enters `parse_sexpr`. The
recursive parser still checks, as a second line of defense.

## Walks that remain recursive

These walks still recurse, but only over trees the parser already
admitted, so their depth is at most the budget that admitted them
(64 public, 65 generated WIR):

- formatter `weave_fmt_format_node`
- backend `emit_expr` / `emit_stmt`
- frontend lowering and comment walks
- semantic-index and project-manifest `parse()` callers, which use the
  same parser and therefore cannot build a deeper tree

Compiler-owned trees that are not parsed from untrusted text (for
example interned type graphs) are not this bound. JSON publication uses
its own `WEAVE_JSON_MAX_DEPTH` of 32.

## Tests

`test/tree-walk-depth` compiles a shallow admitted program, rejects
depth 65 for untrusted surface, WIR, and `fmt`, accepts depth 64 on the
public bound, accepts depth 65 and rejects depth 66 on the internal
generated-WIR bound, and repeats the untrusted rejection under a
reduced `ulimit -s` and with spoofed `WEAVEC_INTERNAL_WIR_PARSE`.
