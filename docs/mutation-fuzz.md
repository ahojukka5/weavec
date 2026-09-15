# Deterministic mutation-fuzzing lane

Status: first milestone for compiler robustness over mutated S-expression
inputs ([#387](https://github.com/ahojukka5/weavec/issues/387)).

The lane does not prove that an accepted random program is semantically
correct. It checks that parser, frontend, and backend either accept or
reject generated cases through documented exits, without crashing,
hanging, emitting invalid diagnostics, or publishing a partial artifact.

## Command

One command runs a bounded campaign against `$WEAVEC`, defaulting to
`build/weavec`:

```sh
bash test/mutation-fuzz/test.sh
python3 scripts/mutation_fuzz.py --budget=pr --seed=387
```

The recorded default seed is **387**, the issue that introduced the lane.
A failure prints the seed, case index, dumped input, and a `--replay`
command so the same case can be run locally.

## Seeds and mutations

Surface seeds come from the [conformance corpus](conformance.md) plus
`test/correctness/surface/01_return_42.weave`. Direct WIR seeds come from
`test/correctness/wir/*.wir`.

The mutator parses one S-expression form and applies a bounded sequence
of deterministic edits:

- delete, duplicate, or swap a child;
- change a list head;
- mutate integer, string, or identifier tokens;
- insert balanced nested lists up to the public depth budget of 64;
- splice a subtree from another seed;
- perturb a WIR `core-module` / `core-version` envelope.

Generation is unbounded only in the RNG stream. Nesting stops at the
admitted public depth. There is no libFuzzer or AFL integration.

## Oracle

Each case must:

- terminate within the budget timeout;
- avoid memory, stack, and abort faults (`SIGSEGV`, `SIGBUS`, `SIGABRT`,
  and the usual crash banners);
- use a documented exit class for the invoked mode;
- publish schema-shaped `weavec-diagnostics-v1` when
  `weavec build --diagnostics-json` is requested;
- leave no executable or LLVM file after a failed run.

Surface cases invoke `weavec build --diagnostics-json` so the stable
phase exits `0`, `2`, and `10`–`15` apply. Direct WIR cases invoke
`weavec --backend`, which keeps historical `0` / `1` / `2` exits and
must still delete a partial `.ll` file on failure.

The suite includes synthetic stubs that crash, hang, write a partial
output, or emit invalid diagnostics, so a broken oracle cannot stay
green.

## Budgets

| Budget | Cases | Timeout | Where it runs |
|---|---:|---:|---|
| `pr` | 24 | 8 s | pull-request compile gate |
| `nightly` | 192 | 10 s | `scripts/test-all.sh` on master |

Override with `WEAVEC_MUTATION_FUZZ_BUDGET=pr|nightly|<count>`. Dump
failing inputs under `build/mutation-fuzz/` or
`WEAVEC_MUTATION_FUZZ_DUMP`. Pull-request CI uploads that directory when
the compile gate fails.

The master/self-hosted ladder is the larger budget. Use a still larger
integer locally when hunting a rare crash:

```sh
WEAVEC_MUTATION_FUZZ_BUDGET=1024 python3 scripts/mutation_fuzz.py
```

## Promoted regressions

Copy a minimized failing input to
`test/mutation-fuzz/regressions/` as `*.weave` or `*.wir`. The campaign
replays every file there before new mutations. A promoted case that
starts passing remains a regression until it is deliberately removed.

## Non-goals

- coverage-guided fuzzing;
- semantic checks on randomly accepted programs;
- unbounded random source generation.
