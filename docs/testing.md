# Language testing

Status: specified contract for epic
[#114](https://github.com/ahojukka5/weavec/issues/114). The parser, harness,
and `weavec test` command are not implemented yet. This document is the
semantic authority for those slices.

Weave programs define tests as ordinary surface declarations. The compiler
discovers them, lowers them through WIR core version 3 as ordinary functions
plus a generated harness, and runs that harness with `weavec test`. There is
no reflection-based discovery, no plugin runner, and no hidden `*_test.weave`
naming rule.

The example corpus and checker under `spec/testing/` and
`scripts/check_testing_spec.py` are normative for the first-milestone
decisions. Implementation issues must not invent new forms, states, or
exits.

## Canonical example

```weave
(module arithmetic
  (export add-two)
  (fn add-two ((a i32) (b i32)) i32
    (return (+ a b)))

  (test add-two-basic
    (tags unit)
    (do
      (expect-eq (add-two 40 2) 42))))
```

Intended invocation after the command exists:

```text
weavec test
weavec test add-two-basic
weavec test --tag unit
weavec test --json test-results.json
```

## Test declarations

A `test` is a top-level declaration inside `program` or `module`, sibling to
`fn`, `entry`, and `const`. It is not an expression and must not nest inside
another `test`, `fn`, or `do`.

```weave
(test NAME
  (tags TAG...)
  BODY)
```

`NAME` is a portable identifier `[A-Za-z][A-Za-z0-9_-]*`. It must be unique
among tests in the same module. It may match a test in another module. It
must not collide with a `fn`, `entry`, or `const` in the same module.

`(tags ...)` is optional and may occur at most once. Each tag is a portable
identifier. Duplicate tags in one test are an error. The canonical formatter
sorts tags by UTF-8 bytes; source order is not semantically meaningful.

`BODY` is a single `do` of statements. A test does not return a value. An
explicit `(return ...)` inside a test is an error: pass/fail is determined
only by assertions and by process termination.

## Assertions

Assertions are statements, not expressions. They are compiler surface forms,
not standard-library functions, so a failure records the test result instead
of calling `abort` unless the process crashes.

| Form | Meaning |
|---|---|
| `(expect EXPR)` | `EXPR` has type `bool`. The test fails if the value is false. |
| `(expect-eq A B)` | `A` and `B` have the same admitted equality type. The test fails if they are not equal. |
| `(expect-ne A B)` | Same types as `expect-eq`. The test fails if they are equal. |
| `(fail)` | The test fails. |
| `(fail MESSAGE)` | The test fails. `MESSAGE` is a string literal used in human and JSON output. |

First-milestone equality types are `i32`, `i64`, `bool`, `f32`, and `f64`.
`f32`/`f64` use IEEE equality: `NaN` is not equal to itself, so
`(expect-eq (/ 0.0 0.0) (/ 0.0 0.0))` fails. Enum values, including `Option` and
`Result`, have no identity and are not admitted to `expect-eq` /
`expect-ne`; compare payloads after `match`. Pointer and `String` equality
are not in the first milestone.

`(expect-eq)` and `(expect-ne)` require exactly two operands of one admitted
type. Mixed types are a compile-time error, not a failed test.

## Visibility

A test may use private declarations of its own module. A test in a different
module, including a file under `test-roots`, uses the same import and export
rules as ordinary code. Format 1 does not add a designated test-module
privilege that sees another module's privates.

## Ordering and duplicates

Discovered tests are ordered by:

1. module identity, UTF-8 bytes;
2. test name, UTF-8 bytes.

Declaration order, file creation time, and absolute checkout path do not
affect run order. Duplicate test names in one module are a compile-time
error at the later declaration's name span, naming both.

## Lowering

Each test lowers to one ordinary WIR function with a compiler-owned
identity. The harness is one generated entry that calls the selected tests
in the order above. No new WIR dialect is required. Generated names are not
a public API and must not collide with user `fn`/`entry` names.

A `weavec build` of a program or project that contains tests must not run
those tests and must not include test-root modules. Tests execute only
through `weavec test`.

## Command

`weavec test` is a user-facing command next to `weavec build`. Invalid
usage returns `2`.

Explicit source-list mode is selected when any non-option `.weave` argument
is present:

```text
weavec test <input.weave> [input2.weave ...]
```

With no source arguments, project mode uses the same manifest selection as
`weavec build`. It discovers tests from:

- `test` declarations in modules under `source-roots`;
- admitted `.weave` files under `test-roots`, using the same visibility,
  symlink, and sorting rules as source discovery.

`weavec build` continues to ignore `test-roots`. There is no `*_test.weave`
bypass of the manifest.

Filtering by name, module, and tag is specified for a later slice. Until
that slice, `weavec test` runs every discovered test.

`--json PATH` writes `weavec-test-results-v1` without changing stderr.
Human output lists each test's final state and a summary line.

A failed `weavec test` does not publish a partial user program at `-o`.
Harness temporaries follow `weavec build` temporary policy.

## Result states

Every discovered test has exactly one of these states:

| State | Meaning |
|---|---|
| `passed` | The test body finished and no assertion failed. |
| `failed` | An assertion failed or `(fail)` ran. |
| `error` | The test could not run because the harness did not compile or link, or a compile-fail fixture got an unexpected compiler result. |
| `crashed` | The test process terminated abnormally. Without isolation, this also ends the command. |
| `skipped` | Reserved. Not produced in the first runner slice. |
| `filtered` | Discovered but excluded by a later name, module, or tag filter. |

## Exit codes

When the harness fails to compile, optimize, code-generate, link, or
publish, `weavec test` uses the same stable phase codes as
`weavec build` with `--diagnostics-json`:

| Code | Meaning |
|---:|---|
| `2` | Invalid command-line request. |
| `10` | Surface frontend or source parse failed. |
| `11` | WIR backend failed. |
| `12` | LLVM optimization or target code generation failed. |
| `13` | Target linker failed. |
| `14` | Atomic output publication failed. |
| `15` | Driver or toolchain setup failed. |

After a successful harness build:

| Code | Meaning |
|---:|---|
| `0` | Every selected test `passed`. Zero discovered tests is success. |
| `20` | At least one selected test `failed`, and none `crashed`. |
| `21` | At least one selected test `crashed`. |

`filtered` and `skipped` tests do not change the exit code. Document-level
JSON `status` is `passed` for exit `0`, `failed` for `20` or `21`, and
`error` when a phase code `10`–`15` is returned.

## JSON protocol

`--json` writes `weavec-test-results-v1`. The schema is
[`schemas/weavec-test-results-v1.schema.json`](schemas/weavec-test-results-v1.schema.json)
with identifier `urn:weavec:schema:test-results:v1`.

```json
{
  "format": "weavec-test-results-v1",
  "status": "failed",
  "exit_code": 20,
  "tests": [
    {
      "name": "add-two-basic",
      "module": "arithmetic",
      "tags": ["unit"],
      "status": "failed",
      "message": "expect-eq"
    }
  ]
}
```

Records are ordered like the run order. `additionalProperties` remains true
so later slices can add fields. Unknown `format` values must be rejected by
consumers that require this protocol.

## Diagnostics

First-milestone diagnostic codes:

| Code | Meaning |
|---|---|
| `test.malformed-name` | Test name is not a portable identifier. |
| `test.duplicate-name` | Two tests in one module share a name. |
| `test.duplicate-tag` | A test lists the same tag twice. |
| `test.nested` | `test` appears where only statements or expressions are allowed. |
| `test.return` | A test body contains `return`. |
| `test.collision` | A test name collides with a `fn`, `entry`, or `const` in the same module. |
| `test.expect-type` | `expect` did not receive `bool`. |
| `test.expect-eq-type` | `expect-eq` / `expect-ne` operands are missing, mixed, or not an admitted equality type. |
| `test.private-cross-module` | A test used a private declaration from another module. |

## Relationship to the conformance corpus

`weavec test` is the in-language test facility specified here. It is separate
from the [surface conformance corpus](conformance.md), which is a
compiler-independent public-behavior contract driven from the command line and
runnable against any `weavec` binary. The corpus does not depend on `test`
declarations and does not wait for this command.

## Non-goals

The first milestone does not include coverage, property testing, fuzzing,
reflection, a plugin runner, process isolation, compile-fail fixtures, or
generic assertion helpers beyond the forms above. Isolation, filtering,
JSON publication, compile-fail fixtures, and package qualification are
separate subissues of #114.

## WIR boundary

Surface lowering over WIR v3 only.
