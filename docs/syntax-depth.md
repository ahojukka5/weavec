# Syntax tree-walk depth budget

Status: compiler-owned resource bound for untrusted S-expression
input ([#386](https://github.com/ahojukka5/weavec/issues/386)).

Deeply nested generated source must fail with a stable diagnostic. It
must not crash with `SIGSEGV` or `SIGBUS`. Over-limit input is rejected
before recursive `parse_sexpr`, so diagnosing it does not need a large
host stack.

## Budget

The admitted nesting depth is **64** open lists. The same integer is
defined in:

- `tree_walk_max_depth` in `src/parser/parser.weave`
- `WEAVEC_TREE_WALK_MAX_DEPTH` in `runtime/tree_walk_depth.h`

Opening a 65th list fails in the owning phase. Ordinary programs and the
compiler sources sit below this bound (the deepest current module is
about 22). The number is a resource contract, not a style preference.

A left-deep expression chain at depth 64 still uses one recursive
Weave frame per list in lowering and emission. That shape is not how
real modules are written; the qualification suite compiles a shallow
program plus compiler/stdlib modules, and rejects over-limit input
without compiling a 64-deep `add_i32` spine.

## Where it is enforced

| Path | Mechanism |
| --- | --- |
| `weavec build` surface sources | Heap preflight in `runtime/diagnostics_driver.c`, then the parser |
| `weavec --frontend` | Iterative token walk in `parse_recorded`, then `parse_sexpr` |
| `weavec --backend` | The same parser on WIR text |
| `weavec fmt` | `parse_recorded`, then the formatter walk of a bounded tree |

The preflight and the token walk use an explicit heap stack or a
token-index loop, so over-limit input never enters `parse_sexpr`. The
recursive parser still checks, as a second line of defense.

`weavec build` re-parses frontend WIR in a child `--backend`. That text
can be one list deeper than the admitted surface program, so the child
sets the private `WEAVEC_INTERNAL_WIR_PARSE` variable and skips the
bound. Direct `weavec --backend` of untrusted WIR still checks.

On failure the diagnostic is:

- code `frontend.parse.nesting-too-deep` or
  `backend.parse.nesting-too-deep`
- message `nesting exceeds the compiler depth budget of 64`
- span at the `(` that would exceed the budget
- no executable, WIR, or formatted output is published

## Walks that remain recursive

These walks still recurse, but only over trees the parser already
admitted, so their depth is at most 64:

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
depth 65 for surface, WIR, and `fmt`, and repeats the `weavec build`
rejection under a reduced `ulimit -s`.
