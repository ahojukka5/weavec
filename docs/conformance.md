# Surface conformance corpus

The conformance corpus is a small, stable, compiler-independent contract for the
public Weave surface language. It exists so language behavior can be qualified
separately from compiler internals: an internal representation change must not
create user-language test churn, and any `weavec` binary that claims to
implement the language must satisfy the same cases unchanged.

The corpus is not a second copy of the low-level compiler regressions under
[`test/correctness/`](../test/correctness). Those tests pin WIR text, LLVM
structure, and backend behavior on purpose and remain the authority for the
internal contract. See [Source and fixture style](source-style.md).

## Contract

Every case is defined only by behavior a user can observe from the command line:

- canonical or otherwise accepted surface source;
- compile success, or a stable `weavec-diagnostics-v1` code with its stable
  phase exit;
- stdout, stderr, and process exit status of the built native program;
- canonical formatter observations through `weavec fmt`.

A case never asserts emitted WIR text, LLVM text, mangled or generated symbol
names, private runtime layout, temporary paths, or any other compiler-internal
spelling. `scripts/check_conformance_corpus.py` rejects a case whose expectation
files contain those spellings.

Diagnostic expectations name the stable `code` from
[Machine-readable diagnostics](diagnostics.md), never a human-readable message,
so a message rewording is not a corpus change.

## Running it against any compiler

One command runs the whole corpus:

```sh
bash test/conformance/run.sh
```

The compiler under test is `$WEAVEC`, using the same override every other suite
in this repository honors. It defaults to `build/weavec`:

```sh
WEAVEC=/path/to/weavec bash test/conformance/run.sh
```

That is the only knob a caller needs, so the same cases qualify:

- the checkout compiler at `build/weavec`;
- an extracted release package, whose `bin/weavec` finds its own packaged
  `stdlib/` beside it (see [Releasing](releasing.md));
- a stage-2 self-host binary produced by `./selfhost.sh`, which runs the
  corpus itself as one of its stage-2 suites;
- any future frontend or execution path that implements the same public
  contracts.

The user-facing standard library resolves automatically: `$WEAVEC_STDLIB` when
set, otherwise the `stdlib` directory one level above the compiler when it
exists, otherwise the repository `stdlib`. An extracted package therefore needs
no extra configuration because it keeps the documented repository-relative
paths.

A compiler that sits outside a package layout and outside the checkout `build/`
directory cannot discover the private target runtime on its own. Point it at the
checkout runtime with the documented control, the same way `scripts/selfhost.sh`
qualifies its own generations:

```sh
WEAVEC=build/selfhost/stage2/weavec \
WEAVEC_RUNTIME=runtime/program.c \
  bash test/conformance/run.sh
```

Useful options:

```sh
bash test/conformance/run.sh --list
bash test/conformance/run.sh --case=variants-and-match
```

Native cases need `clang` and `llc` on `PATH`. When either is missing the runner
reports the run cases as skipped and still checks the compile-fail and formatter
cases, matching the toolchain policy of the other native suites.

## Case layout

One directory per case under [`test/conformance/cases`](../test/conformance/cases):

```text
test/conformance/cases/<case-name>/
├── meta               declarative expectation
├── *.weave            the case sources
├── expected-stdout    exact stdout for a run case
├── expected-stderr    exact stderr for a run case, when it is not empty
└── expected-format    exact canonical output for a format case
```

`meta` is a list of `key: value` lines. `#` lines are comments.

| Key | Meaning |
|---|---|
| `mode` | `run`, `compile-fail`, or `format`. |
| `area` | Coverage area; see the table below. |
| `sources` | Case-local `.weave` files, in compile order. |
| `stdlib` | Standard-library module file names to compile first. |
| `args` | Command-line arguments for a `run` case. |
| `exit` | Expected process exit for `run`; expected stable phase exit for `compile-fail`, default `10`. |
| `diagnostic` | Expected stable diagnostic code for `compile-fail`. |
| `canonical` | `yes` when every declared source must satisfy `weavec fmt --check`. |

### Modes

`run` builds the case with `weavec build`, runs the program with `args`, and
compares the exit status, stdout, and stderr byte for byte. A run case with no
`expected-stderr` must write nothing to stderr.

`compile-fail` builds with `--diagnostics-json` and requires the stable phase
exit, a `failed` diagnostics document carrying the expected `code`, and no
published executable.

`format` requires `weavec fmt --check` to report the input as noncanonical
without modifying it, `weavec fmt --output` to produce `expected-format`
exactly, and that canonical output to be canonical itself.

### Coverage areas

| Area | Scope |
|---|---|
| `control-flow` | Calls, operators, casts, conditionals, loops, explicit returns. |
| `functions-modules` | Function signatures, module roots, exports, imports. |
| `data-types` | Structs, generics, tagged variants, exhaustive match. |
| `option-result` | `Option`, `Result`, `try`, recoverable failure. |
| `strings` | String literal forms and interpolation. |
| `contracts` | `requires`, `ensures`, and effect declarations. |
| `stdlib` | Current user-facing standard-library behavior. |
| `formatting` | Observable canonical formatter behavior. |

## Adding a case

1. Create `test/conformance/cases/<case-name>/` using a lowercase kebab-case
   name that describes the behavior, not the compiler phase.
2. Write the source. Prefer canonical surface forms, and run
   `weavec fmt` over the file so `canonical: yes` holds.
3. Write `meta`, choosing the area the behavior belongs to.
4. Record the expectation from the built compiler, never from documentation:
   run the program and capture its real stdout, stderr, and exit, or read the
   real `code` out of the `--diagnostics-json` document.
5. Add the case name to [`test/conformance/MANIFEST`](../test/conformance/MANIFEST),
   keeping the file sorted.
6. Run `bash test/conformance/run.sh` and
   `python3 scripts/check_conformance_corpus.py`.

A new canonical surface feature belongs in the area that already owns its
neighbours. If a documented behavior does not reproduce against the built
compiler, do not record the observed defect as the contract; leave the case out
and file the defect.

## Completeness guard

`scripts/check_conformance_corpus.py` is a file-based check that needs no
compiler. It exists because a corpus whose runner reads a hand-maintained list
can be silently reduced to a subset that still passes. The guard requires that:

- `MANIFEST` and the case directories agree exactly, in both directions, and
  `MANIFEST` stays sorted and duplicate-free;
- every case declares a complete, well-formed expectation for its mode;
- every `.weave` file in a case directory is declared in `sources`;
- every required coverage area has at least one case;
- expectation files contain no compiler-internal spelling;
- `run.sh` never names an individual case, so cases stay filesystem-discovered;
- `scripts/pr-compile.sh`, `scripts/test-all.sh`, and `scripts/selfhost.sh`
  still run the corpus.

The runner enforces the same manifest agreement at run time and fails when the
number of executed cases does not match the number discovered.

## Where the corpus runs

| Check | What runs |
|---|---|
| `scripts/pr-check.sh` | the file-based completeness guard |
| `scripts/pr-compile.sh` | the corpus against the freshly built compiler |
| `scripts/test-all.sh` | both |
| `scripts/selfhost.sh` | the corpus against the stage-2 self-host compiler |

See [Contributing](../CONTRIBUTING.md) for the pull-request readiness rules.

## Non-goals

The corpus does not fuzz, does not replace backend or WIR structural tests, and
does not measure performance.
