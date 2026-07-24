# Loop-carried SSA contract (weavec)

weavec lowers `while` loops and `if` statements inside loop bodies to
LLVM with explicit loop phis, per-iteration merges, and latch edges.
This document states the invariants the emitter must preserve so IR
passes `llvm-as` and self-host (`build/weavec.wir`).

## Names and blocks

For loop suffix `L` and if suffix `N`:

| LLVM name | Role |
|-----------|------|
| `%while.preL` | Init block: load stack slots into loop-carried temps |
| `%while.condL` | Header phi: `[init, while.preL]`, `[merge, while.latchL]` |
| `%while.bodyL` | Loop body entry |
| `%while.latchL` | Backedge to header |
| `%while.exit-mergeL` | Stack sync on exit (false edge from cond) |
| `%while.endL` | After exit merge |
| `%thenN`, `%elseN`, `%endifN` | If branches and merge |
| `%name.phiL` | Loop-carried value at header |
| `%name.nextTAG` | Assignment in a branch (TAG encodes loop/if/branch) |
| `%name.mergeN` | Merge at `%endifN` for locals touched in that if |

Block suffixes come from `ctx_alloc_blk`; the emitter tracks the
active block with `ctx_set_emit_blk` / `ctx_get_emit_blk`.

## Loop phi at header

Each loop-carried local gets one phi at `%while.condL`:

```llvm
%v.phiL = phi T [ %v.initL, %while.preL ], [ %v.mergeM, %while.latchL ]
```

`mergeM` is the suffix of the innermost merge that last updated `v` in
the body (often the last `%endif` in the body for that iteration).

## If merge inside a loop

At `%endifN`, for each loop-carried local updated in the if (then
and/or else), emit:

```llvm
%v.mergeN = phi T [ <then-value>, <then-pred> ], [ <else-value>, <else-pred> ]
```

### Then operand

- If the local is set directly in `%thenN`: use `%v.nextTAG` with
  predecessor `%thenN`.
- If the then branch contains a nested if that sets the local: use
  `%v.mergeINNER` with predecessor `%endif{rejoin}` where `rejoin` is
  the block suffix after `then_do` finishes (`then_rejoin` in
  `emit_if_stmt`). The merge suffix and predecessor suffix may differ
  when control falls through later blocks before joining `%endifN`.

### Else arm ingress

Before emitting a non-empty `else` block inside a loop, call
`restore_loop_carried_before_else` so `local_get` in the else arm sees
header phis, not merge names from the sibling then arm.

### Else operand (`else_hit = 0`, local unchanged in else)

Priority order in `emit_if_loop_phi_merges`:

1. Sequential sibling: prior if at `N-1` left a merge at `%endif{N-1}`.
2. `else_exit_suf`: nested if in the else branch exited at a later
   `%endif`.
3. Non-empty else on this if: predecessor `%elseN`, value `%v.phiL`.
4. Empty else, nested in parent then: predecessor `%then{parent}`.
5. Empty else, sequential chain: predecessor from `cond_ingress`
   (`%while.bodyL` when ingress equals loop suffix, else
   `%endif{ingress}`).
6. Fallback: `%while.bodyL` or `%elseN` as appropriate.

### Else operand (`else_hit = 1`)

Use `%v.nextTAG` or inner `%v.mergeM` with predecessor `%elseN` or
`%endif{inner}` mirroring the then rules.

## Exit merge

On loop exit, `%while.exit-mergeL` stores header phi values back to
stack slots so code after the loop sees the final iteration state.
Do not emit stack stores at `%while.endL` without dominating phis.

## Testing

| Script | Checks |
|--------|--------|
| `./test.sh` | Correctness programs |
| `./test/performance/test.sh` | Golden LLVM diff + `llvm-as` + optional `opt -mem2reg` |
| `./test/selfhost/test.sh` | `build/weavec.wir` → LLVM → `llvm-as` |
| `./test-all.sh` | All of the above after `./build.sh` |

Self-host is the integration gate for nested control flow in real
compiler sources (`stmt.weave`, `loop-phi.weave`, etc.).
