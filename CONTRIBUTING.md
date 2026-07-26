# Contributing to weavec

`weavec` is the user-facing self-hosted compiler written primarily in surface
Weave. It combines surface lowering, analysis, self-hosted WIR-to-LLVM emission,
native build orchestration, diagnostics, and package runtime discovery.

The reproducible bootstrap path is:

```text
weavec0 → weavec1 → weavec-bootstrap → weavec
```

Read [`docs/index.md`](docs/index.md),
[`docs/architecture.md`](docs/architecture.md), and
[`docs/source-style.md`](docs/source-style.md) before changing compiler
boundaries or production `.weave` modules.

## WIR rule

The complete chain uses WIR core version 2. The self-hosted frontend must emit
exactly one `(core-version 2)` declaration, and the self-hosted backend must
reject other envelopes before output creation.

Do not add a private `weavec` WIR dialect. Prefer existing admitted WIR v2 forms;
incompatible WIR semantics require an explicit coordinated version transition,
regenerated fixtures, and the complete bootstrap and self-host gates. See
[`docs/wir.md`](docs/wir.md).

## WIR evolution proposals

When implementation work reveals a well-justified capability that WIR v2 cannot
express cleanly, preserve the current specification and use a compatible
workaround when possible. Create a feature-request issue in `weavec` so the idea
can be evaluated with other candidates for the next coordinated WIR version.

Use a title such as:

```text
WIR next-version candidate: <capability>
```

The issue should describe:

- the concrete compiler, tooling, or user need;
- the current WIR v2 workaround and its limitations;
- why existing admitted forms are insufficient;
- the proposed semantics, not merely an implementation sketch;
- affected compiler stages, runtimes, validators, and tools;
- migration, determinism, fixture, bootstrap, and self-host implications;
- unresolved design questions and plausible alternatives.

Do not modify WIR v2 merely to solve one local problem. Keep credible candidates
open, periodically review them together, and implement a coherent set in one
explicit specification bump across the complete compiler chain.

## Principles

- **Surface Weave evolves here.** New surface forms, contracts, structs, quantum
  rewrites, and user-facing compiler behavior belong in this repository.
- **Preserve the WIR v2 boundary.** Prefer existing admitted forms; coordinate
  incompatible WIR semantics as a versioned compiler-chain change.
- **No feature without a regression.** Add correctness, performance, quantum,
  diagnostics, package, or self-host coverage matching the changed boundary.
- **Review LLVM goldens.** Regenerate them only after intentional backend-output
  changes and inspect the complete diff.
- **Keep self-hosting green.** The normal ladder and deep two-generation
  self-host job are permanent gates.
- **Preserve deterministic source ordering.** `build.sh` and `selfhost.sh` must
  list compiler modules in the same order.
- **Keep bootstrap boundaries named.** Consume `weavec-bootstrap` through its
  command, multifile driver, and `libweave-sexpr.bc`; do not depend on private
  generated parser modules.
- **Prefer published SDKs.** The normal Linux build must remain reproducible from
  release archives and checksums without source-repository side effects.
- **Keep runtime ownership explicit.** Compiler host support and the private
  target program runtime are separate responsibilities.
- **Version automation contracts deliberately.** Incompatible manifest or
  diagnostics changes require a new format identifier.
- **Keep documentation navigable.** Files under `docs/` use lowercase kebab-case
  names, and current local links must resolve.

## Commit discipline

Prefer small, targeted commits. Each commit must form one logical unit, group
files that belong together meaningfully, and tell exactly one story. Separate
unrelated refactoring, behavior changes, tests, generated output, and
 documentation when they can stand independently.

Use Conventional Commits:

```text
<type>(<optional-scope>): <description>
```

Common types include `feat`, `fix`, `docs`, `test`, `refactor`, `perf`, `build`,
`ci`, and `chore`. Use `!` before the colon for an intentional breaking change.

The subject line must:

- be shorter than 72 characters;
- describe only the commit's single logical change;
- use an imperative, concise description;
- omit a trailing period.

Every commit must have a body separated from the subject by one blank line. The
body must have exactly this structure:

1. Open with a brief one-to-three-sentence summary of the commit content.
2. Add an optional bullet-pointed list only when more specific detail is useful.
3. End after the summary or optional bullet list; add no trailers, footers,
   separate test-log sections, or unrelated notes.

Wrap every commit-body line to at most 80 characters. Keep bullets concrete and
limited to details that support the summary. Explain breaking behavior in the
summary or bullets rather than adding a `BREAKING CHANGE` footer.

Example:

```text
feat(frontend): preserve exact source identity

Record the original build-input index in diagnostics-only WIR mappings.
This keeps byte-identical files distinguishable without changing WIR v2.

- Preserve ordinary frontend output.
- Add identical-input and multifile regressions.
```

## What does not belong here

- A private final-compiler WIR primitive added only to make one surface feature
  convenient.
- Uncoordinated changes to Stage 0 runtime externs or Stage 1 WIR v2 contracts.
- General maintenance of the frozen `weavec-bootstrap` frontend.
- Production quantum-runtime behavior hidden inside the current test stub.
- Compatibility aliases for the retired `weavec2` or `weavefront` names.
- Speculative syntax presented as implemented reference material.

A new bootstrap-runtime ABI symbol must be released through the required
lower-stage boundary and propagated through the Stage 1 SDK. An ordinary host or
libc extern used only by the final compiler may be declared in `weavec` when it is
portable across supported hosts and covered by the complete platform matrix.

## Development workflow

1. Create a focused branch.
2. Read the relevant architecture, source-style, command, language, diagnostics,
   manifest, runtime, or backend contract document.
3. Make the smallest coherent change.
4. Add or update fixtures under the relevant test tree.
5. Run the normal ladder:

   ```sh
   ./build.sh
   ./test-all.sh
   ```

6. For frontend, backend, emitted-WIR, source-order, parser-boundary, or
   compiler-generation changes, also run:

   ```sh
   ./selfhost.sh
   ```

7. For intentional performance LLVM changes:

   ```sh
   ./test/performance/regen-golden.sh
   git diff -- test/performance
   ```

8. Update the README, changelog, and every affected reference or design
   document.
9. Inspect the complete diff and open a focused pull request.

CI runs the normal ladder with Linux glibc SDKs, Linux musl SDKs, and the macOS
source fallback. The deep-selfhost CI job builds the seed first, then verifies
stage-one and stage-two self-hosted compilers.

## Documentation-only changes

Documentation changes must not silently redefine compiler behavior. Ground
reference material in current source, tests, package scripts, and released
protocols.

For a documentation-only pull request:

- do not edit `src/`, `runtime/`, build scripts, test scripts, or workflows unless
  the scope is explicitly expanded;
- use lowercase kebab-case names under `docs/`;
- update all local links when moving a document;
- distinguish implemented behavior, current limitations, historical notes, and
  future proposals;
- state the relevant WIR core version when discussing frontend/backend behavior;
- avoid workspace-specific paths or commands that assume sibling repositories;
- record meaningful structural documentation changes under `Unreleased`.

The normal compiler workflows remain useful evidence that documentation-only
renames did not accidentally alter tracked executable files, but no compiler
rebuild is required merely to prove Markdown prose compiles.

## Dependency controls

The canonical controls are:

- `WEAVEC1_VERSION` and `WEAVEC1_LIBC` — published Stage 1 SDK;
- `WEAVEC1_SDK` — extracted local Stage 1 SDK;
- `WEAVEC_BOOTSTRAP_VERSION` and `WEAVEC_BOOTSTRAP_LIBC` — published bootstrap
  SDK;
- `WEAVEC_BOOTSTRAP_SDK` — extracted local bootstrap SDK;
- `WEAVEC1`, `WEAVEC1_TAG`, `WEAVEC_BOOTSTRAP`, and
  `WEAVEC_BOOTSTRAP_REF` — explicit source fallbacks;
- `WEAVEC0` and `WEAVEC0_TAG` — Stage 0 source fallback controls;
- `WEAVEC_BACKEND` — existing self-hosted backend executable.

When changing an SDK pin:

- verify the release provides both required libc archives and `SHA256SUMS`;
- inspect `SDK-MANIFEST` for required commands and library paths;
- run the complete glibc, musl, and macOS matrix;
- run deep self-hosting when compiler output or frontend modules changed;
- document why the pin changed;
- update architecture and release documents when the dependency contract changes.

Stage 0 controls matter only when the Stage 1 source fallback is required.

## Public interface changes

Changes to any of the following require documentation and regression coverage:

- `weavec build` command syntax or phase behavior;
- low-level frontend/backend modes;
- surface language syntax or semantics;
- emitted WIR core version or forms;
- `weavec-build-manifest-v1`;
- `weavec-diagnostics-v1` and stable public exit codes;
- private runtime discovery or target layout;
- package `BUILD-MANIFEST`;
- source ordering or self-host generation rules.

See:

- [`docs/command-reference.md`](docs/command-reference.md)
- [`docs/language-reference.md`](docs/language-reference.md)
- [`docs/source-style.md`](docs/source-style.md)
- [`docs/build-manifest.md`](docs/build-manifest.md)
- [`docs/diagnostics.md`](docs/diagnostics.md)
- [`docs/releasing.md`](docs/releasing.md)

## Licensing

By submitting a contribution, you agree that it is licensed under the Apache
License, Version 2.0. See [`LICENSE`](LICENSE).
