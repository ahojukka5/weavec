# Contributing to weavec

`weavec` is the user-facing self-hosted compiler written primarily in surface
Weave. It combines surface lowering, analysis, self-hosted WIR-to-LLVM emission,
native build orchestration, diagnostics, and package runtime discovery.

The reproducible bootstrap path is:

```text
weavec0 → weavec1 → weavec-bootstrap → weavec
```

Read [`AGENTS.md`](AGENTS.md), [`docs/index.md`](docs/index.md),
[`docs/architecture.md`](docs/architecture.md), and
[`docs/source-style.md`](docs/source-style.md) before changing compiler
boundaries, production `.weave` modules, or repository state through an
automated agent.

## WIR rule

The self-hosted frontend must emit exactly one `(core-version 3)` declaration,
and the self-hosted backend must reject every other envelope before output
creation. The frozen seed stages remain at core version 2 and are not affected
by changes here; the two boundaries never meet.

Do not add a private `weavec` WIR dialect. Prefer existing admitted forms;
incompatible WIR semantics require an explicit coordinated version transition,
regenerated fixtures, and the complete bootstrap and self-host gates. See
[`docs/wir.md`](docs/wir.md).

## WIR evolution proposals

When implementation work reveals a well-justified capability that the current
core version cannot
express cleanly, preserve the current specification and use a compatible
workaround when possible. Create a feature-request issue in `weavec` so the idea
can be evaluated with other candidates for the next coordinated WIR version.

Use a title such as:

```text
WIR next-version candidate: <capability>
```

The issue should describe:

- the concrete compiler, tooling, or user need;
- the current workaround and its limitations;
- why existing admitted forms are insufficient;
- the proposed semantics, not merely an implementation sketch;
- affected compiler stages, runtimes, validators, and tools;
- migration, determinism, fixture, bootstrap, and self-host implications;
- unresolved design questions and plausible alternatives.

Do not modify the WIR contract merely to solve one local problem. Keep credible
candidates
open, periodically review them together, and implement a coherent set in one
explicit specification bump across the complete compiler chain.

## Principles

- **Surface Weave evolves here.** New surface forms, contracts, structs, quantum
  rewrites, and user-facing compiler behavior belong in this repository.
- **Preserve the WIR boundary.** Prefer existing admitted forms; coordinate
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
  command and multifile driver only. The production parser lives in
  `src/parser/`; do not depend on lower-stage parser bitcode or private
  generated modules.
- **Prefer published SDKs.** The normal Linux build must remain reproducible from
  release archives and checksums without source-repository side effects.
- **Keep runtime ownership explicit.** Compiler host support and the private
  target program runtime are separate responsibilities.
- **Version automation contracts deliberately.** Incompatible manifest or
  diagnostics changes require a new format identifier.
- **Keep documentation navigable.** Files under `docs/` use lowercase kebab-case
  names, and current local links must resolve.

## Branch and publication safety

The default branch is protected working history. It must never be used as a
staging area by a human, script, automated agent, or connector-backed tool.

- Create a focused branch from the exact current default-branch head before the
  first repository mutation.
- Never create, update, delete, or temporarily replace a file directly on
  `master`, `main`, or whatever branch GitHub reports as the repository default.
- Never omit the target branch from a connector write. An omitted branch usually
  selects the default branch and must be treated as unsafe.
- Do not create a branch by writing a marker, placeholder, empty, or temporary
  file. Use `git switch -c`, the branch API, or the ref API directly.
- If branch creation or lookup fails, stop. Do not retry the write without a
  branch and do not fall back to the default branch.
- A reversible or no-net-content write is still a direct default-branch write and
  is forbidden.
- Never force-update the default branch. Rewrite a feature branch only when its
  review history needs cleaning and repository rules permit it.
- Prefer local `git` for substantial or multi-file work. Use connector file APIs
  only when complete payloads fit their limits and can be verified after upload.
- Treat a truncated or incomplete uploaded blob as a failed publication. Do not
  split production source merely to work around a transport limit unless that
  split is independently the correct architecture.

If an accidental default-branch write occurs, stop all writes immediately,
record and report the exact commit and affected paths, and do not stack further
direct commits to hide or repair it. Restore content through a normal reviewed
revert, or ask the repository owner to repair protected history when a ref-level
correction is required.

Before opening a pull request, compare the feature branch against its intended
base and verify both the complete file list and commit list. The branch must
contain only the intended logical work.

## Commit discipline

Prefer small, targeted commits. Each commit must form one logical unit, group
files that belong together meaningfully, and tell exactly one story. Separate
unrelated refactoring, behavior changes, tests, generated output, and
documentation when they can stand independently.

This also runs in reverse: commits that were only split by authorship
mechanics, not by logical independence, belong back together. A chain of
`fix` commits that each corrects a mistake introduced earlier in the same,
not-yet-reviewed branch — rather than a regression in already-merged code —
was never independently revertable; squash it into the commit whose mistake
it corrects so the merged history shows the feature working correctly on the
first attempt, not the debugging trail.

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
This keeps byte-identical files distinguishable without changing the WIR
contract.

- Preserve ordinary frontend output.
- Add identical-input and multifile regressions.
```

## Task completion

After completing a `weavec` task, report the finished result and propose concrete
follow-up work. Suggestions should be specific, prioritized, and grounded in the
code, tests, architecture, or product direction discovered during the task.

Include useful candidates from one or both categories:

- strengthening work that improves correctness, test coverage, diagnostics,
  maintainability, performance, documentation, portability, or release quality;
- functionality that fills a standard compiler gap or gives `weavec` a distinctive
  capability compared with existing compilers.

When a follow-up exposes a justified WIR capability gap, create a next-version
feature-request issue using the WIR evolution process above. Do not propose a
private WIR extension as a shortcut.

## What does not belong here

- A private final-compiler WIR primitive added only to make one surface feature
  convenient.
- Uncoordinated changes to Stage 0 runtime externs or Stage 1 WIR contracts.
- General maintenance of the frozen `weavec-bootstrap` frontend.
- Production quantum-runtime behavior hidden inside the current test stub.
- Compatibility aliases for the retired `weavec2` or `weavefront` names.
- Speculative syntax presented as implemented reference material.

A new bootstrap-runtime ABI symbol must be released through the required
lower-stage boundary and propagated through the Stage 1 SDK. An ordinary host or
libc extern used only by the final compiler may be declared in `weavec` when it is
portable across supported hosts and covered by the complete platform matrix.

## Development workflow

1. Resolve the current default branch and create a focused feature branch from
   its exact head before making any repository mutation.
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
9. Inspect the complete base-to-head diff and commit list, clean feature-branch
   history, and open a focused pull request as a draft while validation runs.

## Pull request readiness and CI completion

Pull-request CI is intentionally light so review is not blocked by the full
compiler ladder. The required PR checks are commit-message lint and the
file-based contract smoke (`scripts/pr-check.sh`). They run on GitHub-hosted
runners and do not build the compiler.

A pull request is ready for review when those PR checks for the exact current
head have completed successfully.

- Keep the pull request in draft while a required PR check is queued, pending,
  in progress, cancelled, timed out, or failing.
- A red or cancelled PR check is unfinished work. Inspect its logs, fix the
  underlying code, tests, workflow, or runner interaction, and trigger fresh
  validation for the exact corrected head.
- After rebasing, squashing, force-pushing, or otherwise rewriting history,
  treat earlier PR-check results as stale and wait for the new head.
- Mark the pull request ready for review only after the light PR checks are
  green and the branch history and validation summary are final.
- If GitHub-hosted PR infrastructure is unavailable, leave the pull request in
  draft and describe the blocker precisely.

Do not wait for the full ladder or deep self-host on a pull request. Those jobs
run only after merge, on `master`, with Linux glibc SDKs and Linux musl SDKs.
A red post-merge check is a follow-up fix, not a reason to keep the original
PR open. There is no macOS job. macOS is a supported build host, so a change
that could behave differently there should be run locally and the result stated
in the pull request.

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

- `WEAVEC1_VERSION` and `WEAVEC1_LIBC` (Linux only) — published Stage 1 SDK;
- `WEAVEC1_SDK` — extracted local Stage 1 SDK, bypassing the download;
- `WEAVEC_BOOTSTRAP_VERSION` and `WEAVEC_BOOTSTRAP_LIBC` (Linux only) —
  published bootstrap SDK;
- `WEAVEC_BOOTSTRAP_SDK` — extracted local bootstrap SDK, bypassing the
  download;
- `WEAVEC_BACKEND` — existing self-hosted backend executable.

There is no source-chain fallback: an unavailable package for the host's
platform (`linux-x86_64-glibc`, `linux-x86_64-musl`, `macos-arm64`, or
`macos-x86_64`) is a release dependency failure, not permission to clone and
rebuild `weavec0`, `weavec1`, or `weavec-bootstrap`.

When changing an SDK pin:

- verify the release provides all four platform archives and `SHA256SUMS`;
- inspect `SDK-MANIFEST` for required commands and library paths;
- run the glibc and musl matrix in CI, and the macOS build locally;
- run deep self-hosting when compiler output or frontend modules changed;
- document why the pin changed;
- update architecture and release documents when the dependency contract changes.

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
