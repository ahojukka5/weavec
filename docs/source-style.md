# Compiler source and fixture style

This document records the conventions used by the self-hosted `.weave` compiler
sources and their regression fixtures. It describes current repository practice;
it does not define new language semantics.

The repository-wide whitespace baseline comes from `.editorconfig`:

- UTF-8 text;
- LF line endings;
- final newline;
- spaces, not tabs;
- two-space indentation;
- trailing whitespace removed, except where Markdown requires it.

## File header

Production `.weave` files begin with an SPDX identifier and a short purpose
comment:

```weave
; SPDX-License-Identifier: Apache-2.0
; util.weave — tree traversal helpers for weavec
```

Use semicolon line comments. Explain why a module or non-obvious invariant
exists rather than restating every expression.

## Module shape

A compiler source file contains one surface module:

```weave
(program
  (name "module-name")
  (version "0.1")

  declarations...)
```

The module `name` normally matches the filename concept. Compiler module
filenames and identifiers use lowercase snake_case where multiple words are
needed.

Do not change the module order casually. `build.sh` and `selfhost.sh` must list
the same production modules in the same deterministic order.

## Functions

Use explicit parameter and return declarations:

```weave
(fn count_children
  (params (tree ptr) (node i64))
  (returns i64)
  (do
    ...))
```

Function and local names use lowercase snake_case. Choose names that expose the
representation or role when useful, such as `name_node`, `source_ref`,
`decls_node`, or `expected_exit`.

Add a short preceding comment for exported helpers, recursive traversals,
portability-sensitive behavior, and code-generation invariants:

```weave
; Return the nth child, or -1 when the index is out of range.
(fn nth_child ...)
```

Comments are especially important where a numeric sentinel, byte offset,
runtime layout, LLVM block relationship, or source-order rule is load-bearing.

## Explicit values and types

Compiler implementation code generally uses explicit typed forms:

```weave
(param_get tree)
(local_get child)
(const_i32 0)
(const_i64 -1)
(call_i64 node_first_child ...)
```

Surface sugar may be used deliberately in language fixtures that exist to test
that sugar. Production compiler sources should prefer the explicit form when it
makes data flow, width, or ownership clearer.

Do not rely on implicit numeric conversion. Use the admitted typed operation or
cast that matches the value representation.

## Control flow

Keep `condition`, `then`, `else`, and `do` structure visually aligned:

```weave
(if
  (condition (eq_ptr value (const_null)))
  (then (do
    (return (const_i32 1))))
  (else (do)))
```

Use early returns for invalid nodes, failed allocation, missing children, or
other guard conditions when that shortens the main path.

Before reading a list head or child shape, verify the node kind and sentinel
state. Tree walkers must not call list-only helpers on scalar nodes. This rule is
both a readability convention and a correctness requirement established by
past multi-file and audit failures.

For loops, preserve uniform mutable stack semantics and ordinary structured
control flow. Changes to nested `if`/`while` emission must be reviewed against
[LLVM code-generation analysis](llvm-codegen-analysis.md), optimized evidence,
and the performance goldens.

## Resource ownership

Compiler sources manually manage C-compatible resources. Keep acquisition and
cleanup visible:

- check allocation and parser results before use;
- close file descriptors on every failure path;
- free token, tree, source, and temporary storage according to the owning API;
- do not hide ownership transfers behind a helper unless its contract is clear;
- keep compiler host support separate from the private target program runtime.

When adding a helper, document whether it borrows, owns, frees, or returns a
resource when that is not obvious from the name.

## Output generation

Text emitters should be deterministic:

- never depend on map or filesystem iteration order;
- preserve documented source and declaration ordering;
- emit stable whitespace expected by golden fixtures;
- validate a complete unit before opening an output when a failure can be found
  without partial emission;
- route platform-specific file creation through the portability boundary rather
  than embedding host flag values.

The self-hosted frontend emits WIR core version 3; the frozen seed bootstrap
emits core version 2. State the
version explicitly in format-sensitive comments and fixtures, and do not add private
final-compiler forms without a coordinated version decision.

## C host-support files

Files under `runtime/` use conventional C formatting already present in the
repository:

- four-space indentation;
- braces on the same line as declarations and control statements;
- explicit error checks and stderr diagnostics;
- no shell interpolation for process execution;
- feature-test macros before system headers;
- compiler host support and private program runtime kept in separate files.

Documentation-only changes must not reformat or alter these files.

## Compilation-trace actions

Do not embed trace `kind`, `pass`, and `action` strings directly in frontend
lowering code. Add or reuse a semantic wrapper in
`src/core/trace_registry.weave`, then call that wrapper from the transformation
site.

A new stable action requires one coherent change containing:

- the registry declaration and wrapper implementation;
- a real compiler call site;
- the action table in `docs/compilation-trace.md`;
- `test/trace/expected-actions.txt` and an end-to-end input that reaches it;
- any consumer migration needed for a renamed or removed action.

Run `scripts/check-trace-registry.sh` before the normal compiler ladder. The
audit rejects free-form frontend metadata, generic helper bypasses, unused
wrappers, and registry/documentation/regression drift.

## Correctness fixtures

Surface correctness fixtures live under `test/correctness/surface/`. Begin new
fixtures with concise metadata comments when the purpose is not obvious:

```weave
; purpose: verify typed integer literal sugar.
; expected-exit: 42
; tags: let, literal_sugar, i32, i64
```

A behavior-changing surface fixture normally needs:

- the `.weave` input;
- an expected WIR file when frontend output is contractual;
- an expected native exit or expected failure diagnostic;
- registration in the appropriate test runner.

Use the smallest program that isolates the behavior. Integration fixtures may
combine features, but their comments should identify the interaction being
protected.

## Performance fixtures

Performance inputs use:

```text
NNNN_lowercase_snake_case.wir
```

They require the descriptive header and workflow documented in
[Performance demonstrations](performance-demonstrations.md). Golden LLVM is
pre-optimization output and must be reviewed completely after intentional
backend changes.

## Quantum fixtures

Quantum fixtures are ordinary `.weave` sources. Use the implemented `Qubit`,
`qgate`, and `qmeasure` forms rather than proposal syntax. Depending on the
change, update WIR, metrics, LLVM, and runtime-stub expectations together.

See [Quantum surface support](quantum.md).

## Documentation and comments

Current reference documents are authoritative over stale comments or historical
proposal text. When behavior changes:

1. update the relevant reference document;
2. update nearby source comments that describe the changed invariant;
3. update the changelog when the change is user-visible or structurally
   significant;
4. preserve historical release wording inside existing changelog sections.

Files under `docs/` use lowercase kebab-case. Conventional root metadata retains
its standard uppercase spelling.

## Required validation

For source changes, run:

```sh
./build.sh
./test-all.sh
```

Also run `./selfhost.sh` for frontend, backend, emitted-WIR, source-order,
parser-boundary, or compiler-generation changes.

Documentation-only changes should verify all local links and confirm that the
diff contains no unintended source, runtime, build, test, package, or workflow
changes.
